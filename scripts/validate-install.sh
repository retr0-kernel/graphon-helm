#!/usr/bin/env bash
# validate-install.sh — comprehensive post-install health check for Graphon.
#
# Usage:
#   ./scripts/validate-install.sh
#
# Environment variables:
#   NAMESPACE   Kubernetes namespace (default: graphon)
#   RELEASE     Helm release name    (default: graphon)
#   TIMEOUT     Seconds to wait for pods (default: 180)
#   DIAG        Set to 1 to always collect diagnostics (default: on failure only)
#
# Exit codes:
#   0  All checks passed
#   1  One or more checks failed (diagnostics auto-collected on failure)

set -euo pipefail

NAMESPACE="${NAMESPACE:-graphon}"
RELEASE="${RELEASE:-graphon}"
TIMEOUT="${TIMEOUT:-180}"
DIAG="${DIAG:-0}"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

PASS=0
FAIL=0

pass()   { PASS=$((PASS+1)); printf "  ${GREEN}✓${RESET}  %s\n" "$1"; }
fail()   { FAIL=$((FAIL+1)); printf "  ${RED}✗${RESET}  %s\n" "$1"; [[ -n "${2:-}" ]] && printf "      ${RED}↳${RESET} %s\n" "$2"; }
warn()   { printf "  ${YELLOW}⚠${RESET}  %s\n" "$1"; }
info()   { printf "  ${YELLOW}→${RESET}  %s\n" "$1"; }
header() { printf "\n${BOLD}${CYAN}══ %s ══${RESET}\n" "$1"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

require_tool() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: required tool '$1' not found in PATH"
    exit 1
  fi
}

kns() { kubectl -n "$NAMESPACE" "$@"; }

# Track all port-forward PIDs for cleanup
PF_PIDS=()

cleanup() {
  for pid in "${PF_PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  if (( FAIL > 0 )); then
    collect_diagnostics
  elif (( DIAG == 1 )); then
    collect_diagnostics
  fi
}
trap cleanup EXIT

start_port_forward() {
  local svc="$1" local_port="$2" remote_port="$3"
  kns port-forward "svc/$svc" "${local_port}:${remote_port}" &>/dev/null &
  PF_PIDS+=($!)
  sleep 2
}

collect_diagnostics() {
  printf "\n${BOLD}${RED}══ Diagnostics ══════════════════════════════${RESET}\n"

  echo ""
  echo "--- kubectl get all ---"
  kubectl -n "$NAMESPACE" get all 2>/dev/null || true

  echo ""
  echo "--- Events (last 20, sorted by time) ---"
  kubectl -n "$NAMESPACE" get events \
    --sort-by='.lastTimestamp' 2>/dev/null | tail -20 || true

  echo ""
  echo "--- StatefulSets ---"
  kubectl -n "$NAMESPACE" get statefulsets 2>/dev/null || true

  echo ""
  echo "--- DaemonSets ---"
  kubectl -n "$NAMESPACE" get daemonsets 2>/dev/null || true

  echo ""
  echo "--- PVCs ---"
  kubectl -n "$NAMESPACE" get pvc 2>/dev/null || true

  echo ""
  echo "--- Secrets ---"
  kubectl -n "$NAMESPACE" get secrets 2>/dev/null || true

  echo ""
  echo "--- Pod descriptions ---"
  kubectl -n "$NAMESPACE" describe pods 2>/dev/null || true

  echo ""
  echo "--- Backend logs (last 60 lines) ---"
  kubectl -n "$NAMESPACE" logs \
    -l "app.kubernetes.io/component=backend" --tail=60 2>/dev/null || true

  echo ""
  echo "--- UI logs (last 30 lines) ---"
  kubectl -n "$NAMESPACE" logs \
    -l "app.kubernetes.io/component=ui" --tail=30 2>/dev/null || true

  echo ""
  echo "--- Agent logs (last 40 lines) ---"
  kubectl -n "$NAMESPACE" logs \
    -l "app.kubernetes.io/component=agent" --tail=40 2>/dev/null || true

  echo ""
  echo "--- Neo4j logs (last 40 lines) ---"
  kubectl -n "$NAMESPACE" logs \
    -l "app.kubernetes.io/component=neo4j" --tail=40 2>/dev/null || true

  echo ""
  echo "--- PostgreSQL logs (last 40 lines) ---"
  kubectl -n "$NAMESPACE" logs \
    -l "app.kubernetes.io/component=postgresql" --tail=40 2>/dev/null || true
}

