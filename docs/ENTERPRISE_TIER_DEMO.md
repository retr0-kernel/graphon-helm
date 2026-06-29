# Graphon Enterprise Tier — Full Demo (Scratch to Done)

**Prereq:** Free tier demo complete (TOKEN, TID, CID variables set) OR run steps 0–2 from FREE_TIER_DEMO.md first.

---

## 0. Generate a demo Enterprise license key

```bash
cd graphon-backend/
go run ./cmd/keygen \
  --plan enterprise \
  --org "Acme Engineering" \
  --features multi-cluster,sso,rbac,scheduled-snapshots,github-app,gitlab-app,export-drawio,webhooks,audit-log \
  --clusters 10 --users 50 --retention-days 365 --expiry 90d \
  --out /tmp/graphon-demo.license

LICENSE_KEY=$(cat /tmp/graphon-demo.license)
echo "License: $LICENSE_KEY"
```

---

## 1. Apply the Enterprise license

```bash
curl -s -X POST http://localhost:8080/api/v1/license/key \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"$LICENSE_KEY\"}" | jq .
```

Expected:
```json
{
  "plan": "enterprise",
  "features": ["multi-cluster","sso","rbac","scheduled-snapshots","github-app","gitlab-app","export-drawio","webhooks","audit-log"],
  "limits": {"clusters":10,"users":50,"retention_days":365},
  "org_name": "Acme Engineering"
}
```

---

## 2. RBAC — prove roles are enforced

```bash
# Create a viewer key
VIEWER=$(curl -s -X POST http://localhost:8080/api/v1/auth/keys \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d '{"name":"alice-viewer","role":"viewer"}' | jq -r .token)

# Viewer CAN read the graph
curl -s \
  -H "X-API-Key: $VIEWER" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "http://localhost:8080/api/v1/graph" | jq '.nodes | length'
# → 7

# Viewer CANNOT create a snapshot (the demo moment)
curl -s -X POST \
  -H "X-API-Key: $VIEWER" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  -d '{"label":"test"}' \
  http://localhost:8080/api/v1/snapshots | jq .
# → {"error":"forbidden","required":"snapshot:write","your_role":"viewer"}

# Developer key — can update ownership, cannot capture snapshots
DEV=$(curl -s -X POST http://localhost:8080/api/v1/auth/keys \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d '{"name":"bob-developer","role":"developer"}' | jq -r .token)

curl -s -X PUT \
  -H "X-API-Key: $DEV" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  "http://localhost:8080/api/v1/services/orders/ownership" \
  -d '{"team":"orders-team","contact":"bob@acme.io"}' | jq .status
# → "ok"
```

Role matrix:
```
viewer        read graph only
developer     read graph + write ownership
manager       + capture snapshots
platform-admin  + manage clusters
admin         everything + manage users
agent         ingest events only
```

---

## 3. OIDC / SSO (configure before demo if IdP available)

```bash
kubectl set env deploy/graphon-backend -n graphon \
  OIDC_ENABLED=true \
  OIDC_ISSUER_URL=https://accounts.google.com \
  OIDC_CLIENT_ID="YOUR_CLIENT_ID.apps.googleusercontent.com" \
  OIDC_CLIENT_SECRET="GOCSPX-..." \
  OIDC_REDIRECT_URL="http://localhost:8080/auth/callback" \
  OIDC_SCOPES="openid,email,profile,groups" \
  OIDC_GROUP_ROLE_MAPPING="platform-eng:admin,developers:developer,read-only:viewer" \
  RBAC_ENABLED=true \
  RBAC_DEFAULT_ROLE=viewer

kubectl rollout status deploy/graphon-backend -n graphon

# Confirm SSO redirect works
curl -v http://localhost:8080/auth/login 2>&1 | grep "Location:"
# → Location: https://accounts.google.com/o/oauth2/auth?...
```

---

## 4. Scheduled snapshots

```bash
# Confirm scheduler is running
kubectl logs -n graphon deploy/graphon-backend --since=5m | grep -i "scheduler\|snapshot"
# → level=INFO msg="scheduler started" snapshot_interval=6h0m0s

# Trigger a manual snapshot with scheduled label to show it in the list
curl -s -X POST \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  -d '{"label":"scheduled-demo","trigger":"scheduled"}' \
  http://localhost:8080/api/v1/snapshots | jq '{id:.id,trigger:.trigger,label:.label}'

# Show retention is now 365 days (vs 30 on Free)
curl -s -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" \
  http://localhost:8080/api/v1/license | jq .limits.retention_days
# → 365
```

---

## 5. GitHub webhook — PR impact comment

