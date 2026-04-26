# Research Brief: Canvas UX for SBOM Exploration

## Scope

This research looks for open-source and self-hosted tooling that can support a
workspace with the following UX:

- freely movable elements on a large canvas
- groups and nested structures
- rich interactive content inside blocks
- arrows and relationships between blocks
- visual exploration of structured data rather than static diagrams only

The target use case is a future interactive view over `base` and
`after-packages`, not just generic whiteboarding.

## The UX Requirement in Plain Terms

The requested UX is closer to a **custom graph workspace with rich embedded
widgets** than to a traditional dashboard or a simple whiteboard.

It requires all of the following at the same time:

1. free spatial placement
2. nested/grouped nodes
3. rich block content such as tables, badges, stats, text, maybe charts/forms
4. arrows/edges that remain attached during movement
5. self-hosted and open-source deployment

That combination is rare in ready-made products.

## Market Structure

The relevant market breaks into three categories:

### 1. Ready-made whiteboard/workspace products

These are fastest to adopt, but usually weaker at deeply interactive nested
content.

### 2. Graph/canvas SDKs

These are strongest when each node must behave like a mini-application with
custom UI.

### 3. Dashboard canvas layers

These can visualize data and connections, but usually do not provide the full
“whiteboard with living tables inside” experience.

## Key Candidates

