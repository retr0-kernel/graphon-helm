# Upgrade Guide: 0.2.x → 0.3.0

This guide covers upgrading an existing Graphon installation from any 0.2.x version to 0.3.0.

---

## What Changed in 0.3.0

### New Database Tables (Migration 003)

Migration `003_phase3.up.sql` adds:

| Table | Purpose |
|---|---|
| `users` | OIDC user accounts (created on first SSO login) |
| `sessions` | Server-side session store for OIDC (cookie auth) |
| `clusters` | Multi-cluster registry (enterprise feature) |
| `graph_snapshots` | Historical graph snapshots |
| `user_namespace_permissions` | Per-namespace RBAC permissions |

Additionally, `ownership_assignments` gains a `search_vector` generated column for full-text search.

**Migration is backwards compatible.** No existing columns are altered or dropped. The migration runner applies files in order and is idempotent — running it twice is safe.

### New Configuration Fields

All new fields are **opt-in** with safe defaults:

| Environment Variable | Default | Purpose |
|---|---|---|
| `RBAC_ENABLED` | `false` | Enable RBAC enforcement |
| `OIDC_ENABLED` | `false` | Enable SSO login |
| `OIDC_GROUP_ROLE_MAPPING` | `""` | Map IdP groups to roles |
| `GITHUB_TOKEN` | `""` | GitHub PAT for PR comments |
| `GITLAB_TOKEN` | `""` | GitLab token for MR comments |

---

## Upgrade Steps

### Standard In-Place Upgrade

```bash
# Pull latest chart
helm repo update

# Upgrade — migrations run automatically on backend startup
helm upgrade graphon graphon/graphon \
  --namespace graphon \
  --reuse-values \
  --wait \
  --timeout 5m
```

The backend pod will:
1. Start
2. Connect to PostgreSQL
3. Apply `003_phase3.up.sql` (adds new tables, non-destructive)
4. Continue normal startup

**Expected logs during upgrade:**
```
applied migration  file=003_phase3.up.sql
connected to neo4j
license: no key configured — running as free tier
scheduler started
http server listening
```

### Verify Upgrade

```bash
kubectl get pods -n graphon
curl -s http://localhost:8080/ready | jq .
```

---

## Rollback Procedure

If you need to roll back to a 0.2.x chart:

### 1. Roll back Helm release
```bash
helm rollback graphon -n graphon
kubectl rollout status deployment/graphon-backend -n graphon
```

### 2. Remove Phase 3 tables (only if needed)

The 0.2.x backend will ignore unknown tables. You only need to remove them if:
- You want to reclaim disk space
- A table is causing an unexpected conflict

```sql
-- Run on your PostgreSQL instance
-- WARNING: This deletes all data in these tables. Only run if intentional.

DROP TABLE IF EXISTS user_namespace_permissions;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS graph_snapshots;
DROP TABLE IF EXISTS clusters;
ALTER TABLE ownership_assignments DROP COLUMN IF EXISTS search_vector;
```

### 3. Verify rollback
```bash
curl -s http://localhost:8080/ready | jq .
curl -s -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  http://localhost:8080/api/v1/graph | jq '.nodes | length'
```

---

## External Database Upgrade

If you use external PostgreSQL:
- Ensure the Graphon database user has `CREATE TABLE` permission
- The migration runs automatically on startup with no manual intervention

If you use RDS, CloudSQL, or another managed database, no pre-migration steps are needed.

---

## Frequently Asked Questions

**Will my existing graph data survive the upgrade?**  
Yes. Migration 003 only adds new tables. Existing data in Neo4j and PostgreSQL is untouched.

**Will existing API keys still work?**  
Yes. API key authentication is unchanged in 0.3.0.

**Does RBAC break my existing setup?**  
No. `RBAC_ENABLED` defaults to `false`. Your existing API clients and agents continue to work exactly as before.

**Can I downgrade after upgrading?**  
Yes, by rolling back the Helm release. The new tables are ignored by the 0.2.x backend. Use the SQL above to clean them up if needed.
