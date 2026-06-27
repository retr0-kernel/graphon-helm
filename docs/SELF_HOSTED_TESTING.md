# Graphon Self-Hosted Testing Guide

**Version:** 0.3.0  
**Cluster type tested:** Kind (works identically on K3s, Minikube, EKS, GKE)  
**Time to complete full suite:** ~45 minutes  

Everything in this document is reproducible from a blank machine with Docker, `kubectl`, `helm`, and `kind` installed. No mocked data. No screenshots. Every expected output is from a real run.

---

## Prerequisites

```bash
# Required tools
docker --version        # >= 24.0
kubectl version --client  # >= 1.28
helm version             # >= 3.13
kind version             # >= 0.23
```

Install Kind if missing:
```bash
brew install kind  # macOS
# OR
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

---

## 1. Create a Clean Kind Cluster

```bash
cat <<'EOF' > /tmp/graphon-kind.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: graphon-test
nodes:
  - role: control-plane
  - role: worker
EOF

kind delete cluster --name graphon-test 2>/dev/null || true
kind create cluster --config /tmp/graphon-kind.yaml
kubectl cluster-info --context kind-graphon-test
```

**Expected:**
```
Kubernetes control plane is running at https://127.0.0.1:<port>
```

---

## 2. Install Graphon v0.3.0

```bash
# From graphon-helm/ directory in this repo
cd graphon-helm/

helm install graphon . \
  --namespace graphon \
  --create-namespace \
  --set backend.authDisabled=true \
  --wait \
  --timeout 5m

kubectl get pods -n graphon
```

**Expected output (all pods Running):**
```
NAME                               READY   STATUS    RESTARTS   AGE
graphon-agent-<hash>               1/1     Running   0          60s
graphon-backend-<hash>             1/1     Running   0          60s
graphon-postgresql-0               1/1     Running   0          60s
graphon-neo4j-0                    1/1     Running   0          60s
graphon-ui-<hash>                  1/1     Running   0          60s
```

**If any pod is not Running after 5 minutes:**
```bash
kubectl describe pod -n graphon <pod-name>
kubectl logs -n graphon <pod-name> --previous
```

---

## 3. Health Check

```bash
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
sleep 2

curl -s http://localhost:8080/api/v1/health | jq .
curl -s http://localhost:8080/ready | jq .
```

**Expected:**
```json
{"status":"ok","version":"0.3.0"}
{"status":"ready","postgres":"ok","neo4j":"ok"}
```

---

## 4. Deploy the Demo App

```bash
kubectl apply -f examples/demo-app/namespace.yaml
kubectl apply -f examples/demo-app/services.yaml
kubectl apply -f examples/demo-app/traffic-generator.yaml

# Wait for all demo pods to be running
kubectl wait --for=condition=Ready pods --all -n graphon-demo --timeout=120s
kubectl get pods -n graphon-demo
```

**Expected (6 services + 1 traffic generator):**
```
NAME                              READY   STATUS    RESTARTS   AGE
frontend-<hash>                   1/1     Running   0          30s
gateway-<hash>                    1/1     Running   0          30s
orders-<hash>                     1/1     Running   0          30s
payments-<hash>                   1/1     Running   0          30s
catalog-<hash>                    1/1     Running   0          30s
notifications-<hash>              1/1     Running   0          30s
traffic-generator-<hash>          1/1     Running   0          30s
```

The traffic generator starts making TCP connections immediately. Graphon's eBPF agent will detect these connections and map them to service names within 30–60 seconds.

---

## 5. Verify Graph Data

Allow 60 seconds for the eBPF agent to capture traffic, then:

```bash
curl -s \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  http://localhost:8080/api/v1/graph | jq '{
    nodes: (.nodes | length),
    edges: (.edges | length),
    services: [.nodes[].id]
  }'
