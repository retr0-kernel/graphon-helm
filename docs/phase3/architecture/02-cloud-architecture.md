# Graphon Cloud Architecture

## Overview

Graphon Cloud is a managed SaaS offering where customers deploy **only the eBPF Agent** in their cluster. All backend logic, graph storage, and UI run on Graphon's managed infrastructure. The same `graphon-backend` binary serves both modes; cloud mode enables multi-tenancy, tenant routing, and centralized identity.

---

## Infrastructure Stack

```
┌─────────────────────────────────────────────────────────────────────┐
│                     GRAPHON CLOUD (AWS / GCP)                        │
│                                                                       │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────────────┐    │
│  │  CloudFront │    │   api.        │    │  app.graphon.io     │    │
│  │  / CDN      │    │  graphon.io   │    │  (Next.js / Vercel) │    │
│  └─────────────┘    └──────┬───────┘    └─────────────────────┘    │
│                             │                                         │
│                    ┌────────▼────────────────────────┐               │
│                    │     API Gateway / Load Balancer  │               │
│                    │     (AWS ALB or GCP GCLB)        │               │
│                    └────────┬────────────────────────┘               │
│                             │                                         │
│              ┌──────────────┼──────────────┐                        │
│              ▼              ▼              ▼                         │
│       ┌─────────┐   ┌─────────┐   ┌─────────┐                      │
│       │Tenant A  │   │Tenant B  │   │Tenant N  │  ← K8s Namespaces  │
│       │backend  │   │backend  │   │backend  │                       │
│       └────┬────┘   └────┬────┘   └────┬────┘                      │
│            │              │              │                            │
│       ┌────▼────┐   ┌────▼────┐   ┌────▼────┐                      │
│       │  PG DB  │   │  PG DB  │   │  PG DB  │  ← RDS schema/DB     │
│       │ Neo4j A │   │ Neo4j B │   │ Neo4j N │  ← Neo4j AuraDB      │
│       └─────────┘   └─────────┘   └─────────┘                      │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Control Plane (shared)                                        │   │
│  │  • Tenant registry     • License validator                     │   │
│  │  • Cluster registration• Identity provider (Auth0 / Cognito)  │   │
│  │  • Billing hooks       • Usage metering                        │   │
│  └──────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Tenant Isolation Model

### Option A: Namespace-per-tenant (Selected)

Each tenant runs their own backend pod in a dedicated Kubernetes namespace on Graphon Cloud:

```
graphon-cloud/
  tenant-acme/      ← namespace
    deployment: graphon-backend
    secret: tenant-db-credentials
    configmap: tenant-config
  tenant-widgets/
    ...
```

**Rationale:**
- Strong process isolation
- Independent scaling per tenant
- Independent secret management
- Tenant can be migrated/evicted independently
- No shared-memory blast radius

### Database Isolation

| Layer | Strategy |
|-------|----------|
| PostgreSQL | Separate RDS instance (enterprise) OR schema-per-tenant on shared cluster (standard) |
| Neo4j | Separate AuraDB instance (enterprise) OR separate DB on shared Neo4j (community) |

---

## Agent → Cloud Communication

```
Customer Cluster                    Graphon Cloud
─────────────────                  ──────────────────
eBPF Agent
  │
  │  HTTPS (mutual TLS)
  │  POST /api/v1/events
  │  Headers:
  │    X-Tenant-ID: acme
  │    X-Cluster-ID: prod-us-east-1
  │    Authorization: Bearer <cluster-token>
  │
  └──────────────────────────────▶  API Gateway
                                      │
                                      ├─ Validate cluster token
                                      ├─ Route to tenant-acme backend
                                      └─ Store in tenant DB
```

**Cluster Token Generation:**
1. Customer creates account at app.graphon.io
2. Creates tenant (org name)
3. Clicks "Register Cluster"
4. Backend generates a signed JWT: `{ sub: cluster-id, tenant: acme, exp: 90d }`
5. Customer copies `helm install` command that embeds the token

---

## Multi-Cluster Support

```
Tenant "acme" has registered 3 clusters:
  • prod-us-east-1  (healthy, 142 services)
  • prod-eu-west-1  (healthy, 89 services)
  • staging         (degraded, 12 services)

UI shows:
  [Cluster selector dropdown]  → user picks cluster or "All Clusters"
  Cross-cluster search         → fans out to all cluster DBs
  Cluster health cards         → per-cluster event rate, last-seen
```

Backend implementation:
```go
// GET /api/v1/clusters — list all clusters for tenant
// GET /api/v1/graph?cluster=prod-us-east-1 — scoped query
// GET /api/v1/graph?cluster=* — fan-out, merge results
```

---

## Cloud Onboarding Flow

```
1. app.graphon.io/signup
   └─ Google / GitHub OAuth → create account

2. Create Organization (Tenant)
   └─ org name → creates tenant record + database

3. Register First Cluster
   └─ Enter cluster name + region
   └─ Copy generated helm command:
      helm install graphon-agent graphon/agent \
        --set cloud.endpoint=https://api.graphon.io \
        --set cloud.tenantId=acme \
        --set cloud.clusterToken=eyJ...

4. Deploy Agent
   └─ `helm install` on customer cluster
   └─ Agent starts sending events to cloud API

5. View Graph
   └─ First data visible within 60 seconds
   └─ Full graph visible after ~5 minutes of traffic
```

---

## Security Controls

| Control | Implementation |
|---------|----------------|
| Transport | mTLS between agent and cloud API |
| Authentication | Cluster JWT tokens (90-day expiry, rotatable) |
| Tenant isolation | Namespace isolation + ABAC (Kubernetes) |
| Data encryption | AES-256 at rest (RDS, EBS), TLS 1.3 in transit |
| Network | VPC-per-region, private subnets for backends |
| Secrets | AWS Secrets Manager / GCP Secret Manager |
| Audit log | All API calls logged to CloudWatch / Cloud Logging |
| Vulnerability | Regular Trivy scans on all images |
| PenTest | Annual third-party penetration test |

---

## Scalability Targets

| Metric | Target |
|--------|--------|
| Tenants | 10,000 |
| Clusters per tenant | 50 |
| Events/sec per tenant | 10,000 |
| Graph nodes per tenant | 100,000 |
| Query p99 latency | < 500ms |
| Agent connection concurrency | 50,000 |

---

## Deployment Regions (Phase 3 MVP)

- `us-east-1` — Primary (AWS)
- `eu-west-1` — EU (GDPR residency option)

Future: GCP, Azure, APAC.