```bash
# Set credentials (run ahead of demo)
kubectl set env deploy/graphon-backend -n graphon \
  GITHUB_TOKEN="ghp_your_pat" \
  GITHUB_WEBHOOK_SECRET="demo-secret"

kubectl rollout status deploy/graphon-backend -n graphon

# Simulate a PR open event
BODY='{"action":"opened","number":42,"pull_request":{"title":"feat: remove notifications"},"repository":{"full_name":"acme-org/platform"}}'
SIG=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "demo-secret" | awk '{print $2}')

curl -s -X POST http://localhost:8080/api/v1/webhooks \
  -H "X-GitHub-Event: pull_request" \
  -H "X-Hub-Signature-256: sha256=$SIG" \
  -H "Content-Type: application/json" \
  -d "$BODY" | jq .
# → {"status":"ok"}

# See the backend log — it computed blast radius and posted to GitHub
kubectl logs -n graphon deploy/graphon-backend --since=1m | grep -i "webhook\|comment"
```

---

## 6. GitLab webhook — MR impact note

```bash
kubectl set env deploy/graphon-backend -n graphon \
  GITLAB_TOKEN="glpat_your_token" \
  GITLAB_WEBHOOK_SECRET="demo-secret-gl" \
  GITLAB_INSTANCE_URL="https://gitlab.com"

kubectl rollout status deploy/graphon-backend -n graphon

curl -s -X POST http://localhost:8080/api/v1/webhooks \
  -H "X-Gitlab-Event: Merge Request Hook" \
  -H "X-Gitlab-Token: demo-secret-gl" \
  -H "Content-Type: application/json" \
  -d '{
    "object_kind":"merge_request",
    "object_attributes":{"iid":15,"state":"opened","title":"refactor: consolidate payments"},
    "project":{"path_with_namespace":"acme-org/api"}
  }' | jq .
```

---

## 7. Draw.io export (Enterprise-only)

```bash
curl -s -X POST \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  -d '{"format":"drawio"}' \
  http://localhost:8080/api/v1/export > /tmp/graphon-arch.xml

head -3 /tmp/graphon-arch.xml
# → <?xml version="1.0"...<mxGraphModel>...
```

Open `/tmp/graphon-arch.xml` at [app.diagrams.net](https://app.diagrams.net) — full editable diagram.

---

## 8. Multi-cluster

```bash
# Register a second cluster
curl -s -X POST http://localhost:8080/api/v1/clusters/register \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d '{"id":"eks-prod","name":"Production EKS","tenant_id":"acme","region":"us-east-1"}' | jq .

# List all clusters
curl -s http://localhost:8080/api/v1/clusters \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" | jq '{total:.total, clusters:[.clusters[]|{id:.id,name:.name}]}'
# → {"total":2,"clusters":[{"id":"k8s-demo","name":"Demo Cluster"},{"id":"eks-prod","name":"Production EKS"}]}
```

---

## Pre-demo health check

```bash
echo "=== ENTERPRISE PREFLIGHT ==="
echo -n "[health]       "; curl -s http://localhost:8080/api/v1/health | jq -r .status
echo -n "[plan]         "; curl -s -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" \
  http://localhost:8080/api/v1/license | jq -r .plan
echo -n "[rbac]         "
RBAC=$(curl -s -X POST -H "X-API-Key: $VIEWER" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"label":"t"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .error 2>/dev/null)
[ "$RBAC" = "forbidden" ] && echo "ok (viewer correctly blocked)" || echo "FAIL"
echo -n "[graph]        "; curl -s -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  http://localhost:8080/api/v1/graph | jq '.nodes | length'
echo -n "[drawio]       "; curl -s -X POST -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"format":"drawio"}' \
  http://localhost:8080/api/v1/export | grep -q "mxGraphModel" && echo "ok" || echo "FAIL"
echo -n "[retention]    "; curl -s -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: $TID" \
  http://localhost:8080/api/v1/license | jq .limits.retention_days
echo "=== DONE ==="
```

---

## Enterprise vs Free — quick reference

| | Free | Enterprise |
|---|---|---|
| Graph + ownership + drift | ✓ | ✓ |
| Manual snapshots | ✓ | ✓ |
| Mermaid/DOT/SVG export | ✓ | ✓ |
| **RBAC (6 roles)** | ✗ | ✓ |
| **OIDC/SSO** | ✗ | ✓ |
| **Scheduled snapshots (6h)** | ✗ | ✓ |
| **Snapshot retention** | 30 days | 365 days |
| **GitHub/GitLab webhooks** | ✗ | ✓ |
| **Draw.io export** | ✗ | ✓ |
| **Multi-cluster** | ✗ | ✓ (10) |
| **Audit log** | ✗ | ✓ |
| Users | 3 | 50 |
