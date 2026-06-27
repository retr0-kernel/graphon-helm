# Graphon Documentation

**Graphon** is a Runtime Dependency Intelligence & Governance Platform for Kubernetes. It uses eBPF to automatically discover how your services communicate — no instrumentation, no sidecars, no code changes required.

---

## Getting Started

| Guide | Description |
|---|---|
| [Getting Started](./getting-started.md) | Install in 3 commands, see data in 5 minutes |
| [Kubernetes Installation](./installation.md) | Full installation guide — TLS, ingress, external DBs, production |
| [Configuration Reference](./configuration.md) | All `values.yaml` options and environment variables |

## Core Features

| Guide | Description |
|---|---|
| [Ownership Labels](./ownership.md) | Auto-discover service ownership from Kubernetes pod labels |
| [Drift Detection](./drift-detection.md) | Get alerted when unexpected new dependencies appear |
| [Safe Delete Analysis](./safe-delete.md) | Assess risk before decommissioning a service |

## Operations

| Guide | Description |
|---|---|
| [Architecture](./architecture.md) | How Graphon works internally — eBPF, ingestion, graph, databases |
| [Troubleshooting](./troubleshooting.md) | Diagnose common issues with logs and commands |
| [Upgrade Guide](./upgrade.md) | Upgrade from previous versions — breaking changes, migration steps |

## Testing & Demos

| Guide | Description |
|---|---|
| [Self-Hosted Testing](./SELF_HOSTED_TESTING.md) | End-to-end validation on a real Kind cluster with real workloads |
| [Demo Presentation Guide](./DEMO_PRESENTATION_GUIDE.md) | Exact commands, timing, talking points, and a recovery playbook for live demos |

## Contributing

| Guide | Description |
|---|---|
| [Contributing](./contributing.md) | How to build locally, submit issues, and contribute code |

---

## Overview

```
Your Kubernetes Cluster
├── graphon-agent (DaemonSet)   — eBPF on every node, zero-instrumentation
├── graphon-backend (Deployment)— Go API, graph queries, governance engine
├── graphon-ui (Deployment)     — React dashboard
├── PostgreSQL                  — ownership, drift, review items, sessions
└── Neo4j                       — live service dependency graph
```

Graphon runs fully **self-hosted** inside your cluster. There is no external callback, no phone-home, and no data leaves your infrastructure.

---

## Deployment Modes

| Mode | Description |
|---|---|
| **Self-Hosted (Free)** | Full stack in your cluster. `AUTH_DISABLED=true` for single-tenant. |
| **Self-Hosted (Enterprise)** | Full stack with OIDC SSO, RBAC, multi-cluster, and a license key. |
| **Graphon Cloud** | Agent only in your cluster; backend hosted by Graphon. _Coming soon._ |

---

## Helm Chart

```bash
helm repo add graphon https://retr0-kernel.github.io/graphon
helm repo update
helm search repo graphon
```

Current chart version: **0.3.0** | App version: **v0.3.0**

---

## Links

- [GitHub Repository](https://github.com/retr0-kernel/graphon)
- [Open an Issue](https://github.com/retr0-kernel/graphon/issues)
- [Helm Chart Source](https://github.com/retr0-kernel/graphon/tree/main/graphon-helm)
