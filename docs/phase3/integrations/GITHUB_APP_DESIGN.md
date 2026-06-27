# GitHub App Integration Design

## Overview

The Graphon GitHub App analyzes Terraform, Helm, Kubernetes YAML, and ArgoCD changes on every pull request and generates an impact report showing how the proposed changes affect the live dependency graph.

---

## Capabilities

| Feature | Description |
|---------|-------------|
| Dependency change summary | Which service dependencies are added/removed |
| Architecture change detection | New services, removed services, namespace changes |
| Risk analysis | Services affected downstream, blast radius |
| Drift detection | Does PR match live graph? |
| Historical comparison | Compare proposed state vs snapshot at tag/commit |

---

## How It Works

```
Developer opens PR → GitHub fires webhook
                            │
                     Graphon GitHub App
                            │
                     ┌──────┴──────────────────────────────┐
                     │  1. Parse changed files               │
                     │     - *.tf (Terraform)                │
                     │     - Chart.yaml + values.yaml        │
                     │     - k8s/*.yaml (Deployments, etc.)  │
                     │     - Application.yaml (ArgoCD)        │
                     ├──────────────────────────────────────┤
                     │  2. Extract service graph changes     │
                     │     - New Deployments / StatefulSets  │
                     │     - Changed environment variables   │
                     │     - Changed service endpoints       │
                     │     - Changed ingress rules           │
                     ├──────────────────────────────────────┤
                     │  3. Compare with live graph from API  │
                     │     GET /api/v1/graph?cluster=prod    │
                     ├──────────────────────────────────────┤
                     │  4. Generate impact report            │
                     └──────────────────────────────────────┘
                            │
                     Post PR comment + check status
```

---

## PR Comment Format

```markdown
## 🔍 Graphon Dependency Impact Analysis

**Cluster:** prod-us-east-1  
**Snapshot baseline:** pre-deploy (2026-06-27 09:00 UTC)

### Changes Detected

| Type | Count |
|------|-------|
| ➕ New services | 1 |
| 🔄 Modified services | 2 |
| ❌ Removed services | 0 |
| ➕ New dependencies | 3 |
| ❌ Removed dependencies | 1 |

### New Services
- `fraud-detection-v2` (namespace: `payments`)

### New Dependencies
- `checkout-service` → `fraud-detection-v2` (port 8443)
- `fraud-detection-v2` → `postgres` (port 5432)
- `fraud-detection-v2` → `redis` (port 6379)

### Removed Dependencies
- `checkout-service` → `fraud-detection-v1` ⚠️ (still running — zombie dependency?)

### Risk Assessment
- **Risk level:** 🟡 Medium
- `checkout-service` is called by 4 other services — changes may have broad impact
- `fraud-detection-v1` still receives traffic from `checkout-service` in live graph

[View full graph →](https://graphon.example.com/graph?cluster=prod&focus=checkout-service)
```

---

## GitHub App Setup (Self-Hosted)

### Step 1: Create GitHub App

```
GitHub → Settings → Developer Settings → GitHub Apps → New GitHub App

Name: Graphon (or your-company-graphon)
Homepage URL: https://graphon.example.com
Webhook URL: https://graphon.example.com/api/v1/webhooks/github
Webhook Secret: <random-256-bit>

Permissions:
  Repository: Pull Requests → Read & Write (to post comments)
  Repository: Contents → Read (to read changed files)
  Repository: Checks → Read & Write (to post check status)
```

### Step 2: Configure Graphon

```yaml
# values.yaml
backend:
  github:
    enabled: true
    appId: "123456"
    installationId: "789012"
    privateKeySecret: "graphon-github-app-key"
    webhookSecret: ""          # use existingSecret
    defaultCluster: "prod-us-east-1"
    postCheckStatus: true
    postPRComment: true
```

### Step 3: Install App on Repositories

GitHub App installation page → select repositories to analyze.

---

## File Type Parsers

### Kubernetes YAML Parser

Extracts:
- `kind: Deployment/StatefulSet/DaemonSet` → service node
- `spec.containers[].env` → downstream dependencies (e.g., `REDIS_URL`, `DATABASE_URL`)
- `spec.containers[].ports` → exposed ports
- `metadata.labels` → ownership information

### Helm Chart Parser

Extracts:
- `Chart.yaml` dependencies → service graph nodes
- `values.yaml` image tags → version changes
- Service templates → port/endpoint changes

### Terraform Parser

Extracts:
- `kubernetes_deployment` resources → service nodes
- `kubernetes_service` resources → exposed endpoints
- Environment variable changes → dependency hints

### ArgoCD Application Parser

Extracts:
- `spec.source.repoURL` + `spec.source.path` → links code to live service
- `spec.destination.namespace` → namespace context

---

## GitLab Integration

Identical capabilities, implemented via GitLab Webhooks API:
- MR events instead of PR events
- GitLab API for comment posting
- GitLab CI status instead of GitHub Checks

See [GITLAB_APP_DESIGN.md](GITLAB_APP_DESIGN.md) for GitLab-specific details.
