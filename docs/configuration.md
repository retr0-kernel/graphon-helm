# Configuration Reference

This page documents every configurable option in `values.yaml` and the environment variables the backend reads at runtime.

For installation steps, see [Kubernetes Installation](./installation.md).

---

## Global

| Key | Default | Description |
|---|---|---|
| `global.imageRegistry` | `""` | Override to pull all images from a private registry, e.g. `your-registry.io` |
| `global.imagePullSecrets` | `[]` | List of image pull secret names, e.g. `["regcred"]` |
| `global.storageClass` | `""` | Storage class for PVCs. Empty = cluster default. |

---

## Backend

### Core

| Key | Default | Description |
|---|---|---|
| `backend.enabled` | `true` | Deploy the backend. Set `false` for agent-only (Cloud mode). |
| `backend.replicaCount` | `1` | Number of backend pods. |
| `backend.image.tag` | `v0.2.7` | Docker image tag. |
| `backend.authDisabled` | `true` | `true` = self-hosted mode (X-Tenant-ID trusted, no API key required). `false` = API key required. |
| `backend.baselineDays` | `7` | Days before an `OBSERVED` edge is promoted to `BASELINE`. |
| `backend.corsOrigins` | `"*"` | Allowed CORS origins. Use a specific origin in production when OIDC is enabled. |
| `backend.deploymentMode` | `"self-hosted"` | `"self-hosted"` or `"cloud"`. |
| `backend.extraEnv` | `[]` | Inject arbitrary environment variables into the backend pod. |

### License

| Key | Default | Description |
|---|---|---|
| `backend.license.key` | `""` | Enterprise license key (JWT). Leave empty to run in Free tier. |
| `backend.license.validationEnabled` | `false` | Validate against online revocation list every 24h (requires outbound internet). |
| `backend.license.gracePeriodDays` | `14` | Days to continue operating after license expiry before downgrading to Free tier. |
| `backend.license.existingSecret` | `""` | Use a pre-existing Kubernetes secret instead of putting the key inline. |
| `backend.license.existingSecretKey` | `""` | Key name within the existing secret. |

### OIDC / SSO

| Key | Default | Description |
|---|---|---|
| `backend.oidc.enabled` | `false` | Enable OIDC SSO. Requires an Enterprise license. |
| `backend.oidc.issuerUrl` | `""` | OIDC issuer URL, e.g. `https://accounts.google.com`. |
| `backend.oidc.clientId` | `""` | OAuth 2.0 client ID. |
| `backend.oidc.clientSecret` | `""` | OAuth 2.0 client secret. Use `existingSecret` in production. |
| `backend.oidc.redirectUrl` | `""` | Callback URL, e.g. `https://graphon.example.com/auth/callback`. |
| `backend.oidc.scopes` | `"openid,email,profile,groups"` | Space or comma-separated OIDC scopes. |
| `backend.oidc.groupRoleMapping` | `""` | Map OIDC groups to Graphon roles: `"eng:admin,readonly:viewer"`. |
| `backend.oidc.sessionSecret` | `""` | 32-character random string for session signing. Auto-generated if empty. |
| `backend.oidc.existingSecret` | `""` | Use a pre-existing secret for `clientSecret` and `sessionSecret`. |

### RBAC

| Key | Default | Description |
|---|---|---|
| `backend.rbac.enabled` | `false` | Enable role-based access control. Requires OIDC or API key auth. |
| `backend.rbac.defaultRole` | `"viewer"` | Role assigned to authenticated users with no explicit role mapping. |

### GitHub Integration

| Key | Default | Description |
|---|---|---|
| `backend.github.enabled` | `false` | Enable GitHub webhook receiver and PR comment posting. |
| `backend.github.webhookSecret` | `""` | HMAC-SHA256 secret configured in your GitHub webhook settings. |
| `backend.github.token` | `""` | GitHub PAT or App installation token with `repo` write scope (for posting PR comments). |
| `backend.github.existingSecret` | `""` | Use a pre-existing Kubernetes secret instead. |

### GitLab Integration

