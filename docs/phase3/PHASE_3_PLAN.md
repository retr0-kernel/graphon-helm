# Phase 3 — Commercial Productionization: Master Plan

**Status:** Planning  
**Version:** 3.0.0  
**Target:** Enterprise-ready commercial platform  

---

## Overview

Phase 3 transforms Graphon from an open-source MVP into a commercial-grade platform supporting two distinct deployment modes: **Self-Hosted** (free, Kubernetes-native) and **Graphon Cloud** (managed SaaS, multi-tenant). The same backend codebase serves both modes, differentiated at runtime by deployment configuration and license entitlements.

---

## Deployment Modes Summary

| Dimension | Self-Hosted | Graphon Cloud |
|-----------|-------------|---------------|
| Infrastructure | Customer's Kubernetes | Graphon-managed cloud |
| Components deployed | Backend + UI + Agent + DBs | Agent only |
| License type | Self-Hosted (Free / Enterprise) | Cloud (per-cluster or per-seat) |
| Data residency | Customer's cluster | Graphon Cloud (SOC 2 region) |
| Multi-cluster | Via single Helm install per cluster | Native — register N clusters |
| Auth | Self-managed OIDC / local | Graphon Cloud Identity |
| Billing | External invoicing / license keys | Future: Stripe / Paddle |

---

## Document Index

### Architecture
| Document | Description |
|----------|-------------|
| [architecture/01-updated-architecture.md](architecture/01-updated-architecture.md) | Full system architecture v3 |
| [architecture/02-cloud-architecture.md](architecture/02-cloud-architecture.md) | Graphon Cloud infra design |
| [architecture/03-tenant-architecture.md](architecture/03-tenant-architecture.md) | Multi-tenancy isolation model |
| [architecture/04-multi-cluster-design.md](architecture/04-multi-cluster-design.md) | Cross-cluster data & UI |
| [architecture/05-historical-graph-design.md](architecture/05-historical-graph-design.md) | Snapshots, time-travel, diffs |
| [architecture/06-export-design.md](architecture/06-export-design.md) | PNG / SVG / PDF / Draw.io |
| [architecture/07-advanced-search-design.md](architecture/07-advanced-search-design.md) | Full-text search architecture |

### Licensing
| Document | Description |
|----------|-------------|
| [licensing/LICENSE_DESIGN.md](licensing/LICENSE_DESIGN.md) | Complete licensing system |
| [licensing/FEATURE_GATES.md](licensing/FEATURE_GATES.md) | Feature entitlement model |
| [licensing/ANTI_ABUSE_STRATEGY.md](licensing/ANTI_ABUSE_STRATEGY.md) | Free tier protection |
| [licensing/LICENSE_VALIDATION_FLOW.md](licensing/LICENSE_VALIDATION_FLOW.md) | Online / offline validation |

### Authentication & RBAC
| Document | Description |
|----------|-------------|
| [auth/SSO_OIDC_DESIGN.md](auth/SSO_OIDC_DESIGN.md) | Google / Azure AD / Okta / OIDC |
| [auth/RBAC_DESIGN.md](auth/RBAC_DESIGN.md) | Role model & permission matrix |

### Deployment
| Document | Description |
|----------|-------------|
| [deployment/SELF_HOSTED_ARCHITECTURE.md](deployment/SELF_HOSTED_ARCHITECTURE.md) | All 4 DB configuration modes |
| [deployment/CLOUD_ARCHITECTURE.md](deployment/CLOUD_ARCHITECTURE.md) | Graphon Cloud SaaS architecture |
| [deployment/EXTERNAL_DATABASE_ARCHITECTURE.md](deployment/EXTERNAL_DATABASE_ARCHITECTURE.md) | RDS, AuraDB, CloudSQL guide |
| [deployment/PRODUCTION_DEPLOYMENT_STRATEGY.md](deployment/PRODUCTION_DEPLOYMENT_STRATEGY.md) | Upgrade, migration, DR |

### Integrations
| Document | Description |
|----------|-------------|
| [integrations/GITHUB_APP_DESIGN.md](integrations/GITHUB_APP_DESIGN.md) | GitHub App — PR impact analysis |
| [integrations/GITLAB_APP_DESIGN.md](integrations/GITLAB_APP_DESIGN.md) | GitLab App — MR analysis |

### Testing & Operations
| Document | Description |
|----------|-------------|
| [testing/CUSTOMER_TESTING_GUIDE.md](testing/CUSTOMER_TESTING_GUIDE.md) | Real-workload onboarding guide |
| [testing/DEMO_ENVIRONMENT_SETUP.md](testing/DEMO_ENVIRONMENT_SETUP.md) | Conference / investor demo setup |
| [testing/PRODUCTION_READINESS_CHECKLIST.md](testing/PRODUCTION_READINESS_CHECKLIST.md) | Go-live verification |

### Website
| Document | Description |
|----------|-------------|
| [website/LANDING_WEBSITE_ARCHITECTURE.md](website/LANDING_WEBSITE_ARCHITECTURE.md) | All pages, copy, CTAs |
| [website/DOCS_PORTAL_ARCHITECTURE.md](website/DOCS_PORTAL_ARCHITECTURE.md) | Documentation site structure |

### Root Documents
| Document | Description |
|----------|-------------|
| [../../../UI_REDESIGN_GUIDE.md](../../../UI_REDESIGN_GUIDE.md) | Per-page redesign + Stitch prompts |
| [../../../PHASE_3_COMPLETION_REPORT.md](../../../PHASE_3_COMPLETION_REPORT.md) | Completion tracking |

---

## Implementation Sequence

```
Week 1-2:  Licensing system + feature gates (backend only, no billing)
Week 3-4:  Auth — OIDC/SSO integration
Week 5-6:  RBAC
Week 7-8:  Multi-cluster backend support
Week 9-10: Historical graph (snapshots + time-travel)
Week 11-12: GitHub App + GitLab App
Week 13-14: Advanced search
Week 15-16: Architecture export (PNG/SVG/PDF)
Week 17-18: Graphon Cloud infrastructure (tenant isolation, agent-only mode)
Week 19-20: Landing website + docs portal
Week 21-22: Customer testing documentation + demo environment
Week 23-24: Security audit, performance tuning, production hardening
```
