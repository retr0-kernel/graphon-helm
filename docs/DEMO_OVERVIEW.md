# Graphon Live Demo — Master Guide

**Version:** v0.3.0  
**Audience:** Demo presenter / sales engineer  
**Total setup time:** ~12 minutes  
**Demo runtime:** 20–40 minutes depending on tier

---

## What This Demo Proves

Graphon answers questions that no existing tool does in real time:

| Question | How the demo shows it |
|---|---|
| "What does my service actually call?" | Live graph auto-populated from eBPF — no instrumentation |
| "If I delete X, what breaks?" | Safe-delete analysis with inbound dependency count |
| "Did the architecture drift from our baseline?" | Drift detection with review items |
| "Who owns this orphaned service?" | Ownership map with team/email/Slack |
| "What did the graph look like last Tuesday?" | Snapshot history + diff |
| "Which team shipped the unexpected dependency?" | RBAC-scoped view per team (Enterprise) |

---

## Why Multi-Namespace Matters

The original demo app puts all services in one namespace (`graphon-demo`). That works but it undersells Graphon's core value: **detecting dependencies that cross team boundaries**.

The new demo uses three namespaces that mirror a real company:

```
demo-web    →  frontend, gateway          (frontend-team)
demo-api    →  orders, payments, catalog  (orders-team, payments-team, catalog-team)
demo-data   →  notifications, user-service (platform-team)
```

**Cross-namespace connections the eBPF agent will discover automatically:**

```
frontend (demo-web)    → gateway (demo-web)          # same namespace
gateway  (demo-web)    → orders (demo-api)            # CROSS-NAMESPACE ← demo moment
gateway  (demo-web)    → catalog (demo-api)           # CROSS-NAMESPACE
gateway  (demo-web)    → user-service (demo-data)     # CROSS-NAMESPACE
orders   (demo-api)    → payments (demo-api)          # same namespace
orders   (demo-api)    → notifications (demo-data)    # CROSS-NAMESPACE ← demo moment
```

This lets you show the namespace filter in the UI and demonstrate that Graphon sees through
namespace boundaries without any network policy changes or service mesh configuration.

---

## Demo Architecture

```
┌─────────────────── Kind Cluster ──────────────────────────┐
│                                                            │
│  namespace: graphon                                        │
│  ┌──────────────────────────────────────────────────────┐ │
│  │ graphon-backend (:8080)  graphon-ui (:80)            │ │
│  │ graphon-bpf (DaemonSet)  postgres  neo4j             │ │
│  └──────────────────────────────────────────────────────┘ │
│            ↑ captures TCP from all namespaces              │
│                                                            │
│  namespace: demo-web         namespace: demo-api           │
│  ┌─────────────────────┐    ┌──────────────────────────┐  │
│  │ frontend   :80      │    │ orders      :80          │  │
│  │ gateway    :80      │───▶│ payments    :80          │  │
│  │ traffic-gen         │    │ catalog     :80          │  │
│  └─────────────────────┘    └──────────────────────────┘  │
│                    │                                        │
│                    ▼         namespace: demo-data           │
│              ┌──────────────────────────────────────────┐  │
│              │ notifications  :80                       │  │
│              │ user-service   :80                       │  │
│              └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

---

## Quick Setup (Run Once Before Demo)

```bash
# 1. Create cluster
kind create cluster --name graphon-demo

# 2. Install Graphon
cd graphon-helm/
helm install graphon . \
  --namespace graphon --create-namespace \
  --set backend.authDisabled=true \
  --wait --timeout 5m

# 3. Deploy multi-namespace demo app
kubectl apply -f examples/demo-app-multi-ns/namespaces.yaml
kubectl apply -f examples/demo-app-multi-ns/services.yaml
kubectl apply -f examples/demo-app-multi-ns/traffic-generator.yaml

# 4. Wait for traffic to generate (2 minutes)
sleep 120

# 5. Port-forward
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
kubectl port-forward -n graphon svc/graphon-ui 3000:80 &

# 6. Open UI
open http://localhost:3000
```

After step 4, Graphon will have discovered all 7 services and 6 cross-namespace connections.

---

## Demo Scripts Per Tier

| Tier | Document | What it covers |
|---|---|---|
| **Free Self-Hosted** | [FREE_TIER_DEMO.md](./FREE_TIER_DEMO.md) | Graph, ownership, drift detection, safe-delete, snapshots, search, export |
| **Enterprise Self-Hosted** | [ENTERPRISE_TIER_DEMO.md](./ENTERPRISE_TIER_DEMO.md) | License key, RBAC, OIDC/SSO, scheduled snapshots, webhooks, Draw.io export, multi-cluster |

---

## Namespace Filter: The Killer Demo Moment

When you have the graph open on screen, filter to one namespace:

```bash
# See only demo-api services
curl -s \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  "http://localhost:8080/api/v1/graph?namespace=demo-api" | jq '{
    nodes: (.nodes | length),
    services: [.nodes[].id]
  }'
```

Expected:
```json
{
  "nodes": 3,
  "services": ["orders", "payments", "catalog"]
}
```

Then remove the filter to show the full cross-namespace picture — this is the moment that
resonates with platform engineers who have hundreds of services across tens of namespaces.

---

## Timing Guide (20-min demo)

| Time | What you do |
|---|---|
| 0:00 | Health check, show all pods running |
| 1:00 | Open UI, show live graph with all 3 namespaces colour-coded |
| 3:00 | Namespace filter — show demo-api only, then full picture |
| 5:00 | Click a service — show ownership (team, contact, Slack) |
| 7:00 | Safe-delete analysis on `gateway` — show dependents |
| 9:00 | Take a snapshot, scale down `notifications`, take second snapshot, show diff |
| 13:00 | Seed drift baselines, introduce unexpected pod, show drift alert |
| 16:00 | Export as Mermaid — paste into mermaid.live |
| 18:00 | Q&A |

For Enterprise demos (40 min), follow the FREE_TIER_DEMO first then continue with ENTERPRISE_TIER_DEMO.

---

## Cleanup

```bash
kubectl delete -f examples/demo-app-multi-ns/
kind delete cluster --name graphon-demo
```
