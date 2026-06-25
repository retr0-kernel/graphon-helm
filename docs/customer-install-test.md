# Customer Installation Test

This document describes the process a brand-new customer would follow to install Graphon on a fresh Kubernetes cluster. It assumes:

- No prior knowledge of Graphon internals
- No access to source code
- Only: a Kubernetes cluster, `helm`, `kubectl`, and internet access

---

## Scenario

**Customer:** Platform engineering team at Acme Corp  
**Goal:** Evaluate Graphon to understand service dependencies and ownership  
**Starting point:** Fresh GKE standard cluster, `kubectl` configured, `helm` installed

---

## Step 1 — Verify prerequisites

```bash
# Check tools
helm version    # must be >= 3.12
kubectl version # must be >= 1.26

# Check cluster access
kubectl get nodes
# Expected: 1+ nodes in Ready state

# Check node kernel version (must be >= 5.4 for eBPF agent)
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.kernelVersion}'
```

If nodes show kernel < 5.4, the eBPF agent won't run. The rest of Graphon still works — you just won't get automatic discovery. You can ingest events manually via the API.

---

## Step 2 — Add Helm repository

```bash
helm repo add graphon https://retr0-kernel.github.io/graphon
helm repo update
helm search repo graphon
```

Expected:
```
NAME              CHART VERSION   APP VERSION   DESCRIPTION
graphon/graphon   0.2.0           v0.2.0        Graphon – Runtime Dependency...
```

---

## Step 3 — Install (quickstart mode)

```bash
helm install graphon graphon/graphon \
  --namespace graphon \
  --create-namespace \
  --set agent.tenantId="acme"
```

This installs:
- graphon-backend (Go API server)
- graphon-ui (React dashboard)
- graphon-agent (eBPF DaemonSet — one pod per node)
- PostgreSQL (embedded)
- Neo4j Community (embedded)

---

## Step 4 — Wait for pods

```bash
kubectl get pods -n graphon -w
```

Expected timeline:
- `graphon-postgresql-0` — Ready in ~30s
- `graphon-neo4j-0` — Ready in ~90s (Neo4j takes longer)
- `graphon-backend-xxx` — Ready once both DBs are up (~2 min total)
- `graphon-ui-xxx` — Ready in ~30s
- `graphon-agent-xxx` — Ready in ~30s (one pod per node)

---

## Step 5 — Validate the installation

```bash
# Download and run the validate script
curl -sSL https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/scripts/validate-install.sh | \
  NAMESPACE=graphon RELEASE=graphon bash
```

Expected output:
```
Graphon Install Validator
  Namespace : graphon
  Release   : graphon

══ 1. Prerequisites ══
  ✓  Namespace 'graphon' exists
  ✓  Helm release 'graphon' found

══ 2. Pod Readiness ══
  ✓  Backend pod(s) ready (1 running)
  ✓  UI pod ready
  ✓  Running pods in namespace: 5
  ✓  Agent DaemonSet pods running: 3

══ 3. Backend Health ══
  ✓  GET /api/v1/health → status=ok version=v0.2.0
  ✓  GET /ready → ready=true
  ✓  Neo4j connectivity: ok
  ✓  PostgreSQL connectivity: ok

══ 4. Graph API ══
  ✓  GET /api/v1/graph → reachable (nodes: 0)

══ 5. UI ══
  ✓  UI is reachable (HTTP 200)

══ 6. Review Center ══
  ✓  GET /api/v1/review-items/counts → total=0

══ Results ══
  Total  : 11
  Passed : 11

  ✓ Graphon is healthy and ready!
```

---

## Step 6 — Access the UI

```bash
kubectl port-forward -n graphon svc/graphon-ui 3000:80 &
open http://localhost:3000
```

The graph will be empty because no services have been discovered yet.

---

## Step 7 — See Graphon working (demo app)

Deploy sample microservices with automatic traffic generation:

```bash
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/examples/demo-app/
```

Wait 30–60 seconds, then refresh the graph in the UI. You should see:
- 6 service nodes (frontend, gateway, orders, payments, catalog, notifications)
- Edges showing which services call which
- In the node detail panel: ownership information (from pod labels)

---

## Step 8 — Add ownership labels to your own services

For each team that owns services in your cluster, add these labels to their Deployment pod specs:

```bash
# Example: add ownership labels to the "checkout" service
kubectl patch deployment checkout -n production \
  -p '{"spec":{"template":{"metadata":{"labels":{
    "app.graphon.io/owner-team":"checkout-team",
    "app.graphon.io/owner-email":"checkout@acme.com",
    "app.graphon.io/owner-slack":"#checkout"
  }}}}}'
```

Within the next agent flush cycle (5 seconds), the ownership data will appear in Graphon.

---

## Step 9 — Set up drift detection baseline

After your real services have been running in Graphon for 7 days (or if you want to baseline immediately):

```bash
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &

curl -X POST http://localhost:8080/api/v1/drift/seed \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.machineID}' | head -c 8)"
```

From now on, any new dependency that appears will show as DRIFT in the review center.

---

## Step 10 — Configure Slack notifications (optional)

```bash
curl -X PUT http://localhost:8080/api/v1/slack/config \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: acme" \
  -d '{
    "webhook_url": "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK",
    "notify_orphan": true,
    "notify_drift": true,
    "notify_cleanup": false
  }'
```

---

## Step 11 — Production hardening (before going live)

1. **Enable ingress with TLS** — see [kubernetes-installation.md § 3](./kubernetes-installation.md)
2. **Switch to external databases** — RDS or Cloud SQL instead of embedded PostgreSQL/Neo4j
3. **Enable API key auth** — set `backend.authDisabled=false` and create keys
4. **Set resource limits** — tune `backend.resources` and `neo4j.resources` for your load
5. **Configure backups** — for embedded databases, set up PVC snapshots

---

## Checklist

| Step | Done? |
|---|---|
| Prerequisites verified | ☐ |
| Helm repo added | ☐ |
| `helm install` succeeded | ☐ |
| All pods are Running | ☐ |
| Validate script passes | ☐ |
| UI accessible in browser | ☐ |
| Demo app deployed and visible in graph | ☐ |
| Ownership labels added to real services | ☐ |
| Baseline seeded | ☐ |
| Slack configured (optional) | ☐ |
| Production hardening (for go-live) | ☐ |

---

## Getting help

- Troubleshooting guide: [troubleshooting.md](./troubleshooting.md)
- GitHub Issues: https://github.com/retr0-kernel/graphon/issues
- Include: your Kubernetes version, Helm chart version, output of `kubectl get pods -n graphon`, and logs from the failing pod.
