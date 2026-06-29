#!/usr/bin/env bash
# Graphon Enterprise Tier — End-to-End Test Script
# Runs every check, never exits early, dumps raw responses on failure.
#
# Usage:
#   LICENSE_KEY="eyJ..." ./scripts/enterprise-tier-test.sh
#
# Prereqs:
#   - Free tier tests passing (./scripts/free-tier-test.sh)
#   - kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
#   - LICENSE_KEY env var set

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

FAILURES=0
BACKEND="${BACKEND:-http://localhost:8080}"
TID="${TENANT_ID:-default}"
CID="${CLUSTER_ID:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'default')}"
LICENSE_KEY="${LICENSE_KEY:-}"

ok()      { echo -e "  ${GREEN}✔${NC}  $*"; }
fail()    { echo -e "  ${RED}✘${NC}  $*"; FAILURES=$((FAILURES+1)); }
info()    { echo -e "  ${YELLOW}→${NC}  $*"; }
dump()    { echo -e "${DIM}    raw: $*${NC}"; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

api() {
  local method="$1" path="$2"
  shift 2
  curl -s --max-time 10 -X "$method" \
    -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    "$@" "$BACKEND$path" 2>&1 || echo '{"_curl_error":true}'
}

echo -e "\n${BOLD}Graphon Enterprise Tier — End-to-End Test${NC}"
echo -e "Backend : ${CYAN}$BACKEND${NC}"
echo -e "Tenant  : ${CYAN}$TID${NC}"
echo -e "Cluster : ${CYAN}$CID${NC}\n"

if [ -z "$LICENSE_KEY" ]; then
  echo -e "${RED}ERROR: LICENSE_KEY not set.${NC}"
  echo "Generate one:"
  echo "  cd graphon-backend && go run ./cmd/keygen --plan enterprise --org Demo --expiry 90d --out /tmp/demo.license"
  echo "  export LICENSE_KEY=\$(cat /tmp/demo.license)"
  exit 1
fi

# ─── 1. Apply License ─────────────────────────────────────────────────────────
section "1. Apply Enterprise License"

LIC_RESP=$(curl -s --max-time 10 -X POST "$BACKEND/api/v1/license/key" \
  -H "X-Tenant-ID: $TID" \
  -H "Content-Type: application/json" \
  -d "{\"key\":\"$LICENSE_KEY\"}" 2>&1 || echo '{"_curl_error":true}')

PLAN=$(echo "$LIC_RESP" | jq -r '.plan // "unknown"' 2>/dev/null || echo "unknown")
if [ "$PLAN" = "enterprise" ]; then
  FEATS=$(echo "$LIC_RESP"   | jq -r '.features | length'    2>/dev/null || echo "?")
  ORG=$(echo "$LIC_RESP"     | jq -r '.org_name // "?"'      2>/dev/null || echo "?")
  EXPIRY=$(echo "$LIC_RESP"  | jq -r '.expiry   // "?"'      2>/dev/null || echo "?")
  RET=$(echo "$LIC_RESP"     | jq -r '.limits.retention_days // "?"' 2>/dev/null || echo "?")
  ok "License applied  (plan=$PLAN  org=$ORG  features=$FEATS  retention=${RET}d  expires=$EXPIRY)"
else
  fail "License apply failed  (plan=$PLAN)"
  dump "$LIC_RESP"
  echo -e "${DIM}  backend logs:${NC}"
  kubectl logs -n graphon deploy/graphon-backend --tail=20 2>/dev/null | grep -i "license\|error" | sed 's/^/    /'
fi

CURRENT=$(curl -s --max-time 10 -H "X-Tenant-ID: $TID" "$BACKEND/api/v1/license" 2>&1 || echo '{}')
CURRENT_PLAN=$(echo "$CURRENT" | jq -r '.plan // "unknown"' 2>/dev/null || echo "unknown")
[ "$CURRENT_PLAN" = "enterprise" ] && ok "License confirmed via GET" || { fail "License GET returned plan=$CURRENT_PLAN"; dump "$CURRENT"; }

# ─── 2. RBAC ──────────────────────────────────────────────────────────────────
section "2. RBAC — Role Enforcement"

# Create viewer key
VIEWER_RESP=$(api POST /api/v1/auth/keys -H "Content-Type: application/json" -d '{"name":"test-viewer","role":"viewer"}')
VIEWER_TOKEN=$(echo "$VIEWER_RESP" | jq -r '.token // ""' 2>/dev/null || echo "")

if [ -z "$VIEWER_TOKEN" ]; then
  fail "Could not create viewer API key"
  dump "$VIEWER_RESP"
else
  ok "Viewer key created  (${VIEWER_TOKEN:0:12}...)"

  # Viewer CAN read graph
  GRAPH_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" \
    -H "X-API-Key: $VIEWER_TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    "$BACKEND/api/v1/graph" 2>/dev/null || echo "000")
  [ "$GRAPH_CODE" = "200" ] && ok "Viewer can read graph  (HTTP $GRAPH_CODE)" || { fail "Viewer cannot read graph  (HTTP $GRAPH_CODE)"; }

  # Viewer CANNOT create snapshot
  SNAP_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST \
    -H "X-API-Key: $VIEWER_TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    -H "Content-Type: application/json" -d '{"label":"rbac-test"}' \
    "$BACKEND/api/v1/snapshots" 2>/dev/null || echo "000")
  SNAP_BODY=$(curl -s --max-time 10 -X POST \
    -H "X-API-Key: $VIEWER_TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    -H "Content-Type: application/json" -d '{"label":"rbac-test"}' \
    "$BACKEND/api/v1/snapshots" 2>/dev/null || echo '{}')
  if [ "$SNAP_CODE" = "403" ] || [ "$SNAP_CODE" = "401" ]; then
    ok "Viewer blocked from snapshot  (HTTP $SNAP_CODE — RBAC enforced)"
  else
    fail "Viewer NOT blocked from snapshot  (HTTP $SNAP_CODE)"
    dump "$SNAP_BODY"
  fi
fi

# Create developer key
DEV_RESP=$(api POST /api/v1/auth/keys -H "Content-Type: application/json" -d '{"name":"test-developer","role":"developer"}')
DEV_TOKEN=$(echo "$DEV_RESP" | jq -r '.token // ""' 2>/dev/null || echo "")

if [ -z "$DEV_TOKEN" ]; then
  fail "Could not create developer API key"
  dump "$DEV_RESP"
else
  ok "Developer key created  (${DEV_TOKEN:0:12}...)"
  OWN_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X PUT \
    -H "X-API-Key: $DEV_TOKEN" -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    -H "Content-Type: application/json" \
    -d '{"team":"orders-team","contact":"dev@acme.io"}' \
    "$BACKEND/api/v1/services/orders/ownership" 2>/dev/null || echo "000")
  [ "$OWN_CODE" = "200" ] && ok "Developer can update ownership  (HTTP $OWN_CODE)" || fail "Developer blocked from ownership  (HTTP $OWN_CODE)"
