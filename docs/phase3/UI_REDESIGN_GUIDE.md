# UI Redesign Guide — Graphon v3

**Document purpose:** Per-page redesign specification and Stitch prompts for redesigning every Graphon UI page using [https://stitch.withgoogle.com](https://stitch.withgoogle.com).

Do NOT implement any UI changes based on this document. This is a design specification for future execution.

---

## How to Use This Document

1. Open [stitch.withgoogle.com](https://stitch.withgoogle.com)
2. Select the page you want to redesign
3. Copy the Stitch prompt from this document
4. Paste into Stitch and iterate
5. Export component specs back into `graphon-ui`

---

## Page 1: Dependency Graph (Main View)

**Purpose:** Primary interface — shows the live dependency graph of all services in the cluster.

**Target Users:** Platform engineers, SREs, developers

**Components:**
- Full-screen interactive force-directed or hierarchical graph (React Flow)
- Node cards: service name, namespace, owner team badge, port info on hover
- Edge lines: thickness = call frequency; color = health status
- Top toolbar: cluster selector, namespace filter, team filter, time selector (live/snapshot)
- Side panel (right): selected node detail — incoming/outgoing dependencies, owner, labels
- Bottom status bar: event rate, last updated, cluster health
- Floating controls: zoom in/out, fit to screen, layout selector

**Tables:** None (graph-primary view)

**Charts:**
- Call frequency heatmap (edge thickness encoding)
- Node size = incoming call count (optional toggle)

**Actions:**
- Click node → select, open side panel
- Double-click node → focus (ego-centric view)
- Right-click node → context menu (view history, export, safe-delete, set owner)
- Drag graph to pan
- Scroll to zoom
- Cluster dropdown → switch cluster
- "Snapshot" button → take manual snapshot
- "Export" button → format picker

**Filters:**
- Namespace multi-select
- Team multi-select
- Show/hide internal vs external services
- Show only changed services (diff mode)
- Depth limiter (1, 2, 3, 5, ∞ hops)

**Navigation:** Part of main layout, accessible from sidebar

**Empty State:**
> "No dependency data yet.  
> The eBPF agent is collecting data. Check back in a few minutes.  
> If data doesn't appear, [check agent health →]"

**Loading State:** Skeleton nodes and edges fading in with pulse animation

**Error State:** "Failed to load graph data. [Retry] [Check backend health]"

**Responsive:** Mobile: simplified list view of services; full graph on tablet+

**Accessibility:** Keyboard navigation between nodes (Tab/Arrow), ARIA labels on all interactive elements

---

### Stitch Prompt — Dependency Graph Page

```
Design a full-screen dependency graph visualization UI for a Kubernetes observability platform called Graphon.

The main component is a React Flow interactive graph occupying the full viewport minus a top toolbar and right side panel.

Graph nodes:
- Rounded rectangle cards
- Service name in bold, namespace in muted smaller text
- Left color accent bar indicating team/owner (color-coded per team)
- Bottom row: incoming/outgoing dependency count badges
- On hover: show port, last seen, event rate
- Selected state: highlighted border with shadow

Graph edges:
- Directional arrows showing dependency direction
- Line thickness proportional to call frequency
- Color: green=healthy, yellow=degraded, red=circuit breaker
- On hover: show source→dest port, call count

Top toolbar (sticky):
- Left: Graphon logo + product name
- Center: Cluster selector dropdown, Namespace filter chips, Team filter chips
- Right: Time selector (Live | Snapshot picker), Snapshot button, Export button, Settings

Right side panel (slides in on node click):
- Service name + namespace header
- Owner team chip + owner email
- "Incoming dependencies" list (service name + port)
- "Outgoing dependencies" list (service name + port)
- "History" mini timeline (last 7 days activity)
- Action buttons: [View History] [Safe Delete Analysis] [Set Owner] [Export]

Bottom status bar:
- Events/min counter
- Last updated timestamp
- Cluster health indicator
- Agent status (active/degraded/offline)

Empty state:
- Centered illustration of an empty graph
- Muted text: "No data yet — the agent is collecting"
- Secondary text: "Check back in 5 minutes"

Use: dark background (#0f1117), node cards in #1e2130, accent colors from Tailwind slate/blue/violet palette. Font: Inter. Typography scale: 14px base.
```

---

## Page 2: Service Detail

**Purpose:** Deep-dive into a single service — its dependencies, history, owner, and metadata.

**Target Users:** Service owners, SREs debugging incidents

**Components:**
- Service header: name, namespace, cluster, owner team badge
- Tabs: Overview | Dependencies | History | Settings
- Overview tab: key metrics (call rate, dep count, age), owner card
- Dependencies tab: table of incoming + outgoing deps with port, frequency, first/last seen
- History tab: activity sparkline, snapshot timeline, diff selector
- Settings tab: owner labels, team assignment, tags

**Tables:**
- Incoming dependencies: columns = source service, port, calls/min, first seen, last seen
- Outgoing dependencies: columns = target service, port, calls/min, first seen, last seen

**Actions:**
- "Safe Delete Analysis" button → opens modal with blast radius
- "Take Snapshot" button
- "View in Graph" button → opens main graph centered on this node
- "Export" button

**Empty State per tab:** "No incoming dependencies detected"

**Responsive:** Single column on mobile

---

### Stitch Prompt — Service Detail Page

```
Design a service detail page for a Kubernetes dependency intelligence platform called Graphon.

Page header:
- Service name (h1), namespace chip, cluster chip
- Owner team badge (colored chip with team name and avatar)
- Owner email (muted)
- Breadcrumb: Graph > default > payment-service

Tabs below header: Overview | Dependencies | History | Settings

Overview tab:
- 4 metric cards in a row: Incoming deps (count), Outgoing deps (count), Call rate (events/min), Age (first seen)
- "Owner" section: team name, owner email, edit button
- "Labels" section: K8s label chips (key=value format)

Dependencies tab:
- Two sections: "Incoming" and "Outgoing"
- Each as a sortable data table
- Columns: Service name (link), Namespace, Port, Calls/min, First Seen, Last Seen, Actions
- Row hover: highlight + show "View in Graph" action
- Empty state: illustrated placeholder with muted text

History tab:
- Activity sparkline chart (last 7 days, event frequency)
- Snapshot list: label, trigger (auto/manual), node count, edge count, created time, "View" button
- "Compare" select two snapshots → diff view

Settings tab:
- Owner team text field + save
- Owner email field + save
- Custom tags (add/remove chips)
- Danger zone: "Mark for deletion" toggle

Style: Light mode option OR dark mode matching main graph page. Clean, data-dense, Inter font.
```

---

## Page 3: Drift Detection

**Purpose:** Compare live graph state against a saved baseline to detect unexpected dependency changes.

**Target Users:** Platform engineers, release engineers

**Components:**
- Baseline selector (dropdown — list of snapshots or "current baseline")
- "Run Drift Analysis" button
- Results panel with diff visualization
- Diff table: added/removed edges, changed services
- Severity score

**Tables:**
- Added edges: source → destination, port, first detected
- Removed edges: source → destination, port, last seen
- Changed services: what changed (labels, port, owner)

**Actions:**
- Update baseline to current state
- Export diff report (PDF / JSON)
- View diff in graph

**Empty State:** "No drift detected — your graph matches the baseline."

**Error State:** "Drift analysis failed — backend unreachable."

---

### Stitch Prompt — Drift Detection Page

```
Design a drift detection page for Graphon, a Kubernetes dependency graph platform.

Page layout:
- Header: "Drift Detection" title, subtitle "Compare live graph against saved baseline"
- Toolbar: Baseline selector dropdown + "Run Analysis" primary button + "Update Baseline" secondary button

Results section (shown after analysis):
- Summary banner: green (no drift) | yellow (minor) | red (significant drift)
  - Text: "3 new dependencies, 1 removed since last baseline"
  
- Two-column diff section:
  Left: "Added Dependencies" (green border) — list of src→dst with port
  Right: "Removed Dependencies" (red border) — list of src→dst with last-seen

- "Changed Services" section: table showing service name, what changed, when

- Graph diff view (toggleable): same React Flow graph but with green nodes (added), red nodes (removed), gray (unchanged)

- Action buttons: [Export Diff] [View in Graph] [Accept as New Baseline]

Empty state (no baseline set):
- Illustrated empty state
- "Set a baseline to start detecting drift. Take a snapshot now →"

Style: Match main Graphon dark theme. Use green/red semantic colors from Tailwind. Clear iconography for added (plus) and removed (minus).
```

---

## Page 4: Safe Delete Analysis

**Purpose:** Before decommissioning a service, calculate the full blast radius — what other services depend on it.

**Target Users:** Developers preparing to retire a service

**Components:**
- Service search input ("Which service do you want to delete?")
- Risk assessment card (High/Medium/Low/Safe)
- Dependency tree visualization showing all callers
- "Dead callers" detection — services that haven't called in N days
- Recommendation text

**Tables:**
- Active callers: service, last call, frequency
- Inactive callers: service, last call, days since last call

**Actions:**
- Run analysis
- Export report (for incident review)
- Open in Graph (centered on this service)

---

### Stitch Prompt — Safe Delete Analysis Page

```
Design a "Safe Delete Analysis" page for Graphon. The purpose is to help engineers safely decommission Kubernetes services by showing all dependents.

Layout:
- Page title: "Safe Delete Analysis"
- Search section: large search input "Enter service name to analyze..." with autocomplete

Results (shown after search):
- Risk badge prominently at top: SAFE (green) | LOW RISK (yellow) | HIGH RISK (red)
  - "This service has 4 active callers — safe to delete only after migrating traffic"

- "Active Callers" table:
  Columns: Service, Namespace, Last Call, Calls/min, Status
  Row color: green if last call >7 days ago (likely stale), red if active

- "Inactive Callers" section:
  Services that previously called but haven't in 7+ days
  Marked with "Likely stale — verify before proceeding"

- Dependency tree visualization: tree view showing caller → target → target's callers (2 levels)

- Recommendation box:
  Blue info box: step-by-step recommended decommission order
  e.g., "1. Notify fraud-detection team 2. Deprecate endpoint 3. Delete after 14 days"

- Action bar: [Export PDF Report] [Open in Graph] [Mark as Deprecated]

Style: Clean, medical/surgical feel — white backgrounds, clear iconography, semantic colors.
```

---

## Page 5: Multi-Cluster View

**Purpose:** Manage and visualize dependencies across multiple Kubernetes clusters.

**Target Users:** Platform engineers managing multi-cluster deployments

**Components:**
- Cluster health cards (grid or list)
- Per-cluster: name, status, service count, event rate, last seen
- "All Clusters" merged graph view
- Cluster comparison (diff between two clusters)
- Register new cluster button + generated helm command

**Tables:**
- Cluster list: name, region, status, services, events/min, last seen, actions

**Actions:**
- Register cluster
- Revoke cluster token
- View cluster graph
- Compare two clusters

---

### Stitch Prompt — Multi-Cluster View

```
Design a multi-cluster management page for Graphon, a Kubernetes dependency platform.

Layout:
- Header: "Clusters" | subtitle "Manage and monitor all registered clusters"
- Primary action: [Register New Cluster] button

Cluster grid (cards, 3-per-row on desktop):
Each card shows:
  - Cluster name (bold) + region chip
  - Status indicator: green dot (healthy) | yellow (degraded) | red (offline)
  - Stats row: "142 services" | "1,240 events/min" | "Last seen 30s ago"
  - Progress bar showing event rate (relative to max)
  - Action row: [View Graph] [Compare] [Manage]

"Register New Cluster" modal:
  - Input: cluster name
  - Select: region
  - Output (read-only, copy-to-clipboard): generated helm install command
  - Progress indicator: "Waiting for first connection..."
  - Success state: "Cluster connected! 12 events received."

Cross-cluster view toggle:
  - "Merge All" button shows unified graph with cluster color-coded nodes

Style: Dark theme matching Graphon main UI. Status colors: green/yellow/red from Tailwind. Card layout with subtle borders.
```

---

## Page 6: Historical Graph / Time-Travel

**Purpose:** Browse the dependency graph as it existed at a past point in time.

**Target Users:** SREs doing incident investigation, architects doing change tracking

**Components:**
- Timeline slider spanning available snapshot period
- Graph view updates on slider move
- Snapshot list (sidebar)
- Diff mode: compare two snapshots side-by-side or overlay

---

### Stitch Prompt — Historical Graph / Time-Travel

```
Design a "Historical Graph" time-travel UI for Graphon.

Layout:
- Full-screen graph view (same as main graph)
- Prominent timeline bar at the bottom of the screen

Timeline bar:
  - Horizontal scrubber spanning available date range (e.g., Jun 1 → Jun 27)
  - Snapshot markers as dots on the timeline
    - Auto snapshots: small gray dots
    - Manual snapshots: larger blue diamonds with label tooltip
  - Current position indicator
  - "Now" button (rightmost) → jumps to live view
  - Date/time display showing currently viewed point

Top toolbar:
  - "Time Travel Mode" badge (orange, indicating historical view)
  - Date/time input for jumping to specific time
  - "Compare with Now" button → opens diff mode
  - "Compare two snapshots" button → opens snapshot picker

Diff mode (side-by-side):
  - Left graph: baseline snapshot
  - Right graph: comparison snapshot
  - Color coding: green nodes/edges (added), red (removed), gray (unchanged)
  - Summary panel: "+3 deps, -1 dep, +2 services"

Snapshot list sidebar (togglable):
  - Label, trigger (auto/manual), nodes, edges, date
  - Click to jump to that snapshot
  - Delete button (admin only)

Style: Cinematic/timeline feel. Dark background. Timeline bar should feel like a video scrubber.
```

---

## Page 7: Advanced Search

**Purpose:** Global search across all services, teams, namespaces, and dependencies.

**Target Users:** All users

**Components:**
- Fullscreen search overlay (triggered by ⌘K)
- Search input with query type hints
- Grouped results (Services / Teams / Namespaces / Paths)
- Faceted filters in sidebar
- Keyboard navigation

---

### Stitch Prompt — Advanced Search

```
Design an advanced search interface for Graphon, triggered as a full-screen overlay (⌘K / Ctrl+K).

Overlay layout:
- Dark semi-transparent backdrop
- Centered modal, 700px wide, max-height 80vh
- Search input at top, full-width, large font (18px), placeholder: "Search services, teams, namespaces..."
- Below input: query type hints as pills: [service:] [team:] [ns:] [port:] [path:]

Results list:
- Grouped by type: Services (bold group header), Teams, Namespaces, Paths
- Service result item:
  Left: colored service icon
  Center: service name (with matched chars highlighted), namespace muted text
  Right: cluster chip, team chip
- Team result item: team name + "12 services" count
- Path result item: "checkout-service → payment-service → stripe" chain visualization

Keyboard navigation:
- Arrow keys move selection (highlighted row)
- Enter → navigate to result
- Escape → close overlay

Filter sidebar (shown when results exist):
- Cluster multiselect
- Namespace multiselect
- Team multiselect

Empty state:
- "No results for 'xyz'" with suggestion to try broader query

No results illustration (friendly, not scary).

Style: Match Graphon dark theme. Highlight matched text in yellow/orange. Fast feel — results should feel instant (debounced 150ms).
```

---

## Page 8: Architecture Export

**Purpose:** Export the graph as a static artifact for documentation, PR comments, or reports.

**Target Users:** Platform engineers, architects, technical leads

**Components:**
- Export modal (triggered from graph toolbar)
- Format picker (PNG / SVG / PDF / Draw.io / Mermaid / DOT)
- Scope selector (current view / full graph / filtered subset)
- Theme picker (light / dark)
- Preview pane
- Download button

---

### Stitch Prompt — Architecture Export

```
Design an export dialog for Graphon's dependency graph.

Dialog (modal, ~600px wide):
- Title: "Export Architecture Diagram"

Format section:
  - Format cards in a 3-column grid:
    [PNG] [SVG] [PDF*]
    [Draw.io*] [Mermaid] [DOT]
    (* = Pro/Enterprise badge)
  - Selected card highlighted with primary color border

Scope section:
  - Radio options:
    ○ Current view (what's visible on screen)
    ○ Full graph (all clusters and namespaces)
    ○ Selected namespace: [dropdown]
    ○ Focal service: [service search input] with depth selector (1/2/3/∞)

Options section:
  - Layout: [Hierarchical] [Force] [Circular] [Dagre]
  - Theme: [Light] [Dark]
  - Include labels: toggle
  - Include metadata (owner, team): toggle

Preview pane:
  - Small rendered preview of the export (live preview as options change)
  - "Preview updates as you configure"

Action bar:
  - [Cancel] [Download] primary button

Upgrade prompt (for locked formats):
  - Shown inline below locked format card: "PDF export requires Pro — Upgrade →"

Style: Clean modal, consistent with Graphon design system.
```

---

## Page 9: Settings

**Purpose:** Configure Graphon — license, auth, RBAC, clusters, notifications.

**Target Users:** Admin, Platform Admin

**Sections:**
- General (instance name, timezone)
- License (current plan, key input, expiry)
- Authentication (OIDC config)
- Users & RBAC (user list, role assignment)
- Clusters (see multi-cluster page)
- Integrations (GitHub App, GitLab App)
- Notifications (webhook URLs, email)
- Danger Zone (reset data, export all data)

---

### Stitch Prompt — Settings Page

```
Design a settings page for Graphon, a Kubernetes dependency platform.

Layout:
- Left sidebar navigation: General | License | Authentication | Users & Roles | Integrations | Notifications | Danger Zone
- Right content area for each section

General section:
  - Instance name text field
  - Timezone selector
  - Logo upload
  - Save button

License section:
  - Current plan badge (Free / Pro / Enterprise / Cloud)
  - Expiry date + days remaining (red if <14 days)
  - License key input (masked, show/hide toggle)
  - [Apply License Key] button
  - [Renewal instructions link]
  - Feature list showing what current plan includes (checkmarks)

Authentication section:
  - Auth enabled toggle
  - Provider: radio [OIDC] [Local (dev only)]
  - OIDC config form: Issuer URL, Client ID, Client Secret (masked), Redirect URL
  - Group role mapping table: Group name | Graphon role
  - [Save] [Test Connection] buttons

Users & Roles section:
  - User list table: Avatar | Name | Email | Role | Last Login | Actions
  - Actions: change role, deactivate
  - [Invite User] button (opens modal with email + role picker)
  - Namespace permissions: per-user namespace/cluster scope configuration

Integrations section:
  - GitHub App card: connected/disconnected status, configure button
  - GitLab App card: same
  - Each card shows: app name, last webhook received, repos connected

Danger Zone section:
  - Red bordered card
  - "Reset graph data" button (requires confirmation)
  - "Export all data" button (exports JSON dump)
  - "Unregister all clusters" button

Style: Clean admin panel aesthetic, form-heavy, muted color palette, Inter font.
```

---

## Page 10: Onboarding / First-Run

**Purpose:** Guide new users through installing the agent and viewing their first graph.

**Target Users:** New self-hosted deployers

**Steps:**
1. Welcome + product intro
2. Install Helm chart (copy command)
3. Waiting for agent connection (live status)
4. Deploy sample microservices (optional)
5. First graph view walkthrough

---

### Stitch Prompt — Onboarding Page

```
Design an onboarding wizard for Graphon — a first-run setup experience for new self-hosted users.

Progress bar at top: 5 steps [Welcome] [Install] [Waiting] [Explore] [Done]

Step 1 — Welcome:
  - Graphon logo + "Welcome to Graphon"
  - 3 benefit cards: "See every dependency" | "Detect drift instantly" | "Safe decommissioning"
  - [Get Started] button

Step 2 — Install Agent:
  - Title: "Deploy the Graphon Agent"
  - Short explanation: "The eBPF agent captures connections from every node"
  - Code block with copy button (pre-filled helm command)
  - [I've run the command] button → goes to step 3

Step 3 — Waiting for Connection:
  - Animated spinner + "Waiting for agent..."
  - Live status: "0 events received" updating in real-time to "12 events received"
  - On success: green checkmark + "Agent connected! First events received."
  - Timeout message (after 5 min): "Agent not connected? [Troubleshooting guide]"
  - [Skip for now] link

Step 4 — Explore:
  - "Your first dependency graph is ready!"
  - Annotated screenshot/preview of the graph UI
  - 3 tips with icons: [Click a node] [Try drift detection] [Set ownership labels]
  - [Open Graph] primary button

Step 5 — Done:
  - "You're all set!"
  - Quick links: Documentation | Pricing | GitHub
  - Confetti animation

Style: Friendly, clean, progress-driven. Light mode for onboarding (feels welcoming). Use Graphon blue accent.
```

---

## Page 11: Login

**Purpose:** Authentication entry point — OIDC or local.

---

### Stitch Prompt — Login Page

```
Design a login page for Graphon — a Kubernetes dependency intelligence platform.

Layout: Centered card on subtle grid/dot pattern background

Card:
  - Graphon logo at top
  - Title: "Sign in to Graphon"
  - Subtitle: "Runtime dependency intelligence for Kubernetes"

  SSO buttons (if providers configured):
  - [Continue with Google] (Google logo)
  - [Continue with Microsoft] (Azure AD logo)
  - [Continue with Okta] (Okta logo)
  - [Continue with SSO] (generic — triggers OIDC)

  Divider: "or" (shown only if local mode enabled)

  Local mode form (only if enabled):
  - Email input
  - Password input
  - [Sign In] button

Footer of card:
  - "Self-Hosted by your organization"
  - "Need help? docs.graphon.io"

Background: subtle dark geometric pattern (Kubernetes hexagon motif)
Card: white/dark depending on theme, subtle shadow
```

---

## Summary: All Pages

| # | Page | Priority | Stitch Prompt |
|---|------|----------|---------------|
| 1 | Dependency Graph | P0 | Included above |
| 2 | Service Detail | P0 | Included above |
| 3 | Drift Detection | P0 | Included above |
| 4 | Safe Delete Analysis | P0 | Included above |
| 5 | Multi-Cluster View | P1 | Included above |
| 6 | Historical Graph | P1 | Included above |
| 7 | Advanced Search | P1 | Included above |
| 8 | Architecture Export | P1 | Included above |
| 9 | Settings | P1 | Included above |
| 10 | Onboarding | P2 | Included above |
| 11 | Login | P2 | Included above |

---

## Design System Notes

When redesigning any page, maintain:
- **Font:** Inter (already used)
- **Color palette:** Tailwind slate/blue for primary, red/green/yellow for semantics
- **Graph library:** React Flow (do not replace — it powers the core feature)
- **Icons:** Lucide React (consistent with current codebase)
- **Component library:** shadcn/ui preferred
- **Dark mode:** All pages must support dark mode (Graphon's primary mode)
- **Keyboard shortcuts:** ⌘K (search), Escape (close modals), standard table navigation