| Tool | Type | License | Self-host | Free canvas | Rich node content | Groups/nesting | Arrows/relationships | Verdict |
|---|---|---|---|---|---|---|---|---|
| [AFFiNE](https://affine.pro/) | Workspace product | MIT CE | Yes | Yes | Yes, via docs/db/blocks | Partial | Yes | Best ready-made candidate |
| [React Flow](https://reactflow.dev/) | SDK | MIT | Yes | Yes | Yes, any React component | Yes | Yes | Best custom foundation |
| [AntV X6](https://x6.antv.antgroup.com/en/) | SDK | MIT | Yes | Yes | Yes, HTML/SVG/React/Vue | Yes | Yes | Strong diagram editor engine |
| [BlockSuite](https://github.com/toeverything/blocksuite) | Editor toolkit | MPL-2.0 | Yes | Yes | Yes, shared doc + edgeless model | Yes | Yes | Best hybrid foundation |
| [Cytoscape.js](https://js.cytoscape.org/) | Graph library | MIT | Yes | Limited | Limited | Yes | Yes | Graph-strong, UX-weaker |
| [Grafana Canvas](https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/canvas/) | Dashboard canvas | Grafana OSS core | Yes | Yes | Weak | Weak | Yes | Secondary layer only |
| [Excalidraw](https://github.com/excalidraw/excalidraw) | Whiteboard | MIT | Yes | Yes | Weak | Weak | Yes | Good whiteboard, weak rich-content fit |
| [diagrams.net](https://github.com/jgraph/drawio) | Diagram app | Apache-2.0 repo | Yes | Yes | Weak | Yes | Yes | Good schematics, weak live-content fit |
| [Rete.js](https://retejs.org/docs/) | Node editor SDK | MIT | Yes | Yes | Yes, controls in nodes | Yes | Yes | Better for workflow editors |

## Candidate Analysis

### AFFiNE

- Official:
  - <https://affine.pro/>
  - <https://docs.affine.pro/>
  - <https://github.com/toeverything/AFFiNE>
- License/self-host status:
  - official repo states Community Edition is free for self-host under MIT
- What it offers:
  - merges docs, whiteboards, and databases
  - “Edgeless Mode” turns structured content into spatial canvas content
  - official positioning emphasizes unified docs + whiteboard rather than
    separate silos
- Why it matters:
  - this is the closest ready-made open-source/self-hosted product to a “Notion
    + Miro + database” model
- Weaknesses:
  - not a native SBOM workspace
  - relationship semantics are generic, not supply-chain-native
  - database features are useful, but not a graph editor in the strict sense
- Verdict: **best ready-made product fit**

### React Flow

- Official:
  - <https://reactflow.dev/>
  - <https://reactflow.dev/learn/customization/custom-nodes>
  - <https://reactflow.dev/learn/layouting/sub-flows>
  - <https://reactflow.dev/learn/customization/custom-edges>
- License/self-host status:
  - MIT, library/SDK model
- What it offers:
  - custom nodes can contain any React UI, including interactive inputs, charts,
    and rich widgets
  - grouping and sub-flows
  - custom edges and handles
- Why it matters:
  - strongest fit if each node in the future SBOM canvas must contain rich,
    structured, interactive content
- Weaknesses:
  - not a product; everything above the graph layer must be built
- Verdict: **best custom foundation**

### AntV X6

- Official:
  - <https://x6.antv.antgroup.com/en/>
  - <https://github.com/antvis/X6>
  - <https://x6.antv.antgroup.com/en/tutorial/intermediate/html>
- License/self-host status:
  - MIT
- What it offers:
  - graph editing engine based on HTML and SVG
  - custom nodes using HTML / React / Vue / Angular
  - ports, groups, minimap, and graph-editing extensions
- Why it matters:
  - strong for more “diagram editor” style applications with rich nodes and
    controlled edges
- Weaknesses:
  - usually a steeper productization path than React Flow
- Verdict: **very strong engine candidate**

### BlockSuite

- Official:
  - <https://blocksuite.io/>
  - <https://github.com/toeverything/blocksuite>
- License/self-host status:
  - MPL-2.0
- What it offers:
  - `PageEditor` and `EdgelessEditor`
  - shared document model across document and spatial editor
  - collaborative block-based editing toolkit
- Why it matters:
  - closest technical foundation to “document + table + whiteboard on one model”
- Weaknesses:
  - higher integration complexity
  - toolkit, not a finished SBOM application
- Verdict: **best hybrid doc/canvas foundation**

### Cytoscape.js

- Official:
  - <https://js.cytoscape.org/>
- License/self-host status:
  - MIT
- What it offers:
  - compound nodes
  - strong graph rendering and relationship modeling
  - HTML label/overlay ecosystem
- Why it matters:
  - good if the main requirement is dependency graph exploration
- Weaknesses:
  - less natural for “node as rich embedded mini-app”
- Verdict: **graph-strong, richer-UI weaker**

### Grafana Canvas and Node Graph

- Official:
  - <https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/canvas/>
  - <https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/node-graph/>
  - <https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/table/>
- What it offers:
  - Canvas supports freely placed elements and connections
  - Node Graph supports nodes and edges with pan/zoom/layout
- Critical limitation:
  - Canvas element types are limited to items such as metric value, text,
    shapes, icon, server, and button
  - there is no true full table widget embedded as a movable first-class canvas
    element
- Why it matters:
  - useful as a visual overlay, but not as the primary rich-content canvas
- Verdict: **secondary visualization layer only**

### Excalidraw

- Official:
  - <https://github.com/excalidraw/excalidraw>
- License/self-host status:
  - MIT
- What it offers:
  - excellent whiteboard for sketching, arrows, and spatial ideation
- Weaknesses:
  - not designed for true nested structured widgets/tables inside nodes
- Verdict: **good whiteboard, weak fit for structured SBOM workspace**

### diagrams.net / draw.io

- Official:
  - <https://github.com/jgraph/drawio>
  - <https://www.drawio.com/blog/use-connectors>
- License/self-host status:
  - Apache-2.0 on the published repo
- What it offers:
  - mature diagram editor
  - connectors, groups, shapes, and self-hosting options
- Weaknesses:
  - repo README explicitly notes that real-time collaborative editing is not
    supported in this version
  - weak fit for living embedded rich-content widgets
- Verdict: **strong for schematics, weak for live canvas workspace**

### Rete.js

- Official:
  - <https://retejs.org/docs/>
  - <https://github.com/retejs/rete>
  - <https://retejs.org/examples/controls/>
- License/self-host status:
  - MIT
- What it offers:
  - visual interfaces and workflows
  - controls inside nodes
  - strong workflow/dataflow orientation
- Weaknesses:
  - better for workflow/programming-style editors than for a freeform knowledge
    workspace
- Verdict: **strong if the UX becomes workflow-first**

## Important Exclusion

### tldraw

- Official:
  - <https://github.com/tldraw/tldraw>
  - <https://github.com/tldraw/tldraw/blob/main/LICENSE.md>
- Why it is excluded from the main shortlist:
  - UX capabilities are strong
  - but the official license states free development use, while production use
    requires a license key
- Verdict: **not a clean open-source/self-hosted production candidate for this project**

## Structural Insight

This problem space has three realistic paths:

### A. Ready-made workspace path

- Best candidate: **AFFiNE**
- Trade-off:
  - fastest adoption
  - weakest supply-chain-specific semantics

### B. Graph editor with rich nodes path

- Best candidates: **React Flow**, **X6**
- Trade-off:
  - strongest UX control
  - requires custom product work

### C. Hybrid docs + blocks + edgeless path

- Best candidate: **BlockSuite**
- Trade-off:
  - strongest “documents and canvas are one model” story
  - highest integration complexity

## Shortlist

### 1. AFFiNE

Use when:

- the project wants a ready-made self-hosted workspace first
- rich docs/database/whiteboard coexistence matters more than graph purity

### 2. React Flow

Use when:

- the project wants to build a dedicated SBOM canvas UI with real interactive
  cards, groups, and dependency edges

### 3. AntV X6

Use when:

- the project wants a more formal diagram-editor engine with rich HTML/SVG nodes

### 4. BlockSuite

Use when:

- the project wants a single content model across docs, blocks, and edgeless
  spatial views

### 5. Cytoscape.js

Use when:

- graph semantics and large relationship views matter more than deep embedded UI
  inside each node

## Bottom Line

The requested UX is **not** best served by dashboards and **not** best served by
simple whiteboards alone.

It is closest to a **custom graph workspace with rich embedded blocks**.

That leads to a clear ranking:

- best ready-made open-source/self-hosted fit: **AFFiNE**
- best custom UI foundation: **React Flow**
- best diagram-engine alternative: **AntV X6**
- best hybrid doc/canvas toolkit: **BlockSuite**

## Sources

- AFFiNE:
  - <https://github.com/toeverything/AFFiNE>
  - <https://docs.affine.pro/>
  - <https://affine.pro/whiteboard>
  - <https://affine.pro/blog/affine-app>
  - <https://affine.pro/blog/interactive-whiteboard-app>
- BlockSuite:
  - <https://github.com/toeverything/blocksuite>
  - <https://blocksuite.io/>
- React Flow:
  - <https://reactflow.dev/>
  - <https://reactflow.dev/learn/customization/custom-nodes>
  - <https://reactflow.dev/learn/layouting/sub-flows>
  - <https://reactflow.dev/learn/customization/custom-edges>
- AntV X6:
  - <https://github.com/antvis/X6>
  - <https://x6.antv.antgroup.com/en/>
  - <https://x6.antv.antgroup.com/en/tutorial/intermediate/html>
- Cytoscape.js:
  - <https://js.cytoscape.org/>
- Grafana:
  - <https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/canvas/>
  - <https://grafana.com/docs/grafana/latest/visualizations/panels-visualizations/visualizations/node-graph/>
  - <https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/table/>
- Excalidraw:
  - <https://github.com/excalidraw/excalidraw>
- diagrams.net / draw.io:
  - <https://github.com/jgraph/drawio>
  - <https://www.drawio.com/blog/use-connectors>
- Rete.js:
  - <https://retejs.org/docs/>
  - <https://github.com/retejs/rete>
  - <https://retejs.org/examples/controls/>
- tldraw:
  - <https://github.com/tldraw/tldraw>
  - <https://github.com/tldraw/tldraw/blob/main/LICENSE.md>
