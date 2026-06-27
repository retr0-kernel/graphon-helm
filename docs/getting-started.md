# Getting Started

Graphon is a Runtime Dependency Intelligence & Governance Platform. It uses eBPF to automatically discover how services communicate inside your Kubernetes cluster — no instrumentation, no sidecars, no code changes required.

---

## What you get

- **Live dependency graph** — every TCP connection between services, updated in real time
- **Ownership discovery** — automatically maps services to teams via Kubernetes pod labels
- **Drift detection** — alerts when unexpected new dependencies appear
- **Safe-delete analysis** — tells you who depends on a service before you delete it
- **Review center** — a queue of orphans, drift events, and cleanup candidates for your team to action
- **OIDC SSO + RBAC** — enterprise-grade access control (optional, Enterprise tier)

---

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Kubernetes cluster | ≥ 1.26 | GKE, EKS, AKS, k3s, or Kind |
| Helm | ≥ 3.12 | `brew install helm` or [helm.sh](https://helm.sh/docs/intro/install/) |
| kubectl | ≥ 1.26 | configured with cluster access |
| Linux kernel on nodes | ≥ 5.4 | required for eBPF |

> **Managed node note:** The eBPF agent requires `CAP_SYS_ADMIN`. It does **not** run on GKE Autopilot or AWS Fargate. Use standard node pools on those providers.

---

## Quick Install

```bash
helm repo add graphon https://retr0-kernel.github.io/graphon
helm repo update
helm install graphon graphon/graphon --namespace graphon --create-namespace
```

Wait for all pods to be ready (typically 60–90 seconds):

```bash
kubectl get pods -n graphon -w
```

Expected output when ready:

```
NAME                               READY   STATUS    RESTARTS   AGE
graphon-backend-xxx                1/1     Running   0          90s
graphon-ui-xxx                     1/1     Running   0          90s
graphon-agent-xxx (on each node)   1/1     Running   0          90s
graphon-postgresql-0               1/1     Running   0          90s
graphon-neo4j-0                    1/1     Running   0          90s
```

Open the UI:

```bash
kubectl port-forward -n graphon svc/graphon-ui 3000:80
open http://localhost:3000
```

---

## Generate traffic (demo app)

If you don't have a running application, deploy the sample microservices to see the graph immediately:

```bash
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/examples/demo-app/
```

Within 30 seconds, 6 services and their dependencies appear in the graph view.

---

## Components deployed

| Component | What it does |
|---|---|
| `graphon-backend` | Go API server — ingests events, stores graph in Neo4j, metadata in PostgreSQL |
| `graphon-ui` | React dashboard — graph view, ownership panel, review center, settings |
| `graphon-agent` | eBPF DaemonSet — captures TCP connections on every node |
| `PostgreSQL` | Stores ownership, drift baselines, review items, sessions, API keys |
| `Neo4j` | Stores the live service dependency graph |

All components run inside your cluster. No data leaves your infrastructure.

---

## Authentication modes

### Auth disabled (default — single-tenant self-hosted)

The default install has `AUTH_DISABLED=true`. Every request is trusted; the `X-Tenant-ID` header sets the tenant.

```yaml
# This is the default — no change needed for local or single-org installs
backend:
  authDisabled: true
agent:
  tenantId: "my-company"
  clusterId: "prod"
```

### API key auth (multi-tenant / secure)

Generate a key in the UI (Settings → API Keys) or via the API, then pass it on every request:

```bash
curl -H "X-API-Key: gph_..." http://graphon-api/api/v1/graph
```

### OIDC SSO (Enterprise)

Set up single sign-on with any OIDC provider (Okta, Google Workspace, Keycloak, Azure AD):

```yaml
backend:
  authDisabled: false
oidc:
  enabled: true
  issuerUrl: "https://accounts.google.com"
  clientId: "your-client-id"
  clientSecret: "your-client-secret"
  redirectUrl: "https://graphon.example.com/oidc/callback"
```

See [Kubernetes Installation](./installation.md#oidc-sso) for the full OIDC setup.

---

## Add ownership to your services

Add labels to your pod specs so Graphon can show who owns each service:

```yaml
metadata:
  labels:
    app.graphon.io/owner-team: "payments-team"
    app.graphon.io/owner-email: "payments@example.com"
    app.graphon.io/owner-slack: "#payments-alerts"
```

No restart required — the agent reads labels on new connections. See [Ownership](./ownership.md) for details.

---

## Set up drift detection

After your services have been running for a few days, seed the baseline:

```bash
curl -X POST "http://graphon-api/api/v1/drift/seed" \
  -H "X-Tenant-ID: my-company" \
  -H "X-Cluster-ID: prod"
```

New unexpected connections will now appear as drift events in the Review Center. See [Drift Detection](./drift-detection.md).

---

## Uninstall

```bash
helm uninstall graphon -n graphon
kubectl delete namespace graphon
```

This removes all Graphon components. If you used `--set postgresql.primary.persistence.enabled=false` (the default), PostgreSQL data is gone too. If you attached a PVC, delete it separately.

---

## Next steps

- [Production installation with TLS and ingress](./installation.md)
- [Full configuration reference](./configuration.md)
- [Architecture overview](./architecture.md)
- [Troubleshooting](./troubleshooting.md)
