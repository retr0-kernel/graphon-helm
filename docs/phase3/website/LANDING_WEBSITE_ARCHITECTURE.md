# Landing Website Architecture

## Site Map

```
graphon.io
├─ /                          Home
├─ /features                  Features overview
├─ /architecture              How it works (technical)
├─ /self-hosted               Self-Hosted product page
├─ /cloud                     Graphon Cloud product page
├─ /pricing                   Pricing (placeholder)
├─ /enterprise                Enterprise page
├─ /security                  Security overview
├─ /docs                      → docs.graphon.io (external)
├─ /blog                      Blog (placeholder CMS)
├─ /about                     About / team
├─ /contact                   Contact form
├─ /roadmap                   Public roadmap
├─ /demo                      Request demo form
├─ /customers                 Customer stories (placeholder)
├─ /changelog                 Version changelog
└─ /github                    → github.com/retr0-kernel/graphon-helm
```

---

## Page Designs

### Home (`/`)

**Purpose:** Convert visitors to either "Install Self-Hosted" or "Try Cloud"

**Hero:**
> Understand every dependency in your Kubernetes cluster.  
> Runtime dependency intelligence. Zero instrumentation.

CTA 1: "Get started free" → `/self-hosted`  
CTA 2: "Try Graphon Cloud" → `/cloud`

**Sections:**
1. Hero + animated graph visualization
2. How it works (3 steps: Deploy Agent → Capture Connections → Explore Graph)
3. Feature highlights (6-grid: Live Graph, Drift Detection, Safe Delete, Multi-Cluster, GitHub Integration, Export)
4. "Works where you work" (K8s logos: EKS, GKE, AKS, Kind, k3d, Minikube)
5. Architecture diagram (eBPF → graph)
6. Call to action (Self-Hosted vs Cloud comparison)

---

### Features (`/features`)

Detailed breakdown of all platform capabilities:

1. **Runtime Dependency Mapping** — eBPF-powered, zero instrumentation
2. **Dependency Drift Detection** — baseline vs live comparison
3. **Safe Delete Analysis** — blast radius before decommissioning
4. **Ownership Intelligence** — team attribution for every service
5. **Multi-Cluster View** — unified graph across environments
6. **Historical Graph** — snapshots, time-travel, diffs
7. **GitHub / GitLab Integration** — PR impact analysis
8. **Advanced Search** — find anything instantly
9. **Architecture Export** — PNG, SVG, PDF, Draw.io
10. **SSO / RBAC** — enterprise identity management

---

### Self-Hosted (`/self-hosted`)

**Hero:** "Deploy Graphon in your Kubernetes cluster. Free forever."

```
helm repo add graphon https://retr0-kernel.github.io/graphon-helm
helm install graphon graphon/graphon -n graphon --create-namespace
```

Sections:
1. Installation command (copy-to-clipboard)
2. Database configuration matrix (4 modes)
3. "Works with" logos (RDS, AuraDB, Azure, CloudSQL)
4. Resource requirements table
5. Comparison: Free vs Pro vs Enterprise
6. Self-Hosted FAQ

---

### Graphon Cloud (`/cloud`)

**Hero:** "Deploy just the agent. We handle the rest."

Sections:
1. Signup CTA + demo video
2. How cloud works (3 steps)
3. Multi-cluster management diagram
4. Security & data residency
5. Cloud vs Self-Hosted comparison
6. Cloud pricing tiers (Standard / Enterprise)

---

### Pricing (`/pricing`)

**Note: Placeholder — will be filled when commercial launch is ready**

Table structure (not final prices):
| | Free | Pro | Enterprise | Cloud |
|-|------|-----|------------|-------|
| Price | Free | $X/mo | Contact sales | $Y/cluster/mo |
| Clusters | Unlimited | 5 | Unlimited | Unlimited |
| Users | 3 | 25 | Custom | Custom |
| Features | Basic | Pro | All | All |

---

### Security (`/security`)

- Architecture security overview
- Data handling policy
- Encryption at rest/in-transit
- SOC 2 roadmap
- CVE response process
- Security contact: security@graphon.io
- Bug bounty policy

---

### Enterprise (`/enterprise`)

- Enterprise capabilities
- Compliance (SOC 2, GDPR roadmap)
- SLA
- Professional services
- On-premises deployment
- Air-gapped installation
- Contact Sales form

---

## Tech Stack Recommendation

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 14 (App Router) |
| Styling | Tailwind CSS |
| Components | shadcn/ui |
| Animations | Framer Motion |
| Graph visualization | React Flow (demo graph) |
| Blog CMS | Contentlayer / MDX |
| Forms | React Hook Form |
| Analytics | Plausible (privacy-first) |
| Deployment | Vercel |

---

## SEO Strategy

Target keywords:
- "kubernetes dependency mapping"
- "service mesh visualization"
- "kubernetes observability tools"
- "runtime service discovery kubernetes"
- "kubernetes architecture diagram"
- "ebpf kubernetes monitoring"

Meta structure:
```html
<title>Graphon — Runtime Dependency Intelligence for Kubernetes</title>
<meta name="description" content="Automatically map every service dependency in your Kubernetes cluster using eBPF. Zero instrumentation, zero sidecars." />
```
