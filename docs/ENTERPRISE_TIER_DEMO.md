# Graphon Enterprise Tier — Customer Demo Walkthrough

**Plan:** Enterprise Self-Hosted (Annual License, RSA-JWT)  
**Audience:** Engineering manager, platform lead, or security team evaluating Enterprise features  
**Prereq:** Free tier demo complete OR setup from [DEMO_OVERVIEW.md](./DEMO_OVERVIEW.md)  
**Time:** ~25 minutes (standalone) or ~20 minutes (after Free tier demo)

> **Demo tip:** Enterprise features are unlocked by a JWT signed with an RSA private key.
> Generate a demo license key ahead of time using the keygen tool.

---

## Pre-Demo: Generate an Enterprise License Key

```bash
# From the graphon-backend directory
cd graphon-backend/

# Generate a 90-day enterprise license for the demo
go run ./cmd/keygen \
  --plan enterprise \
  --org "Acme Engineering" \
  --features multi-cluster,sso,rbac,scheduled-snapshots,github-app,gitlab-app,export-drawio,webhooks,audit-log \
  --clusters 10 \
  --users 50 \
  --retention-days 365 \
  --expiry 90d \
  --out /tmp/graphon-demo.license

cat /tmp/graphon-demo.license
# eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

Save the token:
```bash
LICENSE_KEY=$(cat /tmp/graphon-demo.license)
TOKEN="gph_xxxxxxxxxxxxxxxxxx"   # admin API key from Free tier demo (or create a new one)
```

---

## Step 1 — Apply the Enterprise License

> **What to say:** "Enterprise is activated by a single API call — or via a Helm value.
> The key is verified locally using RSA. No internet connection required. No license server."

```bash
curl -s -X POST http://localhost:8080/api/v1/license/key \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"$LICENSE_KEY\"}" | jq .
```

**Expected:**
```json
{
  "plan": "enterprise",
  "features": [
    "multi-cluster","sso","rbac","scheduled-snapshots",
    "github-app","gitlab-app","export-drawio","webhooks","audit-log"
  ],
  "limits": {
    "clusters": 10,
    "users": 50,
    "retention_days": 365,
    "snapshot_count": 0
  },
  "org_name": "Acme Engineering",
  "expiry": "2026-09-28T00:00:00Z"
}
```

> **What to say:** "The license is a JWT. It carries the plan name, the exact feature list,
> and numeric limits. If it expires, the system automatically falls back to the Free tier
> after a 14-day grace period — nothing breaks immediately."

---

## Step 2 — RBAC: Role-Based Access Control

> **What to say:** "In Enterprise, every API key has a role. A viewer can read the graph but
> cannot capture snapshots or modify ownership. Let's prove it."

### 2a. Create a viewer key

```bash
VIEWER_TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/keys \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "Content-Type: application/json" \
  -d '{"name":"alice-viewer","role":"viewer"}' | jq -r .token)

echo "Viewer token: $VIEWER_TOKEN"
```

### 2b. Viewer CAN read the graph

```bash
curl -s \
  -H "X-API-Key: $VIEWER_TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  "http://localhost:8080/api/v1/graph" | jq '{nodes: (.nodes | length)}'
```
**Expected:** `{"nodes": 7}` — read succeeds.

### 2c. Viewer CANNOT capture a snapshot

```bash
curl -s -X POST \
  -H "X-API-Key: $VIEWER_TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  -d '{"label":"test"}' \
  http://localhost:8080/api/v1/snapshots | jq .
```

**Expected — this is the demo moment:**
```json
{
  "error": "forbidden",
  "required": "snapshot:write",
  "your_role": "viewer",
  "upgrade_url": "https://graphon.io/pricing"
}
```

### 2d. Create a developer key — can write ownership but not snapshots

```bash
DEV_TOKEN=$(curl -s -X POST http://localhost:8080/api/v1/auth/keys \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "Content-Type: application/json" \
  -d '{"name":"bob-developer","role":"developer"}' | jq -r .token)

# Developer CAN write ownership
curl -s -X PUT \
  -H "X-API-Key: $DEV_TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  "http://localhost:8080/api/v1/services/orders/ownership" \
  -d '{"team":"orders-team","contact":"bob@acme.io","service_type":"api"}' | jq .status
