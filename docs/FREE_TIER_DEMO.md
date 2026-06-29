# Graphon Free Tier — Customer Demo Walkthrough

**Plan:** Self-Hosted Free (Apache 2.0, no license key)  
**Audience:** Engineer evaluating Graphon for their team  
**Prereq:** Setup from [DEMO_OVERVIEW.md](./DEMO_OVERVIEW.md) complete — cluster running, traffic generating  
**Time:** ~20 minutes

> **Demo tip:** Run every `curl` command in a terminal the audience can see. The raw JSON
> output is intentional — it proves there is no mock data.

---

## Step 0 — Confirm Everything is Ready

```bash
# All Graphon pods must be Running
kubectl get pods -n graphon

# Health + readiness
curl -s http://localhost:8080/api/v1/health | jq .
curl -s http://localhost:8080/ready | jq .
```

**Expected:**
```json
{"status":"ok","version":"0.3.0"}
{"postgres":"ok","neo4j":"ok"}
```

If `neo4j` shows `"connecting"`, wait 30 seconds and retry. Neo4j takes slightly longer to warm up.

---

## Step 1 — Register Tenant + Create API Key

> **What to say:** "On the Free tier there is no sign-up, no cloud, no phone home.
> You register locally and get an API key in seconds."

```bash
# Register the tenant (run once per organisation)
curl -s -X POST http://localhost:8080/api/v1/tenants/register \
  -H "Content-Type: application/json" \
  -d '{"id":"acme","name":"Acme Engineering"}' | jq .
```

```json
{"id":"acme","name":"Acme Engineering"}
```

```bash
# Create an admin API key
curl -s -X POST http://localhost:8080/api/v1/auth/keys \
  -H "X-Tenant-ID: acme" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-key","role":"admin"}' | jq .
```

```json
{"id":"key-xxxxx","token":"gph_xxxxxxxxxxxxxxxxxx","role":"admin","name":"demo-key"}
```

```bash
# Save the token — used in every subsequent call
TOKEN="gph_xxxxxxxxxxxxxxxxxx"   # replace with your value
```

---

## Step 2 — Register the Demo Cluster

```bash
curl -s -X POST http://localhost:8080/api/v1/clusters/register \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "Content-Type: application/json" \
  -d '{"id":"kind-demo","name":"Kind Demo Cluster","tenant_id":"acme","region":"local"}' | jq .
```

```json
{"id":"kind-demo","name":"Kind Demo Cluster","tenant_id":"acme","region":"local"}
```

> **What to say:** "In production this step happens once per cluster. After that, the agent
> just needs the cluster ID header — there is no agent config file to maintain."

---

## Step 3 — View the Live Dependency Graph

> **Demo moment:** Open `http://localhost:3000` in the browser and show the graph canvas live.
> Then prove the same data is available over the API.

```bash
# Full graph — all 3 namespaces
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/graph" | jq '{
    total_nodes: (.nodes | length),
    total_edges: (.edges | length),
    namespaces: ([.nodes[].namespace] | unique)
  }'
```

**Expected:**
```json
{
  "total_nodes": 7,
  "total_edges": 6,
  "namespaces": ["demo-api","demo-data","demo-web"]
}
```

**Namespace filter — the cross-namespace visibility moment:**

```bash
# Show only the API layer
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/graph?namespace=demo-api" | jq '{
    nodes: [.nodes[].id],
    edges: [.edges[] | "\(.source) → \(.target)"]
  }'
```

**Expected:**
```json
{
  "nodes": ["orders","payments","catalog"],
  "edges": ["orders → payments"]
}
```

```bash
# Show all cross-namespace edges (namespace filter removed)
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/graph" | jq '[.edges[] | "\(.source) → \(.target)"]'
```

**Expected:**
```json
[
  "frontend → gateway",
  "gateway → orders",
  "gateway → catalog",
  "gateway → user-service",
  "orders → payments",
  "orders → notifications"
]
```

> **What to say:** "These six connections were discovered entirely by the eBPF agent watching
> TCP connections at the kernel level. No service mesh, no sidecar, no code change."

---

## Step 4 — List Namespaces

```bash
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/namespaces" | jq .
```

**Expected:** All three demo namespaces returned with service counts.

---

## Step 5 — Ownership Discovery

> **What to say:** "Every service has labels on the pod spec. Graphon reads those labels
> on ingest and builds an ownership map. No separate config file."

```bash
# List all ownership records
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/ownership" | jq '[.[] | {service: .node_id, team: .team, contact: .contact}]'
```

