# Production Readiness Checklist

## Infrastructure

- [ ] Cluster has ≥ 3 nodes (for HA)
- [ ] Each node has ≥ 4 vCPU and ≥ 8 GB RAM
- [ ] PersistentVolumes backed by durable storage (not hostPath)
- [ ] StorageClass supports volume expansion
- [ ] Network policy support available (Calico / Cilium / Weave)

## Installation

- [ ] Installed with `-f values-production.yaml`
- [ ] Neo4j password changed from default (`graphon-neo4j-password`)
- [ ] Production license key applied
- [ ] External databases used (RDS, AuraDB) or embedded DBs backed up
- [ ] Image pull secrets configured for private registries
- [ ] All `imagePullPolicy: IfNotPresent` (not `Always` in production)

## Network

- [ ] Ingress controller installed (NGINX or Traefik)
- [ ] TLS certificate provisioned (cert-manager + Let's Encrypt)
- [ ] `backend.auth.enabled: true` if exposed to internet
- [ ] `backend.corsOrigins` set to specific domains (not `*`)
- [ ] Agent → backend network path verified (`curl` from agent pod)

## Security

- [ ] RBAC enabled (`rbac.enabled: true`)
- [ ] SSO configured (`auth.oidc.issuerUrl` set)
- [ ] Secrets not stored in values.yaml plaintext (use `existingSecret`)
- [ ] Pod security policy / security context configured
- [ ] `runAsNonRoot: true` on all non-privileged containers
- [ ] Network policies restrict ingress to only required ports
- [ ] Audit log enabled (Enterprise license required)

## Observability

- [ ] Prometheus scraping enabled (`/metrics` endpoint accessible)
- [ ] Alerting on `graphon_backend_ready=0`
- [ ] Alerting on pod `CrashLoopBackOff`
- [ ] Log aggregation configured (Loki / ELK / Splunk)
- [ ] Health dashboard created

## Backup

- [ ] PostgreSQL backup schedule configured (minimum: daily)
- [ ] Neo4j backup schedule configured
- [ ] PVC snapshots automated
- [ ] Backup restore tested

## Disaster Recovery

- [ ] DR runbook documented
- [ ] RTO/RPO defined
- [ ] Restore from backup tested
- [ ] Multi-region or cross-AZ failover considered

## Performance

- [ ] Backend resources match expected load (see values-production.yaml)
- [ ] Neo4j heap sized for graph complexity
- [ ] Agent flush interval tuned for event volume
- [ ] Database connection pool size verified

## Operations

- [ ] Upgrade runbook documented
- [ ] On-call rotation covers Graphon alerts
- [ ] Graphon version pinned (not `latest`)
- [ ] Rollback procedure tested
- [ ] `helm history` shows at least 2 revisions (rollback available)
