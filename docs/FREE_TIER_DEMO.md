# Graphon Free Tier — Full Demo

**Prereq:** Graphon deployed (`helm upgrade --install graphon . --namespace graphon --create-namespace --set backend.authDisabled=true --wait`), port-forward open.

```bash
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
kubectl port-forward -n graphon svc/graphon-ui 3000:80 &
```

**All tenant/cluster IDs** — the agent sends `TENANT_ID=default` and uses the node name as cluster ID. Match that in every call:

```bash
TID="default"
CID=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
echo "Using: TID=$TID  CID=$CID"
```

> No API key needed when `authDisabled=true`. Just use the two headers above.

---

## 0. Health check

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

## 1. Fix UI proxy (one-time — needed because VITE_API_URL is baked at build time)

```bash
kubectl create configmap graphon-ui-nginx -n graphon --from-literal=default.conf='
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y; add_header Cache-Control "public, immutable"; try_files $uri =404;
    }
    location /api/ {
        proxy_pass http://graphon-backend:8080/api/;
        proxy_set_header Host $host;
        proxy_read_timeout 30s;
    }
    location / { try_files $uri $uri/ /index.html; add_header Cache-Control "no-cache"; }
    location /healthz { return 200 "ok\n"; add_header Content-Type text/plain; }
}
' --dry-run=client -o yaml | kubectl apply -f -

kubectl patch deployment graphon-ui -n graphon --type=json -p='[
  {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"nginx-cfg","configMap":{"name":"graphon-ui-nginx"}}]},
  {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"nginx-cfg","mountPath":"/etc/nginx/conf.d","readOnly":true}]}
]'

kubectl rollout status deployment/graphon-ui -n graphon
```

Open: **http://localhost:3000**

---

## 2. Live graph — all 3 namespaces

```bash
curl -s \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/graph" | jq '{
    nodes: (.nodes | length),
    edges: (.edges | length),
    namespaces: ([.nodes[].namespace] | unique)
  }'
```

Expected:
```json
{"nodes":7,"edges":6,"namespaces":["demo-api","demo-data","demo-web"]}
```

**Namespace filter:**
```bash
curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/graph?namespace=demo-api" | \
  jq '{nodes:[.nodes[].id], edges:[.edges[]|"\(.source) → \(.target)"]}'
```

**All edges:**
```bash
curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/graph" | jq '[.edges[]|"\(.source) → \(.target)"]'
```

---

## 3. Ownership

```bash
curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/ownership" | \
  jq '[.[]|{service:.node_id,team:.team,contact:.contact}]'
```

---

## 4. Safe-delete analysis

```bash
# gateway — has dependents (not safe)
curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/services/gateway/safe-delete" | jq .

# payments — leaf node (safe)
curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/services/payments/safe-delete" | jq .
```

---

## 5. Snapshots + diff

```bash
SNAP1=$(curl -s -X POST \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  -d '{"label":"before-incident","trigger":"manual"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id)
echo "Snap1: $SNAP1"

kubectl scale deployment notifications -n demo-data --replicas=0
sleep 90

SNAP2=$(curl -s -X POST \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  -d '{"label":"after-notifications-down","trigger":"manual"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id)
echo "Snap2: $SNAP2"

curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/snapshots/diff?from=$SNAP1&to=$SNAP2" | jq .

kubectl scale deployment notifications -n demo-data --replicas=1
```

---

## 6. Drift detection

```bash
curl -s -X POST -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  http://localhost:8080/api/v1/drift/seed | jq .

kubectl run drift-actor --image=busybox:1.36 --namespace=demo-api --restart=Never \
  -- sh -c "while true; do wget -q -O /dev/null http://payments.demo-api.svc.cluster.local/health; sleep 3; done"

sleep 90

curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/review-items?item_type=DRIFT" | jq '{drift_count:.total}'

kubectl delete pod drift-actor -n demo-api
```

---

## 7. Search

```bash
curl -s -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/search?q=orders" | jq .
```

---

## 8. Export

```bash
# Mermaid — paste into mermaid.live
curl -s -X POST -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"format":"mermaid"}' \
  http://localhost:8080/api/v1/export

# DOT — paste into graphviz.online
curl -s -X POST -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"format":"dot"}' \
  http://localhost:8080/api/v1/export
```

---

## Pre-demo preflight (run 5 min before going live)

```bash
./scripts/free-tier-test.sh
```

Next: [ENTERPRISE_TIER_DEMO.md](./ENTERPRISE_TIER_DEMO.md)
