# Documentation Portal Architecture

## URL Structure

`docs.graphon.io` — dedicated documentation site (separate from marketing site)

---

## Site Structure

```
docs.graphon.io
├─ /                          Documentation home / search
├─ /getting-started
│   ├─ /quickstart             5-minute install
│   ├─ /concepts               Key concepts explained
│   └─ /first-graph            Interpreting your first graph
│
├─ /installation
│   ├─ /helm                   Helm chart installation
│   ├─ /self-hosted            Self-Hosted complete guide
│   ├─ /cloud                  Graphon Cloud setup
│   ├─ /external-postgres      External PostgreSQL guide
│   ├─ /external-neo4j         External Neo4j guide
│   ├─ /air-gapped             Air-gapped / offline installation
│   └─ /upgrade                Upgrade guide
│
├─ /configuration
│   ├─ /values-reference       All Helm values documented
│   ├─ /dev-profile            Development cluster sizing
│   ├─ /production-profile     Production sizing guide
│   ├─ /auth                   Authentication setup
│   ├─ /rbac                   RBAC configuration
│   └─ /licensing              License key management
│
├─ /features
│   ├─ /dependency-graph       Graph visualization guide
│   ├─ /drift-detection        Drift detection usage
│   ├─ /safe-delete            Safe delete analysis
│   ├─ /ownership-labels       Ownership label schema
│   ├─ /multi-cluster          Multi-cluster management
│   ├─ /historical-graph       Snapshots and time-travel
│   ├─ /search                 Advanced search usage
│   └─ /export                 Architecture export formats
│
├─ /integrations
│   ├─ /github-app             GitHub App setup
│   └─ /gitlab-app             GitLab App setup
│
├─ /api-reference
│   ├─ /overview               API authentication, base URL
│   ├─ /graph                  Graph API endpoints
│   ├─ /events                 Events API (agent → backend)
│   ├─ /clusters               Cluster management API
│   ├─ /snapshots              Historical graph API
│   ├─ /search                 Search API
│   ├─ /export                 Export API
│   └─ /webhooks               Incoming webhook API
│
├─ /operations
│   ├─ /production-best-practices
│   ├─ /performance-tuning
│   ├─ /observability          Metrics, logs, traces
│   ├─ /backup-restore
│   ├─ /disaster-recovery
│   └─ /scaling
│
├─ /security
│   ├─ /overview
│   ├─ /network-policies
│   ├─ /secrets-management
│   └─ /compliance
│
├─ /troubleshooting
│   ├─ /common-issues
│   ├─ /agent-debugging
│   ├─ /database-connectivity
│   ├─ /graph-empty
│   └─ /upgrade-issues
│
├─ /contributing
│   ├─ /development-setup
│   ├─ /architecture-decisions
│   ├─ /testing
│   └─ /release-process
│
└─ /changelog
    ├─ /v0.2.x
    └─ /v0.3.x
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Docusaurus 3 / Nextra |
| Language | MDX (Markdown + React) |
| Search | Algolia DocSearch (free for OSS) |
| Versioning | Docusaurus versioning |
| API docs | OpenAPI spec + Swagger UI |
| Deployment | Vercel / GitHub Pages |
| Analytics | Plausible |

---

## Documentation Standards

Every page must include:

1. **Purpose** — what the feature does, one sentence
2. **Prerequisites** — what's needed before
3. **Configuration** — all relevant Helm values with types and defaults
4. **Step-by-step** — numbered instructions
5. **Expected output** — what success looks like
6. **Troubleshooting** — 3-5 common failure modes
7. **Next steps** — links to related docs

---

## API Reference Generation

The backend exposes OpenAPI 3.0 spec at `/api/v1/openapi.json`. Documentation portal auto-generates API reference from this spec.

Every API endpoint documents:
- HTTP method + path
- Required permissions (RBAC role)
- Required license tier
- Request body schema
- Response schema
- Error codes
- Example request + response (curl)