```

**Expected:** `"ok"` — developer role has `ownership:write` permission.

### 2e. Roles summary for the audience

| Role | Can read graph | Can capture snapshots | Can manage clusters | Can manage users |
|---|---|---|---|---|
| viewer | ✓ | ✗ | ✗ | ✗ |
| developer | ✓ | ✗ | ✗ | ✗ |
| manager | ✓ | ✓ | ✗ | ✗ |
| platform-admin | ✓ | ✓ | ✓ | ✗ |
| admin | ✓ | ✓ | ✓ | ✓ |
| agent | events only | ✗ | ✗ | ✗ |

---

## Step 3 — OIDC / SSO Setup (Optional Live Demo)

> **When to run this:** Only if the audience has an identity provider configured
> (Google Workspace, Okta, Azure AD, Keycloak). Otherwise describe it and skip to Step 4.

```bash
# Enable OIDC (example with Google Workspace)
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

# Wait for the backend to restart
kubectl rollout status deploy/graphon-backend -n graphon

# Hit the login endpoint — should redirect to the identity provider
curl -v http://localhost:8080/auth/login 2>&1 | grep "Location:"
```

**Expected:**
```
< Location: https://accounts.google.com/o/oauth2/auth?client_id=...&state=<csrf-token>
```

> **What to say:** "Once configured, users log in via their existing SSO. Their group membership
> in the identity provider maps directly to Graphon roles — no manual provisioning.
> A user in the `platform-eng` group instantly has admin rights."

---

## Step 4 — Scheduled Snapshots

> **What to say:** "On Enterprise, the backend automatically captures a graph snapshot
> every 6 hours. You get a full 12-month rolling history without anyone remembering
> to click a button."

```bash
# Confirm the scheduler is running (look for scheduled snapshot log lines)
kubectl logs -n graphon \
  $(kubectl get pods -n graphon -l app.kubernetes.io/component=backend -o name | head -1) \
  --since=5m | grep -i "snapshot\|scheduler"
```

**Expected log lines:**
```
level=INFO msg="scheduler started" snapshot_interval=6h0m0s
level=INFO msg="scheduled snapshot captured" component=scheduler tenant_id=acme cluster_id=kind-demo
```

> If you just deployed, the first scheduled snapshot fires 6 hours after startup.
> For the demo, you can trigger a manual one with `trigger:"scheduled"` to show the label:

```bash
curl -s -X POST \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  -d '{"label":"scheduled-demo","trigger":"scheduled"}' \
  http://localhost:8080/api/v1/snapshots | jq '{id: .id, trigger: .trigger, label: .label}'
```

**Expected:**
```json
{"id":"snap-xxxx","trigger":"scheduled","label":"scheduled-demo"}
```

```bash
# Show snapshot retention — Enterprise gets 365 days (as per license)
curl -s http://localhost:8080/api/v1/license \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" | jq .limits.retention_days
```

**Expected:** `365` (vs `30` on Free tier)

---

## Step 5 — GitHub Webhook: PR Impact Analysis

> **What to say:** "When a developer opens a PR, Graphon automatically runs a blast-radius
> analysis against the live graph and posts the result as a PR comment — before the code
> is merged."

### Setup (run ahead of demo)

```bash
# Set the GitHub token and webhook secret
kubectl set env deploy/graphon-backend -n graphon \
  GITHUB_TOKEN="ghp_your_pat_with_repo_write_access" \
  GITHUB_WEBHOOK_SECRET="demo-secret-change-me"

kubectl rollout status deploy/graphon-backend -n graphon
```

### Simulate a GitHub PR webhook payload

```bash
# Compute HMAC-SHA256 signature for the payload
BODY='{"action":"opened","number":42,"pull_request":{"title":"feat: remove notifications coupling"},"repository":{"full_name":"acme-org/platform"}}'
SIG=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "demo-secret-change-me" | awk '{print $2}')

curl -s -X POST http://localhost:8080/api/v1/webhooks \
  -H "X-GitHub-Event: pull_request" \
  -H "X-Hub-Signature-256: sha256=$SIG" \
  -H "Content-Type: application/json" \
  -d "$BODY" | jq .