**Expected:**
```json
[
  {"service":"frontend","team":"frontend-team","contact":"frontend@demo.io"},
  {"service":"gateway","team":"platform-team","contact":"platform@demo.io"},
  {"service":"orders","team":"orders-team","contact":"orders@demo.io"},
  {"service":"payments","team":"payments-team","contact":"payments@demo.io"},
  {"service":"catalog","team":"catalog-team","contact":"catalog@demo.io"},
  {"service":"notifications","team":"platform-team","contact":"platform@demo.io"},
  {"service":"user-service","team":"platform-team","contact":"platform@demo.io"}
]
```

```bash
# Get ownership for a specific service
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/services/gateway/ownership" | jq .
```

**Update ownership manually (shows the API is live):**
```bash
curl -s -X PUT \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  "http://localhost:8080/api/v1/services/gateway/ownership" \
  -d '{"team":"platform-team","contact":"alice@acme.io","service_type":"gateway","slack_channel":"#platform"}' | jq .
```

---

## Step 6 — Safe-Delete Analysis

> **What to say:** "This is the question every engineer asks before deleting a service.
> Graphon answers it instantly from the live graph."

```bash
# Can we safely delete the gateway service?
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/services/gateway/safe-delete" | jq .
```

**Expected:**
```json
{
  "safe": false,
  "service_id": "gateway",
  "inbound_count": 1,
  "dependents": ["frontend"],
  "reason": "1 service(s) depend on gateway"
}
```

```bash
# What about a leaf service (payments has no dependents)?
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/services/payments/safe-delete" | jq .
```

**Expected:**
```json
{"safe": true, "service_id": "payments", "inbound_count": 0, "dependents": []}
```

---

## Step 7 — Snapshot + Diff (Time Travel)

> **What to say:** "Take a snapshot before any change, make the change, take another snapshot,
> diff them. You get an exact changelog of what was added or removed from the architecture."

```bash
# Snapshot 1: current state (the healthy baseline)
SNAP1=$(curl -s -X POST \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  -d '{"label":"before-incident","trigger":"manual"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id)

echo "Snapshot 1: $SNAP1"
```

```bash
# Simulate an incident: take notifications offline
kubectl scale deployment notifications -n demo-data --replicas=0
echo "Waiting 90s for graph to update..."
sleep 90
```

```bash
# Snapshot 2: post-incident state
SNAP2=$(curl -s -X POST \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  -d '{"label":"after-notifications-down","trigger":"manual"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id)

echo "Snapshot 2: $SNAP2"
```

```bash
# Diff: what changed between the two snapshots?
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/snapshots/diff?from=$SNAP1&to=$SNAP2" | jq .
```

**Expected:**
```json
{
  "removed": [
    {"source": "orders", "target": "notifications"},
    {"source": "gateway", "target": "user-service"}
  ],
  "added": [],
  "changed": []
}
```

> **What to say:** "In an incident review, this diff is the exact answer to: what disappeared
> from the architecture when notifications went down?"

```bash
# Restore notifications
kubectl scale deployment notifications -n demo-data --replicas=1
```

---

## Step 8 — Drift Detection

> **What to say:** "Drift is when someone ships a dependency that was never approved.
> Graphon detects it automatically."

```bash
# Step 1: Seed the current graph as the approved baseline
curl -s -X POST \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  http://localhost:8080/api/v1/drift/seed | jq .
```

```bash
# Step 2: Simulate drift — a new pod making unexpected calls to payments
kubectl run drift-actor \
  --image=busybox:1.36 \
  --namespace=demo-api \
  --restart=Never \
  -- sh -c "while true; do wget -q -O /dev/null http://payments.demo-api.svc.cluster.local/health; sleep 3; done"

echo "Waiting 90s for drift to be detected..."
sleep 90
```

```bash
# Step 3: Check for drift events in the review centre
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/review-items?item_type=DRIFT" | jq '{
    drift_count: .total,
    events: [.items[] | {source: .node_id, type: .item_type}]
  }'
```

**Expected:** `drift_count > 0` showing `drift-actor` → `payments` as an unexpected dependency.

```bash
# Cleanup
kubectl delete pod drift-actor -n demo-api
```

---

## Step 9 — Search

```bash
# Find all services with "order" in their name or metadata
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/search?q=orders" | jq .
```

```bash
# Find all services owned by platform-team
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/search?q=platform-team" | jq .
```

---

## Step 10 — Architecture Export

> **What to say:** "On the Free tier you get Mermaid, DOT, and SVG. Paste the Mermaid output
> directly into mermaid.live or GitHub — it renders instantly."

