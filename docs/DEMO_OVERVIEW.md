# Graphon Live Demo — From Absolute Zero

**Assumes:** `kubectl` works and is pointed at the target cluster. That's it.

---

## Step 0 — Install prerequisites (if missing)

```bash
# Helm (if not installed)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Git (if not installed — usually present)
git --version || brew install git   # macOS
# git --version || apt-get install -y git  # Ubuntu/Debian
```

Confirm cluster access:
```bash
kubectl get nodes
kubectl get ns
```

---

## Step 1 — Clone the repo

```bash
git clone https://github.com/retr0-kernel/graphon-helm.git
cd graphon-helm
```

---

## Step 2 — Install Graphon

Pick a namespace. If a `demos` or `graphon` namespace already exists, use it. Otherwise create one:

```bash
kubectl create namespace graphon   # skip if namespace already exists

helm upgrade --install graphon . \
  --namespace graphon \
  --set backend.authDisabled=true \
  --wait --timeout 5m
```

Watch pods come up:
```bash
kubectl get pods -n graphon -w
```

All pods should reach `Running` within 3–5 minutes.

---

## Step 3 — Deploy the multi-namespace demo app

```bash
kubectl apply -f examples/demo-app-multi-ns/namespaces.yaml
kubectl apply -f examples/demo-app-multi-ns/services.yaml
kubectl apply -f examples/demo-app-multi-ns/traffic-generator.yaml

# Wait for pods
kubectl wait --for=condition=Ready pods --all -n demo-web --timeout=120s
kubectl wait --for=condition=Ready pods --all -n demo-api --timeout=120s
kubectl wait --for=condition=Ready pods --all -n demo-data --timeout=120s
```

This deploys 7 services across 3 namespaces and a traffic generator that starts making cross-namespace TCP connections immediately.

```
demo-web   →  frontend, gateway
demo-api   →  orders, payments, catalog
demo-data  →  notifications, user-service
```

---

## Step 4 — Wait for eBPF to capture traffic

```bash
sleep 120
```

The eBPF agent needs ~2 minutes to see enough TCP connections to build the graph.

---

## Step 5 — Port-forward and open the UI

```bash
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
kubectl port-forward -n graphon svc/graphon-ui 3000:80 &
```

Open: **http://localhost:3000**

Quick sanity check:
```bash
curl -s http://localhost:8080/api/v1/health | jq .
curl -s http://localhost:8080/ready | jq .
```

Expected:
```json
{"status":"ok","version":"0.3.0"}
{"postgres":"ok","neo4j":"ok"}
```

---

## Now run the tier demo

| Tier | Doc |
|---|---|
| **Free** | [FREE_TIER_DEMO.md](./FREE_TIER_DEMO.md) |
| **Enterprise** | [ENTERPRISE_TIER_DEMO.md](./ENTERPRISE_TIER_DEMO.md) |

---

## Cleanup when done

```bash
kubectl delete -f examples/demo-app-multi-ns/
helm uninstall graphon -n graphon
kubectl delete namespace graphon demo-web demo-api demo-data
```