```

**Expected:**
```json
{"status":"ok"}
```

Check the backend logs for the impact analysis:
```bash
kubectl logs -n graphon \
  $(kubectl get pods -n graphon -l app.kubernetes.io/component=backend -o name | head -1) \
  --since=1m | grep -i "webhook\|impact\|PR\|comment"
```

**Expected log lines:**
```
level=INFO msg="webhook: github PR event" pr=42 repo=acme-org/platform action=opened
level=INFO msg="webhook: posted GitHub PR comment" repo=acme-org/platform pr=42
```

> **What to say:** "The comment Graphon posts on the PR shows exactly which services are
> downstream of the changed code — calculated from the live graph, not from static analysis."

---

## Step 6 — GitLab Webhook: MR Impact Analysis

```bash
# Setup (run ahead of demo)
kubectl set env deploy/graphon-backend -n graphon \
  GITLAB_TOKEN="glpat_your_token" \
  GITLAB_WEBHOOK_SECRET="demo-secret-gl" \
  GITLAB_INSTANCE_URL="https://gitlab.com"

# Simulate a GitLab MR webhook
curl -s -X POST http://localhost:8080/api/v1/webhooks \
  -H "X-Gitlab-Event: Merge Request Hook" \
  -H "X-Gitlab-Token: demo-secret-gl" \
  -H "Content-Type: application/json" \
  -d '{
    "object_kind":"merge_request",
    "object_attributes":{
      "iid":15,
      "state":"opened",
      "title":"refactor: consolidate payments logic"
    },
    "project":{"path_with_namespace":"acme-org/api"}
  }' | jq .
```

**Expected:** `{"status":"ok"}` — MR comment posted to GitLab if token is valid.

---

## Step 7 — Draw.io Export (Enterprise-Only Format)

> **What to say:** "Free tier gives you Mermaid, DOT, and SVG. Enterprise adds Draw.io —
> the format architects actually use in Confluence and Notion."

```bash
curl -s -X POST \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" \
  -d '{"format":"drawio"}' \
  http://localhost:8080/api/v1/export > /tmp/graphon-arch.xml

head -5 /tmp/graphon-arch.xml
```

**Expected:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/>
```

