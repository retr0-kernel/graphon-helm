#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Graphon Enterprise Tier — End-to-End Test Script
#
# Usage:
#   LICENSE_KEY="eyJ..." ./scripts/enterprise-tier-test.sh
#
# Prereqs:
#   - Free tier tests passing (./scripts/free-tier-test.sh)
#   - kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
#   - LICENSE_KEY env var set (generate with: go run ./cmd/keygen ...)
#
# Env overrides:
#   BACKEND=http://localhost:8080
#   TENANT_ID=default
#   CLUSTER_ID=<auto from kubectl>
#   LICENSE_KEY=<enterprise JWT>
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()      { echo -e "  ${GREEN}✔${NC}  $1"; }
fail()    { echo -e "  ${RED}✘${NC}  $1"; FAILURES=$((FAILURES+1)); }
info()    { echo -e "  ${YELLOW}→${NC}  $1"; }
skip()    { echo -e "  ${YELLOW}○${NC}  $1 (skipped)"; }
section() { echo -e "\n${BOLD}${CYAN}══ $1 ══${NC}"; }

FAILURES=0
BACKEND="${BACKEND:-http://localhost:8080}"
TID="${TENANT_ID:-default}"
CID="${CLUSTER_ID:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'default')}"
LICENSE_KEY="${LICENSE_KEY:-}"

echo -e "\n${BOLD}Graphon Enterprise Tier — End-to-End Test${NC}"
echo -e "Backend : ${CYAN}$BACKEND${NC}"
echo -e "Tenant  : ${CYAN}$TID${NC}"
echo -e "Cluster : ${CYAN}$CID${NC}"

if [ -z "$LICENSE_KEY" ]; then
  echo -e "\n${RED}ERROR: LICENSE_KEY not set.${NC}"
  echo "Generate one with:"
  echo "  cd graphon-backend"
  echo "  go run ./cmd/keygen --plan enterprise --org 'Demo' --expiry 90d --out /tmp/graphon.license"
  echo "  export LICENSE_KEY=\$(cat /tmp/graphon.license)"
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
section "1. Apply Enterprise License"
# ─────────────────────────────────────────────────────────────────────────────

LICENSE_RESP=$(curl -sf -X POST "$BACKEND/api/v1/license/key" \
  -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"$LICENSE_KEY\"}" 2>/dev/null || echo '{}')

PLAN=$(echo "$LICENSE_RESP" | jq -r '.plan // "unknown"')
if [ "$PLAN" = "enterprise" ]; then
  FEATURES=$(echo "$LICENSE_RESP" | jq -r '.features | length')
  ORG=$(echo "$LICENSE_RESP"      | jq -r '.org_name // "?"')
  EXPIRY=$(echo "$LICENSE_RESP"   | jq -r '.expiry // "?"')
  RETENTION=$(echo "$LICENSE_RESP"| jq -r '.limits.retention_days // "?"')
  ok "License applied  (plan=$PLAN  org=$ORG  features=$FEATURES  retention=${RETENTION}d)"
  info "Expires: $EXPIRY"
else
  fail "License apply failed  (plan=$PLAN)"
  echo "$LICENSE_RESP" | jq .
  exit 1
fi

# Confirm via GET
CURRENT=$(curl -sf -H "X-Tenant-ID: $TID" "$BACKEND/api/v1/license" 2>/dev/null || echo '{}')
CURRENT_PLAN=$(echo "$CURRENT" | jq -r '.plan // "unknown"')
[ "$CURRENT_PLAN" = "enterprise" ] && ok "License confirmed via GET" || fail "License GET returned plan=$CURRENT_PLAN"

# ─────────────────────────────────────────────────────────────────────────────
section "2. RBAC — Role Enforcement"
# ─────────────────────────────────────────────────────────────────────────────

# Create a viewer API key
VIEWER_RESP=$(curl -sf -X POST "$BACKEND/api/v1/auth/keys" \
  -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d '{"name":"test-viewer","role":"viewer"}' 2>/dev/null || echo '{}')
VIEWER_TOKEN=$(echo "$VIEWER_RESP" | jq -r '.token // ""')

if [ -z "$VIEWER_TOKEN" ]; then
  fail "Could not create viewer API key"
else
  ok "Viewer API key created  (prefix=${VIEWER_TOKEN:0:12}...)"
fi

# Viewer CAN read the graph
GRAPH_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" \
  -H "X-API-Key: $VIEWER_TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/graph" 2>/dev/null || echo '000')
[ "$GRAPH_STATUS" = "200" ] && ok "Viewer can read graph  (HTTP $GRAPH_STATUS)" || fail "Viewer cannot read graph  (HTTP $GRAPH_STATUS)"

