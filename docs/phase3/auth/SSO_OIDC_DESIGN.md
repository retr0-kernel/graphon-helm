# SSO / OIDC Authentication Design

## Overview

Graphon v3 supports standard OIDC-based SSO. The same implementation works for Google Workspace, Azure AD, Okta, GitHub, and any OIDC-compliant provider — configured entirely via Helm values, no code changes required.

---

## Supported Providers

| Provider | Config | Notes |
|----------|--------|-------|
| Google Workspace | `issuerUrl: https://accounts.google.com` | Use `hd` claim for org domain restriction |
| Azure AD / Entra | `issuerUrl: https://login.microsoftonline.com/{tenant}/v2.0` | Supports M365 groups via `groups` claim |
| Okta | `issuerUrl: https://your-org.okta.com` | Supports Okta groups for RBAC |
| GitHub (OIDC) | Via GitHub App OAuth | Used for Cloud mode self-service |
| Any OIDC | `issuerUrl: https://your-idp.example.com` | Standard compliance |
| Local (dev) | `provider: local` | Username/password, dev/demo only |

---

## Architecture

```
Browser → Graphon UI → /auth/login → OIDC Provider (redirect)
                                          │
                                          │  authorization_code flow
                                          ▼
                                  /auth/callback
                                          │
                                          ├─ Exchange code for tokens
                                          ├─ Verify ID token (RS256)
                                          ├─ Extract: sub, email, name, groups
                                          ├─ Resolve or create user record
                                          ├─ Map groups → Graphon roles (RBAC)
                                          ├─ Issue session cookie (httpOnly, SameSite=Lax)
                                          └─ Redirect to UI
```

### Token Storage
- **Server-side session** in PostgreSQL `sessions` table
- Session cookie contains only opaque session ID (not JWT)
- Session TTL: 8 hours (configurable), refresh on activity
- No client-side JWT storage — prevents XSS token theft

---

## Configuration (Helm)

```yaml
backend:
  auth:
    enabled: true
    provider: "oidc"
    sessionSecret: ""          # auto-generated if empty; use existingSecret in prod

    oidc:
      issuerUrl: "https://accounts.google.com"
      clientId: "123456.apps.googleusercontent.com"
      clientSecret: ""         # use existingSecret
      redirectUrl: "https://graphon.example.com/auth/callback"
      scopes:
        - openid
        - email
        - profile
        - groups                # required for RBAC group mapping

      # Optional: restrict to specific domain (Google Workspace)
      hostedDomain: "example.com"

      # Group → role mapping
      groupRoleMapping:
        "graphon-admins": "admin"
        "platform-team": "platform-admin"
        "developers": "developer"
        "viewers": "viewer"
```

---

## Data Model

```sql
CREATE TABLE users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   TEXT NOT NULL,
    sub         TEXT NOT NULL,              -- OIDC subject (stable identifier)
    email       TEXT NOT NULL,
    name        TEXT,
    avatar_url  TEXT,
    provider    TEXT NOT NULL,              -- google | azure | okta | local
    role        TEXT NOT NULL DEFAULT 'viewer',
    last_login  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, sub)
);

CREATE TABLE sessions (
    id          TEXT PRIMARY KEY,           -- random 32-byte hex
    user_id     UUID REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   TEXT NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    user_agent  TEXT,
    ip_address  INET
);

CREATE INDEX idx_sessions_expiry ON sessions(expires_at);
```

---

## API Endpoints

```
GET  /auth/login              ← starts OIDC redirect
GET  /auth/callback           ← OIDC callback handler
POST /auth/logout             ← clears session
GET  /auth/me                 ← returns current user info (for UI)
GET  /auth/providers          ← list configured providers (for login page)
```

---

## Self-Hosted vs Cloud Auth

| Aspect | Self-Hosted | Cloud |
|--------|-------------|-------|
| Identity provider | Customer's OIDC (Google, Azure, Okta) | Graphon Cloud Identity (Auth0/Cognito) |
| Session storage | Local PostgreSQL | Shared session store |
| User provisioning | JIT on first login | Managed by Graphon |
| MFA | Delegated to IdP | Enforced via Auth0 |
| SCIM/directory sync | Phase 4 | Phase 4 |

---

## Security Controls

| Control | Implementation |
|---------|----------------|
| State parameter | CSRF prevention on OAuth flow |
| PKCE | Required for all new integrations |
| Token validation | Verify iss, aud, exp, nonce claims |
| Session fixation | New session ID on login |
| Secure cookies | httpOnly, SameSite=Lax, Secure flag in prod |
| Session expiry | 8h idle, 24h absolute |
| Brute force | 5 failed logins → 15 min lockout (local mode only) |
| Token revocation | Session deleted on logout; OIDC logout propagation |
