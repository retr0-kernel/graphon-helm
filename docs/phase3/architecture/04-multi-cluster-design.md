# Multi-Cluster Design

## Overview

Graphon supports multiple Kubernetes clusters within a single tenant (Self-Hosted Enterprise and Cloud). Cluster data is physically isolated but logically queryable from one UI.

---

## Cluster Registry

### Data Model (PostgreSQL)

```sql
-- clusters table
CREATE TABLE clusters (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id    TEXT NOT NULL,
    name         TEXT NOT NULL,                    -- "prod-us-east-1"
    display_name TEXT,
    region       TEXT,
    token_hash   TEXT NOT NULL,                    -- SHA-256 of cluster JWT
    token_expiry TIMESTAMPTZ NOT NULL,
    last_seen    TIMESTAMPTZ,
    event_rate   INTEGER DEFAULT 0,               -- events/min rolling
    status       TEXT DEFAULT 'healthy',           -- healthy | degraded | offline
    metadata     JSONB DEFAULT '{}',               -- labels, annotations
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, name)
);

CREATE INDEX idx_clusters_tenant ON clusters(tenant_id);
CREATE INDEX idx_clusters_last_seen ON clusters(last_seen);
```

### Cluster Health States

| State | Condition | Action |
|-------|-----------|--------|
| `healthy` | Events received within 2 min | Green indicator |
| `degraded` | No events for 2–10 min | Yellow, alert |
| `offline` | No events for 10+ min | Red, notification |
| `pending` | Never sent events | Gray |
| `revoked` | Token explicitly revoked | Locked |

---

## Agent-to-Backend Routing

### Self-Hosted (Single Backend)

All agents write to the same backend. Cluster identity is passed per-request:

```
X-Cluster-ID: <k8s node name or user-defined label>
```

The backend stores `cluster_id` on every edge/event row.

### Cloud (Multi-Backend)

Cluster JWT contains `tenant` claim. API gateway routes to tenant namespace.

---

## Cross-Cluster Query API

```
GET /api/v1/graph?cluster=prod-us-east-1         ← single cluster
GET /api/v1/graph?cluster=prod-us-east-1,prod-eu  ← multi cluster, merged
GET /api/v1/graph                                  ← all clusters (fan-out)

GET /api/v1/search?q=payment-service&cluster=*    ← global search
GET /api/v1/clusters                               ← cluster registry
GET /api/v1/clusters/{id}/health                   ← cluster health
```

### Fan-Out Strategy

```go
// When cluster=* (or omitted), backend:
// 1. Fetches all cluster IDs for tenant from registry
// 2. Issues parallel queries to each cluster's Neo4j DB
// 3. Merges node/edge sets, deduplicates by service identity
// 4. Returns unified graph with per-node cluster annotations

type ClusterGraphResult struct {
    ClusterID   string
    ClusterName string
    Nodes       []Node
    Edges       []Edge
}

// Merge strategy: union by (namespace + service_name)
// Conflicts (same service in multiple clusters): retain both with cluster label
```

---

## UI: Cluster Switching

### Cluster Selector Component

```
┌──────────────────────────────────────────────┐
│  📍 All Clusters (3)          ▼              │
├──────────────────────────────────────────────┤
│  ● prod-us-east-1    142 services   healthy  │
│  ● prod-eu-west-1     89 services   healthy  │
│  ◐ staging            12 services   degraded │
└──────────────────────────────────────────────┘
```

- Persisted in URL: `?cluster=prod-us-east-1`
- "All Clusters" merges graphs with cluster badges on each node
- Degraded/offline clusters shown with visual indicator + tooltip

---

## Cluster Registration Flow

### Self-Hosted Enterprise

```bash
# Admin generates registration token
kubectl exec -n graphon svc/graphon-backend -- \
  graphon-cli cluster register --name prod-us-east-1

# Output:
# Token: eyJhbGciOiJIUzI1NiJ9...
# Expires: 2027-06-27
# Add to agent values: --set cloud.clusterToken=eyJ...
```

### Cloud

1. User clicks "Add Cluster" in app.graphon.io
2. UI calls `POST /api/v1/clusters { name, region }`
3. Backend creates cluster record, generates signed JWT
4. UI renders `helm install` command with token embedded
5. User pastes command in their terminal
6. Agent comes online, first health heartbeat received
7. Cluster status → `healthy`

---

## Tenant Isolation

Every row in PostgreSQL includes `tenant_id`. All queries are filtered at the repository layer:

```go
// NEVER queries without tenant scope
func (r *Repo) GetEdges(ctx context.Context, tenantID string, clusterID string) ([]Edge, error) {
    return r.db.QueryContext(ctx,
        `SELECT * FROM edges WHERE tenant_id = $1 AND cluster_id = $2`,
        tenantID, clusterID,
    )
}
```

Neo4j: each tenant gets a dedicated database (`USE graphon_acme;`). The backend resolves the database name from the authenticated tenant context.

---

## Cross-Cluster Service Identity

Services with the same name across clusters are correlated by:
1. `namespace/service-name` pair (primary key)
2. Owner labels (`app.graphon.io/owner-team`)
3. Image repository (same image → likely same service)

Correlation enables:
- "This service runs in 3 clusters"
- "Dependency pattern diverges between prod and staging"
- Cross-cluster drift detection