| Key | Default | Description |
|---|---|---|
| `backend.gitlab.enabled` | `false` | Enable GitLab webhook receiver and MR note posting. |
| `backend.gitlab.instanceUrl` | `"https://gitlab.com"` | GitLab instance URL. Change for self-hosted GitLab. |
| `backend.gitlab.webhookSecret` | `""` | Secret token configured in your GitLab webhook settings. |
| `backend.gitlab.token` | `""` | GitLab PAT with `api` scope for posting MR notes. |
| `backend.gitlab.existingSecret` | `""` | Use a pre-existing Kubernetes secret instead. |

### Resources & Probes

| Key | Default | Description |
|---|---|---|
| `backend.resources.requests.cpu` | `100m` | CPU request. |
| `backend.resources.requests.memory` | `128Mi` | Memory request. |
| `backend.resources.limits.cpu` | `500m` | CPU limit. |
| `backend.resources.limits.memory` | `512Mi` | Memory limit. |
| `backend.startupProbe.failureThreshold` | `24` | Startup budget = `failureThreshold × periodSeconds`. Increase for slow clusters. |

---

## UI

| Key | Default | Description |
|---|---|---|
| `ui.enabled` | `true` | Deploy the UI. Set `false` for API-only deployments. |
| `ui.replicaCount` | `1` | Number of UI pods. |
| `ui.image.tag` | `v0.2.7` | Docker image tag. |
| `ui.apiUrl` | `""` | Backend URL as seen by the browser. Empty = in-cluster service (`http://graphon-backend:8080`). Set to your ingress hostname in production. |
| `ui.service.type` | `ClusterIP` | Service type. |
| `ui.service.port` | `80` | Service port. |

---

## eBPF Agent

| Key | Default | Description |
|---|---|---|
| `agent.enabled` | `true` | Deploy the DaemonSet on every node. |
| `agent.image.tag` | `v0.2.8` | Docker image tag. |
| `agent.flushInterval` | `5s` | How often the agent flushes captured events to the backend. |
| `agent.tenantId` | `"default"` | Tenant identifier. Must be a DNS-safe string. |
| `agent.clusterId` | `"default"` | Cluster identifier. Used to scope the graph for multi-cluster. |
| `agent.privileged` | `true` | Required for eBPF kprobe attachment. |
| `agent.tolerateAllTaints` | `true` | Run on master/control-plane nodes. |
| `agent.apiKey` | `""` | API key for agent → backend auth. Only required when `authDisabled=false`. |
| `agent.existingSecret` | `""` | Use a pre-existing Kubernetes secret for the API key. |
| `agent.backendUrl` | `""` | Override the backend URL. Used in Cloud mode to point at Graphon Cloud. |

---

## Ingress

| Key | Default | Description |
|---|---|---|
| `ingress.enabled` | `false` | Create an Ingress resource. |
| `ingress.className` | `"nginx"` | Ingress class. |
| `ingress.certManagerIssuer` | `"letsencrypt-prod"` | cert-manager ClusterIssuer name. |
| `ingress.hosts.ui` | `"graphon.example.com"` | Hostname for the UI. |
| `ingress.hosts.api` | `"api.graphon.example.com"` | Hostname for the backend API. |
| `ingress.tls.enabled` | `false` | Enable TLS. Requires cert-manager. |
| `ingress.annotations` | `{}` | Additional annotations for the Ingress resource. |

---

## PostgreSQL (embedded)

| Key | Default | Description |
|---|---|---|
| `postgresql.enabled` | `true` | Deploy embedded PostgreSQL (Bitnami chart). Set `false` to use an external instance. |
| `postgresql.auth.username` | `graphon` | Database username. |
| `postgresql.auth.database` | `graphon` | Database name. |
| `postgresql.auth.password` | `""` | Password. Auto-generated if not set. |
| `postgresql.auth.existingSecret` | `""` | Use a pre-existing secret for the password. |
| `postgresql.primary.persistence.size` | `5Gi` | PVC size. Increase to 50+ Gi in production. |

To use an external PostgreSQL instance:

```yaml
postgresql:
  enabled: false

externalPostgresql:
  host: "postgres.example.com"
  port: 5432
  database: graphon
  username: graphon
  password: "..."
  sslMode: "require"
```

---

## Neo4j (embedded)

