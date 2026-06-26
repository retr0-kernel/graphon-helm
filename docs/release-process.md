# Release Process

This document describes how to cut a production release of Graphon across all four repositories.

## Repository Overview

| Repository | Visibility | Publishes |
|---|---|---|
| `graphon-backend` | private | `ghcr.io/retr0-kernel/graphon-backend` |
| `graphon-ui` | private | `ghcr.io/retr0-kernel/graphon-ui` |
| `graphon-bpf` | private | `ghcr.io/retr0-kernel/graphon-agent` |
| `graphon-helm` | **public** | OCI chart + GitHub Pages helm repo |

## Release Trigger

Every release is triggered by pushing a semver git tag to the target repository. The CI workflows do the rest automatically.

```
git tag v0.2.1
git push origin v0.2.1
```

Tags follow [Semantic Versioning](https://semver.org/):
- `v1.0.0` — stable release
- `v1.0.0-rc.1` — pre-release (does not overwrite `latest`)

---

## Step-by-Step Release Walkthrough

### 1 — Release the Backend

```bash
cd graphon-backend
git checkout main && git pull

# Bump the release notes if needed:
# Edit docs/releases/v0.2.1.md

git tag v0.2.1
git push origin v0.2.1
```

**What happens:**
```
Tag pushed (v0.2.1)
  → CI: go test -race ./...
  → CI: docker buildx (linux/amd64, linux/arm64)
  → CI: push ghcr.io/retr0-kernel/graphon-backend:0.2.1
  → CI: push ghcr.io/retr0-kernel/graphon-backend:0.2
  → CI: push ghcr.io/retr0-kernel/graphon-backend:latest
  → CI: create GitHub Release "graphon-backend v0.2.1"
```

**Verify:**
```bash
docker pull ghcr.io/retr0-kernel/graphon-backend:0.2.1
docker inspect ghcr.io/retr0-kernel/graphon-backend:0.2.1 | jq '.[0].Os'
```

---

### 2 — Release the UI

```bash
cd graphon-ui
git checkout main && git pull

git tag v0.2.1
git push origin v0.2.1
```

**What happens:**
```
Tag pushed (v0.2.1)
  → CI: npm ci && tsc --noEmit && npm run build
  → CI: docker buildx (linux/amd64, linux/arm64)
  → CI: push ghcr.io/retr0-kernel/graphon-ui:0.2.1
  → CI: push ghcr.io/retr0-kernel/graphon-ui:latest
  → CI: create GitHub Release "graphon-ui v0.2.1"
```

---

### 3 — Release the Agent

```bash
cd graphon-bpf
git checkout main && git pull

git tag v0.2.1
git push origin v0.2.1
```

**What happens:**
```
Tag pushed (v0.2.1)
  → CI: go test (non-eBPF packages)
  → CI: docker buildx (linux/amd64 only — eBPF is arch-specific)
  → CI: push ghcr.io/retr0-kernel/graphon-agent:0.2.1
  → CI: push ghcr.io/retr0-kernel/graphon-agent:latest
  → CI: create GitHub Release "graphon-agent v0.2.1" with install instructions
```

> **Why amd64 only?** eBPF kprobe programs attach to kernel functions at specific memory offsets that differ by architecture. BTF-based CO-RE maps for arm64 require separate kernel headers and are validated independently. See `graphon-bpf/docs/` for roadmap.

---

### 4 — Update the Helm Chart

After all three images are published, update the default image tags in `values.yaml`:

```bash
cd graphon-helm
git checkout main && git pull
```

Edit `values.yaml`:

```yaml
# values.yaml
backend:
  image:
    tag: "v0.2.1"   # ← bump this

ui:
  image:
    tag: "v0.2.1"   # ← bump this

agent:
  image:
    tag: "v0.2.1"   # ← bump this
```

Commit and tag:

```bash
git add values.yaml
git commit -m "chore: release v0.2.1"
git tag v0.2.1
git push origin main v0.2.1
```

**What happens:**
```
Tag pushed (v0.2.1)
  → CI: helm dependency update (fetches bitnami/postgresql + neo4j sub-charts)
  → CI: helm lint --strict (two configurations: embedded + external DBs)
  → CI: helm template sanity check (embedded + external + ingress + TLS)
  → CI: helm package graphon-0.2.1.tgz
  → CI: helm push oci://ghcr.io/retr0-kernel/charts/graphon:0.2.1
  → CI: update gh-pages branch with new tgz + regenerated index.yaml
  → CI: create GitHub Release "graphon-helm v0.2.1" attaching graphon-0.2.1.tgz
```

**Verify chart published:**
```bash
# OCI
helm show chart oci://ghcr.io/retr0-kernel/charts/graphon --version 0.2.1

# Classic helm repo
helm repo add graphon https://retr0-kernel.github.io/graphon-helm
helm repo update
helm search repo graphon --versions
```

---

## Pre-release (release candidates)

All four repos support pre-release tags. The `latest` tag is **not** overwritten for pre-releases.

```bash
# In each repo:
git tag v0.3.0-rc.1
git push origin v0.3.0-rc.1
```

This publishes:
- `ghcr.io/retr0-kernel/graphon-backend:0.3.0-rc.1` (no `latest`)
- `graphon-0.3.0-rc.1.tgz` (chart marked `prerelease: true`)

Install a pre-release:
```bash
helm install graphon oci://ghcr.io/retr0-kernel/charts/graphon \
  --version 0.3.0-rc.1 \
  --namespace graphon --create-namespace
```

---

## Rollback

Helm makes rollback trivial:

```bash
# See release history
helm history graphon -n graphon

# Rollback to the previous release
helm rollback graphon -n graphon

# Rollback to a specific revision
helm rollback graphon 3 -n graphon
```

To roll back Docker images explicitly:
```bash
helm upgrade graphon graphon/graphon \
  --set backend.image.tag=v0.2.0 \
  --set ui.image.tag=v0.2.0 \
  --set agent.image.tag=v0.2.0 \
  -n graphon
```

---

## Hotfix Process

For urgent patches between scheduled releases:

```bash
# 1. Create hotfix branch from the tag
git checkout -b hotfix/v0.2.1 v0.2.0
# Fix the bug
git commit -m "fix: ..."

# 2. Tag from the hotfix branch (NOT main)
git tag v0.2.1
git push origin hotfix/v0.2.1 v0.2.1

# 3. Merge hotfix back to main
git checkout main
git merge hotfix/v0.2.1
git push origin main

# 4. Delete the hotfix branch
git branch -d hotfix/v0.2.1
git push origin --delete hotfix/v0.2.1
```

---

## Release Checklist

```
BEFORE TAGGING:
  [ ] All PRs for this milestone are merged
  [ ] CHANGELOG / docs/releases/vX.Y.Z.md is written
  [ ] Integration tests pass locally against the new version
  [ ] values.yaml image tags updated in graphon-helm (for Helm release)

BACKEND:
  [ ] git tag vX.Y.Z && git push origin vX.Y.Z
  [ ] CI: all checks green
  [ ] Verify: docker pull ghcr.io/retr0-kernel/graphon-backend:X.Y.Z

UI:
  [ ] git tag vX.Y.Z && git push origin vX.Y.Z
  [ ] CI: all checks green
  [ ] Verify: docker pull ghcr.io/retr0-kernel/graphon-ui:X.Y.Z

AGENT:
  [ ] git tag vX.Y.Z && git push origin vX.Y.Z
  [ ] CI: all checks green
  [ ] Verify: docker pull ghcr.io/retr0-kernel/graphon-agent:X.Y.Z

HELM:
  [ ] Update values.yaml image tags → commit → git tag vX.Y.Z
  [ ] CI: all checks green
  [ ] Verify: helm show chart oci://ghcr.io/retr0-kernel/charts/graphon --version X.Y.Z
  [ ] Verify: helm repo update && helm search repo graphon

POST-RELEASE:
  [ ] Close the GitHub milestone
  [ ] Announce in Slack / community channels
  [ ] Update graphon.io documentation site (if applicable)
```

---

## CI Workflow Summary

| Repo | Workflow | Trigger | Does |
|---|---|---|---|
| graphon-backend | `build.yml` | push main / PR | go test, go build |
| graphon-backend | `release.yml` | git tag `v*` | test → multi-arch Docker → GHCR → GitHub Release |
| graphon-ui | `build.yml` | push main / PR | tsc, npm build |
| graphon-ui | `release.yml` | git tag `v*` | build-check → multi-arch Docker → GHCR → GitHub Release |
| graphon-bpf | `build.yml` | push main / PR | go test, go build (amd64) |
| graphon-bpf | `release.yml` | git tag `v*` | test → Docker (amd64 only) → GHCR → GitHub Release |
| graphon-helm | `release.yml` | git tag `v*` | lint → package → OCI push → gh-pages → GitHub Release |
