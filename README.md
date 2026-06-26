# Graphon Helm Chart

[![Helm Version](https://img.shields.io/badge/helm-v0.2.6-blue)](https://github.com/retr0-kernel/graphon-helm)
[![App Version](https://img.shields.io/badge/app-v0.2.6-green)](https://github.com/retr0-kernel/graphon-helm)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/graphon)](https://artifacthub.io/packages/search?repo=graphon)

**Graphon** is a Runtime Dependency Intelligence & Governance Platform that uses eBPF to automatically map service dependencies in Kubernetes — no instrumentation, no sidecars, no code changes.

## Install

**OCI (recommended):**
```bash
helm install graphon oci://ghcr.io/retr0-kernel/charts/graphon \
  --version 0.2.0 \
  --namespace graphon \
  --create-namespace
```

**Classic Helm repo:**
```bash
helm repo add graphon https://retr0-kernel.github.io/graphon-helm
helm repo update
helm install graphon graphon/graphon --namespace graphon --create-namespace
```

## Access

```bash
kubectl port-forward -n graphon svc/graphon-ui 3000:80
open http://localhost:3000
```

## Documentation

| Guide | Description |
|---|---|
| [Getting Started](./docs/getting-started.md) | 5-minute quickstart |
| [Kubernetes Installation](./docs/kubernetes-installation.md) | Production install with TLS |
| [Architecture](./docs/architecture.md) | How Graphon works |
| [Ownership Labels](./docs/ownership-labels.md) | Auto-discover service owners |
| [Drift Detection](./docs/drift-detection.md) | Detect unexpected dependencies |
| [Safe Delete](./docs/safe-delete.md) | Risk analysis before decommissioning |
| [Troubleshooting](./docs/troubleshooting.md) | Fix common issues |
| [Release Process](./docs/release-process.md) | How releases are published |

## Values Quick Reference

```yaml
# Minimal production override
backend:
  replicaCount: 2
  authDisabled: false
  baselineDays: 14

agent:
  tenantId: "my-company"

ingress:
  enabled: true
  className: nginx
  certManagerIssuer: letsencrypt-prod
  hosts:
    ui: graphon.example.com
    api: api.graphon.example.com
  tls:
    enabled: true
```

Full values reference: [`values.yaml`](./values.yaml)

## Validate Installation

```bash
NAMESPACE=graphon RELEASE=graphon ./scripts/validate-install.sh
```

## Release a New Version

```bash
./scripts/release.sh v0.2.5
git add -A && git commit -m "chore(release): prepare v0.2.5"
git tag v0.2.5 && git push && git push --tags
```

## Demo App

Deploy sample microservices to see Graphon working immediately:

```bash
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon-helm/main/examples/demo-app/
```

## Source

| Repository | Description |
|---|---|
| [graphon-helm](https://github.com/retr0-kernel/graphon-helm) | This Helm chart |
| [graphon-backend](https://github.com/retr0-kernel/graphon-backend) | Go API server |
| [graphon-ui](https://github.com/retr0-kernel/graphon-ui) | React dashboard |
| [graphon-bpf](https://github.com/retr0-kernel/graphon-bpf) | eBPF agent |
