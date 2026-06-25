# Ownership Labels

Graphon can automatically discover who owns each service by reading Kubernetes pod labels. This requires zero code changes — just add labels to your pod specs.

## The Labels

```yaml
# Add to your Pod template spec:
metadata:
  labels:
    app.graphon.io/owner-team: "payments-team"
    app.graphon.io/owner-email: "payments@example.com"
    app.graphon.io/owner-slack: "#payments-alerts"
```

| Label | Required | Description |
|---|---|---|
| `app.graphon.io/owner-team` | Yes | Team name — shown in the graph and review center |
| `app.graphon.io/owner-email` | No | Team email for escalations |
| `app.graphon.io/owner-slack` | No | Slack channel for notifications |

## How to add them to existing Deployments

**Option A — edit your deployment directly:**

```bash
kubectl patch deployment my-service -n production \
  -p '{"spec":{"template":{"metadata":{"labels":{
    "app.graphon.io/owner-team":"my-team",
    "app.graphon.io/owner-email":"my-team@company.com",
    "app.graphon.io/owner-slack":"#my-team"
  }}}}}'
```

**Option B — edit the Deployment YAML:**

```yaml
# my-deployment.yaml
spec:
  template:
    metadata:
      labels:
        app: my-service
        app.graphon.io/owner-team: "my-team"         # ← add this
        app.graphon.io/owner-email: "my-team@co.com" # ← and this
        app.graphon.io/owner-slack: "#my-team"        # ← and this
```

**Option C — use a Helm values overlay (if your services use Helm):**

```yaml
# your-service/values.yaml
podLabels:
  app.graphon.io/owner-team: "my-team"
  app.graphon.io/owner-email: "my-team@company.com"
  app.graphon.io/owner-slack: "#my-team"
```

## Manual ownership via API

If labels aren't possible, assign ownership through the API:

```bash
NODE_ID="svc:my-tenant:my-cluster:production:my-service"
ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$NODE_ID")

curl -X PUT "http://graphon-api/api/v1/services/$ENCODED/ownership" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster" \
  -d '{
    "owner_team": "my-team",
    "owner_email": "my-team@company.com",
    "owner_slack": "#my-team",
    "assigned_by": "alice"
  }'
```

## Orphan detection

Services without any ownership assignment are **orphans**. Graphon:

1. Detects them in the background scanner (runs every 15 minutes)
2. Creates a `ORPHAN` review item in the review center
3. Sends a Slack notification if configured

To see all orphans:

```bash
curl "http://graphon-api/api/v1/ownership/orphans" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster" | jq .
```

## Confidence scoring

Ownership assignments have a confidence score:

| Source | Confidence |
|---|---|
| Kubernetes label (`app.graphon.io/owner-team`) | `0.95` |
| Namespace-level inference | `0.60` |
| Manual assignment via API | `1.00` |

Higher confidence assignments are shown differently in the UI.

## Removing ownership

```bash
curl -X DELETE "http://graphon-api/api/v1/services/$ENCODED/ownership" \
  -H "X-Tenant-ID: my-tenant" \
  -H "X-Cluster-ID: my-cluster"
```

This will re-open the orphan review item on the next scanner cycle.