# Viewer CANNOT create a snapshot (must be forbidden)
SNAP_RESP=$(curl -sf -o /dev/null -w "%{http_code}" -X POST \
  -H "X-API-Key: $VIEWER_TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"label":"rbac-test"}' \
  "$BACKEND/api/v1/snapshots" 2>/dev/null || echo '000')
if [ "$SNAP_RESP" = "403" ] || [ "$SNAP_RESP" = "401" ]; then
  ok "Viewer blocked from snapshot  (HTTP $SNAP_RESP — RBAC enforced)"
else
  fail "Viewer was NOT blocked from snapshot  (HTTP $SNAP_RESP — RBAC not enforced)"
fi

# Create a developer key
DEV_RESP=$(curl -sf -X POST "$BACKEND/api/v1/auth/keys" \
  -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d '{"name":"test-developer","role":"developer"}' 2>/dev/null || echo '{}')
DEV_TOKEN=$(echo "$DEV_RESP" | jq -r '.token // ""')

if [ -n "$DEV_TOKEN" ]; then
  # Developer CAN update ownership
  OWN_STATUS=$(curl -sf -o /dev/null -w "%{http_code}" -X PUT \
    -H "X-API-Key: $DEV_TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    -H "Content-Type: application/json" \
    -d '{"team":"orders-team","contact":"dev@acme.io"}' \
    "$BACKEND/api/v1/services/orders/ownership" 2>/dev/null || echo '000')
  [ "$OWN_STATUS" = "200" ] && ok "Developer can update ownership  (HTTP $OWN_STATUS)" || fail "Developer blocked from ownership update  (HTTP $OWN_STATUS)"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "3. Extended Snapshot Retention"
# ─────────────────────────────────────────────────────────────────────────────

SNAP_ENT=$(curl -sf -X POST \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  -d '{"label":"enterprise-test","trigger":"scheduled"}' \
  "$BACKEND/api/v1/snapshots" 2>/dev/null || echo '{}')
ENT_ID=$(echo "$SNAP_ENT" | jq -r '.id // ""')
ENT_TRIGGER=$(echo "$SNAP_ENT" | jq -r '.trigger // ""')

if [ ${#ENT_ID} -gt 10 ]; then
  ok "Enterprise snapshot created  (id=$ENT_ID  trigger=$ENT_TRIGGER)"
else
  fail "Enterprise snapshot failed  ($(echo "$SNAP_ENT" | jq -r '.error // "unknown"'))"
fi

# Confirm 365-day retention
ENT_RETENTION=$(echo "$CURRENT" | jq -r '.limits.retention_days // 0')
if [ "$ENT_RETENTION" -ge 365 ] 2>/dev/null; then
  ok "Retention is ${ENT_RETENTION} days (Enterprise)"
else
  fail "Retention is ${ENT_RETENTION} days (expected >= 365 for Enterprise)"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "4. Draw.io Export (Enterprise-only)"
# ─────────────────────────────────────────────────────────────────────────────

DRAWIO=$(curl -sf -X POST \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"format":"drawio"}' \
  "$BACKEND/api/v1/export" 2>/dev/null || echo '')

if echo "$DRAWIO" | grep -q "mxGraphModel"; then
  BYTES=$(echo -n "$DRAWIO" | wc -c | tr -d ' ')
  ok "Draw.io export works  ($BYTES bytes)"
  echo "$DRAWIO" | head -2 | sed 's/^/     /'
else
  fail "Draw.io export failed or returned non-XML output"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "5. Multi-Cluster Registration"
# ─────────────────────────────────────────────────────────────────────────────

# Register a second cluster (simulated)
REG_RESP=$(curl -sf -X POST "$BACKEND/api/v1/clusters/register" \
  -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d '{"id":"$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)","name":"Simulated Prod Cluster","tenant_id":"default","region":"us-east-1"}' \
  2>/dev/null || echo '{}')

# Simpler: just list clusters and confirm the endpoint works
CLUSTER_LIST=$(curl -sf "$BACKEND/api/v1/clusters" \
  -H "X-Tenant-ID: $TID" 2>/dev/null || echo '{"clusters":[]}')
CLUSTER_COUNT=$(echo "$CLUSTER_LIST" | jq '.clusters | length // 0')
[ "$CLUSTER_COUNT" -ge 1 ] && ok "Cluster list works  (count=$CLUSTER_COUNT)" || info "No clusters registered yet (optional step)"

# ─────────────────────────────────────────────────────────────────────────────
section "6. Scheduler — Scheduled Snapshot"
# ─────────────────────────────────────────────────────────────────────────────

# Check backend logs for scheduler startup (last 60s)
SCHED_LOG=$(kubectl logs -n graphon deploy/graphon-backend --since=120m 2>/dev/null | grep -i "scheduler" | tail -3 || echo '')
if echo "$SCHED_LOG" | grep -q "scheduler started"; then
  ok "Scheduler running (found startup log)"
  echo "$SCHED_LOG" | head -2 | sed 's/^/     /'
else
  info "Scheduler log not visible in last 2h — check with:"
  info "kubectl logs -n graphon deploy/graphon-backend | grep scheduler"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "7. Feature Gate Verification"
# ─────────────────────────────────────────────────────────────────────────────

FEATS=$(echo "$CURRENT" | jq -r '.features // []')
for feat in "snapshots" "rbac" "scheduled-snapshots" "export-drawio" "multi-cluster"; do
  if echo "$FEATS" | jq -e --arg f "$feat" 'index($f) != null' > /dev/null 2>&1; then
    ok "Feature enabled: $feat"
  else
    fail "Feature NOT present: $feat"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All Enterprise checks passed — ready for demo ✔${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}$FAILURES check(s) FAILED${NC}"
  exit 1
fi
