# RBAC Design

## Roles

| Role | Who | Summary |
|------|-----|---------|
| `admin` | Graphon installation owner | Full access including user management, license, settings |
| `platform-admin` | Platform/SRE team | All graph operations, cluster registration, no billing/users |
| `manager` | Engineering managers | Read all, can set ownership labels and baselines |
| `developer` | Individual contributors | Read their team's namespaces, trigger safe-delete |
| `viewer` | Stakeholders, auditors | Read-only, no mutations |
| `agent` | eBPF agent service account | Write-only events endpoint (machine identity) |

---

## Permission Matrix

| Operation | admin | platform-admin | manager | developer | viewer | agent |
|-----------|:-----:|:--------------:|:-------:|:---------:|:------:|:-----:|
| View graph (all namespaces) | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| View graph (own namespaces) | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| Trigger drift detection | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| Seed baseline | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| Safe delete analysis | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| Set ownership labels | ✓ | ✓ | ✓ | ✓ | ✗ | ✗ |
| Create graph snapshot | ✓ | ✓ | ✓ | ✗ | ✗ | ✗ |
| View snapshots | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| Export graph | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| Register cluster | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| Revoke cluster | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| Manage users | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| View audit log | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| Manage license | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |
| Write events (agent) | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |
| Delete data | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |

### Namespace-Scoped Permissions

Developers and viewers are scoped to specific namespaces:

```sql
CREATE TABLE user_namespace_permissions (
    user_id      UUID REFERENCES users(id),
    tenant_id    TEXT NOT NULL,
    namespace    TEXT NOT NULL,   -- "*" = all namespaces
    cluster_id   TEXT NOT NULL,   -- "*" = all clusters
    granted_by   UUID REFERENCES users(id),
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, tenant_id, namespace, cluster_id)
);
```

---

## RBAC Middleware

```go
// Usage in handler registration:
router.Handle("GET /api/v1/graph", 
    rbac.Require("graph:read")(graphHandler))

router.Handle("POST /api/v1/clusters",
    rbac.Require("cluster:register")(clusterHandler))

// Middleware implementation:
func (m *Middleware) Require(permission string) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            user := auth.UserFromContext(r.Context())
            if !m.can(user.Role, permission, r) {
                slog.Warn("rbac denied",
                    "user_id", user.ID,
                    "role", user.Role,
                    "permission", permission,
                    "path", r.URL.Path,
                )
                http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
                return
            }
            next.ServeHTTP(w, r)
        })
    }
}
```

---

## Permission String Taxonomy

```
graph:read              View dependency graph
graph:read:namespace    View graph filtered to namespace
graph:write             Mutate graph data (seeds, baselines)
cluster:register        Register new cluster
cluster:revoke          Revoke cluster token
snapshot:read           View historical snapshots
snapshot:create         Create manual snapshot
export:read             Export graph (PNG/SVG/etc)
export:pdf              Export PDF (license gated)
search:read             Basic search
search:advanced         Full-text + path search
user:read               View user list
user:write              Create/update/delete users
license:read            View license status
license:write           Apply new license key
audit:read              View audit log
events:write            Submit eBPF events (agent only)
```

---

## Group Sync from IdP

When an OIDC login includes `groups` claim, Graphon maps groups to roles:

```yaml
oidc:
  groupRoleMapping:
    "graphon-admins@example.com": "admin"
    "platform-sre":               "platform-admin"
    "engineering-managers":       "manager"
    "engineers":                  "developer"
```

If a user belongs to multiple groups, highest-privilege role wins.

---

## Default Behavior When RBAC Disabled

When `rbac.enabled: false` (default):
- All authenticated users have `admin` role
- No permission checks on any endpoint
- Suitable for small self-hosted teams

When `auth.enabled: false` (default for self-hosted):
- All requests treated as `admin`
- Suitable for private cluster installs without external access
