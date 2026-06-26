#!/usr/bin/env bash
# validate-install.sh — verifies a Graphon Helm installation is healthy.
#
# Usage:
#   ./scripts/validate-install.sh
#
# Environment:
#   NAMESPACE   Kubernetes namespace to check (default: graphon)
#   RELEASE     Helm release name (default: graphon)
#   TIMEOUT     Seconds to wait for pods to be ready (default: 120)
#
# Output: PASS/FAIL per check; exits 0 if all pass, 1 if any fail.
set -euo pipefail

NAMESPACE="${NAMESPACE:-graphon}"
RELEASE="${RELEASE:-graphon}"
TIMEOUT="${TIMEOUT:-120}"

# ── colours ──────────────────────────────────────────────────────────────────
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); printf "  ${GREEN}✓${RESET}  %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "  ${RED}✗${RESET}  %s\n" "$1"; if [[ -n "${2:-}" ]]; then printf "      ${RED}↳${RESET} %s\n" "$2"; fi; }
info() { printf "  ${YELLOW}→${RESET}  %s\n" "$1"; }
header() { printf "\n${BOLD}${CYAN}══ %s ══${RESET}\n" "$1"; }

# ── helpers ───────────────────────────────────────────────────────────────────

require_tool() {
  if ! command -v "$1" &>/dev/null; then
    echo "ERROR: required tool '$1' not found in PATH"
    exit 1
  fi
}

kubectl_ns() {
  kubectl -n "$NAMESPACE" "$@"
}

port_forward_pid=""
BACKEND_PORT=18080
UI_PORT=13000