# ── Banner ────────────────────────────────────────────────────────────────────

printf "\n${BOLD}Graphon Install Validator${RESET}\n"
printf "  Namespace : %s\n" "$NAMESPACE"
printf "  Release   : %s\n" "$RELEASE"
printf "  Timestamp : %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"

require_tool kubectl
require_tool helm
require_tool curl
require_tool jq

BACKEND_PORT=18080
UI_PORT=13000

# ── 1. Namespace + Helm release ───────────────────────────────────────────────
header "1. Prerequisites"

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  pass "Namespace '$NAMESPACE' exists"
else
  fail "Namespace '$NAMESPACE' not found" \
    "Run: helm install $RELEASE graphon/graphon -n $NAMESPACE --create-namespace"
  exit 1
fi

if helm status "$RELEASE" -n "$NAMESPACE" &>/dev/null; then
  CHART_VER=$(helm list -n "$NAMESPACE" -f "^${RELEASE}$" -o json 2>/dev/null | jq -r '.[0].chart // "unknown"')
  pass "Helm release '$RELEASE' found ($CHART_VER)"
else
  fail "Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
  exit 1
fi

# ── 2. Secrets ────────────────────────────────────────────────────────────────
header "2. Secrets"

for secret_suffix in "neo4j-creds"; do
  SECRET_NAME="${RELEASE}-${secret_suffix}"
  if kns get secret "$SECRET_NAME" &>/dev/null; then
    pass "Secret '$SECRET_NAME' exists"
  else
    warn "Secret '$SECRET_NAME' not found (may be external DB mode)"
  fi
done

TOTAL_SECRETS=$(kns get secrets --no-headers 2>/dev/null | wc -l | tr -d ' ')
pass "Total secrets in namespace: $TOTAL_SECRETS"

# ── 3. Pod readiness ──────────────────────────────────────────────────────────
header "3. Pod Readiness (timeout: ${TIMEOUT}s)"

