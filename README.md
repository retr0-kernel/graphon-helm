# Graphon Helm Chart

[![Helm Version](https://img.shields.io/badge/helm-v0.2.0-blue)](https://github.com/retr0-kernel/graphon)
[![App Version](https://img.shields.io/badge/app-v0.2.0-green)](https://github.com/retr0-kernel/graphon)

**Graphon** is a Runtime Dependency Intelligence & Governance Platform that uses eBPF to automatically map service dependencies in Kubernetes — no instrumentation, no sidecars, no code changes.

## Install

```bash
helm repo add graphon https://retr0-kernel.github.io/graphon
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

## Demo App

Deploy sample microservices to see Graphon working immediately:

```bash
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/examples/demo-app/
```

## Source

GitHub: https://github.com/retr0-kernel/graphon
# graphon-helm
