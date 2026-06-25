# Getting Started with Graphon

Graphon is a Runtime Dependency Intelligence & Governance Platform. It uses eBPF to automatically discover how services communicate inside Kubernetes — no instrumentation, no sidecars, no code changes.

## What you get in 5 minutes

- A live service dependency graph updated in real time
- Automatic ownership discovery from Kubernetes pod labels
- Drift detection when new unexpected dependencies appear
- Safe-delete risk analysis before you delete a service

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Kubernetes cluster | ≥ 1.26 | GKE, EKS, AKS, or k3s |
| Helm | ≥ 3.12 | `brew install helm` |
| kubectl | ≥ 1.26 | configured with cluster access |
| Linux kernel on nodes | ≥ 5.4 | required for eBPF agent |

> **Managed node caveat:** The eBPF agent requires `CAP_SYS_ADMIN`. It does **not** run on GKE Autopilot or AWS Fargate. Use standard node pools.

## Quick Install (3 commands)

```bash
helm repo add graphon https://retr0-kernel.github.io/graphon
helm repo update
helm install graphon graphon/graphon --namespace graphon --create-namespace
```

Wait for pods to be ready:

```bash
kubectl get pods -n graphon -w
```

Access the UI:

```bash
kubectl port-forward -n graphon svc/graphon-ui 3000:80
open http://localhost:3000
```

## What just got deployed?

| Component | What it does |
|---|---|
| **graphon-backend** | Go API server — stores graph in Neo4j, metadata in PostgreSQL |
| **graphon-ui** | React dashboard — graph view, ownership panel, review center |
| **graphon-agent** | eBPF DaemonSet — captures TCP connections on every node |
| **PostgreSQL** | Stores ownership, drift baselines, review items, API keys |
| **Neo4j** | Stores the service dependency graph |

## See data immediately (demo app)

If you don't have a live application, deploy our sample microservices:

```bash
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/examples/demo-app/
```

Within 30 seconds you'll see 6 services and their dependencies in the graph.

## Next steps

- [Add ownership labels to your pods](./ownership-labels.md)
- [Set up drift detection baselines](./drift-detection.md)
- [Production installation with TLS](./kubernetes-installation.md)
- [Architecture overview](./architecture.md)
