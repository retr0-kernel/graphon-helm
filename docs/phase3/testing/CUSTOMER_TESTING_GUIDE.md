# Customer Testing Guide

## Purpose

This guide enables real customer onboarding, investor demos, conference presentations, and engineering evaluations using **real Kubernetes workloads** with **real service communication** and **real dependency generation**. No mocks, no fake data, no screenshots.

---

## Part 1: Self-Hosted Testing

### Prerequisites

```
Kubernetes cluster:  Kind / Minikube / k3d / EKS / GKE / AKS
Helm:                ≥ 3.12
kubectl:             configured with cluster access
Docker:              (for Kind only)
```

### Step 1: Fresh Cluster

```bash
# Kind (recommended for demos)
kind create cluster --name graphon-demo --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        system-reserved: memory=512Mi
- role: worker
- role: worker
EOF

# OR Minikube
minikube start --cpus=4 --memory=8192 --driver=docker
```

### Step 2: Install Graphon

```bash
helm repo add graphon https://retr0-kernel.github.io/graphon-helm
helm repo update
helm install graphon graphon/graphon \
  --namespace graphon \
  --create-namespace

# Watch pods come up (~90 seconds)
kubectl get pods -n graphon -w
```

**Expected state after 2 minutes:**
```
NAME                               READY   STATUS    RESTARTS
graphon-0                          1/1     Running   0
graphon-agent-xxxxx                1/1     Running   0
graphon-backend-xxxxx              1/1     Running   ≤1
graphon-postgresql-0               1/1     Running   0
graphon-ui-xxxxx                   1/1     Running   0
```

### Step 3: Validate Graphon Health

```bash
# Backend health
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
curl -s http://localhost:8080/ready | jq .
# Expected: { "ready": true, "checks": { "neo4j": {"ok":true}, "postgres": {"ok":true} } }

# UI
kubectl port-forward -n graphon svc/graphon-ui 3000:80 &
open http://localhost:3000
```

### Step 4: Deploy Demo Microservices

The demo app is a realistic e-commerce platform with real HTTP communication between services.

```bash
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon-helm/main/examples/demo-app/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon-helm/main/examples/demo-app/
```

**Services deployed:**
```
demo-app/
  ├─ frontend           → calls api-gateway
  ├─ api-gateway        → calls order-service, user-service, product-service
  ├─ order-service      → calls payment-service, inventory-service
  ├─ payment-service    → calls fraud-detection, notification-service
  ├─ user-service       → calls auth-service
  ├─ product-service    → calls inventory-service
  ├─ inventory-service  (writes to postgres)
  ├─ notification-service (writes to redis)
  ├─ auth-service       (writes to postgres)
  ├─ fraud-detection    (reads from redis)
  └─ traffic-generator  → generates continuous HTTP traffic between all services
```

### Step 5: Wait for Graph to Populate

```bash
# Watch dependency events arrive
kubectl logs -n graphon -l app.kubernetes.io/component=backend -f | grep "dependency"

# Check event count
curl -s http://localhost:8080/api/v1/stats | jq .
# Expected after 5 min:
# { "edges": ">15", "nodes": ">10", "events_processed": ">1000" }
```

### Step 6: View the Graph

```bash
open http://localhost:3000
```

**What you should see:**
- All 10+ demo services as nodes
- Real dependency edges with port information
- Owner team labels on each node
- Event frequency indicators on edges

### Step 7: Validation Checklist

```bash
# Run automated validation
curl -sSL https://raw.githubusercontent.com/retr0-kernel/graphon-helm/main/scripts/validate-install.sh | \
  NAMESPACE=graphon RELEASE=graphon bash
```

Manual checks:
- [ ] All pods Running
- [ ] Backend `/ready` returns `true`
- [ ] UI loads at port 3000
- [ ] Graph shows ≥ 10 service nodes
- [ ] Graph shows ≥ 15 dependency edges
- [ ] Owner team labels visible on nodes
- [ ] Drift detection returns baseline differences
- [ ] Safe delete shows risk analysis for `order-service`

---

## Part 2: External PostgreSQL Testing

