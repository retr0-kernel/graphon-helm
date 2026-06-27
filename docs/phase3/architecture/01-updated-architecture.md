# Updated System Architecture — Graphon v3

## Overview

Graphon v3 is a **Runtime Dependency Intelligence Platform** with a unified backend codebase serving two deployment modes. The architecture extends the Phase 2 monolith by adding horizontal concerns — licensing, multi-tenancy, RBAC, SSO, multi-cluster, and optional SaaS hosting — without splitting the service into microservices.

---

## High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SELF-HOSTED MODE                              │
│                                                                       │
│  ┌──────────────┐    ┌─────────────────────────────────────────┐    │
│  │  eBPF Agent  │───▶│           graphon-backend                │    │
│  │  (DaemonSet) │    │                                          │    │
│  └──────────────┘    │  ┌─────────┐  ┌─────────┐  ┌────────┐  │    │
│                       │  │  Auth   │  │  RBAC   │  │License │  │    │
│  ┌──────────────┐    │  │  (OIDC) │  │ Engine  │  │ Engine │  │    │
│  │  graphon-ui  │◀──▶│  └─────────┘  └─────────┘  └────────┘  │    │
│  └──────────────┘    │                                          │    │
│                       │  ┌──────────┐  ┌───────────────────┐   │    │
│                       │  │ Graph API│  │  Dependency Store  │   │    │
│                       │  │ (Neo4j)  │  │   (PostgreSQL)     │   │    │
│                       │  └──────────┘  └───────────────────┘   │    │
│                       └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        CLOUD MODE                                     │
│                                                                       │
│  Customer Cluster A           Customer Cluster B                     │
│  ┌──────────────┐             ┌──────────────┐                      │
│  │  eBPF Agent  │──┐          │  eBPF Agent  │──┐                   │
│  └──────────────┘  │          └──────────────┘  │                   │
│                    ▼                             ▼                   │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                    Graphon Cloud                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │  Tenant Router  →  graphon-backend (shared)             │  │  │
│  │  │  Tenant A DB    │  Tenant B DB    │  Tenant N DB        │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  │  ┌─────────────────────────────────────────────────────────┐  │  │
│  │  │  Graphon Cloud UI  (multi-tenant, multi-cluster)        │  │  │
│  │  └─────────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Backend Module Map (monolith, extended)

```
graphon-backend/
  cmd/server/main.go          ← entrypoint, unchanged
  internal/
    config/config.go          ← extended with license, auth, mode config
    auth/                     ← NEW: OIDC/SSO middleware
      oidc.go
      jwt.go
      session.go
    rbac/                     ← NEW: role engine
      roles.go
      permissions.go
      middleware.go
    license/                  ← NEW: licensing engine
      engine.go
      validator.go
      gates.go
      storage.go
    tenant/                   ← NEW: tenant isolation
      context.go
      resolver.go
      router.go
    cluster/                  ← NEW: multi-cluster registry
      registry.go
      health.go
    graph/                    ← EXTENDED: historical + export
      snapshot.go             ← NEW
      diff.go                 ← NEW
      export.go               ← NEW
    search/                   ← NEW: advanced full-text search
      engine.go
      indexer.go
    store/                    ← existing PostgreSQL layer
    api/v1/                   ← extended with new routes
      handlers/
        auth.go               ← NEW
        license.go            ← NEW
        clusters.go           ← NEW
        snapshots.go          ← NEW
        export.go             ← NEW
        search.go             ← NEW
```

---

## Data Flow — Self-Hosted

```
1. eBPF Agent captures tcp_connect on every node
2. Agent enriches with K8s pod metadata (namespace, labels, owner)
3. Agent batches events and POSTs to /api/v1/events (X-Tenant-ID header)
4. Backend validates license, authenticates request
5. Backend writes edge to PostgreSQL (time-series events)
6. Backend writes/updates vertex+edge in Neo4j (graph)
7. UI queries via /api/v1/graph/* — authenticated by session
8. RBAC controls which namespaces/clusters user can see
```

---

## Data Flow — Cloud

```
1. Customer deploys Helm chart (agent-only) with cloud endpoint
2. Agent sends events to api.graphon.io with tenant token
3. Cloud API layer routes to tenant-scoped backend instance
4. Data stored in tenant-isolated PostgreSQL schema + Neo4j database
5. Customer accesses app.graphon.io — SSO login
6. UI tenant-resolves from auth token
```

---

## Key Architectural Principles (v3)

| Principle | Decision |
|-----------|----------|
| Single codebase | Same binary for self-hosted and cloud |
| Mode detection | `DEPLOYMENT_MODE=self-hosted\|cloud` env var |
| Tenant isolation | PostgreSQL schema-per-tenant, Neo4j db-per-tenant |
| License enforcement | In-process Go, no external call on hot path |
| Auth | OIDC-native, no custom password flows |
| RBAC | Attribute-based (tenant + role + resource) |
| Multi-cluster | Cluster registry in PostgreSQL, graph query fan-out |
| Backwards compat | All Phase 1+2 APIs remain at v1 |
| No microservices | Horizontal concerns are modules, not services |

---

## New Configuration Parameters (v3)

```yaml
# values.yaml additions
graphon:
  mode: "self-hosted"   # self-hosted | cloud

  license:
    key: ""                       # leave empty for free tier
    validationEndpoint: ""        # optional online validation URL
    gracePeriodDays: 14

  auth:
    enabled: false                # set true to require login
    provider: "oidc"              # oidc | local
    oidc:
      issuerUrl: ""               # https://accounts.google.com
      clientId: ""
      clientSecret: ""            # use existingSecret in prod
      redirectUrl: ""
      scopes: ["openid", "email", "profile", "groups"]

  rbac:
    enabled: false                # set true to enforce RBAC
    defaultRole: "viewer"

  multiCluster:
    enabled: false
    registrationToken: ""         # generated per-org
```

---

## Observability (v3 additions)

Every new module emits structured `log/slog` entries with:
- `module` — which subsystem
- `tenant_id` — tenant context
- `cluster_id` — cluster context  
- `user_id` — authenticated user (hashed)
- `operation` — what action
- `duration_ms` — latency
- `error` — error message when applicable

Prometheus metrics exposed at `/metrics`:
- `graphon_license_validation_total{result="ok|expired|invalid"}`
- `graphon_auth_attempts_total{provider="oidc|local", result="ok|failed"}`
- `graphon_rbac_denials_total{role, resource}`
- `graphon_clusters_registered_total`
- `graphon_graph_snapshots_total`
- `graphon_search_queries_total{type}`