```bash
# Mermaid (works in GitHub, Notion, Confluence)
curl -s -X POST \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  -d '{"format":"mermaid"}' \
  http://localhost:8080/api/v1/export
```

**Expected output:**
```
flowchart LR
  frontend --> gateway
  gateway --> orders
  gateway --> catalog
  gateway --> user-service
  orders --> payments
  orders --> notifications
```

```bash
# DOT (GraphViz — paste into graphviz.online)
curl -s -X POST \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  -d '{"format":"dot"}' \
  http://localhost:8080/api/v1/export
```

---

## Step 11 — Review the License Status

```bash
# Confirm you are on the Free plan with no key applied
curl -s \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  http://localhost:8080/api/v1/license | jq .
```

**Expected:**
```json
{
  "plan": "free",
  "features": ["snapshots"],
  "limits": {
    "clusters": 999999,
    "users": 3,
    "retention_days": 30,
    "snapshot_count": 10
  },
  "expiry": null
}
```

> **What to say:** "On Free you get unlimited clusters, 3 users, 30 days of snapshot retention,
> and up to 10 snapshots. For a solo engineer or small team evaluating the product, this is
> fully production-capable."

---

## Step 12 — Quick Pre-Demo Health Checklist

Run this immediately before a live demo to confirm everything is green:

```bash
echo "=== GRAPHON FREE TIER — PRE-DEMO CHECKLIST ==="

echo -n "[1] Backend health:    "
STATUS=$(curl -s http://localhost:8080/api/v1/health | jq -r .status 2>/dev/null)
[ "$STATUS" = "ok" ] && echo "PASS" || echo "FAIL"

echo -n "[2] Databases ready:   "
PG=$(curl -s http://localhost:8080/ready | jq -r .postgres 2>/dev/null)
NEO=$(curl -s http://localhost:8080/ready | jq -r .neo4j 2>/dev/null)
[ "$PG" = "ok" ] && [ "$NEO" = "ok" ] && echo "PASS" || echo "FAIL (pg=$PG neo4j=$NEO)"

echo -n "[3] Graph has data:    "
NODES=$(curl -s -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" -H "X-Cluster-ID: kind-demo" \
  http://localhost:8080/api/v1/graph | jq '.nodes | length' 2>/dev/null)
[ "${NODES:-0}" -ge 7 ] && echo "PASS ($NODES nodes)" || echo "WARN ($NODES nodes — wait for traffic generator)"

echo -n "[4] Snapshots work:    "
SNAP=$(curl -s -X POST -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" -d '{"label":"preflight"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id 2>/dev/null)
[ ${#SNAP} -gt 5 ] && echo "PASS" || echo "FAIL"

echo -n "[5] Export works:      "
EXP=$(curl -s -X POST -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" -d '{"format":"mermaid"}' \
  http://localhost:8080/api/v1/export | head -1)
[[ "$EXP" == *"flowchart"* ]] && echo "PASS" || echo "FAIL"

echo -n "[6] UI reachable:      "
UI=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
[ "$UI" = "200" ] && echo "PASS" || echo "FAIL (HTTP $UI)"

echo "=== ALL CHECKS DONE ==="
```

---

## Free Tier Limitations (Know Before the Demo)

| Limit | Value | What to say |
|---|---|---|
| Users | 3 | "Perfect for a pilot team or individual evaluation." |
| Snapshot retention | 30 days | "Enough for month-over-month comparison. Enterprise removes the cap." |
| Snapshots | 10 max | "For a demo or small team, more than enough." |
| Scheduled snapshots | ✗ | "Manual only. Enterprise adds automatic 6-hour snapshots." |
| OIDC/SSO | ✗ | "API key auth only. Enterprise adds Okta, Google, Azure AD." |
| RBAC | ✗ | "All API keys have admin access. Enterprise adds role-based isolation." |
| PR/MR impact comments | ✗ | "Available in Enterprise with GitHub/GitLab webhooks." |
| Draw.io export | ✗ | "Mermaid/DOT/SVG on Free. Draw.io in Enterprise." |

---

## What to Say at the End

> "Everything you just saw — the live graph, ownership, drift detection, safe-delete,
> snapshots, and export — is **completely free**, **open source**, and runs entirely in
> your cluster. No data leaves your environment. No sign-up. No telemetry.
>
> When your team grows beyond 3 engineers, or you need SSO, RBAC, automated snapshots,
> and GitHub integration, that's when Enterprise makes sense."

Next: [ENTERPRISE_TIER_DEMO.md](./ENTERPRISE_TIER_DEMO.md)
