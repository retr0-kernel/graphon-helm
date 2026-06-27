# Historical Graph Design — Snapshots, Time-Travel, Diffs

## Overview

The Historical Graph feature records the state of the dependency graph at regular intervals and on-demand, enabling operators to:
- Browse the dependency graph as it existed at any past point in time
- Compare two graph states to see what changed
- Trace when a new dependency was introduced
- Audit dependency drift over days, weeks, or months

---

## Data Model

### Snapshot Table (PostgreSQL)

```sql
CREATE TABLE graph_snapshots (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     TEXT NOT NULL,
    cluster_id    TEXT NOT NULL,
    label         TEXT,                    -- "pre-deploy", "v2.4.0", auto timestamp
    trigger       TEXT NOT NULL,           -- scheduled | manual | pre_deploy | post_deploy
    node_count    INTEGER NOT NULL,
    edge_count    INTEGER NOT NULL,
    snapshot_data JSONB NOT NULL,          -- full graph serialization
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    expires_at    TIMESTAMPTZ,             -- null = keep forever; free tier = 30 days
    size_bytes    INTEGER
);

CREATE INDEX idx_snapshots_tenant_cluster ON graph_snapshots(tenant_id, cluster_id);
CREATE INDEX idx_snapshots_created ON graph_snapshots(created_at DESC);
CREATE INDEX idx_snapshots_label ON graph_snapshots(label);
```

### Snapshot Data Format

```json
{
  "version": "1",
  "captured_at": "2026-06-27T12:00:00Z",
  "cluster_id": "prod-us-east-1",
  "nodes": [
    {
      "id": "default/payment-service",
      "namespace": "default",
      "name": "payment-service",
      "owner_team": "payments",
      "owner_email": "payments@example.com",
      "labels": { "app": "payment-service" }
    }
  ],
  "edges": [
    {
      "src": "default/checkout-service",
      "dst": "default/payment-service",
      "dst_port": 8080,
      "first_seen": "2026-06-20T08:00:00Z",
      "last_seen": "2026-06-27T11:59:59Z",
      "call_count": 4820
    }
  ]
}
```

---

## Snapshot Schedule

| Plan | Frequency | Retention |
|------|-----------|-----------|
| Free / Self-Hosted | Manual only | 30 days, max 10 snapshots |
| Self-Hosted Pro | Every 6 hours | 90 days |
| Enterprise | Every 1 hour | 1 year |
| Cloud Standard | Every 6 hours | 90 days |
| Cloud Enterprise | Configurable (min 15 min) | Configurable |

---

## API Design

```
# Snapshot management
POST   /api/v1/snapshots                         ← create manual snapshot
GET    /api/v1/snapshots?cluster=&from=&to=      ← list snapshots
GET    /api/v1/snapshots/{id}                    ← fetch one snapshot
DELETE /api/v1/snapshots/{id}                    ← delete (admin only)

# Time-travel query
GET    /api/v1/graph?snapshot={id}               ← graph at snapshot point
GET    /api/v1/graph?at=2026-06-20T00:00:00Z     ← nearest snapshot to timestamp

# Diff
GET    /api/v1/snapshots/diff?from={id}&to={id}  ← compute diff
GET    /api/v1/snapshots/diff?from={ts}&to={ts}  ← compute diff by timestamp
```

---

## Diff Algorithm

```go
type GraphDiff struct {
    AddedNodes   []Node  // appeared in "to" but not "from"
    RemovedNodes []Node  // in "from" but not "to"
    AddedEdges   []Edge  // new dependency in "to"
    RemovedEdges []Edge  // dependency gone in "to"
    ChangedEdges []EdgeChange  // edge exists in both but changed (e.g. port, frequency)
}

// Algorithm: O(n+m) using map lookup
// 1. Build node map for "from" and "to" snapshots
// 2. Added = keys in "to" not in "from"
// 3. Removed = keys in "from" not in "to"
// 4. Changed = keys in both where edge attributes differ
```

Diff response example:
```json
{
  "from": { "id": "...", "captured_at": "2026-06-20T00:00:00Z" },
  "to":   { "id": "...", "captured_at": "2026-06-27T00:00:00Z" },
  "summary": {
    "added_nodes": 3,
    "removed_nodes": 1,
    "added_edges": 8,
    "removed_edges": 2
  },
  "added_nodes": [...],
  "removed_nodes": [...],
  "added_edges": [
    { "src": "order-service", "dst": "fraud-service", "first_seen": "2026-06-25T..." }
  ],
  "removed_edges": [...]
}
```

---

## Time-Travel UI

```
Timeline bar:
  [Jun 1] ──────●────●──●──────────────●── [Today]
                 ↑    ↑  ↑              ↑
                 Auto snapshots         Manual ("pre-v2.4")

User drags slider → graph re-renders at nearest snapshot
"Compare with now" button → diff view with +/- annotations

Diff view annotations:
  ● Green nodes  = added since baseline
  ● Red nodes    = removed since baseline
  ● Green edges  = new dependencies
  ● Red edges    = removed dependencies (dashed)
  ● Gray         = unchanged
```

---

## GitHub/GitLab Integration Hook

When a deployment webhook arrives:
1. Backend auto-creates a `pre_deploy` snapshot (if not exists in last 5 min)
2. Deployment lands
3. Backend auto-creates a `post_deploy` snapshot
4. Diff is attached to the PR/MR as a comment

This gives automatic "what changed architecturally" on every deploy.

---

## Storage Estimation

| Scenario | Nodes | Edges | Snapshot size | 1 yr @ 1h |
|----------|-------|-------|---------------|-----------|
| Small team | 50 | 150 | ~50 KB | ~438 MB |
| Medium company | 500 | 2000 | ~500 KB | ~4.4 GB |
| Large enterprise | 5000 | 20000 | ~5 MB | ~44 GB |

Compression: JSONB with LZ4 reduces by ~60%. Enterprise tier should use columnar snapshots or delta storage.
