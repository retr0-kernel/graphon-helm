#!/usr/bin/env bash
# release.sh — prepare a Graphon Helm chart release.
#
# Usage:
#   ./scripts/release.sh vX.Y.Z
#
# What it does:
#   1. Validates the semver argument
#   2. Patches Chart.yaml  (version + appVersion)
#   3. Patches values.yaml (all three image tags)
#   4. Patches README.md   (badge versions)
#   5. Runs helm dependency update
#   6. Runs helm lint --strict
#   7. Runs helm template (two profiles: embedded DBs and external DBs)
#   8. Runs helm package into /tmp/helm-pkg/
#   9. Prints next steps (commit → tag → push)
#
# After this script succeeds:
#   git add Chart.yaml Chart.lock values.yaml README.md
#   git commit -m "chore(release): prepare vX.Y.Z"
#   git tag vX.Y.Z
#   git push && git push --tags
#
# The push triggers .github/workflows/release.yml which handles:
#   • OCI push to GHCR
#   • GitHub Pages Helm repo update
#   • GitHub Release creation

set -euo pipefail

# ── Argument validation ────────────────────────────────────────────────────────

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 vX.Y.Z"
  echo "  Example: $0 v0.2.5"
  exit 1
fi

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
  echo "ERROR: '$VERSION' is not a valid semver."
  echo "  Expected: vX.Y.Z or vX.Y.Z-rc.N (e.g. v0.2.5, v0.3.0-rc.1)"
  exit 1
fi

CHART_VERSION="${VERSION#v}"   # strip leading v for Chart.yaml version field
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(dirname "$SCRIPT_DIR")"

# ── Helpers ────────────────────────────────────────────────────────────────────

GREEN="\033[0;32m"
CYAN="\033[0;36m"
BOLD="\033[1m"
RESET="\033[0m"

step() { printf "\n${BOLD}${CYAN}▶ %s${RESET}\n" "$1"; }
ok()   { printf "  ${GREEN}✓${RESET}  %s\n" "$1"; }

# ── Check dependencies ─────────────────────────────────────────────────────────

for tool in helm sed git; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: required tool '$tool' not found in PATH"
    exit 1
  fi
done

# ── Step 1: Patch Chart.yaml ───────────────────────────────────────────────────

step "Patching Chart.yaml → version: ${CHART_VERSION}, appVersion: \"${VERSION}\""

# macOS sed requires '' after -i, Linux sed does not
SED_INPLACE=(-i)
if [[ "$(uname)" == "Darwin" ]]; then
  SED_INPLACE=(-i '')
fi

sed "${SED_INPLACE[@]}" "s/^version:.*/version: ${CHART_VERSION}/" "${CHART_DIR}/Chart.yaml"
sed "${SED_INPLACE[@]}" "s/^appVersion:.*/appVersion: \"${VERSION}\"/" "${CHART_DIR}/Chart.yaml"

ok "Chart.yaml updated"
grep -E "^(version|appVersion):" "${CHART_DIR}/Chart.yaml" | sed 's/^/    /'

# ── Step 2: Patch values.yaml image tags ──────────────────────────────────────

step "Patching values.yaml image tags → ${VERSION}"

# Matches lines like:  tag: "v0.2.0"  or  tag: "0.2.0"
sed "${SED_INPLACE[@]}" -E "s|^(    tag: \")v?[0-9]+\.[0-9]+\.[0-9]+[^\"]*(\")|\1${VERSION}\2|" "${CHART_DIR}/values.yaml"

ok "values.yaml updated"
grep "tag:" "${CHART_DIR}/values.yaml" | head -6 | sed 's/^/    /'

# ── Step 3: Patch README.md badge versions ────────────────────────────────────

step "Patching README.md version badges"

sed "${SED_INPLACE[@]}" -E "s|helm-v[0-9]+\.[0-9]+\.[0-9]+-blue|helm-v${CHART_VERSION}-blue|g" "${CHART_DIR}/README.md"
sed "${SED_INPLACE[@]}" -E "s|app-v[0-9]+\.[0-9]+\.[0-9]+-green|app-v${CHART_VERSION}-green|g" "${CHART_DIR}/README.md"
# Also update OCI install example version
sed "${SED_INPLACE[@]}" -E "s|(oci://ghcr.io/retr0-kernel/charts/graphon \\\\)[[:space:]]*--version [0-9]+\.[0-9]+\.[0-9]+|\1\n  --version ${CHART_VERSION}|g" "${CHART_DIR}/README.md" 2>/dev/null || true

ok "README.md badges updated"

# ── Step 4: helm dependency update ────────────────────────────────────────────

step "Running helm dependency update"
helm dependency update "${CHART_DIR}"
ok "Dependencies updated"

# ── Step 5: helm lint --strict ────────────────────────────────────────────────

step "Running helm lint --strict (embedded DBs)"
helm lint "${CHART_DIR}" --strict
ok "Lint passed (embedded)"

step "Running helm lint --strict (external DBs)"
helm lint "${CHART_DIR}" --strict \
  --set postgresql.enabled=false \
  --set externalPostgresql.host=pg.example.com \
  --set externalPostgresql.password=ci-test \
  --set neo4j.enabled=false \
  --set externalNeo4j.boltUrl=bolt://neo4j.example.com:7687 \
  --set externalNeo4j.password=ci-test
ok "Lint passed (external)"

# ── Step 6: helm template sanity checks ───────────────────────────────────────

step "Running helm template (embedded DBs)"
helm template ci-release "${CHART_DIR}" \
  --set agent.tenantId=ci \
  --debug > /dev/null
ok "Template rendered (embedded)"

step "Running helm template (external DBs + ingress + TLS)"
helm template ci-release "${CHART_DIR}" \
  --set postgresql.enabled=false \
  --set externalPostgresql.host=pg.example.com \
  --set externalPostgresql.password=ci-test \
  --set neo4j.enabled=false \
  --set externalNeo4j.boltUrl=bolt://neo4j.example.com:7687 \
  --set externalNeo4j.password=ci-test \
  --set ingress.enabled=true \
  --set ingress.tls.enabled=true \
  --debug > /dev/null
ok "Template rendered (external + ingress)"

# ── Step 7: helm package ──────────────────────────────────────────────────────

step "Packaging chart → /tmp/helm-pkg/"
mkdir -p /tmp/helm-pkg
helm package "${CHART_DIR}" \
  --destination /tmp/helm-pkg/ \
  --version "${CHART_VERSION}" \
  --app-version "${VERSION}"

ok "Packaged:"
ls -lh /tmp/helm-pkg/graphon-*.tgz | sed 's/^/    /'

# ── Next steps ────────────────────────────────────────────────────────────────

printf "\n${BOLD}${GREEN}✓ Release ${VERSION} is ready.${RESET}\n\n"
printf "Next steps:\n"
printf "  git add Chart.yaml Chart.lock values.yaml README.md\n"
printf "  git commit -m \"chore(release): prepare %s\"\n" "$VERSION"
printf "  git tag %s\n" "$VERSION"
printf "  git push && git push --tags\n\n"
printf "Pushing the tag triggers the release workflow, which will:\n"
printf "  • Push chart to GHCR OCI  (oci://ghcr.io/retr0-kernel/charts/graphon)\n"
printf "  • Update GitHub Pages Helm repo\n"
printf "  • Create GitHub Release with install instructions\n\n"
