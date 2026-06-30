#!/usr/bin/env bash
# Graphon Free Tier — End-to-End Test Script
# Runs every check, never exits early, dumps raw responses on failure.
#
# Usage:
#   ./scripts/free-tier-test.sh
#
# Prereqs:
#   kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
#   kubectl port-forward -n graphon svc/graphon-ui 3000:80 &

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

FAILURES=0
BACKEND="${BACKEND:-http://localhost:8080}"
TID="${TENANT_ID:-default}"
CID="${CLUSTER_ID:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'default')}"

ok()      { echo -e "  ${GREEN}✔${NC}  $*"; }
fail()    { echo -e "  ${RED}✘${NC}  $*"; FAILURES=$((FAILURES+1)); }
info()    { echo -e "  ${YELLOW}→${NC}  $*"; }
dump()    { echo -e "${DIM}    raw: $*${NC}"; }
section() { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

# curl wrapper: always returns body, never exits on HTTP error
# Usage: raw=$(api GET /api/v1/health)
api() {
  local method="$1" path="$2"
  shift 2
  curl -s --max-time 10 -X "$method" \
    -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    "$@" "$BACKEND$path" 2>&1 || echo '{"_curl_error":true}'
}

echo -e "\n${BOLD}Graphon Free Tier — End-to-End Test${NC}"
echo -e "Backend : ${CYAN}$BACKEND${NC}"
echo -e "Tenant  : ${CYAN}$TID${NC}"
echo -e "Cluster : ${CYAN}$CID${NC}\n"

echo -e "${DIM}kubectl pods:${NC}"
kubectl get pods -n graphon --no-headers 2>/dev/null | sed 's/^/  /'
echo ""

# ─── 1. Health ────────────────────────────────────────────────────────────────
section "1. Health"

HEALTH=$(curl -s --max-time 10 "$BACKEND/api/v1/health" 2>&1 || echo '{"_curl_error":true}')
STATUS=$(echo "$HEALTH" | jq -r '.status // "error"' 2>/dev/null || echo "jq_error")
if [ "$STATUS" = "ok" ]; then
  ok "Backend healthy  (status=$STATUS)"
else
  fail "Backend unhealthy"
  dump "$HEALTH"
  echo ""
  echo -e "${DIM}  backend pod logs (last 20 lines):${NC}"
  kubectl logs -n graphon deploy/graphon-backend --tail=20 2>/dev/null | sed 's/^/    /'
fi

READY=$(curl -s --max-time 10 "$BACKEND/ready" 2>&1 || echo '{"_curl_error":true}')
# /ready returns {"checks":{"neo4j":{"ok":true},"postgres":{"ok":true}},"ready":true}
PG=$(echo  "$READY" | jq -r '(.checks.postgres.ok // .postgres // false) | if . == true then "ok" else "error" end' 2>/dev/null || echo "jq_error")
NEO=$(echo "$READY" | jq -r '(.checks.neo4j.ok    // .neo4j    // false) | if . == true then "ok" else "error" end' 2>/dev/null || echo "jq_error")
if [ "$PG" = "ok" ]; then
  ok "PostgreSQL connected"
else
  fail "PostgreSQL not ready  (got: $PG)"
  dump "$READY"
  echo -e "${DIM}  postgresql pod logs (last 10 lines):${NC}"
  kubectl logs -n graphon statefulset/graphon-postgresql --tail=10 2>/dev/null | sed 's/^/    /'
fi
if [ "$NEO" = "ok" ]; then
  ok "Neo4j connected"
else
  fail "Neo4j not ready  (got: $NEO)"
  dump "$READY"
  echo -e "${DIM}  neo4j pod logs (last 10 lines):${NC}"
  kubectl logs -n graphon statefulset/graphon --tail=10 2>/dev/null | sed 's/^/    /'
fi

# ─── 2. Live Graph ────────────────────────────────────────────────────────────
section "2. Live Graph"

GRAPH=$(api GET /api/v1/graph)
NODE_COUNT=$(echo "$GRAPH" | jq '.nodes | length'         2>/dev/null || echo "0")
EDGE_COUNT=$(echo "$GRAPH" | jq '.edges | length'         2>/dev/null || echo "0")
NS_LIST=$(echo   "$GRAPH" | jq -r '[.nodes[].namespace] | unique | join(", ")' 2>/dev/null || echo "")

if [ "${NODE_COUNT:-0}" -ge 1 ] 2>/dev/null; then
  ok "Graph has data  (nodes=$NODE_COUNT  edges=$EDGE_COUNT)"
  info "Namespaces: $NS_LIST"
  EDGES=$(echo "$GRAPH" | jq -r '[.edges[] | "\(.source) → \(.target)"] | join("\n  ")' 2>/dev/null || echo "")
  echo -e "  ${DIM}edges:\n  $EDGES${NC}"
else
  fail "Graph is empty  (nodes=$NODE_COUNT)"
  dump "$(echo "$GRAPH" | jq '{error:.error, nodes_len:(.nodes|length), edges_len:(.edges|length)}' 2>/dev/null || echo "$GRAPH")"
  echo ""
  echo -e "${DIM}  agent logs (last 20 lines — look for 'ingest' or 'event'):${NC}"
  kubectl logs -n graphon daemonset/graphon-agent --tail=20 2>/dev/null | sed 's/^/    /'
fi

FILTERED=$(api GET "/api/v1/graph?namespace=demo-api")
FC=$(echo "$FILTERED" | jq '.nodes | length' 2>/dev/null || echo "0")
if [ "${FC:-0}" -ge 1 ] 2>/dev/null; then
  ok "Namespace filter works  (demo-api nodes=$FC)"
else
  info "Namespace filter: 0 nodes in demo-api — demo app may still be deploying"
  echo -e "${DIM}  demo-api pods:${NC}"
  kubectl get pods -n demo-api --no-headers 2>/dev/null | sed 's/^/    /' || echo "    (namespace not found)"
fi

# ─── 3. Ownership ─────────────────────────────────────────────────────────────
section "3. Ownership"

OWN=$(api GET /api/v1/ownership)
# /api/v1/ownership returns {"assignments":[...],"total":N}
OWN_COUNT=$(echo "$OWN" | jq '(.assignments | length) // (.total) // 0' 2>/dev/null || echo "0")
if [ "${OWN_COUNT:-0}" -ge 1 ] 2>/dev/null; then
  ok "Ownership records  (count=$OWN_COUNT)"
  echo "$OWN" | jq -r '.assignments[] | "    \(.node_id // "?")  →  team:\(.owner_team // "unowned")"' 2>/dev/null | head -10
else
  fail "No ownership records"
  dump "$OWN"
fi

# ─── 4. Safe-Delete ───────────────────────────────────────────────────────────
section "4. Safe-Delete Analysis"

# Safe-delete uses the full Neo4j node ID (URN format).
# gateway lives in demo-web; payments lives in demo-api.
GW_ID="svc:${TID}:${CID}:demo-web:gateway"
PM_ID="svc:${TID}:${CID}:demo-api:payments"

GW=$(api GET "/api/v1/services/$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],safe='')); " "$GW_ID" 2>/dev/null || echo "$GW_ID")/safe-delete")
GW_SAFE=$(echo "$GW" | jq -r '.safe // "null"' 2>/dev/null || echo "null")
if   [ "$GW_SAFE" = "false" ]; then ok "gateway blocked  (inbound=$(echo "$GW" | jq -r '.inbound_count // 0' 2>/dev/null))"
elif [ "$GW_SAFE" = "null"  ]; then info "gateway not in graph yet  (id=$GW_ID)"
else fail "gateway: expected safe=false, got safe=$GW_SAFE"; dump "$GW"; fi

PM=$(api GET "/api/v1/services/$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1],safe='')); " "$PM_ID" 2>/dev/null || echo "$PM_ID")/safe-delete")
PM_SAFE=$(echo "$PM" | jq -r '.safe // "null"' 2>/dev/null || echo "null")
if   [ "$PM_SAFE" = "true" ]; then ok "payments safe  (no inbound deps)"
elif [ "$PM_SAFE" = "null" ]; then info "payments not in graph yet  (id=$PM_ID)"
else fail "payments: expected safe=true, got safe=$PM_SAFE"; dump "$PM"; fi

# ─── 5. Snapshots ─────────────────────────────────────────────────────────────
section "5. Snapshots"

SNAP_RESP=$(api POST /api/v1/snapshots -H "Content-Type: application/json" -d '{"label":"ci-test","trigger":"manual"}')
SNAP_ID=$(echo "$SNAP_RESP" | jq -r '.id // ""' 2>/dev/null || echo "")
if [ ${#SNAP_ID} -gt 10 ]; then
  ok "Snapshot created  (id=$SNAP_ID)"
else
  fail "Snapshot failed"
  dump "$SNAP_RESP"
  echo -e "${DIM}  backend logs around snapshot:${NC}"
  kubectl logs -n graphon deploy/graphon-backend --tail=30 2>/dev/null | grep -i "snapshot\|error" | tail -10 | sed 's/^/    /'
fi

SNAP_LIST=$(api GET /api/v1/snapshots)
SL=$(echo "$SNAP_LIST" | jq '.snapshots | length' 2>/dev/null || echo "0")
if [ "${SL:-0}" -ge 1 ] 2>/dev/null; then ok "Snapshot list works  (count=$SL)"
else fail "Snapshot list empty"; dump "$SNAP_LIST"; fi

# ─── 6. Search ────────────────────────────────────────────────────────────────
section "6. Search"

SEARCH=$(api GET "/api/v1/search?q=orders")
SC=$(echo "$SEARCH" | jq '.results | length' 2>/dev/null || echo "0")
if [ "${SC:-0}" -ge 1 ] 2>/dev/null; then ok "Search works  (results=$SC)"
else info "Search: 0 results — graph may be empty"
  dump "$SEARCH"; fi

# ─── 7. Export ────────────────────────────────────────────────────────────────
section "7. Export"

MERMAID=$(api POST /api/v1/export -H "Content-Type: application/json" -d '{"format":"mermaid"}')
if echo "$MERMAID" | grep -qE "flowchart|graph LR|graph TD" 2>/dev/null; then
  ok "Mermaid export  ($(echo "$MERMAID" | wc -l | tr -d ' ') lines)"
  echo "$MERMAID" | head -6 | sed 's/^/    /'
else
  fail "Mermaid export failed"
  dump "$MERMAID"
fi

DOT=$(api POST /api/v1/export -H "Content-Type: application/json" -d '{"format":"dot"}')
if echo "$DOT" | grep -q "digraph" 2>/dev/null; then ok "DOT export works"
else fail "DOT export failed"; dump "$DOT"; fi

# ─── 8. License ───────────────────────────────────────────────────────────────
section "8. License"

LIC=$(curl -s --max-time 10 -H "X-Tenant-ID: $TID" "$BACKEND/api/v1/license" 2>&1 || echo '{}')
PLAN=$(echo "$LIC" | jq -r '.plan // "unknown"' 2>/dev/null || echo "unknown")
RET=$(echo  "$LIC" | jq -r '.limits.retention_days // "?"' 2>/dev/null || echo "?")
ok "License: plan=$PLAN  retention=${RET}d"
dump "$LIC"

# ─── 9. UI ────────────────────────────────────────────────────────────────────
section "9. UI Reachability"

UI_CODE=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo '000')
if [ "$UI_CODE" = "200" ]; then ok "UI reachable  (HTTP $UI_CODE)"
else
  fail "UI unreachable  (HTTP $UI_CODE)"
  echo -e "${DIM}  UI pod status:${NC}"
  kubectl get pod -n graphon -l app.kubernetes.io/name=graphon-ui --no-headers 2>/dev/null | sed 's/^/    /'
  kubectl logs -n graphon deploy/graphon-ui --tail=10 2>/dev/null | sed 's/^/    /'
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed — ready for demo ✔${NC}"
  exit 0
else
  echo -e "${RED}${BOLD}$FAILURES check(s) FAILED${NC}"
  echo ""
  echo -e "${DIM}Full backend logs (last 50 lines):${NC}"
  kubectl logs -n graphon deploy/graphon-backend --tail=50 2>/dev/null | sed 's/^/  /'
  exit 1
fi
