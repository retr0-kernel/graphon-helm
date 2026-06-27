# Tenant Architecture

## Overview

Multi-tenancy in Graphon Cloud isolates data, configuration, and compute per organizational tenant. Each tenant is an independent organization with one or more registered clusters.

---

## Tenant Data Model

```sql
CREATE TABLE tenants (
    id           TEXT PRIMARY KEY,          -- "acme-corp" (slug)
    display_name TEXT NOT NULL,
    plan         TEXT NOT NULL DEFAULT 'cloud-standard',
    status       TEXT NOT NULL DEFAULT 'active',  -- active | suspended | deleted
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    metadata     JSONB DEFAULT '{}'
);

-- All data tables have tenant_id column
-- PostgreSQL Row Level Security (RLS) enforces isolation at DB level
ALTER TABLE edges ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON edges
    USING (tenant_id = current_setting('app.current_tenant'));
```

---

## Tenant Resolution

```
HTTP Request → API Gateway
    │
    ├── Extract tenant from:
    │   1. JWT claim: { tenant: "acme" }      (Cloud mode)
    │   2. Subdomain: acme.graphon.io         (Cloud mode)
    │   3. Header: X-Tenant-ID               (Internal only)
    │   4. Config: GRAPHON_TENANT_ID=default  (Self-hosted)
    │
    ├── Set in request context: ctx.WithValue("tenant_id", "acme")
    │
    └── All DB queries scoped to tenant automatically (repository layer)
```

---

## Tenant Lifecycle

```
1. CREATE  → provision PostgreSQL schema, Neo4j database, backend namespace
2. ACTIVE  → normal operation
3. SUSPEND → read-only mode (payment lapsed, abuse detected)
4. DELETE  → 30-day grace period → data export available → permanent deletion
```

---

## Neo4j Multi-Database (Cloud Mode)

Each tenant uses a dedicated Neo4j database:
```
-- Create tenant DB
CREATE DATABASE graphon_acme;

-- Backend uses db routing:
DRIVER.session(database="graphon_acme")
```

Community Neo4j: 1 database (self-hosted). Enterprise/AuraDB: multiple databases per instance.

For Cloud, AuraDB instances are provisioned per tenant (or shared with database-level isolation for standard tier).
