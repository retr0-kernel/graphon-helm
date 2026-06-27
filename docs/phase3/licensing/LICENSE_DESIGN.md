# Licensing System Design

## Overview

Graphon's licensing system gates features by plan tier without requiring billing infrastructure. Any payment processor (Stripe, Paddle, LemonSqueezy, enterprise invoicing) can issue license keys without changing the backend.

---

## License Key Format

License keys are signed JWT tokens with a well-known structure:

```
gph_<base62-encoded-JWT>
```

Example decoded JWT:
```json
{
  "iss": "license.graphon.io",
  "sub": "org_acme_corp",
  "iat": 1719446400,
  "exp": 1751068800,
  "plan": "enterprise",
  "features": ["multi-cluster", "sso", "rbac", "snapshots", "github-app", "export-pdf"],
  "limits": {
    "clusters": 50,
    "users": 500,
    "retention_days": 365,
    "snapshot_interval_minutes": 60
  },
  "metadata": {
    "org_name": "Acme Corp",
    "issued_by": "sales@graphon.io",
    "po_number": "PO-2024-1234"
  }
}
```

**Signed with RS256** — private key held by Graphon, public key embedded in the binary. No outbound call needed to validate a license.

---

## License Tiers

### Free Self-Hosted
- No license key required
- Automatically applied on fresh install
- Limited features, no cluster limit (see Anti-Abuse section)

### Pro Self-Hosted
- Single license key, annual renewal
- 1–5 clusters, 25 users
- Intermediate features

### Enterprise Self-Hosted
- License key with org-level entitlements
- Unlimited clusters, custom user count
- All features
- Offline-first validation

### Cloud Standard
- Per-cluster billing (future: Stripe)
- License embedded in cluster JWT
- 5 clusters, 25 users

### Cloud Enterprise
- Custom contract
- Unlimited clusters and users
- SLA, dedicated support

---

## Feature Gate Map

| Feature | Free | Pro | Enterprise | Cloud Std | Cloud Ent |
|---------|:----:|:---:|:----------:|:---------:|:---------:|
| Core dependency graph | ✓ | ✓ | ✓ | ✓ | ✓ |
| Drift detection | ✓ | ✓ | ✓ | ✓ | ✓ |
| Safe delete | ✓ | ✓ | ✓ | ✓ | ✓ |
| Ownership labels | ✓ | ✓ | ✓ | ✓ | ✓ |
| Basic search | ✓ | ✓ | ✓ | ✓ | ✓ |
| PNG/SVG export | ✓ | ✓ | ✓ | ✓ | ✓ |
| Mermaid/DOT export | ✓ | ✓ | ✓ | ✓ | ✓ |
| Multi-cluster (≤5) | ✗ | ✓ | ✓ | ✓ | ✓ |
| OIDC / SSO | ✗ | ✓ | ✓ | ✓ | ✓ |
| RBAC | ✗ | ✓ | ✓ | ✓ | ✓ |
| Full-text search | ✗ | ✓ | ✓ | ✓ | ✓ |
| Graph snapshots (manual) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Scheduled snapshots | ✗ | ✓ | ✓ | ✓ | ✓ |
| Time-travel (90 days) | ✗ | ✓ | ✓ | ✓ | ✓ |
| Time-travel (1 year) | ✗ | ✗ | ✓ | ✗ | ✓ |
| PDF export | ✗ | ✓ | ✓ | ✓ | ✓ |
| Draw.io export | ✗ | ✓ | ✓ | ✓ | ✓ |
| GitHub App | ✗ | ✗ | ✓ | ✗ | ✓ |
| GitLab App | ✗ | ✗ | ✓ | ✗ | ✓ |
| Path search | ✗ | ✓ | ✓ | ✓ | ✓ |
| Cross-cluster search | ✗ | ✗ | ✓ | ✗ | ✓ |
| API access | ✗ | ✓ | ✓ | ✓ | ✓ |
| Webhooks | ✗ | ✗ | ✓ | ✗ | ✓ |
| Audit log | ✗ | ✗ | ✓ | ✗ | ✓ |
| Multi-cluster (unlimited) | ✗ | ✗ | ✓ | ✗ | ✓ |
| Custom retention | ✗ | ✗ | ✓ | ✗ | ✓ |

---

## License Storage

### Self-Hosted

License key stored in Kubernetes Secret:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: graphon-license
  namespace: graphon
type: Opaque
data:
  license-key: <base64-encoded-key>
```

Or via Helm:
```bash
helm upgrade graphon graphon/graphon \
  --set license.key=gph_eyJ...
```

The backend reads on startup and re-validates every 24 hours. Invalid/expired license → downgrade to Free tier (no crash).

### Cloud

License claims are embedded in the tenant JWT issued at subscription time. The control plane generates/renews automatically.

---

## License Renewal

### Online Renewal (recommended)
1. License expires → backend logs WARN 30 days before
2. Customer renews via Graphon portal (or invoicing)
3. New key issued with extended `exp`
4. Customer runs `helm upgrade --set license.key=<new-key>`
5. Backend validates new key immediately

### Grace Period
- 14-day grace period after expiry
- Features remain active, daily WARN log
- After grace: downgrade to Free tier limits (not shutdown)
- **Never crashes or becomes unavailable**

---

## Offline Validation Strategy

Self-Hosted Enterprise customers may have air-gapped clusters:

1. License key is a **self-contained signed JWT** — no network call needed
2. Public key is embedded in the binary at build time
3. Validation: `jwt.Verify(key, graphon_public_key)` — pure in-process
4. For annual renewal: customer downloads new key from portal, applies via `helm upgrade`
5. Online check (optional): once per 24h, if endpoint reachable, validates key hash against revocation list

---

## Revocation

Compromised or abused license keys:
1. Graphon backend maintains a revocation list at `https://license.graphon.io/revoked`
2. On each 24h check, backend downloads list and caches locally
3. Revoked key → immediate downgrade to Free (with 7-day warning email)
4. For air-gapped: revocation served via signed file on next renewal

---

## Implementation in Go

```go
// internal/license/engine.go

type License struct {
    Plan     string            `json:"plan"`
    Features []string          `json:"features"`
    Limits   map[string]int    `json:"limits"`
    Expires  time.Time
    OrgName  string
}

type Engine struct {
    current  *License
    mu       sync.RWMutex
    pubKey   *rsa.PublicKey
}

func (e *Engine) IsFeatureEnabled(feature string) bool {
    e.mu.RLock()
    defer e.mu.RUnlock()
    if e.current == nil {
        return isFreeFeature(feature)
    }
    for _, f := range e.current.Features {
        if f == feature { return true }
    }
    return false
}

func (e *Engine) GetLimit(key string, defaultVal int) int {
    // returns license limit or default (free tier)
}
```

Gate usage in handlers:
```go
func (h *Handler) handleExportPDF(w http.ResponseWriter, r *http.Request) {
    if !h.license.IsFeatureEnabled("export-pdf") {
        http.Error(w, `{"error":"PDF export requires Pro or higher license"}`, 402)
        return
    }
    // ... proceed with export
}
```