Open `/tmp/graphon-arch.xml` in [draw.io](https://app.diagrams.net/) — it opens as an
interactive editable diagram showing all services and connections.

---

## Step 8 — Multi-Cluster Registration

> **What to say:** "Enterprise supports multiple clusters under a single tenant.
> Platform teams can see all their clusters — production, staging, preview — from
> one pane of glass."

```bash
# Register a second cluster (simulate a prod cluster)
curl -s -X POST http://localhost:8080/api/v1/clusters/register \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" \
  -H "Content-Type: application/json" \
  -d '{"id":"eks-prod","name":"Production EKS","tenant_id":"acme","region":"us-east-1"}' | jq .

# List all clusters for this tenant
curl -s http://localhost:8080/api/v1/clusters \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" | jq '{total: .total, clusters: [.clusters[] | {id: .id, name: .name, region: .region}]}'
```

**Expected:**
```json
{
  "total": 2,
  "clusters": [
    {"id":"kind-demo","name":"Kind Demo Cluster","region":"local"},
    {"id":"eks-prod","name":"Production EKS","region":"us-east-1"}
  ]
}
```

> **What to say:** "Each cluster has its own isolated graph. The UI lets you switch between
> clusters from the sidebar. The eBPF agent just needs the cluster ID in its config —
> everything else is automatic."

---

## Step 9 — Verify the License Expiry Safety Net

> **What to say:** "If an Enterprise license expires, the system doesn't crash.
> It enters a 14-day grace period and then falls back to Free tier functionality."

```bash
# Show current license status
curl -s http://localhost:8080/api/v1/license \
  -H "X-API-Key: $TOKEN" \
  -H "X-Tenant-ID: acme" | jq '{plan: .plan, expires: .expiry, features: (.features | length)}'
```

> To demonstrate the fallback: apply an already-expired JWT and show the plan returns to `"free"`.
> (Skip in a customer demo — describe it verbally.)

---

## Step 10 — Enterprise Pre-Demo Checklist

Run this before any Enterprise demo:

```bash
echo "=== GRAPHON ENTERPRISE — PRE-DEMO CHECKLIST ==="

echo -n "[1] Backend health:         "
STATUS=$(curl -s http://localhost:8080/api/v1/health | jq -r .status 2>/dev/null)
[ "$STATUS" = "ok" ] && echo "PASS" || echo "FAIL"

echo -n "[2] Enterprise plan active: "
PLAN=$(curl -s http://localhost:8080/api/v1/license \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" | jq -r .plan 2>/dev/null)
[ "$PLAN" = "enterprise" ] && echo "PASS ($PLAN)" || echo "FAIL (plan=$PLAN — apply license key first)"

echo -n "[3] RBAC enforced:          "
RBAC=$(curl -s -X POST \
  -H "X-API-Key: $VIEWER_TOKEN" -H "X-Tenant-ID: acme" -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" -d '{"label":"rbac-test"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .error 2>/dev/null)
[ "$RBAC" = "forbidden" ] && echo "PASS (viewer correctly denied)" || echo "FAIL (RBAC not enforced)"

echo -n "[4] Graph has data:         "
NODES=$(curl -s -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" -H "X-Cluster-ID: kind-demo" \
  http://localhost:8080/api/v1/graph | jq '.nodes | length' 2>/dev/null)
[ "${NODES:-0}" -ge 7 ] && echo "PASS ($NODES nodes)" || echo "WARN ($NODES nodes)"

echo -n "[5] Snapshot (365d):        "
SNAP=$(curl -s -X POST -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" -d '{"label":"preflight"}' \
  http://localhost:8080/api/v1/snapshots | jq -r .id 2>/dev/null)
[ ${#SNAP} -gt 5 ] && echo "PASS ($SNAP)" || echo "FAIL"

echo -n "[6] Draw.io export:         "
DRAWIO=$(curl -s -X POST -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" -H "X-Cluster-ID: kind-demo" \
  -H "Content-Type: application/json" -d '{"format":"drawio"}' \
  http://localhost:8080/api/v1/export | head -1)
[[ "$DRAWIO" == *"mxGraphModel"* ]] && echo "PASS" || echo "FAIL"

echo -n "[7] Multi-cluster:          "
CLUSTERS=$(curl -s http://localhost:8080/api/v1/clusters \
  -H "X-API-Key: $TOKEN" -H "X-Tenant-ID: acme" | jq .total 2>/dev/null)
[ "${CLUSTERS:-0}" -ge 2 ] && echo "PASS ($CLUSTERS clusters)" || echo "WARN ($CLUSTERS cluster)"

echo "=== ALL CHECKS DONE ==="
```

---

## Enterprise Tier — What's Included vs Free

| Capability | Free | Enterprise |
|---|---|---|
| Live dependency graph | ✓ | ✓ |
| Ownership + safe-delete | ✓ | ✓ |
| Drift detection | ✓ | ✓ |
| Manual snapshots | ✓ | ✓ |
| Mermaid/DOT/SVG export | ✓ | ✓ |
| Slack alerts | ✓ | ✓ |
| REST API | ✓ | ✓ |
| **OIDC/SSO** | ✗ | ✓ |
| **RBAC (6 roles)** | ✗ | ✓ |
| **Scheduled snapshots (6h)** | ✗ | ✓ |
| **Snapshot retention** | 30 days | 365 days |
| **GitHub PR impact comments** | ✗ | ✓ |
| **GitLab MR impact notes** | ✗ | ✓ |
| **Draw.io export** | ✗ | ✓ |
| **Multi-cluster** | ✗ | ✓ (10 in demo) |
| **Audit log** | ✗ | ✓ |
| **Users** | 3 | 50 (in demo) |
| **Support** | Community | Priority |

---

## Closing Line for Enterprise Demo

> "Everything you just saw — RBAC, SSO, automated snapshots with 365-day history,
> GitHub/GitLab integration, and Draw.io export — runs entirely in your cluster.
> Your architecture data never leaves your environment.
>
> The Enterprise license is a single JWT you apply with one API call. No agents to
> update, no cloud dependency, no vendor lock-in.
>
> When you're ready to move to a fully managed backend where you don't have to run
> Neo4j and PostgreSQL yourself, Graphon Cloud is on the roadmap — and your data
> migrates with you."

---

## Cleanup

```bash
# Remove demo namespaces
kubectl delete -f graphon-helm/examples/demo-app-multi-ns/

# Remove the kind cluster entirely
kind delete cluster --name graphon-demo
```