| Key | Default | Description |
|---|---|---|
| `neo4j.enabled` | `true` | Deploy embedded Neo4j Community. |
| `neo4j.neo4j.password` | `"graphon-neo4j-password"` | **Change this in production.** |
| `neo4j.neo4j.resources.cpu` | `500m` | CPU for Neo4j pod (sets both request and limit). |
| `neo4j.neo4j.resources.memory` | `2Gi` | Memory for Neo4j pod. **Hard minimum is 2 Gi.** |
| `neo4j.volumes.data.defaultStorageClass.requests.storage` | `5Gi` | PVC size. Increase to 100+ Gi for large graphs. |

> The Neo4j community chart enforces a 2 Gi memory minimum. Each Kubernetes node must have ≥ 3 Gi allocatable memory.

To use Neo4j AuraDB (free tier) or a self-hosted instance:

```yaml
neo4j:
  enabled: false

externalNeo4j:
  boltUrl: "bolt+s://xxxxxxxx.databases.neo4j.io:7687"
  username: neo4j
  password: "..."
```

---

## Network Policy

| Key | Default | Description |
|---|---|---|
| `networkPolicy.enabled` | `false` | Create NetworkPolicy resources to restrict pod-to-pod traffic. |

---

## Environment Variables (backend)

These are set automatically from `values.yaml` by the Helm chart. You can also inject them directly via `backend.extraEnv` if needed.

| Variable | Source | Description |
|---|---|---|
| `AUTH_DISABLED` | `backend.authDisabled` | Disables API key auth when `"true"`. |
| `CORS_ORIGINS` | `backend.corsOrigins` | Allowed CORS origins. |
| `BASELINE_DAYS` | `backend.baselineDays` | Edge baseline promotion window. |
| `DEPLOYMENT_MODE` | `backend.deploymentMode` | `"self-hosted"` or `"cloud"`. |
| `GRAPHON_LICENSE_KEY` | `backend.license.key` | Enterprise license JWT. |
| `OIDC_ISSUER_URL` | `backend.oidc.issuerUrl` | OIDC provider issuer URL. |
| `OIDC_CLIENT_ID` | `backend.oidc.clientId` | OIDC client ID. |
| `OIDC_CLIENT_SECRET` | Secret `graphon-oidc` | OIDC client secret. |
| `OIDC_REDIRECT_URL` | `backend.oidc.redirectUrl` | OIDC callback URL. |
| `OIDC_SCOPES` | `backend.oidc.scopes` | OIDC scopes. |
| `OIDC_GROUP_ROLE_MAPPING` | `backend.oidc.groupRoleMapping` | Group → role mapping string. |
| `SESSION_SECRET` | `backend.oidc.sessionSecret` | Server-side session signing key. |
| `RBAC_ENABLED` | `backend.rbac.enabled` | Enables RBAC middleware. |
| `RBAC_DEFAULT_ROLE` | `backend.rbac.defaultRole` | Default role for authed users without an explicit mapping. |
| `GITHUB_WEBHOOK_SECRET` | Secret `graphon-github` | HMAC secret for GitHub webhook verification. |
| `GITHUB_TOKEN` | Secret `graphon-github` | GitHub token for posting PR comments. |
| `GITLAB_WEBHOOK_SECRET` | Secret `graphon-gitlab` | Secret token for GitLab webhook verification. |
| `GITLAB_TOKEN` | Secret `graphon-gitlab` | GitLab token for posting MR notes. |
| `GITLAB_INSTANCE_URL` | `backend.gitlab.instanceUrl` | GitLab base URL. |
| `POSTGRES_DSN` | Secret `graphon-postgresql` | PostgreSQL connection string. |
| `NEO4J_BOLT_URL` | Config map | Neo4j Bolt URL. |
| `NEO4J_USER` | Config map | Neo4j username. |
| `NEO4J_PASSWORD` | Secret `graphon-neo4j` | Neo4j password. |

### Debug/development only

| Variable | Description |
|---|---|
| `GRAPHON_LICENSE_DEV_MODE=true` | Skip RSA signature verification on license JWTs. **Never set in production.** |
| `LOG_LEVEL=debug` | Enable verbose structured logging. |