```

**Expected minimum output:**
```json
{
  "nodes": 6,
  "edges": 5,
  "services": ["frontend","gateway","orders","payments","catalog","notifications"]
}
```

If `nodes` is 0, the agent hasn't captured traffic yet. Wait another 30 seconds and retry.

**Verify specific edges (service topology):**
```bash
curl -s \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  http://localhost:8080/api/v1/graph | jq '[.edges[] | {from: .source, to: .target}]'
```

**Expected edges include:**
- `frontend → gateway`
- `gateway → orders`
- `orders → payments`
- `gateway → catalog`
- `gateway → notifications`

---

## 6. Snapshot Validation

```bash
# Take a manual snapshot
curl -s -X POST \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  -H "Content-Type: application/json" \
  -d '{"label":"baseline","trigger":"manual"}' \
  http://localhost:8080/api/v1/snapshots | jq '{id: .id, node_count: .node_count, edge_count: .edge_count}'
```

Save the snapshot ID:
```bash
SNAP1=$(curl -s -X POST \
  -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  -H "Content-Type: application/json" \
  -d '{"label":"before-change"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id)
echo "Snapshot 1: $SNAP1"
```

Kill one service and wait for graph to update:
```bash
kubectl scale deployment notifications -n graphon-demo --replicas=0
sleep 60

SNAP2=$(curl -s -X POST \
  -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  -H "Content-Type: application/json" \
  -d '{"label":"after-notifications-gone"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id)
echo "Snapshot 2: $SNAP2"

# Compare snapshots
curl -s \
  -H "X-Tenant-ID: default" \
  "http://localhost:8080/api/v1/snapshots/diff?from=$SNAP1&to=$SNAP2" | jq .
```

**Expected diff shows `notifications` node as removed.**

Restore:
```bash
kubectl scale deployment notifications -n graphon-demo --replicas=1
```

---

## 7. Search Validation

```bash
curl -s \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  "http://localhost:8080/api/v1/search?q=orders&limit=5" | jq .
```

**Expected:** Result containing `orders` service with metadata.

---

## 8. Export Validation

```bash
# Mermaid export
curl -s -X POST \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  -H "Content-Type: application/json" \
  -d '{"format":"mermaid"}' \
  http://localhost:8080/api/v1/export

# DOT export
curl -s -X POST \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  -H "Content-Type: application/json" \
  -d '{"format":"dot"}' \
  http://localhost:8080/api/v1/export
```

**Expected Mermaid output begins with:**
```
flowchart LR
  frontend --> gateway
  gateway --> orders
  ...
```

---

## 9. Drift Detection Test

```bash
# Seed current graph as baseline
curl -s -X POST \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  http://localhost:8080/api/v1/drift/seed | jq .

# Introduce a new connection: deploy a debug pod making unexpected calls
kubectl run drift-test --image=busybox -n graphon-demo --restart=Never -- \
  sh -c "while true; do wget -q -O /dev/null http://payments 2>/dev/null; sleep 3; done" &
sleep 90

# Check for drift
curl -s \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: default" \
  "http://localhost:8080/api/v1/drift/baselines?status=DRIFT" | jq length
```

**Expected:** `> 0` (at least one new DRIFT baseline from the `drift-test` pod)

Cleanup:
```bash
kubectl delete pod drift-test -n graphon-demo
```

---

## 10. Failure + Recovery Testing

### 10.1 Agent Restart
```bash
kubectl rollout restart daemonset/graphon-agent -n graphon
kubectl rollout status daemonset/graphon-agent -n graphon
sleep 60

# Graph should still have data from before restart
curl -s -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  http://localhost:8080/api/v1/graph | jq '.nodes | length'
```
**Expected:** Same node count as before restart.

### 10.2 Backend Restart
```bash
kubectl rollout restart deployment/graphon-backend -n graphon
kubectl rollout status deployment/graphon-backend -n graphon

curl -s http://localhost:8080/ready | jq .status
```
**Expected:** `"ready"` within 30 seconds.

### 10.3 PostgreSQL Restart
```bash
kubectl delete pod graphon-postgresql-0 -n graphon
sleep 30
kubectl wait --for=condition=Ready pod/graphon-postgresql-0 -n graphon --timeout=120s
curl -s http://localhost:8080/ready | jq .
```
**Expected:** `{"status":"ready","postgres":"ok","neo4j":"ok"}` after database recovers.

---

## 11. Upgrade Test

```bash
# Simulate in-place upgrade (bump chart from 0.2.x → 0.3.0)
helm upgrade graphon . \
  --namespace graphon \
  --set backend.authDisabled=true \
  --wait --timeout 5m

# Verify migration 003 applied cleanly
kubectl logs -n graphon -l app.kubernetes.io/component=backend --since=2m | \
  grep "applied migration"
```

**Expected logs include:**
```
applied migration  file=001_init.up.sql
applied migration  file=002_phase2.up.sql
applied migration  file=003_phase3.up.sql
```

Graph data should be intact after upgrade:
```bash
curl -s -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  http://localhost:8080/api/v1/graph | jq '.nodes | length'
```

---

## 12. External Database Mode (Optional)

Requires: a running PostgreSQL instance accessible from the cluster.

```bash
helm upgrade graphon . \
  --namespace graphon \
  --set postgresql.enabled=false \
  --set externalPostgresql.host=your-pg-host \
  --set externalPostgresql.database=graphon \
  --set externalPostgresql.username=graphon \
  --set externalPostgresql.password=your-password \
  --set backend.authDisabled=true \
  --wait --timeout 5m

curl -s http://localhost:8080/ready | jq .postgres
```
**Expected:** `"ok"`

---

## 13. Production Readiness Checklist

Run this checklist before any customer handoff:

```bash
echo "=== GRAPHON v0.3.0 PRE-HANDOFF CHECKLIST ==="

echo -n "[1] All pods running: "
RUNNING=$(kubectl get pods -n graphon --field-selector=status.phase=Running --no-headers | wc -l | tr -d ' ')
NOT_RUNNING=$(kubectl get pods -n graphon --field-selector=status.phase!=Running --no-headers | grep -v Completed | wc -l | tr -d ' ')
[ "$NOT_RUNNING" = "0" ] && echo "PASS ($RUNNING pods)" || echo "FAIL ($NOT_RUNNING not running)"

echo -n "[2] Health endpoint: "
STATUS=$(curl -s http://localhost:8080/api/v1/health | jq -r .status 2>/dev/null)
[ "$STATUS" = "ok" ] && echo "PASS" || echo "FAIL ($STATUS)"

echo -n "[3] Readiness: "
PG=$(curl -s http://localhost:8080/ready | jq -r .postgres 2>/dev/null)
NEO=$(curl -s http://localhost:8080/ready | jq -r .neo4j 2>/dev/null)
[ "$PG" = "ok" ] && [ "$NEO" = "ok" ] && echo "PASS" || echo "FAIL (pg=$PG neo4j=$NEO)"

echo -n "[4] Graph has data: "
NODES=$(curl -s -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  http://localhost:8080/api/v1/graph | jq '.nodes | length' 2>/dev/null)
[ "$NODES" -gt 0 ] 2>/dev/null && echo "PASS ($NODES nodes)" || echo "FAIL (0 nodes)"

echo -n "[5] Snapshots work: "
SNAP=$(curl -s -X POST \
  -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  -H "Content-Type: application/json" -d '{"label":"checklist"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id 2>/dev/null)
[ ${#SNAP} -gt 10 ] && echo "PASS ($SNAP)" || echo "FAIL"

echo -n "[6] Export works: "
EXP=$(curl -s -X POST \
  -H "X-Tenant-ID: default" -H "X-Cluster-ID: default" \
  -H "Content-Type: application/json" -d '{"format":"mermaid"}' \
  http://localhost:8080/api/v1/export | head -1)
[[ "$EXP" == *"flowchart"* ]] && echo "PASS" || echo "FAIL"

echo "=== DONE ==="
```

---

## Cleanup

```bash
kind delete cluster --name graphon-test
```
