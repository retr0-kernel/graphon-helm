# License Validation Flow

## Startup Validation

```
Backend starts
    │
    ├── Read license key from:
    │   1. GRAPHON_LICENSE_KEY env var
    │   2. K8s Secret (graphon-license)
    │   3. license.key in config
    │   └── If none found → apply Free tier defaults
    │
    ├── Parse JWT (no network call)
    │   └── Verify RS256 signature with embedded public key
    │
    ├── Check expiry
    │   ├── Valid → load features and limits into memory
    │   ├── Within grace period (14 days) → load features, log WARN daily
    │   └── Expired → apply Free tier, log ERROR, send notification
    │
    └── Schedule 24h background revalidation
```

## Request-Time Gate Check (hot path, no I/O)

```
HTTP request arrives
    │
    ├── Handler calls license.IsFeatureEnabled("export-pdf")
    │   └── Reads from in-memory cache (RWMutex, lock-free read path)
    │
    ├── Feature disabled → 402 Payment Required + JSON error
    │   { "error": "...", "upgrade_url": "https://graphon.io/pricing" }
    │
    └── Feature enabled → proceed
```

## 24-Hour Background Validation

```
Every 24 hours (jittered ±30 min to avoid thundering herd):
    │
    ├── Re-parse license key from source
    ├── Check expiry → update in-memory state
    │
    ├── (Optional) Online check if endpoint configured:
    │   POST https://license.graphon.io/validate
    │   { "key_hash": "sha256:...", "version": "3.0.0" }
    │   Response: { "valid": true, "revoked": false, "message": "" }
    │
    ├── If revoked → downgrade to Free, log ERROR
    └── Log validation result (INFO)
```

## License Downgrade Behavior

When a license expires or is revoked, Graphon **never crashes or becomes unavailable**. It gracefully downgrades:

| Was | Downgrades to | Impact |
|-----|---------------|--------|
| Enterprise features | Free features | Features hidden, not broken |
| 50 clusters | Show only first 3 | Others grayed out, prompt to renew |
| 500 users | First 3 active | Others can't log in |
| 1yr retention | 30-day window | Old snapshots unreadable |

**Critical:** existing data is never deleted on downgrade. Renewal immediately restores access.

## Structured Logs

```json
{"time":"...","level":"INFO","msg":"license validated","plan":"enterprise","expires_in_days":180,"features":["multi-cluster","sso","rbac"]}
{"time":"...","level":"WARN","msg":"license expiring soon","plan":"enterprise","expires_in_days":14,"action":"renew at graphon.io/renew"}
{"time":"...","level":"ERROR","msg":"license expired","plan":"free","grace_period_active":true,"grace_ends_in_days":14}
{"time":"...","level":"ERROR","msg":"license revoked","key_hash":"sha256:...","downgraded_to":"free"}
```
