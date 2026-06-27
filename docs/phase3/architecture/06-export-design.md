# Architecture Export Design

## Overview

Graphon can export the current dependency graph as a static artifact for use in architecture reviews, incident reports, PR comments, and documentation.

---

## Supported Formats

| Format | Use case | Library |
|--------|----------|---------|
| PNG | Screenshots, Slack, Jira tickets | Chromium headless / puppeteer |
| SVG | Scalable diagrams, PDFs, Draw.io import | D3.js → SVG string |
| PDF | Architecture reviews, compliance, audits | puppeteer / wkhtmltopdf |
| Draw.io (XML) | Editable diagrams in draw.io / Confluence | Custom serializer |
| Mermaid | README embedding, GitHub rendering | Graph → Mermaid DSL |
| DOT (Graphviz) | CLI tooling, CI pipelines | Graph → DOT language |

---

## Export API

```
POST /api/v1/export
Content-Type: application/json

{
  "format": "png",                    // png | svg | pdf | drawio | mermaid | dot
  "cluster": "prod-us-east-1",
  "snapshot_id": null,                // null = live graph
  "filters": {
    "namespaces": ["default", "payments"],
    "teams": ["payments", "checkout"],
    "max_depth": 3,                   // from focal node
    "focal_node": "checkout-service"  // optional: ego-centric graph
  },
  "layout": "hierarchical",          // hierarchical | force | circular | dagre
  "theme": "light",                  // light | dark
  "include_labels": true,
  "include_metadata": false           // owner, team, port info
}

Response:
  202 Accepted
  Location: /api/v1/export/{job-id}

GET /api/v1/export/{job-id}
  200 OK  { status: "complete", download_url: "/api/v1/export/{job-id}/file" }
  202     { status: "processing" }

GET /api/v1/export/{job-id}/file
  Content-Type: image/png  (or appropriate)
  Content-Disposition: attachment; filename="graphon-2026-06-27.png"
```

---

## Implementation Approach

### SVG (primary, server-side)

```
1. Fetch graph data from Neo4j (same as UI)
2. Apply layout algorithm (dagre for hierarchy, d3-force for organic)
3. Serialize to SVG string server-side using go-svg or embed a lightweight JS runtime
4. Return SVG bytes directly
```

### PNG / PDF (headless browser)

```
1. Backend starts ephemeral Chromium instance (or calls external render service)
2. Navigates to /internal/graph-render?snapshot=&filters=
3. Captures screenshot → PNG  OR  prints to PDF
4. Returns file

Alternative (lighter): 
  - Use go-chart or go-echarts for simpler graph rendering
  - Avoids Chromium dependency; less fidelity
  - Recommended for first implementation
```

### Draw.io XML

```
Graph nodes → <mxCell vertex>
Graph edges → <mxCell edge>
Layout:  Group by namespace → swimlane containers
Output:  valid Draw.io XML importable to app.diagrams.net
```

### Mermaid

```go
// Example output for a 5-node graph:
func GraphToMermaid(g *Graph) string {
    var b strings.Builder
    b.WriteString("graph LR\n")
    for _, edge := range g.Edges {
        b.WriteString(fmt.Sprintf("  %s --> %s\n", 
            sanitize(edge.Src), sanitize(edge.Dst)))
    }
    return b.String()
}
```

---

## Feature Gate

| Feature | Free | Pro | Enterprise | Cloud |
|---------|------|-----|------------|-------|
| PNG export | ✓ | ✓ | ✓ | ✓ |
| SVG export | ✓ | ✓ | ✓ | ✓ |
| PDF export | ✗ | ✓ | ✓ | ✓ |
| Draw.io | ✗ | ✓ | ✓ | ✓ |
| Mermaid | ✓ | ✓ | ✓ | ✓ |
| DOT (Graphviz) | ✓ | ✓ | ✓ | ✓ |
| Historical export | ✗ | ✓ | ✓ | ✓ |
| Filtered/focal export | ✗ | ✗ | ✓ | ✓ |
| API access to export | ✗ | ✓ | ✓ | ✓ |

---

## UI Integration

"Export" button in graph toolbar:
```
[Export ▼]
  ├─ PNG — Download image
  ├─ SVG — Download vector
  ├─ PDF — Download PDF (Pro)
  ├─ Draw.io — Open in diagrams.net (Pro)
  ├─ Mermaid — Copy to clipboard
  └─ DOT — Copy to clipboard
```

Export dialog:
- Format selector
- Scope (current view / full graph / namespace filter)
- Layout algorithm
- Theme (light/dark)
- Download or "Copy URL"
