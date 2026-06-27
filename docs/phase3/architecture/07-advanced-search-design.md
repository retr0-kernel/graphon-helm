# Advanced Search Design

## Overview

Advanced Search enables engineers to quickly find services, APIs, teams, namespaces, and dependency paths across the entire graph without having to visually navigate the topology.

---

## Search Types

| Type | Query example | Returns |
|------|--------------|---------|
| Service lookup | `payment-service` | Matching service nodes |
| Namespace lookup | `ns:payments` | All services in namespace |
| Team lookup | `team:checkout` | All services owned by team |
| API / port lookup | `port:8080` | Services exposing port 8080 |
| Dependency lookup | `uses:postgres` | Services that call postgres |
| Label lookup | `label:env=prod` | Services with that K8s label |
| Path search | `path:checkout-service → database` | Dependency path query |
| Full-text | `auth grpc internal` | FTS across service names and labels |

---

## Backend Architecture

### Indexing

```
PostgreSQL full-text search (tsvector) on:
  - service name
  - namespace
  - owner_team
  - owner_email
  - labels (JSONB keys + values flattened)
  - image repository

UPDATE services SET search_vector = to_tsvector('english',
    coalesce(name, '') || ' ' ||
    coalesce(namespace, '') || ' ' ||
    coalesce(owner_team, '') || ' ' ||
    jsonb_to_text(labels)
);

CREATE INDEX idx_services_fts ON services USING GIN(search_vector);
```

### Neo4j Path Queries

```cypher
-- Find path between two services
MATCH path = shortestPath(
  (a:Service {name: $src})-[:CALLS*..6]->(b:Service {name: $dst})
)
RETURN path

-- Find all callers of a service
MATCH (caller:Service)-[:CALLS]->(target:Service {name: $name})
RETURN caller

-- Find services by team
MATCH (s:Service {owner_team: $team})
RETURN s
```

---

## Search API

```
GET /api/v1/search?q=payment&type=service&cluster=*&namespace=payments&limit=20

Response:
{
  "query": "payment",
  "total": 4,
  "results": [
    {
      "type": "service",
      "id": "default/payment-service",
      "name": "payment-service",
      "namespace": "default",
      "cluster": "prod-us-east-1",
      "owner_team": "payments",
      "score": 0.98,
      "highlights": { "name": "<mark>payment</mark>-service" },
      "dependency_count": { "incoming": 3, "outgoing": 5 }
    }
  ],
  "facets": {
    "cluster": { "prod-us-east-1": 3, "staging": 1 },
    "namespace": { "default": 2, "payments": 2 },
    "team": { "payments": 4 }
  }
}
```

---

## Search UI

```
┌─────────────────────────────────────────────────────────┐
│  🔍  payment service                              ⌘K    │
├─────────────────────────────────────────────────────────┤
│  Services (4)                                            │
│  ● payment-service         default / prod       ←  top  │
│  ● payment-gateway         payments / prod              │
│  ● payment-service         default / staging            │
│  ● legacy-payment          billing / prod               │
│                                                          │
│  Teams (1)                                               │
│  ◆ payments team  →  12 services                        │
│                                                          │
│  Dependencies                                            │
│  checkout-service → payment-service → stripe-proxy      │
└─────────────────────────────────────────────────────────┘
```

- Global keyboard shortcut: `⌘K` / `Ctrl+K`
- Result grouping: Services / Namespaces / Teams / Paths
- Faceted filtering in sidebar
- Click result → navigates to graph with node selected + highlighted

---

## Feature Gates

| Feature | Free | Pro | Enterprise | Cloud |
|---------|------|-----|------------|-------|
| Basic service search | ✓ | ✓ | ✓ | ✓ |
| Namespace / team search | ✓ | ✓ | ✓ | ✓ |
| Full-text search | ✗ | ✓ | ✓ | ✓ |
| Path search | ✗ | ✓ | ✓ | ✓ |
| Cross-cluster search | ✗ | ✗ | ✓ | ✓ |
| Search API (programmatic) | ✗ | ✓ | ✓ | ✓ |
| Saved searches / alerts | ✗ | ✗ | ✓ | ✓ |
