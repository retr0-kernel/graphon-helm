# Kubernetes Installation Guide

This guide covers a complete production installation of Graphon on Kubernetes — from a fresh cluster to a running, TLS-secured deployment with external databases.

For a quick 3-command install, see [Getting Started](./getting-started.md).

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Add the Helm Repository](#1-add-the-helm-repository)
3. [Minimal Install (embedded databases)](#2-minimal-install-embedded-databases)
4. [Production Install (external databases + TLS)](#3-production-install-external-databases--tls)
5. [Configuration Reference](#4-configuration-reference)
6. [Upgrading](#5-upgrading)
7. [Uninstalling](#6-uninstalling)
8. [Air-gapped Installation](#7-air-gapped-installation)

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Kubernetes | ≥ 1.26 | GKE, EKS, AKS, k3s |
| Helm | ≥ 3.12 | `brew install helm` |
| kubectl | ≥ 1.26 | included with cluster CLI |
| cert-manager | ≥ 1.13 (optional) | TLS automation |
| NGINX Ingress | any (optional) | external access |

> **Node requirement:** The eBPF agent runs only on Linux nodes with kernel ≥ 5.4. It requires `CAP_SYS_ADMIN`. It does **not** work on GKE Autopilot, AWS Fargate, or Azure Virtual Nodes.

---

## 1. Add the Helm Repository

```bash
helm repo add graphon https://retr0-kernel.github.io/graphon
helm repo update
```

Verify the chart is available:
```bash
helm search repo graphon --versions
```

---

## 2. Minimal Install (embedded databases)

The simplest path — PostgreSQL and Neo4j are installed automatically as chart sub-charts.

**Best for:** evaluation, development, small teams.

```bash
# Create namespace
kubectl create namespace graphon

# Install with defaults (embedded PostgreSQL + Neo4j)
helm install graphon graphon/graphon \
  --namespace graphon \
  --set agent.tenantId="my-company"
```

Wait for all pods to be ready (Neo4j takes 60–90s):
```bash
kubectl get pods -n graphon -w
```

Expected output:
```
NAME                              READY   STATUS    RESTARTS
graphon-backend-xxx               1/1     Running   0
graphon-ui-xxx                    1/1     Running   0
graphon-agent-xxx (on each node)  1/1     Running   0
graphon-postgresql-0              1/1     Running   0
graphon-neo4j-0                   1/1     Running   0
```

Access the UI:
```bash
kubectl port-forward -n graphon svc/graphon-ui 3000:80 &
open http://localhost:3000
```

---

## 3. Production Install (external databases + TLS)

**Best for:** production deployments, managed databases (RDS, Cloud SQL, Neo4j AuraDB).

### 3.1 Install cert-manager (if not present)

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

Create a ClusterIssuer:
```yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            ingressClassName: nginx
```
```bash
kubectl apply -f cluster-issuer.yaml
```

### 3.2 Install NGINX Ingress (if not present)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

Get the external IP:
```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
# Wait for EXTERNAL-IP to be assigned, then configure your DNS:
# graphon.example.com     → EXTERNAL-IP
# api.graphon.example.com → EXTERNAL-IP
```

### 3.3 Create database secrets

Never put passwords in `values.yaml` or pass them on the command line in CI.

```bash
# PostgreSQL secret
kubectl create secret generic graphon-postgres-secret \
  --namespace graphon \
  --from-literal=password='YOUR_POSTGRES_PASSWORD'

# Neo4j secret
kubectl create secret generic graphon-neo4j-secret \
  --namespace graphon \
  --from-literal=password='YOUR_NEO4J_PASSWORD'
```

### 3.4 Create production values file

```yaml
# production-values.yaml

backend:
  replicaCount: 2
  authDisabled: false   # Enable API key authentication in production
  baselineDays: 14
  corsOrigins: "https://graphon.example.com"
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi

ui:
  replicaCount: 2
  apiUrl: "https://api.graphon.example.com"
  resources:
    requests:
      cpu: 100m
      memory: 128Mi

agent:
  tenantId: "my-company"
  flushInterval: "5s"

ingress:
  enabled: true
  className: "nginx"
  certManagerIssuer: "letsencrypt-prod"
  hosts:
    ui: "graphon.example.com"
    api: "api.graphon.example.com"
  tls:
    enabled: true
    uiSecretName: "graphon-ui-tls"
    apiSecretName: "graphon-api-tls"

# Disable embedded databases — use external
postgresql:
  enabled: false
neo4j:
  enabled: false

# External PostgreSQL (e.g. RDS, Cloud SQL)
externalPostgresql:
  host: "your-postgres.region.rds.amazonaws.com"
  port: 5432
  database: graphon
  username: graphon
  existingSecret: "graphon-postgres-secret"
  existingSecretKey: "password"
  sslMode: "require"

# External Neo4j (e.g. Neo4j AuraDB or self-managed)
externalNeo4j:
  boltUrl: "bolt+s://your-aura-id.databases.neo4j.io:7687"
  username: neo4j
  existingSecret: "graphon-neo4j-secret"
  existingSecretKey: "password"
```

### 3.5 Install

```bash
helm install graphon graphon/graphon \
  --namespace graphon \
  --create-namespace \
  --values production-values.yaml
```

### 3.6 Validate

```bash
# Wait for pods
kubectl get pods -n graphon -w

# Run full validation
NAMESPACE=graphon RELEASE=graphon \
  bash <(curl -sSL https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/scripts/validate-install.sh)
```

### 3.7 Create your first API key

With `AUTH_DISABLED=false`, all API calls require an API key:

```bash
kubectl port-forward -n graphon svc/graphon-backend 8080:8080 &

# Create key (only X-Tenant-ID is needed to bootstrap the first key)
curl -X POST http://localhost:8080/api/v1/auth/keys \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: my-company" \
  -d '{"name": "production-key"}' | jq .

# Save the returned key — it's only shown once
export GRAPHON_KEY="gph_..."

# All subsequent API calls use X-API-Key:
curl http://localhost:8080/api/v1/graph \
  -H "X-API-Key: $GRAPHON_KEY" \
  -H "X-Cluster-ID: prod-cluster" | jq .
```

---

## 4. Configuration Reference

### Backend

| Value | Default | Description |
|---|---|---|
| `backend.replicaCount` | `1` | Number of backend replicas |
| `backend.image.tag` | `v0.2.0` | Image version |
| `backend.authDisabled` | `true` | Set `false` to require API keys |
| `backend.baselineDays` | `7` | Days before OBSERVED edges become BASELINE |
| `backend.corsOrigins` | `*` | Comma-separated allowed CORS origins |
| `backend.resources` | see values.yaml | CPU/memory requests and limits |

### Agent

| Value | Default | Description |
|---|---|---|
| `agent.tenantId` | `default` | Tenant identifier sent with all events |
| `agent.flushInterval` | `5s` | How often to send events to backend |
| `agent.privileged` | `true` | Required for eBPF |
| `agent.tolerateAllTaints` | `true` | Run on all nodes including control-plane |

### Databases

| Value | Default | Description |
|---|---|---|
| `postgresql.enabled` | `true` | Install embedded PostgreSQL |
| `postgresql.primary.persistence.size` | `10Gi` | Storage for embedded PostgreSQL |
| `neo4j.enabled` | `true` | Install embedded Neo4j |
| `neo4j.volumes.data.defaultStorageClass.requests.storage` | `10Gi` | Storage for embedded Neo4j |

---

## 5. Upgrading

```bash
helm repo update

# Preview changes:
helm diff upgrade graphon graphon/graphon \
  --namespace graphon \
  --values production-values.yaml

# Apply:
helm upgrade graphon graphon/graphon \
  --namespace graphon \
  --values production-values.yaml
```

> **Database note:** Upgrades to embedded Neo4j or PostgreSQL may require manual StatefulSet recreation if pod template labels change. Always snapshot data before upgrading.

---

## 6. Uninstalling

```bash
helm uninstall graphon --namespace graphon

# Delete namespace (also deletes PVCs — data loss!)
kubectl delete namespace graphon
```

To keep data PVCs:
```bash
helm uninstall graphon --namespace graphon
# PVCs remain — reinstall will reuse them
```

---

## 7. Air-gapped Installation

For environments without internet access:

### 7.1 Pull images on a machine with internet access

```bash
VERSION="v0.2.0"
IMAGES=(
  "ghcr.io/retr0-kernel/graphon-backend:$VERSION"
  "ghcr.io/retr0-kernel/graphon-ui:$VERSION"
  "ghcr.io/retr0-kernel/graphon-agent:$VERSION"
)
for img in "${IMAGES[@]}"; do
  docker pull "$img"
  docker save "$img" -o "$(echo $img | tr '/:' '_').tar"
done
```

### 7.2 Transfer and load into your private registry

```bash
for tar in *.tar; do
  docker load -i "$tar"
  # Re-tag and push to your registry
  ORIGINAL=$(docker load -i "$tar" 2>&1 | awk '{print $NF}')
  PRIVATE="your-registry.io/${ORIGINAL#ghcr.io/retr0-kernel/}"
  docker tag "$ORIGINAL" "$PRIVATE"
  docker push "$PRIVATE"
done
```

### 7.3 Override image registry in values

```yaml
# airgap-values.yaml
global:
  imageRegistry: "your-registry.io"

backend:
  image:
    registry: "your-registry.io"
    repository: "graphon-backend"
    tag: "v0.2.0"

ui:
  image:
    registry: "your-registry.io"
    repository: "graphon-ui"
    tag: "v0.2.0"

agent:
  image:
    registry: "your-registry.io"
    repository: "graphon-agent"
    tag: "v0.2.0"
```

### 7.4 Package the Helm chart

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add neo4j https://helm.neo4j.com/neo4j
helm dependency update graphon-helm/
helm package graphon-helm/
# Transfer graphon-0.2.0.tgz to the air-gapped environment
helm install graphon ./graphon-0.2.0.tgz --values airgap-values.yaml -n graphon --create-namespace
```
