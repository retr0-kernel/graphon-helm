# Troubleshooting

## Quick diagnostic

Run the validate script first — it checks everything automatically:

```bash
NAMESPACE=graphon RELEASE=graphon \
  bash <(curl -sSL https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/scripts/validate-install.sh)
```

Or from the cloned repo:
```bash
NAMESPACE=graphon RELEASE=graphon ./graphon-helm/scripts/validate-install.sh
```

---

## Backend won't start

**Symptom:** `graphon-backend` pod is `CrashLoopBackOff` or `Error`.

**Check logs:**
```bash
kubectl logs -n graphon -l app.kubernetes.io/component=backend --tail=50
```

**Common causes:**

### Neo4j not ready yet
```
ERROR cannot connect to Neo4j: dial tcp ...: connection refused
```
Neo4j takes 60–90 seconds to start. The backend startup probe gives it 60s. If Neo4j takes longer:
```yaml
# values.yaml
backend:
  startupProbe:
    failureThreshold: 24  # increase to 120s budget
```

### PostgreSQL migration fails
```
ERROR running migration: pq: permission denied
```
The database user needs CREATE TABLE privileges. If using external PostgreSQL:
```sql
GRANT ALL PRIVILEGES ON DATABASE graphon TO graphon;
```

### Environment variable missing
```
ERROR missing POSTGRES_DSN
```
Check that the secret exists:
```bash
kubectl get secret -n graphon graphon-postgresql -o yaml
```

---

## Graph is empty after installing

**The agent needs eBPF support and Linux ≥ 5.4.**

Check agent pods:
```bash
kubectl get pods -n graphon -l app.kubernetes.io/component=agent
kubectl logs -n graphon -l app.kubernetes.io/component=agent --tail=30
```

**Common issues:**

### Agent CrashLoopBackOff
```
failed to load eBPF program: operation not permitted
```
The node doesn't support eBPF or the pod isn't privileged. Ensure nodes are standard (not Fargate/Autopilot) and `agent.privileged=true`.

### Agent running but no events
The agent is capturing TCP connections. If your namespace has no services calling other services, the graph will be empty. Deploy the [demo app](../examples/demo-app/) to generate traffic.

### No agent pods on some nodes
Check node labels and tolerations:
```bash
kubectl describe daemonset -n graphon graphon-agent
kubectl get nodes -o wide
```

---

## UI shows "Cannot connect to backend"

**Check the backend URL the UI is configured with:**
```bash
kubectl get deployment -n graphon graphon-ui -o yaml | grep VITE_API_URL
```

If ingress is enabled, the UI needs to reach the API via the external URL:
```yaml
# values.yaml
ui:
  apiUrl: "https://api.graphon.example.com"
```

Without ingress, the UI reaches the backend via in-cluster DNS (`http://graphon-backend:8080`). Ensure the services are in the same namespace.

---

## /ready returns ready=false

```bash
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
curl http://localhost:8080/ready | jq .
```

| Check | Fix |
|---|---|
| `neo4j.ok: false` | Neo4j pod not ready yet. Wait or check Neo4j logs. |
| `postgres.ok: false` | PostgreSQL pod not ready yet. Check PVC is bound. |

---

## Ingress 502 Bad Gateway

**NGINX ingress:**
```bash
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=20
```

Ensure `backend.service.port` and `ui.service.port` in values match what the ingress is targeting.

**TLS cert not issuing:**
```bash
kubectl describe certificate -n graphon
kubectl describe certificaterequest -n graphon
```
cert-manager ClusterIssuer must exist and `certManagerIssuer` must match its name.

---

## Ownership not auto-detecting

1. Confirm labels exist on the pod:
```bash
kubectl get pod -n production my-pod -o jsonpath='{.metadata.labels}'
```

2. Confirm the agent has RBAC to read pods:
```bash
kubectl auth can-i get pods --as=system:serviceaccount:graphon:graphon-agent
```

3. Check agent logs for enrichment errors:
```bash
kubectl logs -n graphon -l app.kubernetes.io/component=agent | grep -i "owner\|enrich"
```

---

## Drift items not appearing

1. Seed the baseline first: `POST /api/v1/drift/seed`
2. Wait for the drift scanner to run (up to 10 minutes) or restart the backend to trigger immediately
3. Check review items: `GET /api/v1/review-items?type=DRIFT`

---

## Helm upgrade fails

```bash
helm upgrade graphon graphon/graphon -n graphon --reuse-values
```

If the upgrade fails due to immutable fields (e.g. StatefulSet labels), you may need to delete and recreate the StatefulSet (for Neo4j or PostgreSQL). **This will cause data loss on embedded databases — back up first.**

---

## Getting help

- GitHub Issues: https://github.com/retr0-kernel/graphon/issues
- Include: Kubernetes version, Helm chart version, `kubectl get pods -n graphon`, and logs from the failing component.
