# Drift Detection

Drift detection answers: **"Is this dependency expected?"**

When a service starts calling another service that it never called before, that is **drift** — an unexpected new dependency that could represent a misconfiguration, a security issue, or an architectural change that wasn't reviewed.

## How it works

Every dependency edge in Graphon has a lifecycle:

```
OBSERVED → (after BASELINE_DAYS) → BASELINE
                                         ↑
New edge appears (not in BASELINE) → DRIFT
```

| State | Meaning |
|---|---|
| `OBSERVED` | Edge first seen — not yet confirmed as intentional |
| `BASELINE` | Stable, intentional dependency (promoted after `BASELINE_DAYS`) |
| `DRIFT` | New edge that appeared after baseline was established |

## Setting the baseline

After you've deployed Graphon and your services have been running for a while (usually 7 days), seed the baseline:

```bash
curl -X POST "http://graphon-api/api/v1/drift/seed" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster"
```

This promotes all `OBSERVED` edges older than `BASELINE_DAYS` (default: 7) to `BASELINE`.

You can view the seeded baselines:

```bash
curl "http://graphon-api/api/v1/drift/baselines" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster" | jq '{total: .total, states: [.baselines[].state]}'
```

## What happens when drift is detected

1. The background scanner (runs every 10 minutes) compares new `OBSERVED` edges against `BASELINE` edges
2. For any new edge that isn't in the baseline, a `DRIFT` review item is created
3. A Slack notification is sent if `notify_drift: true` in your Slack config

## Reviewing drift

Open the Review Center in the UI, or use the API:

```bash
# List all open drift items
curl "http://graphon-api/api/v1/review-items?type=DRIFT&status=OPEN" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster" | jq .

# Acknowledge a drift item (you've seen it, investigating)
curl -X PATCH "http://graphon-api/api/v1/review-items/{id}/acknowledge" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster"

# Resolve a drift item (intentional change, accepted)
curl -X PATCH "http://graphon-api/api/v1/review-items/{id}/resolve" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster"

# Ignore a drift item (noise, not interesting)
curl -X PATCH "http://graphon-api/api/v1/review-items/{id}/ignore" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster"
```

## Configuration

### BASELINE_DAYS

Control how many days an OBSERVED edge must exist before it becomes a BASELINE:

```yaml
# values.yaml
backend:
  baselineDays: 7  # default
```

For stable environments, increase to 14–30 days. For fast-moving environments, decrease to 3–5 days.

### Re-seeding after a planned change

After a planned architectural change (new service, new dependency), re-seed the baseline:

```bash
curl -X POST "http://graphon-api/api/v1/drift/seed" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster"
```

This won't delete BASELINE edges that already exist — it only promotes newly OBSERVED ones.

## Drift in the graph view

In the Graphon UI:
- **Blue edges** = BASELINE (expected)
- **Orange edges** = OBSERVED (new, not yet baselined)
- **Red edges** = DRIFT (unexpected — appeared after baseline was set)

Click any edge to see its drift status, first-seen timestamp, and associated review items.