fi

# ─── 3. Extended Retention ────────────────────────────────────────────────────
section "3. Extended Snapshot Retention"

ENT_RET=$(echo "$CURRENT" | jq -r '.limits.retention_days // 0' 2>/dev/null || echo "0")
if [ "${ENT_RET:-0}" -ge 365 ] 2>/dev/null; then
  ok "Retention is ${ENT_RET} days (Enterprise)"
else
  fail "Retention is ${ENT_RET} days (expected >= 365)"
fi

ENT_SNAP=$(api POST /api/v1/snapshots -H "Content-Type: application/json" \
  -d '{"label":"enterprise-test","trigger":"scheduled"}')
ENT_ID=$(echo "$ENT_SNAP" | jq -r '.id // ""' 2>/dev/null || echo "")
ENT_TRIG=$(echo "$ENT_SNAP" | jq -r '.trigger // ""' 2>/dev/null || echo "")
if [ ${#ENT_ID} -gt 10 ]; then
  ok "Scheduled snapshot created  (id=$ENT_ID  trigger=$ENT_TRIG)"
else
  fail "Snapshot failed"
  dump "$ENT_SNAP"
  echo -e "${DIM}  backend snapshot logs:${NC}"
  kubectl logs -n graphon deploy/graphon-backend --tail=30 2>/dev/null | grep -i "snapshot\|error" | tail -10 | sed 's/^/    /'
fi

# ─── 4. Draw.io Export ────────────────────────────────────────────────────────
section "4. Draw.io Export (Enterprise-only)"

DRAWIO=$(api POST /api/v1/export -H "Content-Type: application/json" -d '{"format":"drawio"}')
if echo "$DRAWIO" | grep -q "mxGraphModel" 2>/dev/null; then
  BYTES=$(echo -n "$DRAWIO" | wc -c | tr -d ' ')
  ok "Draw.io export works  ($BYTES bytes)"
  echo "$DRAWIO" | head -2 | sed 's/^/    /'
else
  fail "Draw.io export failed"
  dump "$DRAWIO"
  echo -e "${DIM}  license features present:${NC}"
  echo "$CURRENT" | jq '.features' 2>/dev/null | sed 's/^/    /'
fi

# ─── 5. Cluster List ──────────────────────────────────────────────────────────
section "5. Multi-Cluster Endpoint"

CLUSTERS=$(curl -s --max-time 10 -H "X-Tenant-ID: $TID" "$BACKEND/api/v1/clusters" 2>&1 || echo '{}')
CL_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -H "X-Tenant-ID: $TID" "$BACKEND/api/v1/clusters" 2>/dev/null || echo "000")
[ "$CL_CODE" = "200" ] && ok "Clusters endpoint reachable  (HTTP $CL_CODE)" || { fail "Clusters endpoint failed  (HTTP $CL_CODE)"; dump "$CLUSTERS"; }
echo -e "${DIM}  cluster list:${NC}"
echo "$CLUSTERS" | jq 2>/dev/null | head -10 | sed 's/^/    /' || echo "    $CLUSTERS"

# ─── 6. Scheduler ─────────────────────────────────────────────────────────────
section "6. Scheduler"

SCHED=$(kubectl logs -n graphon deploy/graphon-backend --since=24h 2>/dev/null | grep -i "scheduler" | tail -5)
if echo "$SCHED" | grep -q "scheduler started" 2>/dev/null; then
  ok "Scheduler running"
  echo "$SCHED" | sed 's/^/    /'
else
  info "Scheduler startup log not found — may have started more than 24h ago"
  echo -e "${DIM}  recent backend logs:${NC}"
  kubectl logs -n graphon deploy/graphon-backend --tail=10 2>/dev/null | sed 's/^/    /'
fi

# ─── 7. Feature Gates ─────────────────────────────────────────────────────────
section "7. Feature Gates"

for feat in snapshots rbac scheduled-snapshots export-drawio multi-cluster webhooks audit-log; do
  if echo "$CURRENT" | jq -e --arg f "$feat" '.features // [] | index($f) != null' >/dev/null 2>&1; then
    ok "Feature enabled: $feat"
  else
    fail "Feature NOT in license: $feat"
  fi
done
echo -e "${DIM}  full feature list:${NC}"
echo "$CURRENT" | jq '.features' 2>/dev/null | sed 's/^/    /' || echo "    (parse error)"

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All Enterprise checks passed — ready for demo ✔${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}$FAILURES check(s) FAILED${NC}"
  echo ""
  echo -e "${DIM}Full backend logs (last 50 lines):${NC}"
  kubectl logs -n graphon deploy/graphon-backend --tail=50 2>/dev/null | sed 's/^/  /'
  exit 1
fi