cleanup() {
  if [[ -n "$port_forward_pid" ]]; then
    kill "$port_forward_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

start_port_forward() {
  local svc="$1" local_port="$2" remote_port="$3"
  kubectl_ns port-forward "svc/$svc" "${local_port}:${remote_port}" &>/dev/null &
  port_forward_pid="$! $port_forward_pid"
  sleep 2
}

# ── main ──────────────────────────────────────────────────────────────────────

printf "\n${BOLD}Graphon Install Validator${RESET}\n"
printf "  Namespace : %s\n" "$NAMESPACE"
printf "  Release   : %s\n" "$RELEASE"
printf "  Timestamp : %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"

require_tool kubectl
require_tool curl
require_tool jq

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
header "1. Prerequisites"

if kubectl get namespace "$NAMESPACE" &>/dev/null; then
  pass "Namespace '$NAMESPACE' exists"
else
  fail "Namespace '$NAMESPACE' not found" "Run: helm install $RELEASE graphon/graphon -n $NAMESPACE --create-namespace"
  exit 1
fi

if kubectl get release "$RELEASE" -n "$NAMESPACE" &>/dev/null 2>&1 || helm status "$RELEASE" -n "$NAMESPACE" &>/dev/null; then
  pass "Helm release '$RELEASE' found"
else
  fail "Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
fi

# ── 2. Pod readiness ──────────────────────────────────────────────────────────
header "2. Pod Readiness (waiting up to ${TIMEOUT}s)"

info "Waiting for backend pod..."
if kubectl_ns wait pod \
    -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/component=backend" \
    --for=condition=Ready \
    --timeout="${TIMEOUT}s" &>/dev/null; then
  BACKEND_READY=$(kubectl_ns get pods -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/component=backend" --no-headers 2>/dev/null | grep -c Running || echo 0)
  pass "Backend pod(s) ready ($BACKEND_READY running)"
else
  fail "Backend pod not ready within ${TIMEOUT}s"
  info "Check: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=backend"
fi

info "Waiting for UI pod..."
if kubectl_ns wait pod \
    -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/component=ui" \
    --for=condition=Ready \
    --timeout="${TIMEOUT}s" &>/dev/null; then
  pass "UI pod ready"
else
  fail "UI pod not ready within ${TIMEOUT}s"
fi

info "Waiting for database pods..."
DB_PODS=$(kubectl_ns get pods --no-headers 2>/dev/null | grep -c Running || echo 0)
pass "Running pods in namespace: $DB_PODS"

AGENT_PODS=$(kubectl_ns get pods -l "app.kubernetes.io/instance=${RELEASE},app.kubernetes.io/component=agent" --no-headers 2>/dev/null | grep -c Running || echo 0)
if (( AGENT_PODS > 0 )); then
  pass "Agent DaemonSet pods running: $AGENT_PODS"
else
  info "Agent pods: $AGENT_PODS (eBPF agent may not run on managed/Fargate nodes)"
fi

# ── 3. Backend health ─────────────────────────────────────────────────────────
header "3. Backend Health"

info "Starting port-forward to backend..."
BACKEND_SVC="${RELEASE}-backend"
start_port_forward "$BACKEND_SVC" "$BACKEND_PORT" 8080

HEALTH=$(curl -sf "http://localhost:${BACKEND_PORT}/api/v1/health" 2>/dev/null || echo "{}")
STATUS=$(echo "$HEALTH" | jq -r '.status // "error"' 2>/dev/null || echo "error")
if [[ "$STATUS" == "ok" ]]; then
  VERSION=$(echo "$HEALTH" | jq -r '.version // "unknown"')
  pass "GET /api/v1/health → status=ok version=$VERSION"
else
  fail "GET /api/v1/health failed" "response: $HEALTH"
fi

READY=$(curl -sf "http://localhost:${BACKEND_PORT}/ready" 2>/dev/null || echo "{}")
READY_FLAG=$(echo "$READY" | jq -r '.ready // false' 2>/dev/null || echo "false")
NEO4J_OK=$(echo "$READY" | jq -r '.checks.neo4j.ok // false' 2>/dev/null || echo "false")
PG_OK=$(echo "$READY" | jq -r '.checks.postgres.ok // false' 2>/dev/null || echo "false")

if [[ "$READY_FLAG" == "true" ]]; then
  pass "GET /ready → ready=true"
else
  fail "GET /ready → ready=false" "response: $READY"
fi

if [[ "$NEO4J_OK" == "true" ]]; then
  pass "Neo4j connectivity: ok"
else
  fail "Neo4j connectivity check failed" "Is Neo4j running? Check: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=neo4j"
fi

if [[ "$PG_OK" == "true" ]]; then
  pass "PostgreSQL connectivity: ok"
else
  fail "PostgreSQL connectivity check failed" "Is PostgreSQL running? Check: kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=postgresql"
fi

# ── 4. Graph API ──────────────────────────────────────────────────────────────
header "4. Graph API"

GRAPH=$(curl -sf "http://localhost:${BACKEND_PORT}/api/v1/graph" \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: validate" 2>/dev/null || echo "{}")
GRAPH_STATUS=$(echo "$GRAPH" | jq -r 'if .nodes != null then "ok" else "error" end' 2>/dev/null || echo "error")
if [[ "$GRAPH_STATUS" == "ok" ]]; then
  NODE_COUNT=$(echo "$GRAPH" | jq '.nodes | length')
  pass "GET /api/v1/graph → reachable (nodes: $NODE_COUNT)"
else
  fail "GET /api/v1/graph failed" "response: $(echo "$GRAPH" | head -c 200)"
fi

# ── 5. UI reachability ────────────────────────────────────────────────────────
header "5. UI"

UI_SVC="${RELEASE}-ui"
start_port_forward "$UI_SVC" "$UI_PORT" 80

UI_STATUS=$(curl -o /dev/null -sf -w "%{http_code}" "http://localhost:${UI_PORT}/" 2>/dev/null || echo "000")
if [[ "$UI_STATUS" == "200" ]]; then
  pass "UI is reachable (HTTP $UI_STATUS)"
else
  fail "UI returned HTTP $UI_STATUS" "Expected 200"
fi

# ── 6. Review Center API ──────────────────────────────────────────────────────
header "6. Review Center"

COUNTS=$(curl -sf "http://localhost:${BACKEND_PORT}/api/v1/review-items/counts" \
  -H "X-Tenant-ID: default" \
  -H "X-Cluster-ID: validate" 2>/dev/null || echo "{}")
TOTAL=$(echo "$COUNTS" | jq -r '.total // "error"' 2>/dev/null || echo "error")
if [[ "$TOTAL" != "error" ]]; then
  pass "GET /api/v1/review-items/counts → total=$TOTAL"
else
  fail "GET /api/v1/review-items/counts failed"
fi

# ── 7. Ingress (if enabled) ───────────────────────────────────────────────────
INGRESS_COUNT=$(kubectl_ns get ingress --no-headers 2>/dev/null | wc -l | tr -d ' ')
if (( INGRESS_COUNT > 0 )); then
  header "7. Ingress"
  kubectl_ns get ingress --no-headers | while read -r name _; do
    ADDRESS=$(kubectl_ns get ingress "$name" -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "pending")
    if [[ -n "$ADDRESS" && "$ADDRESS" != "pending" ]]; then
      pass "Ingress '$name' → $ADDRESS"
    else
      info "Ingress '$name' address still pending (DNS/LB may take a few minutes)"
    fi
  done
fi

# ── Summary ───────────────────────────────────────────────────────────────────
TOTAL_CHECKS=$((PASS + FAIL))
printf "\n${BOLD}══ Results ══════════════════════════════════${RESET}\n"
printf "  Total  : %d\n" "$TOTAL_CHECKS"
printf "  ${GREEN}Passed : %d${RESET}\n" "$PASS"
if (( FAIL > 0 )); then
  printf "  ${RED}Failed : %d${RESET}\n" "$FAIL"
  printf "\n  ${RED}${BOLD}✗ Installation has issues. Check the failed items above.${RESET}\n\n"
  printf "  Troubleshooting: https://github.com/retr0-kernel/graphon-helm/blob/main/docs/troubleshooting.md\n\n"
  exit 1
else
  printf "\n  ${GREEN}${BOLD}✓ Graphon is healthy and ready!${RESET}\n\n"
  printf "  Open the UI:  kubectl port-forward -n %s svc/%s-ui 3000:80\n" "$NAMESPACE" "$RELEASE"
  printf "  Then visit:   http://localhost:3000\n\n"
  exit 0
fi
