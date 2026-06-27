# Self-Hosted Architecture — All Database Configurations

## Overview

Self-Hosted mode supports four database configurations. The same Helm chart handles all of them via `values.yaml` flags. No code change required.

---

## Configuration Matrix

| Mode | PostgreSQL | Neo4j | Use case |
|------|-----------|-------|----------|
| 1 | Embedded (Bitnami) | Embedded (neo4j/neo4j) | Default, dev, small teams |
| 2 | External | Embedded (neo4j/neo4j) | Teams with managed Postgres (RDS, CloudSQL) |
| 3 | Embedded (Bitnami) | External (AuraDB / managed) | Teams using Neo4j AuraDB free/professional |
| 4 | External | External | Full external — enterprise production |

---

## Mode 1: Both Embedded (Default)

```bash
# Nothing to configure — just install
helm install graphon graphon/graphon -n graphon --create-namespace
```

Pros: Zero config, works immediately  
Cons: State lives in PVCs, not managed, no HA  
Recommended for: Dev, CI, small internal tools, evaluation  

---

## Mode 2: External PostgreSQL, Embedded Neo4j

```bash
helm install graphon graphon/graphon -n graphon \
  --set postgresql.enabled=false \
  --set externalPostgresql.host=my-rds.us-east-1.rds.amazonaws.com \
  --set externalPostgresql.port=5432 \
  --set externalPostgresql.database=graphon \
  --set externalPostgresql.username=graphon \
  --set externalPostgresql.password=<password>
```

Or using an existing Secret:
```bash
kubectl create secret generic graphon-pg-secret \
  -n graphon --from-literal=password=<password>

helm install graphon graphon/graphon -n graphon \
  --set postgresql.enabled=false \
  --set externalPostgresql.host=my-rds.us-east-1.rds.amazonaws.com \
  --set externalPostgresql.existingSecret=graphon-pg-secret \
  --set externalPostgresql.existingSecretKey=password
```

### Supported PostgreSQL Providers

| Provider | Tested | Notes |
|----------|--------|-------|
| Amazon RDS (PostgreSQL) | ✓ | Set `sslMode=require` |
| Amazon Aurora PostgreSQL | ✓ | Use writer endpoint |
| Azure Database for PostgreSQL | ✓ | Flexible Server, set SSL |
| Google Cloud SQL (PostgreSQL) | ✓ | Use Cloud SQL Auth Proxy or direct |
| Supabase | ✓ | Use connection pooler (PgBouncer) URL |
| Neon | ✓ | Serverless Postgres, set `sslMode=require` |
| Self-managed PostgreSQL | ✓ | Any version ≥ 14 |
| CockroachDB | ⚠ | PostgreSQL-compatible, not fully tested |

---

## Mode 3: Embedded PostgreSQL, External Neo4j

```bash
helm install graphon graphon/graphon -n graphon \
  --set neo4j.enabled=false \
  --set externalNeo4j.boltUrl=neo4j+s://abc123.databases.neo4j.io \
  --set externalNeo4j.username=neo4j \
  --set externalNeo4j.password=<password>
```

### Supported Neo4j Providers

| Provider | Tested | Connection String |
|----------|--------|-------------------|
| Neo4j AuraDB (Free) | ✓ | `neo4j+s://xxx.databases.neo4j.io` |
| Neo4j AuraDB (Professional) | ✓ | Same |
| Neo4j AuraDB (Enterprise) | ✓ | Same |
| Self-managed Neo4j Community | ✓ | `bolt://neo4j.internal:7687` |
| Self-managed Neo4j Enterprise | ✓ | `bolt://neo4j.internal:7687` |
| Neo4j on K8s (separate namespace) | ✓ | `bolt://neo4j.neo4j-ns.svc.cluster.local:7687` |

---

## Mode 4: Both External

```bash
helm install graphon graphon/graphon -n graphon \
  --set postgresql.enabled=false \
  --set neo4j.enabled=false \
  --set externalPostgresql.host=my-rds.example.com \
  --set externalPostgresql.username=graphon \
  --set externalPostgresql.existingSecret=pg-secret \
  --set externalNeo4j.boltUrl=neo4j+s://xxx.databases.neo4j.io \
  --set externalNeo4j.existingSecret=neo4j-secret
```

This mode is recommended for production. All stateful data lives outside the Helm release, enabling:
- Independent backup/restore
- Managed HA
- Independent scaling
- Zero-downtime Graphon upgrades

---

## SSL/TLS Configuration

### PostgreSQL

```yaml
externalPostgresql:
  sslMode: "require"    # disable | require | verify-full
  # For verify-full, mount CA certificate:
  sslCaCertSecret: "pg-ca-cert"
  sslCaCertKey: "ca.crt"
```

### Neo4j

Connection string protocol encodes TLS:
- `bolt://`  — no TLS
- `bolt+s://` — TLS, system CA
- `neo4j+s://` — cluster-aware, TLS (AuraDB always uses this)
- `bolt+ssc://` — self-signed certificate

---

## Database Prerequisites

### PostgreSQL
```sql
-- Graphon creates its own schema; only needs these privileges:
CREATE DATABASE graphon;
CREATE USER graphon WITH PASSWORD '...';
GRANT ALL PRIVILEGES ON DATABASE graphon TO graphon;
-- Extension needed for UUID generation:
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
```

### Neo4j
- Community edition: single database `neo4j` (default)
- Enterprise edition: Graphon can use a dedicated database
- No pre-configuration needed — schema created on first start

---

## Health Check Integration

The backend `/ready` endpoint reports database connectivity:
```json
{
  "ready": true,
  "checks": {
    "postgres": { "ok": true, "latency_ms": 2 },
    "neo4j":    { "ok": true, "latency_ms": 5 }
  }
}
```

If either is unhealthy, `ready: false` and the K8s readiness probe fails, routing no traffic to the pod until databases recover.
