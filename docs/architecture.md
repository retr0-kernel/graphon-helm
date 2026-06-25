# Graphon Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  Your Kubernetes Cluster                                            │
│                                                                     │
│  ┌─────────────────────┐        ┌──────────────────────────────┐   │
│  │  graphon-agent      │        │  graphon-ui (React + Vite)   │   │
│  │  DaemonSet          │        │  Deployment                  │   │
│  │                     │        │  • Graph visualization       │   │
│  │  eBPF kprobe:       │        │  • Ownership management      │   │
│  │  tcp_connect hook   │        │  • Review center             │   │
│  │                     │        │  • Settings / API keys       │   │
│  │  K8s enrichment:    │        └──────────────┬───────────────┘   │
│  │  IP → Pod/Namespace │                       │ REST API calls    │
│  │  Pod labels →       │                       ▼                   │
│  │  owner_team         │        ┌──────────────────────────────┐   │
│  └──────────┬──────────┘        │  graphon-backend (Go+Fiber)  │   │
│             │ POST /ingest      │                              │   │
│             └──────────────────►│  • Ingestion API             │   │
│                                 │  • Graph queries             │   │
│                                 │  • Ownership engine          │   │
│                                 │  • Drift detection           │   │
│                                 │  • Safe delete analysis      │   │
│                                 │  • Review center             │   │
│                                 │  • Background scheduler      │   │
│                                 │  • Slack notifications       │   │
│                                 └──────┬──────────────┬────────┘   │
│                                        │              │            │
│                               ┌────────▼──┐   ┌───────▼────────┐  │
│                               │  Neo4j    │   │  PostgreSQL    │  │
│                               │ Community │   │                │  │
│                               │           │   │ • api_keys     │  │
│                               │ Service   │   │ • ownership    │  │
│                               │ nodes     │   │ • drift_base.  │  │
│                               │ CALLS     │   │ • review_items │  │
│                               │ edges     │   │ • slack_config │  │
│                               └───────────┘   └────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Data Flow

### 1. Event Capture (eBPF Agent)

```
Linux Kernel tcp_connect kprobe
  → IP pair captured (src_ip, dst_ip, dst_port)
  → Kubernetes informer enrichment (IP → Pod name, Namespace, Labels)
  → owner_team extracted from pod labels app.graphon.io/owner-team
  → DependencyEvent buffered in memory
  → Flush every 5s → POST /api/v1/ingest/events
```

### 2. Ingestion (Backend)

```
POST /api/v1/ingest/events
  → Validate tenant + cluster headers
  → For each event:
      MERGE Service/Database/Namespace node in Neo4j
      MERGE CALLS edge (increment weight)
      UpsertEdgeBaseline in PostgreSQL (drift tracking)
      If owner_team present: UpsertOwnership in PostgreSQL + Neo4j
  → INSERT ingestion_events in PostgreSQL (audit)
  → Return {accepted, rejected}
```

### 3. Governance (Background Scheduler)

```
Every 15 min: Orphan Scanner
  → Query Neo4j for Service nodes with null owner_team
  → For each orphan: UpsertReviewItem (ORPHAN, deduped)
  → If Slack enabled + notify_orphan: POST webhook

Every 10 min: Drift Scanner
  → MarkDriftEdges: new OBSERVED edges → DRIFT (if BASELINE edges exist)
  → For each DRIFT edge: UpsertReviewItem (DRIFT, deduped)
  → If Slack enabled + notify_drift: POST webhook

Every 1 hour: Cleanup Scanner
  → Query Neo4j for Service nodes not seen for > BASELINE_DAYS
  → UpsertReviewItem (CLEANUP, deduped)

Every 1 hour: Baseline Promotion
  → PromoteObservedBaselines: OBSERVED edges older than BASELINE_DAYS → BASELINE
```

## Deployment Modes

### Self-Hosted Mode (default)

The full stack runs inside the customer's cluster. `AUTH_DISABLED=true` — no API key required; `X-Tenant-ID` header is trusted.

```yaml
# values.yaml
backend:
  authDisabled: true
agent:
  tenantId: "my-company"
```

### Graphon Cloud Mode

The agent runs in the customer cluster. The backend and databases run in Graphon's infrastructure. `AUTH_DISABLED=false` — all requests require an API key.

```yaml
# Minimal values for cloud-agent-only deployment:
backend:
  enabled: false
ui:
  enabled: false
postgresql:
  enabled: false
neo4j:
  enabled: false
agent:
  tenantId: "my-company"
  # BACKEND_URL is set to the Graphon Cloud ingest endpoint
  backendUrl: "https://ingest.graphon.io"
```

## Database Schema

### Neo4j

| Node Label | Key Properties |
|---|---|
| `Service` | `id`, `name`, `namespace`, `tenant_id`, `cluster_id`, `owner_team`, `is_orphan` |
| `Database` | `id`, `name`, `port`, `db_type`, `tenant_id`, `cluster_id` |
| `Namespace` | `id`, `name`, `tenant_id`, `cluster_id` |

**Relationships:**
- `(Service)-[:CALLS {weight}]->(Service)`
- `(Service)-[:CALLS {weight}]->(Database)`
- `(Namespace)-[:CONTAINS]->(Service)`

### PostgreSQL

| Table | Purpose |
|---|---|
| `ingestion_events` | Audit log per ingest batch |
| `api_keys` | Tenant API keys (SHA-256 hashed) |
| `ownership_assignments` | Service-to-team ownership |
| `drift_baselines` | Dependency edge lifecycle tracking |
| `review_items` | Governance review queue |
| `slack_configs` | Slack webhook settings per tenant |

## Node ID Scheme

All IDs are deterministic property-based strings — stable across restarts, upgrades, and exports:

| Type | Format |
|---|---|
| Service | `svc:{tenant_id}:{cluster_id}:{namespace}:{name}` |
| Database | `db:{tenant_id}:{cluster_id}:{ip}:{port}` |
| Namespace | `ns:{tenant_id}:{cluster_id}:{name}` |

No Neo4j internal IDs are exposed in any API response.
