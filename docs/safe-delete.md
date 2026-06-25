# Safe Delete Analysis

Safe Delete answers: **"What happens if I delete this service?"**

Before decommissioning a service, Graphon analyzes its position in the dependency graph and gives you a risk score with concrete reasons.

## Risk Scores

| Score | Meaning | Action |
|---|---|---|
| `SAFE` | No downstream consumers, no recent traffic | Safe to delete |
| `MEDIUM` | Some consumers or recent traffic | Review before deleting |
| `HIGH` | Active consumers or critical position in graph | Do not delete without migration plan |

## Using Safe Delete

### In the UI

Click any service node → expand the "Safe Delete Analysis" section in the right panel. The analysis loads automatically.

### Via API

```bash
NODE_ID="svc:my-tenant:my-cluster:production:my-service"
ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$NODE_ID")

curl "http://graphon-api/api/v1/services/$ENCODED/safe-delete" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster" | jq .
```

**Example response:**

```json
{
  "node_id": "svc:my-tenant:my-cluster:production:payments",
  "risk_score": "HIGH",
  "risk_reasons": [
    "2 active consumer(s)",
    "High traffic: 1247 calls in last 24h",
    "Last seen 30 seconds ago"
  ],
  "consumer_count": 2,
  "dependency_count": 1,
  "traffic_volume": 1247,
  "last_seen": "2026-06-25T06:15:00Z"
}
```

## Risk Factors

| Factor | Triggers HIGH | Triggers MEDIUM | SAFE |
|---|---|---|---|
| Consumer count | ≥ 2 | 1 | 0 |
| Traffic volume (24h) | > 1000 | 10–1000 | < 10 |
| Last seen | < 5 min | < 24h | > 24h |

## Before you delete

A typical workflow:

1. **Check safe delete** — get the risk score and reasons
2. **Notify consumers** — if consumers exist, work with their owners to migrate
3. **Remove from baseline** — re-seed drift baseline after the dependency is gone
4. **Delete the service** — safe to proceed once risk is SAFE
5. **Check review center** — resolve any CLEANUP items created by the cleanup scanner

## Cleanup scanner

The background cleanup scanner (runs every hour) identifies services that:
- Have not been seen for more than `BASELINE_DAYS`
- Are likely decommissioned but still exist in the graph

These appear as `CLEANUP` type review items. Safe delete analysis can help you confirm whether removal is safe before resolving them.
