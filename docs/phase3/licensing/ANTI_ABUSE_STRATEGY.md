# Anti-Abuse Strategy for Free Self-Hosted

## Problem Statement

Self-Hosted is free. Without any controls, a sophisticated user could:
1. Deploy 100 separate Helm releases, each counting as a new "free" install
2. Gain multi-cluster, unlimited-user enterprise functionality at zero cost
3. Undermine commercial sustainability

The solution must:
- Not harm legitimate developers with 1–2 clusters
- Not require internet connectivity to work
- Not be so heavy-handed that it creates a bad OSS reputation
- Allow genuine open-source contributors to benefit fully
- Drive natural upgrade to Pro/Enterprise for commercial teams

---

## Recommended Approach: Organization-Based License with Fair Use Policy

### Tier Definition

| Tier | Clusters | Users | Enforcement |
|------|----------|-------|-------------|
| Free Self-Hosted | Unlimited | Unlimited | **Honor system + soft limits** |
| Pro Self-Hosted | 5 | 25 | License key, hard enforced |
| Enterprise | Unlimited | Custom | License key, hard enforced |

**Rationale:** For a self-hosted product, hard enforcement of "free = 1 cluster" creates massive friction for legitimate use (dev + staging + prod is already 3). The best protection is making the Pro tier genuinely valuable for commercial teams, not artificially crippling free.

### Soft Limits on Free Tier

Without a license key, the backend applies:

| Feature | Free Limit | Message shown |
|---------|-----------|---------------|
| Clusters | Unlimited | None |
| Users (RBAC) | 3 named users | "Add more users — upgrade to Pro" |
| Graph snapshots | 10 total (oldest deleted) | "Unlock unlimited snapshots" |
| Snapshot retention | 30 days | "Upgrade for 90-day retention" |
| Advanced features | Disabled | Feature-specific upgrade prompt |

### What's Genuinely Free Forever

- Core dependency graph (unlimited nodes/edges)
- Drift detection
- Safe delete analysis
- Basic search
- Ownership labels
- PNG/SVG/Mermaid export
- Agent for unlimited nodes

This is generous enough that a 20-person startup can run self-hosted forever on the free tier and never need to upgrade. This is intentional — viral OSS adoption drives Graphon Cloud upgrades.

---

## Why Not Cluster Registration?

**Option Evaluated:** Require internet registration on first boot.

**Problems:**
1. Air-gapped environments can't reach registration server
2. Creates account management overhead for developer evaluating Graphon
3. Community backlash — "requires phoning home" is a major OSS red flag
4. Does not prevent abuse (attacker just rotates API keys)

**Decision: No forced registration for free tier.**

---

## Why Not Fingerprinting / Hardware Locks?

**Problems:**
1. Cluster fingerprints change frequently in cloud environments
2. False positives lock out legitimate users
3. Security theater — sophisticated abusers bypass it trivially
4. Creates support burden

**Decision: No fingerprinting.**

---

## Actual Abuse Pattern vs Legitimate Use

| Pattern | Legitimate? | Impact | Response |
|---------|-------------|--------|----------|
| Dev + staging + prod | ✓ Yes | None | No action |
| 10 clusters, 1 team | ✓ Growing startup | Low | Natural Pro upgrade prompt |
| 100 clusters, 1 company | Borderline | Medium | Sales outreach, not blocking |
| 100 "companies", all same person | ✗ Abuse | Low (feature-gated) | Legal/ToS |
| CI ephemeral clusters | ✓ Yes | Very low | No action |

**Conclusion:** Real abuse cases are extremely rare, and the free tier already gates the features that matter to enterprises. Natural commercial pressure creates upsells far better than technical enforcement.

---

## Recommended Fair Use Policy (ToS Language)

> "The Free Self-Hosted tier is licensed for use by a single organization or individual. Deploying multiple instances to circumvent feature limits of a single commercial deployment is not permitted. Commercial organizations with production use beyond development/evaluation are encouraged to purchase a Pro or Enterprise license."

---

## Upgrade Nudges (Non-Blocking)

Instead of hard blocks, implement friendly upgrade prompts:

1. **In-UI banners** — "You have 3 clusters. Unlock unlimited with Pro →"
2. **Admin notifications** — Email to admin when approaching soft limits
3. **NOTES.txt** after `helm install` — "Running in production? See graphon.io/pricing"
4. **Log messages** — `WARN license: running free tier — consider Pro for multi-cluster`
5. **API headers** — `X-Graphon-Upgrade-Available: true` on relevant responses (for SREs who see API responses)

---

## Future: Commercial Usage Detection (Optional, Opt-In)

If the user opts in to telemetry, collect:
- Number of clusters (not names)
- Number of services (not names)
- Feature usage frequency (not data)

Used for: identifying high-usage free users for sales outreach.

**This is OPT-IN only.** Default: no telemetry. This preserves OSS trust.

```yaml
# values.yaml
graphon:
  telemetry:
    enabled: false  # default: off
    endpoint: "https://telemetry.graphon.io"
```
