#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Graphon Demo — Synthetic Graph Seed Script
#
# Use this when the eBPF agent is running in degraded mode (kernel too old,
# missing BTF, or unsupported kfunc). Injects realistic traffic events
# directly via the ingest API so the full graph topology is visible in the UI.
#
# Topology seeded (mirrors the multi-namespace demo app):
#   demo-web:   frontend → gateway
#   demo-web → demo-api: gateway → orders, catalog
#   demo-api:   orders → payments
#   demo-api → demo-data: orders → notifications
#   demo-web → demo-data: gateway → user-service
#
# Usage:
#   ./scripts/seed-demo-data.sh
#
# Prereqs:
#   kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &
# ─────────────────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✔${NC}  $*"; }
fail() { echo -e "  ${RED}✘${NC}  $*"; }

BACKEND="${BACKEND:-http://localhost:8080}"
TID="${TENANT_ID:-default}"
CID="${CLUSTER_ID:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo 'default')}"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo -e "\n${BOLD}Graphon — Seeding Demo Graph Data${NC}"
echo -e "Backend : ${CYAN}$BACKEND${NC}"
echo -e "Tenant  : ${CYAN}$TID${NC}"
echo -e "Cluster : ${CYAN}$CID${NC}"
echo -e "Why     : eBPF agent degraded — injecting synthetic events via ingest API\n"

ingest() {
  local src_name="$1" src_ns="$2" src_team="$3" src_email="$4"
  local dst_name="$5" dst_ns="$6"
  local src_ip="$7" dst_ip="$8"

  local PAYLOAD
  PAYLOAD=$(cat <<JSON
{
  "tenant_id": "$TID",
  "cluster_id": "$CID",
  "events": [
    {
      "src_pod":       "$src_name",
      "src_namespace": "$src_ns",
      "src_ip":        "$src_ip",
      "dst_ip":        "$dst_ip",
      "dst_port":      80,
      "dst_service":   "$dst_name",
      "dst_namespace": "$dst_ns",
      "protocol":      "TCP",
      "timestamp":     "$NOW",
      "owner_team":    "$src_team",
      "owner_email":   "$src_email",
      "owner_slack":   "$src_team"
    }
  ]
}
JSON
)

  RESP=$(curl -s --max-time 10 -X POST \
    -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$BACKEND/api/v1/ingest/events" 2>/dev/null || echo '{"_err":true}')

  ACC=$(echo "$RESP" | jq -r '.accepted // 0' 2>/dev/null || echo "0")
  REJ=$(echo "$RESP" | jq -r '.rejected // 0' 2>/dev/null || echo "0")

  if [ "$ACC" -ge 1 ] 2>/dev/null; then
    ok "$src_ns/$src_name → $dst_ns/$dst_name"
  else
    fail "$src_ns/$src_name → $dst_ns/$dst_name  (accepted=$ACC rejected=$REJ resp=$RESP)"
  fi
}

# ── Seed all 6 connections ────────────────────────────────────────────────────
#
#  src_name   src_ns     src_team        src_email              dst_name       dst_ns     src_ip       dst_ip
ingest frontend   demo-web   frontend-team   frontend@demo.io       gateway        demo-web   10.200.1.1   10.200.1.2
ingest gateway    demo-web   platform-team   platform@demo.io       orders         demo-api   10.200.1.2   10.200.2.1
ingest gateway    demo-web   platform-team   platform@demo.io       catalog        demo-api   10.200.1.2   10.200.2.3
ingest gateway    demo-web   platform-team   platform@demo.io       user-service   demo-data  10.200.1.2   10.200.3.2
ingest orders     demo-api   orders-team     orders@demo.io         payments       demo-api   10.200.2.1   10.200.2.2
ingest orders     demo-api   orders-team     orders@demo.io         notifications  demo-data  10.200.2.1   10.200.3.1

# Also seed ownership for destination nodes (they don't have owner_team in ingest)
# Do a second pass so all services have ownership
ingest payments       demo-api   payments-team   payments@demo.io       payments       demo-api   10.200.2.2   10.200.2.2
ingest catalog        demo-api   catalog-team    catalog@demo.io        catalog        demo-api   10.200.2.3   10.200.2.3
ingest notifications  demo-data  platform-team   platform@demo.io       notifications  demo-data  10.200.3.1   10.200.3.1
ingest user-service   demo-data  platform-team   platform@demo.io       user-service   demo-data  10.200.3.2   10.200.3.2

echo ""

# ── Verify ────────────────────────────────────────────────────────────────────
echo -e "${BOLD}Verifying graph...${NC}"
sleep 1

GRAPH=$(curl -s --max-time 10 \
  -H "X-Tenant-ID: $TID" -H "X-Cluster-ID: $CID" \
  "$BACKEND/api/v1/graph" 2>/dev/null || echo '{"nodes":[],"edges":[]}')

NODE_COUNT=$(echo "$GRAPH" | jq '.nodes | length' 2>/dev/null || echo 0)
EDGE_COUNT=$(echo "$GRAPH" | jq '.edges | length' 2>/dev/null || echo 0)
NS=$(echo "$GRAPH" | jq -r '[.nodes[].namespace] | unique | join(", ")' 2>/dev/null || echo "")

echo ""
echo -e "  Nodes      : ${CYAN}$NODE_COUNT${NC}"
echo -e "  Edges      : ${CYAN}$EDGE_COUNT${NC}"
echo -e "  Namespaces : ${CYAN}$NS${NC}"
echo ""

echo -e "${BOLD}Edges discovered:${NC}"
echo "$GRAPH" | jq -r '.edges[] | "  \(.source) → \(.target)"' 2>/dev/null || echo "  (none)"

echo ""
if [ "${NODE_COUNT:-0}" -ge 6 ] 2>/dev/null; then
  echo -e "${GREEN}${BOLD}Graph seeded successfully — open http://localhost:3000${NC}"
  echo -e "\nRun the full test now: ${CYAN}./scripts/free-tier-test.sh${NC}"
else
  echo -e "${RED}Graph has fewer nodes than expected (got $NODE_COUNT, want >= 6)${NC}"
  echo "Check backend logs: kubectl logs -n graphon deploy/graphon-backend --tail=30"
fi
