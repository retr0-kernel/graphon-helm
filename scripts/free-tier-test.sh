#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Graphon Free Tier — End-to-End Test Script
#
# Usage:
#   ./scripts/free-tier-test.sh
#
# Prereqs:
#   kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
#   kubectl port-forward -n graphon svc/graphon-ui 3000:80 &
#
# Env overrides:
#   BACKEND=http://localhost:8080   (default)
#   TENANT_ID=default               (default — matches agent)
#   CLUSTER_ID=<auto from kubectl>  (default — matches agent node name)
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()      { echo -e "  ${GREEN}✔${NC}  $1"; }
fail()    { echo -e "  ${RED}✘${NC}  $1"; FAILURES=$((FAILURES+1)); }
info()    { echo -e "  ${YELLOW}→${NC}  $1"; }
section() { echo -e "\n${BOLD}${CYAN}══ $1 ══${NC}"; }
result()  { local v; v=$(echo "$1" | jq -r "$2" 2>/dev/null); echo "$v"; }

FAILURES=0
BACKEND="${BACKEND:-http://localhost:8080}"
TID="${TENANT_ID:-default}"
CID="${CLUSTER_ID:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'default')}"

echo -e "\n${BOLD}Graphon Free Tier — End-to-End Test${NC}"
echo -e "Backend : ${CYAN}$BACKEND${NC}"
echo -e "Tenant  : ${CYAN}$TID${NC}"
echo -e "Cluster : ${CYAN}$CID${NC}"

# ─────────────────────────────────────────────────────────────────────────────
section "1. Health"
# ─────────────────────────────────────────────────────────────────────────────

HEALTH=$(curl -sf "$BACKEND/api/v1/health" 2>/dev/null || echo '{}')
STATUS=$(echo "$HEALTH" | jq -r '.status // "error"')
if [ "$STATUS" = "ok" ]; then
  ok "Backend healthy  (status=$STATUS)"
else
  fail "Backend unhealthy  (got: $STATUS)"
fi

READY=$(curl -sf "$BACKEND/ready" 2>/dev/null || echo '{}')
PG=$(echo "$READY" | jq -r '.postgres // "error"')
NEO=$(echo "$READY" | jq -r '.neo4j // "error"')
[ "$PG"  = "ok" ] && ok "PostgreSQL connected" || fail "PostgreSQL not ready (got: $PG)"
[ "$NEO" = "ok" ] && ok "Neo4j connected"      || fail "Neo4j not ready (got: $NEO)"

# ─────────────────────────────────────────────────────────────────────────────
section "2. Live Graph"
# ─────────────────────────────────────────────────────────────────────────────

