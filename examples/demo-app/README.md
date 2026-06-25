# Graphon Demo App

A deployable sample microservices topology that lets you see Graphon working immediately — no real application required.

## What it deploys

```
browser
  └── frontend (nginx)
        └── gateway (nginx proxy)
              ├── orders-service (nginx)
              │     └── payments-service (nginx)
              │           └── postgres stub (postgres:16-alpine)
              ├── catalog-service (nginx)
              └── notifications-service (nginx)

traffic-generator (busybox)  → calls all services in a loop
```

Each service has `app.graphon.io/owner-*` labels so Graphon can auto-discover ownership.

## Deploy

```bash
# From this directory:
kubectl apply -f namespace.yaml
kubectl apply -f .

# Or from a URL:
kubectl apply -f https://raw.githubusercontent.com/retr0-kernel/graphon/main/graphon-helm/examples/demo-app/
```

## What you'll see in Graphon

After ~30 seconds:
- 6 service nodes in the graph
- All edges between services
- Ownership auto-populated from K8s labels
- Safe delete analysis showing MEDIUM/HIGH risk for gateway (multiple consumers)

## Cleanup

```bash
kubectl delete namespace graphon-demo
```
