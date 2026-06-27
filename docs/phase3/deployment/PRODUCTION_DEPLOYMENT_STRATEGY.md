# Production Deployment Strategy

## Upgrade Path

### Patch Release (0.2.x → 0.2.y)
```bash
helm repo update
helm upgrade graphon graphon/graphon -n graphon --reuse-values
```
- Zero downtime rolling update
- No migration required
- Safe to apply immediately

### Minor Release (0.2.x → 0.3.x)
```bash
# 1. Review CHANGELOG.md for breaking changes
# 2. Take manual snapshot (data backup)
kubectl exec -n graphon svc/graphon-backend -- \
  curl -X POST http://localhost:8080/api/v1/snapshots \
  -d '{"label":"pre-upgrade-v0.3"}'

# 3. Upgrade
helm repo update
helm upgrade graphon graphon/graphon -n graphon \
  --reuse-values \
  -f values-production.yaml

# 4. Verify
kubectl rollout status deployment/graphon-backend -n graphon
curl http://localhost:8080/ready
```
- Migrations run automatically on backend startup
- Rollback available: `helm rollback graphon 1` (reverts to previous revision)

### Major Release (0.x → 1.0.0)
- Dedicated migration guide published per major version
- Database schema migration scripts included
- Blue-green deployment recommended for zero downtime

---

## Blue-Green Deployment (Zero-Downtime Major Upgrades)

```bash
# Install new version in parallel namespace
helm install graphon-v3 graphon/graphon -n graphon-v3 \
  --create-namespace \
  --set externalPostgresql.host=<production-db>  # same external DB
  --set externalNeo4j.boltUrl=<production-neo4j>

# Validate new version
kubectl get pods -n graphon-v3
curl http://graphon-v3.internal/ready

# Switch ingress to new version
kubectl patch ingress graphon-ingress -n graphon \
  --patch '{"spec":{"rules":[{"host":"graphon.example.com","http":{"paths":[{"backend":{"service":{"name":"graphon-v3-backend"}}}]}}]}}'

# Decommission old version after validation period
helm uninstall graphon -n graphon
```

---

## Rollback Procedure

```bash
# View available revisions
helm history graphon -n graphon

# Rollback to previous revision
helm rollback graphon 1 -n graphon

# Rollback to specific revision
helm rollback graphon 3 -n graphon
```

Database rollback: only required for major versions with destructive schema changes. Standard upgrades are additive only.

---

## External Database Migration

### Moving from Embedded → External PostgreSQL

```bash
# 1. Dump embedded database
kubectl exec -n graphon graphon-postgresql-0 -- \
  pg_dump -U graphon graphon > graphon-backup.sql

# 2. Restore to external database
psql -h my-rds.example.com -U graphon graphon < graphon-backup.sql

# 3. Upgrade Helm values to use external
helm upgrade graphon graphon/graphon -n graphon \
  --set postgresql.enabled=false \
  --set externalPostgresql.host=my-rds.example.com \
  --reuse-values
```

### Moving from Embedded → External Neo4j

```bash
# 1. Export graph data via Graphon API
curl http://localhost:8080/api/v1/export \
  -d '{"format":"dot"}' > graph-export.dot

# 2. Restore via Neo4j import or Cypher LOAD CSV
# (specific steps depend on graph complexity)

# 3. Upgrade Helm values
helm upgrade graphon graphon/graphon -n graphon \
  --set neo4j.enabled=false \
  --set externalNeo4j.boltUrl=neo4j+s://xxx.databases.neo4j.io \
  --reuse-values
```

---

## Observability Plan

### Metrics (Prometheus)

Exposed at `/metrics` (Prometheus scrape format):

```
# Backend health
graphon_backend_ready{} 1

# License
graphon_license_expiry_days{plan="enterprise"} 180
graphon_license_validation_total{result="ok|expired|invalid"}

# Events pipeline
graphon_events_received_total{cluster="prod"}
graphon_events_processed_total
graphon_events_dropped_total{reason="validation_failed|db_error"}

# API
graphon_http_requests_total{method, path, status}
graphon_http_request_duration_seconds{method, path, quantile}

# Database
graphon_db_query_duration_seconds{db="postgres|neo4j", operation}
graphon_db_connections_active{db}

# Graph
graphon_graph_nodes_total{cluster}
graphon_graph_edges_total{cluster}
graphon_snapshots_total{tenant}
```

### Recommended Alerts

| Alert | Condition | Severity |
|-------|-----------|----------|
| BackendDown | `graphon_backend_ready == 0` | Critical |
| DatabaseUnreachable | DB query error rate > 10% | Critical |
| LicenseExpiringSoon | `graphon_license_expiry_days < 14` | Warning |
| HighEventDrop | Drop rate > 5% | Warning |
| AgentOffline | No events in 10 min from cluster | Warning |
| SlowQueries | p99 > 2s | Warning |

### Logging Standards

All logs use `log/slog` structured JSON format:
```json
{"time":"2026-06-27T12:00:00Z","level":"INFO","msg":"...","module":"...","tenant_id":"...","cluster_id":"...","duration_ms":12}
```

Log levels:
- `DEBUG` — development only, disabled in production
- `INFO` — normal operation milestones
- `WARN` — degraded state, recoverable
- `ERROR` — operational failure requiring attention
- `CRITICAL` — data loss or security event

---

## Security Review Plan

| Category | Action | Frequency |
|----------|--------|-----------|
| Dependency audit | `govulncheck ./...` + `trivy image` | Every release |
| SAST | `gosec ./...` | Every PR |
| Secret scanning | `truffleHog` in CI | Every commit |
| Container scan | Trivy in CI | Every image build |
| Pen test | Third-party | Annual |
| SBOM | `syft` attached to release | Every release |

---

## Performance Review Plan

### Benchmarks to Maintain

| Operation | Target | Current baseline |
|-----------|--------|-----------------|
| Graph query (1000 nodes) | < 200ms p99 | TBD |
| Event ingest | 10,000 events/sec | TBD |
| Snapshot creation | < 5s (10k nodes) | TBD |
| Search query | < 100ms p99 | TBD |
| Export (PNG, 500 nodes) | < 3s | TBD |

### Load Testing

```bash
# k6 load test against events endpoint
k6 run scripts/load-test-events.js --vus=50 --duration=60s

# Expected: < 1% error rate at 5000 events/sec
```