GRAPH=$(curl -sf \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/graph" 2>/dev/null || echo '{"nodes":[],"edges":[]}')

NODE_COUNT=$(echo "$GRAPH" | jq '.nodes | length')
EDGE_COUNT=$(echo "$GRAPH" | jq '.edges | length')
NS_LIST=$(echo "$GRAPH" | jq -r '[.nodes[].namespace] | unique | join(", ")')

if [ "$NODE_COUNT" -ge 1 ]; then
  ok "Graph has data  (nodes=$NODE_COUNT  edges=$EDGE_COUNT)"
  info "Namespaces: $NS_LIST"
else
  fail "Graph is empty — wait 2 min for eBPF to capture traffic, then retry"
fi

# Namespace filter test
FILTERED=$(curl -sf \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/graph?namespace=demo-api" 2>/dev/null || echo '{"nodes":[]}')
FILTERED_COUNT=$(echo "$FILTERED" | jq '.nodes | length')
if [ "$FILTERED_COUNT" -ge 1 ]; then
  ok "Namespace filter works  (demo-api nodes=$FILTERED_COUNT)"
else
  info "Namespace filter returned 0 nodes — demo-api may not be deployed yet"
fi

# Cross-namespace edges
EDGES=$(echo "$GRAPH" | jq -r '[.edges[] | "\(.source) → \(.target)"] | join(", ")')
info "Edges: $EDGES"

# ─────────────────────────────────────────────────────────────────────────────
section "3. Ownership"
# ─────────────────────────────────────────────────────────────────────────────

OWNERSHIP=$(curl -sf \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/ownership" 2>/dev/null || echo '[]')
OWN_COUNT=$(echo "$OWNERSHIP" | jq 'length')
if [ "$OWN_COUNT" -ge 1 ]; then
  ok "Ownership records found  (count=$OWN_COUNT)"
  echo "$OWNERSHIP" | jq -r '.[] | "     \(.node_id)  →  \(.team // "unowned")"' | head -7
else
  fail "No ownership records  (are pods labelled with app.graphon.io/owner-team?)"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "4. Safe-Delete Analysis"
# ─────────────────────────────────────────────────────────────────────────────

# Test a hub service — should NOT be safe to delete
GATEWAY_SD=$(curl -sf \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/services/gateway/safe-delete" 2>/dev/null || echo '{"safe":null}')
GW_SAFE=$(echo "$GATEWAY_SD" | jq -r '.safe // "null"')
GW_DEP=$(echo "$GATEWAY_SD"  | jq -r '.inbound_count // 0')

if [ "$GW_SAFE" = "false" ]; then
  ok "gateway: correctly blocked  (inbound_count=$GW_DEP)"
elif [ "$GW_SAFE" = "null" ]; then
  info "gateway: service not in graph yet"
else
  fail "gateway: expected safe=false, got safe=$GW_SAFE"
fi

# Test a leaf service — should be safe to delete
PAYMENTS_SD=$(curl -sf \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/services/payments/safe-delete" 2>/dev/null || echo '{"safe":null}')
PM_SAFE=$(echo "$PAYMENTS_SD" | jq -r '.safe // "null"')
if [ "$PM_SAFE" = "true" ]; then
  ok "payments: correctly marked safe (no inbound dependencies)"
elif [ "$PM_SAFE" = "null" ]; then
  info "payments: service not in graph yet"
else
  fail "payments: expected safe=true, got safe=$PM_SAFE"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "5. Snapshots"
# ─────────────────────────────────────────────────────────────────────────────

SNAP_RESP=$(curl -sf -X POST \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" \
  -d '{"label":"ci-test","trigger":"manual"}' \
  "$BACKEND/api/v1/snapshots" 2>/dev/null || echo '{}')

SNAP_ID=$(echo "$SNAP_RESP" | jq -r '.id // ""')
if [ ${#SNAP_ID} -gt 10 ]; then
  ok "Snapshot created  (id=$SNAP_ID)"
else
  ERROR=$(echo "$SNAP_RESP" | jq -r '.error // "unknown"')
  fail "Snapshot failed  ($ERROR)"
fi

# List snapshots
SNAP_LIST=$(curl -sf \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/snapshots" 2>/dev/null || echo '{"snapshots":[]}')
SNAP_LIST_COUNT=$(echo "$SNAP_LIST" | jq '.snapshots | length')
[ "$SNAP_LIST_COUNT" -ge 1 ] && ok "Snapshot list works  (count=$SNAP_LIST_COUNT)" || fail "Snapshot list empty"

# ─────────────────────────────────────────────────────────────────────────────
section "6. Search"
# ─────────────────────────────────────────────────────────────────────────────

SEARCH=$(curl -sf \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/search?q=orders" 2>/dev/null || echo '{"results":[]}')
S_COUNT=$(echo "$SEARCH" | jq '.results | length // 0')
if [ "$S_COUNT" -ge 1 ]; then
  ok "Search works  (results=$S_COUNT for q=orders)"
else
  info "Search returned 0 results — graph may still be empty"
fi

# ─────────────────────────────────────────────────────────────────────────────
section "7. Export"
# ─────────────────────────────────────────────────────────────────────────────

MERMAID=$(curl -sf -X POST \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"format":"mermaid"}' \
  "$BACKEND/api/v1/export" 2>/dev/null || echo '')

if echo "$MERMAID" | grep -q "flowchart"; then
  LINES=$(echo "$MERMAID" | wc -l | tr -d ' ')
  ok "Mermaid export works  ($LINES lines)"
  echo "$MERMAID" | head -5 | sed 's/^/     /'
else
  fail "Mermaid export failed or returned empty"
fi

DOT=$(curl -sf -X POST \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  -H "Content-Type: application/json" -d '{"format":"dot"}' \
  "$BACKEND/api/v1/export" 2>/dev/null || echo '')

echo "$DOT" | grep -q "digraph" && ok "DOT export works" || fail "DOT export failed"

# ─────────────────────────────────────────────────────────────────────────────
section "8. License Status"
# ─────────────────────────────────────────────────────────────────────────────

LICENSE=$(curl -sf \
  -H "X-Tenant-ID: $TID" \
  "$BACKEND/api/v1/license" 2>/dev/null || echo '{}')
PLAN=$(echo "$LICENSE" | jq -r '.plan // "unknown"')
RETENTION=$(echo "$LICENSE" | jq -r '.limits.retention_days // "?"')
ok "License: plan=$PLAN  retention=${RETENTION}d"

# ─────────────────────────────────────────────────────────────────────────────
section "9. UI Reachability"
# ─────────────────────────────────────────────────────────────────────────────

UI_CODE=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo '000')
[ "$UI_CODE" = "200" ] && ok "UI reachable  (HTTP $UI_CODE)" || fail "UI unreachable  (HTTP $UI_CODE — port-forward running?)"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed — ready for demo ✔${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}$FAILURES check(s) FAILED${NC}"
  exit 1
fi