info "Waiting for backend pods..."
if kns wait pod \
    -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/component=backend" \
    --for=condition=Ready \
    --timeout="${TIMEOUT}s" &>/dev/null; then
  BACKEND_COUNT=$(kns get pods \
    -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/component=backend" \
    --no-headers 2>/dev/null | grep -c "Running" || echo 0)
  pass "Backend pod(s) ready ($BACKEND_COUNT running)"
else
  fail "Backend pods not ready within ${TIMEOUT}s"
  info "Hint: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=backend"
fi

info "Waiting for UI pods..."
if kns wait pod \
    -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/component=ui" \
    --for=condition=Ready \
    --timeout="${TIMEOUT}s" &>/dev/null; then
  pass "UI pod(s) ready"
else
  fail "UI pods not ready within ${TIMEOUT}s"
fi

# ── 4. StatefulSets ───────────────────────────────────────────────────────────
header "4. StatefulSets (Databases)"

STS_LIST=$(kns get statefulsets --no-headers 2>/dev/null || true)
if [[ -z "$STS_LIST" ]]; then
  warn "No StatefulSets found (expected Neo4j and/or PostgreSQL sub-charts)"
else
  while IFS= read -r line; do
    STS_NAME=$(echo "$line" | awk '{print $1}')
    STS_READY=$(echo "$line" | awk '{print $2}')
    STS_TOTAL=$(echo "$line" | awk '{print $3}')
    if [[ "$STS_READY" == "$STS_TOTAL" ]]; then
      pass "StatefulSet '$STS_NAME': $STS_READY/$STS_TOTAL ready"
    else
      fail "StatefulSet '$STS_NAME': $STS_READY/$STS_TOTAL ready"
    fi
  done <<< "$STS_LIST"
fi

# Wait for database StatefulSets to be available
if kns get statefulset -l "app.kubernetes.io/instance=${RELEASE}" &>/dev/null 2>&1; then
  info "Waiting for all StatefulSets..."
  kns rollout status statefulset \
    -l "app.kubernetes.io/instance=${RELEASE}" \
    --timeout="${TIMEOUT}s" &>/dev/null || \
    warn "Some StatefulSets did not finish rolling out"
fi

# ── 5. DaemonSets ─────────────────────────────────────────────────────────────
header "5. DaemonSets (Agent)"

DS_LIST=$(kns get daemonsets --no-headers 2>/dev/null || true)
if [[ -z "$DS_LIST" ]]; then
  warn "No DaemonSets found (agent may be disabled)"
else
  while IFS= read -r line; do
    DS_NAME=$(echo "$line"  | awk '{print $1}')
    DESIRED=$(echo "$line"  | awk '{print $2}')
    READY=$(echo "$line"    | awk '{print $4}')
    if [[ "$READY" == "$DESIRED" ]] && (( DESIRED > 0 )); then
      pass "DaemonSet '$DS_NAME': $READY/$DESIRED pods ready"
    elif (( DESIRED == 0 )); then
      warn "DaemonSet '$DS_NAME': 0 nodes matched (eBPF requires non-Fargate nodes)"
    else
      fail "DaemonSet '$DS_NAME': $READY/$DESIRED pods ready"
    fi
  done <<< "$DS_LIST"
fi

# ── 6. PersistentVolumeClaims ─────────────────────────────────────────────────
header "6. PersistentVolumeClaims"

PVC_LIST=$(kns get pvc --no-headers 2>/dev/null || true)
if [[ -z "$PVC_LIST" ]]; then
  warn "No PVCs found (storage may not be used)"
else
  PVC_FAIL=0
  while IFS= read -r line; do
    PVC_NAME=$(echo "$line"   | awk '{print $1}')
    PVC_STATUS=$(echo "$line" | awk '{print $2}')
    PVC_CAP=$(echo "$line"    | awk '{print $4}')
    if [[ "$PVC_STATUS" == "Bound" ]]; then
      pass "PVC '$PVC_NAME': Bound ($PVC_CAP)"
    else
      fail "PVC '$PVC_NAME': $PVC_STATUS (expected Bound)"
      PVC_FAIL=1
    fi
  done <<< "$PVC_LIST"
fi

# ── 7. Detect failing pods ────────────────────────────────────────────────────
header "7. Pod Health (Crash/Pull/OOM detection)"

BAD_PODS=$(kns get pods --no-headers 2>/dev/null \
  | awk '{print $1, $3}' \
  | grep -E "CrashLoopBackOff|ErrImagePull|ImagePullBackOff|CreateContainerConfigError|OOMKilled" \
  || true)

if [[ -n "$BAD_PODS" ]]; then
  while IFS= read -r line; do
    fail "Failing pod: $line"
  done <<< "$BAD_PODS"
else
  pass "No pods in CrashLoopBackOff / ErrImagePull / OOMKilled state"
fi

# ── 8. Backend health ─────────────────────────────────────────────────────────
header "8. Backend Health API"

BACKEND_SVC="${RELEASE}-backend"
info "Opening port-forward → svc/${BACKEND_SVC}:8080"
start_port_forward "$BACKEND_SVC" "$BACKEND_PORT" 8080

HEALTH=$(curl -sf "http://localhost:${BACKEND_PORT}/api/v1/health" 2>/dev/null || echo '{}')
STATUS=$(echo "$HEALTH" | jq -r '.status // "error"' 2>/dev/null || echo "error")
if [[ "$STATUS" == "ok" ]]; then
  VERSION=$(echo "$HEALTH" | jq -r '.version // "unknown"')
  pass "GET /api/v1/health → status=ok (version=$VERSION)"
else
  fail "GET /api/v1/health failed" "response: $(echo "$HEALTH" | head -c 300)"
fi

READY_RESP=$(curl -sf "http://localhost:${BACKEND_PORT}/ready" 2>/dev/null || echo '{}')
READY_FLAG=$(echo "$READY_RESP" | jq -r '.ready // false' 2>/dev/null || echo "false")
NEO4J_OK=$(echo "$READY_RESP"   | jq -r '.checks.neo4j.ok // false'     2>/dev/null || echo "unknown")
PG_OK=$(echo "$READY_RESP"      | jq -r '.checks.postgres.ok // false'  2>/dev/null || echo "unknown")

if [[ "$READY_FLAG" == "true" ]]; then
  pass "GET /ready → ready=true"
else
  fail "GET /ready → ready=false" "response: $(echo "$READY_RESP" | head -c 300)"
fi

# ── 9. Database connectivity (via /ready checks) ──────────────────────────────
header "9. Database Connectivity"

if [[ "$NEO4J_OK" == "true" ]]; then
  pass "Neo4j connectivity: ok (reported by backend /ready)"
elif [[ "$NEO4J_OK" == "false" ]]; then
  fail "Neo4j connectivity: failed" \
    "Check: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=backend | grep neo4j"
else
  warn "Neo4j connectivity: not reported in /ready response"
fi

if [[ "$PG_OK" == "true" ]]; then
  pass "PostgreSQL connectivity: ok (reported by backend /ready)"
elif [[ "$PG_OK" == "false" ]]; then
  fail "PostgreSQL connectivity: failed" \
    "Check: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=backend | grep postgres"
else
  warn "PostgreSQL connectivity: not reported in /ready response"
fi

# ── 10. Graph API ──────────────────────────────────────────────────────────────
header "10. Graph API"

GRAPH=$(curl -sf "http://localhost:${BACKEND_PORT}/api/v1/graph" \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: validate" 2>/dev/null || echo '{}')
if echo "$GRAPH" | jq -e '.nodes != null' &>/dev/null; then
  NODE_COUNT=$(echo "$GRAPH" | jq '.nodes | length')
  pass "GET /api/v1/graph → reachable (nodes: $NODE_COUNT)"
else
  fail "GET /api/v1/graph failed" "response: $(echo "$GRAPH" | head -c 200)"
fi

COUNTS=$(curl -sf "http://localhost:${BACKEND_PORT}/api/v1/review-items/counts" \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: validate" 2>/dev/null || echo '{}')
if echo "$COUNTS" | jq -e '.total != null' &>/dev/null; then
  TOTAL=$(echo "$COUNTS" | jq -r '.total')
  pass "GET /api/v1/review-items/counts → total=$TOTAL"
else
  warn "GET /api/v1/review-items/counts: non-standard response (may be ok)"
fi

# ── 11. UI reachability ────────────────────────────────────────────────────────
header "11. UI"

UI_SVC="${RELEASE}-ui"
info "Opening port-forward → svc/${UI_SVC}:80"
start_port_forward "$UI_SVC" "$UI_PORT" 80

UI_CODE=$(curl -o /dev/null -sf -w "%{http_code}" \
  "http://localhost:${UI_PORT}/" 2>/dev/null || echo "000")
if [[ "$UI_CODE" == "200" ]]; then
  pass "UI is reachable (HTTP $UI_CODE)"
else
  fail "UI returned HTTP $UI_CODE" "Expected 200. Is the UI deployment healthy?"
fi

# ── 12. Ingress (if present) ───────────────────────────────────────────────────
INGRESS_COUNT=$(kns get ingress --no-headers 2>/dev/null | wc -l | tr -d ' ')
if (( INGRESS_COUNT > 0 )); then
  header "12. Ingress"
  while IFS= read -r line; do
    ING_NAME=$(echo "$line" | awk '{print $1}')
    ING_ADDR=$(kns get ingress "$ING_NAME" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}' \
      2>/dev/null || echo "")
    if [[ -n "$ING_ADDR" ]]; then
      pass "Ingress '$ING_NAME' → $ING_ADDR"
    else
      warn "Ingress '$ING_NAME' address still pending (DNS/LB propagation may take a few minutes)"
    fi
  done < <(kns get ingress --no-headers 2>/dev/null)
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL_CHECKS=$((PASS + FAIL))
printf "\n${BOLD}══ Results ══════════════════════════════════${RESET}\n"
printf "  Total  : %d\n" "$TOTAL_CHECKS"
printf "  ${GREEN}Passed : %d${RESET}\n" "$PASS"

if (( FAIL > 0 )); then
  printf "  ${RED}Failed : %d${RESET}\n" "$FAIL"
  printf "\n  ${RED}${BOLD}✗ Installation has issues — see diagnostics above.${RESET}\n\n"
  printf "  Troubleshooting: https://github.com/retr0-kernel/graphon-helm/blob/main/docs/troubleshooting.md\n\n"
  exit 1
else
  printf "\n  ${GREEN}${BOLD}✓ Graphon is healthy and ready!${RESET}\n\n"
  printf "  Open the UI:\n"
  printf "    kubectl port-forward -n %s svc/%s-ui 3000:80\n" "$NAMESPACE" "$RELEASE"
  printf "    open http://localhost:3000\n\n"
  exit 0
fi