```bash
# Provision external PostgreSQL (example: docker for local testing)
docker run -d --name test-pg \
  -e POSTGRES_DB=graphon \
  -e POSTGRES_USER=graphon \
  -e POSTGRES_PASSWORD=testpassword \
  -p 5433:5432 postgres:16

# Install Graphon with external PostgreSQL
helm install graphon graphon/graphon \
  --namespace graphon \
  --create-namespace \
  --set postgresql.enabled=false \
  --set externalPostgresql.host=host.docker.internal \
  --set externalPostgresql.port=5433 \
  --set externalPostgresql.database=graphon \
  --set externalPostgresql.username=graphon \
  --set externalPostgresql.password=testpassword \
  --set externalPostgresql.sslMode=disable

# Verify
curl -s http://localhost:8080/ready | jq '.checks.postgres'
# Expected: { "ok": true }
```

---

## Part 3: External Neo4j Testing

```bash
# Option A: Neo4j AuraDB (Free tier at console.neo4j.io)
# 1. Create free instance at console.neo4j.io
# 2. Copy Bolt URL and password

helm install graphon graphon/graphon \
  --namespace graphon \
  --create-namespace \
  --set neo4j.enabled=false \
  --set externalNeo4j.boltUrl=neo4j+s://xxx.databases.neo4j.io \
  --set externalNeo4j.username=neo4j \
  --set externalNeo4j.password=<aura-password>

# Option B: Local Neo4j docker
docker run -d --name test-neo4j \
  -e NEO4J_AUTH=neo4j/testpassword \
  -p 7687:7687 neo4j:5

helm install graphon graphon/graphon \
  --namespace graphon \
  --create-namespace \
  --set neo4j.enabled=false \
  --set externalNeo4j.boltUrl=bolt://host.docker.internal:7687 \
  --set externalNeo4j.username=neo4j \
  --set externalNeo4j.password=testpassword
```

---

## Part 4: Failure & Recovery Testing

### Test: Backend Pod Restart

```bash
kubectl delete pod -n graphon -l app.kubernetes.io/component=backend
# Backend restarts with retry logic — verify it reconnects
kubectl logs -n graphon -l app.kubernetes.io/component=backend -f | grep "ready"
```

### Test: Neo4j Restart

```bash
kubectl delete pod -n graphon graphon-0
# Backend should retry connections — verify with logs
# Expected: WARN logs showing retries, then INFO "connected to neo4j"
```

### Test: Agent Restart

```bash
kubectl delete pod -n graphon -l app.kubernetes.io/component=agent
# Agent automatically re-deployed by DaemonSet
# Events should resume within 30 seconds
```

### Test: Helm Upgrade

```bash
helm upgrade graphon graphon/graphon \
  --namespace graphon \
  --reuse-values \
  --set backend.image.tag=v0.3.0  # hypothetical new version
# Rolling update — zero downtime
# Check: kubectl rollout status deployment/graphon-backend -n graphon
```

---

## Part 5: Production Readiness Checklist

```bash
# Run the full production readiness script
NAMESPACE=graphon RELEASE=graphon \
  ./scripts/validate-install.sh --production
```

Manual verification:
- [ ] All pods Running and Ready
- [ ] No CrashLoopBackOff in the last 30 minutes
- [ ] Backend `/ready` returns `true` for both databases
- [ ] Graph populated with real workload data (not empty)
- [ ] Agent logs show events captured or graceful degraded mode
- [ ] Persistent storage (PVCs) bound and accessible
- [ ] UI reachable and rendering graph
- [ ] Network policies (if enabled) allow agent → backend
- [ ] Resource limits set appropriately for cluster size
- [ ] Neo4j password changed from default
- [ ] License key applied (if production)
- [ ] Backup strategy for PVCs documented

---

## Part 6: Expected Architecture Graphs

After deploying the demo app and allowing 10 minutes of traffic generation, the expected graph topology:

```
frontend
    │
    ▼
api-gateway ──────────────────────────────┐
    │                                      │
    ├──────────────┐                       │
    ▼              ▼                       ▼
order-service  user-service        product-service
    │              │                       │
    ├──────┐        ▼                      ▼
    ▼      ▼    auth-service       inventory-service
payment  inventory                         │
-service   -service ────────────────────── ┘
    │
    ├──────────────────────┐
    ▼                      ▼
fraud-detection   notification-service
```

Any deviation from this expected topology (e.g., unexpected edges, missing edges) should be investigated before considering the demo complete.
