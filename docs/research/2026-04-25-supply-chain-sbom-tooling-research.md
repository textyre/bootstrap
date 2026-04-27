# BOOT-009: SBOM/SCA/Supply Chain Tooling Research

## Scope

This research compares open-source and self-hosted tooling for a future
`supply-chain` workflow around two snapshot states:

- `base`: clean post-install Arch Linux baseline
- `after-packages`: package baseline after the first three roles

The focus is on:

- SBOM generation for Arch/package snapshots
- SBOM comparison and validation
- visual tables and grouping
- diff workflows
- graph/diagram automation
- self-hosted UI and end-to-end platforms

This document is research only. It does not propose the final playbook or role
architecture.

## Snapshot Context

The candidate tooling has to work for a package-snapshot workflow, not just for
application dependency trees:

- `base` is the clean post-install package baseline described in
  `docs/default-packages.md`
- `after-packages` is the package state after `reflector`, `package_manager`,
  and `packages`
- the dominant inventory source is Arch Linux OS packages, plus AUR packages in
  the later snapshot

That makes native filesystem/rootfs/package inventory support more important
than language-level dependency support.

## Candidate Categories

### SBOM Generation

#### Syft

- Category: SBOM generation
- License: Apache-2.0
- Status: open-source, self-hosted CLI/library
- Official:
  - <https://github.com/anchore/syft>
  - <https://oss.anchore.com/docs/guides/sbom/catalogers/>
- What it does here:
  - generates SBOMs from filesystem/directory/rootfs inputs
  - has explicit Arch `pacman`/ALPM support in official schema/docs
  - strong fit for `base` and `after-packages`
- Weaknesses:
  - no native long-term UI
  - no rich visual diff workflow by itself
- Applicability:
  - `base`: strong
  - `after-packages`: strong
  - OS packages: strong
  - SBOM generation: yes
  - diff: no
  - visual grouping: no
  - diagram automation: no
- Verdict: suitable

#### cdxgen

- Category: SBOM generation / OBOM generation
- License: Apache-2.0
- Status: open-source, self-hosted CLI/library/server
- Official:
  - <https://github.com/CycloneDX/cdxgen>
- What it does here:
  - generates CycloneDX BOMs, including system-level `OBOM`
  - supports live system / VM style inventory generation
  - can render BOM as tree/table in CLI-oriented workflows
- Weaknesses:
  - more CycloneDX-centric
  - may produce a richer and noisier system view than needed for a strict Arch
    package baseline
- Applicability:
  - `base`: good
  - `after-packages`: good
  - OS packages: good
  - SBOM generation: yes
  - diff: via external CycloneDX tooling
  - visual grouping: limited
  - diagram automation: no
- Verdict: conditionally suitable

#### Trivy

- Category: SBOM generation + SCA
- License: Apache-2.0
- Status: open-source, self-hosted CLI
- Official:
  - <https://github.com/aquasecurity/trivy>
  - <https://trivy.dev/docs/latest/supply-chain/sbom/>
- What it does here:
  - can generate SBOM from filesystem/rootfs
  - supports CycloneDX and SPDX
  - can also consume SBOM as input for later scanning
- Weaknesses:
  - less focused on package snapshot comparison than Syft + dedicated diff layer
  - UI/grouping still external
  - use requires careful version pinning because of the official March 2026
    security advisory:
    <https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23>
- Applicability:
  - `base`: good
  - `after-packages`: good
  - OS packages: good
  - SBOM generation: yes
  - diff: no
  - visual grouping: no
  - diagram automation: no
- Verdict: conditionally suitable

#### DISTRO2SBOM

- Category: SBOM generation
- License: Apache-2.0
- Status: open-source CLI
- Official:
  - <https://spdx.dev/use/spdx-tools/>
  - <https://pypi.org/project/distro2sbom/>
- What it does here:
  - generates SBOM for system installations and installed applications
- Weaknesses:
  - current packaging model is centered around `rpm`, `deb`, Windows, and
    FreeBSD
  - weak fit for Arch snapshot/package inventory
- Applicability:
  - `base`: weak
  - `after-packages`: weak
  - OS packages: weak for Arch
  - SBOM generation: yes
  - diff: no
  - visual grouping: no
  - diagram automation: no
- Verdict: not suitable

### SBOM Comparison and Validation

#### CycloneDX CLI

- Category: diff / merge / validate / sign
- License: Apache-2.0
- Status: open-source CLI
- Official:
  - <https://github.com/CycloneDX/cyclonedx-cli>
- What it does here:
  - gives a strict diff/validate layer between `base` and `after-packages`
  - supports merge, validate, sign, and verify
- Weaknesses:
  - no SBOM generation
  - no UI
- Applicability:
  - `base`: yes
  - `after-packages`: yes
  - OS packages: indirect
  - SBOM generation: no
  - diff: strong
  - visual grouping: no
  - diagram automation: no
- Verdict: suitable

#### sbom-utility

- Category: validation / query / diff / merge
- License: Apache-2.0
- Status: open-source CLI/utility
- Official:
  - <https://github.com/CycloneDX/sbom-utility>
- What it does here:
  - validates CycloneDX and SPDX
  - supports diff and merge workflows
  - useful as an additional content/schema validation layer
- Weaknesses:
  - smaller ecosystem footprint than CycloneDX CLI
  - not a self-hosted dashboard
- Applicability:
  - `base`: yes
  - `after-packages`: yes
  - OS packages: indirect
  - SBOM generation: no
  - diff: good
  - visual grouping: no
  - diagram automation: no
- Verdict: conditionally suitable

### SCA / Vulnerability Overlay

#### Grype

- Category: vulnerability scanning / SCA overlay
- License: Apache-2.0
- Status: open-source, self-hosted CLI
- Official:
  - <https://github.com/anchore/grype>
  - <https://oss.anchore.com/docs/guides/vulnerability/scan-targets/>
- What it does here:
  - scans filesystem or previously generated SBOM
  - combines naturally with Syft in a generate-then-scan flow
- Weaknesses:
  - not a dashboard
  - not a diff tool
- Applicability:
  - `base`: good
  - `after-packages`: good
  - OS packages: good
  - SBOM generation: no
  - diff: no
  - visual grouping: no
  - diagram automation: no
- Verdict: suitable as overlay, not as primary platform

#### OWASP dep-scan

- Category: SCA / risk reporting
- License: MIT
- Status: open-source CLI/container
- Official:
  - <https://owasp.org/www-project-dep-scan/>
- What it does here:
  - supports local repos, container images, and live OS scan mode
  - uses `cdxgen` internally and can produce risk-oriented reporting
- Weaknesses:
  - not a BOM management platform
  - weaker for strict snapshot-to-snapshot diff
- Applicability:
  - `base`: good
  - `after-packages`: good
  - OS packages: good
  - SBOM generation: via cdxgen
  - diff: weak
  - visual grouping: limited
  - diagram automation: no
- Verdict: conditionally suitable

#### OWASP Dependency-Check

- Category: SCA
- License: Apache-2.0
- Status: open-source CLI/plugins
- Official:
  - <https://owasp.org/www-project-dependency-check/>
  - <https://dependency-check.github.io/DependencyCheck/general/dependency-check.pdf>
- What it does here:
  - mature dependency scanning for application ecosystems
- Weaknesses:
  - poor fit for Arch OS package snapshots
  - stronger for Java/.NET style dependency trees than rootfs/package baselines
- Applicability:
  - `base`: poor
  - `after-packages`: poor
  - OS packages: poor
  - SBOM generation: no
  - diff: no
  - visual grouping: report-style only
  - diagram automation: no
- Verdict: not suitable as a primary fit

### Visual Tables, Grouping, and Self-Hosted UI

#### Dependency-Track

- Category: end-to-end platform / self-hosted UI
- License: Apache-2.0
- Status: open-source, self-hosted platform
- Official:
  - <https://dependencytrack.org/>
  - <https://github.com/DependencyTrack/dependency-track>
  - <https://docs.dependencytrack.org/usage/collection-projects/>
- What it does here:
  - imports SBOMs and tracks projects/components/vulnerabilities/licenses
  - supports grouping through parent-child and collection projects
  - strong fit for visualizing `base` and `after-packages` as distinct project
    states or versions
- Weaknesses:
  - not a generator
  - BOM-to-BOM strict diff is weaker than dedicated CLI diff tooling
- Applicability:
  - `base`: strong
  - `after-packages`: strong
  - OS packages: good once BOM exists
  - SBOM generation: no
  - diff: moderate
  - visual grouping: strong
  - diagram automation: moderate
- Verdict: suitable

#### SBOMHub

- Category: self-hosted dashboard / BOM diff UI
- License: AGPL-3.0
- Status: open-source, self-hosted UI
- Official:
  - <https://sbomhub.app/en>
  - <https://github.com/youichi-uda/sbomhub>
- What it does here:
  - imports CycloneDX and SPDX
  - emphasizes explicit SBOM diff comparison with added/removed/updated views
- Weaknesses:
  - appears younger and less battle-tested than Dependency-Track
  - weaker on graph automation
- Applicability:
  - `base`: strong
  - `after-packages`: strong
  - OS packages: good once BOM exists
  - SBOM generation: no
  - diff: strong
  - visual grouping: strong
  - diagram automation: weak
- Verdict: conditionally suitable

### Graph and Diagram Automation

#### GUAC

- Category: graph-based supply chain platform
- License: Apache-2.0
- Status: open-source, self-hosted platform
- Official:
  - <https://guac.sh/guac/>
  - <https://docs.guac.sh/guac/>
  - <https://github.com/guacsec/guac>
- What it does here:
  - ingests SBOM and related artifacts into a graph model
  - useful for relationship queries and graph-centric supply-chain views
- Weaknesses:
  - weaker as a classic “table diff dashboard”
  - more graph-native than release-diff-native
- Applicability:
  - `base`: strong
  - `after-packages`: strong
  - OS packages: good once BOM exists
  - SBOM generation: no
  - diff: query/graph level
  - visual grouping: medium
  - diagram automation: strong
- Verdict: suitable

#### Mermaid / Graphviz

- Category: auxiliary diagram rendering
- License:
  - Mermaid: MIT
  - Graphviz: EPL-2.0
- Status: open-source renderers
- Official:
  - <https://github.com/mermaid-js/mermaid>
  - <https://graphviz.org/license/>
- What they do here:
  - render deterministic diagrams from already prepared relationship/diff data
- Weaknesses:
  - no SBOM analysis
  - no native BOM comparison
- Applicability:
  - `base`: indirect
  - `after-packages`: indirect
  - SBOM generation: no
  - diff: no
  - visual grouping: no
  - diagram automation: strong
- Verdict: suitable only as render layer

### Artifact Repository Layer

#### CycloneDX BOM Repository Server

- Category: BOM storage/distribution
- Status: self-hosted server
- Official:
  - <https://hub.docker.com/r/cyclonedx/cyclonedx-bom-repo-server>
  - <https://cyclonedx.org/news/owasp-cyclonedx-launches-sbom-exchange-api--standardizing-sbom-distribution/>
- What it does here:
  - stores and distributes versioned CycloneDX BOMs
- Weaknesses:
  - not a diff engine
  - not a visual dashboard
- Applicability:
  - `base`: good
  - `after-packages`: good
  - visual grouping: no
  - diagram automation: no
- Verdict: conditionally suitable as storage layer only

## Comparison Table

| Tool | Main Role | Arch Snapshot Fit | Diff/Validate | UI/Tables | Graph/Diagram | Verdict |
|---|---|---:|---:|---:|---:|---|
| Syft | SBOM generation | Strong | No | No | No | Best generator |
| cdxgen | System/OBOM generation | Good | Partial | Limited | No | Good richer generator |
| Trivy | SBOM + scan | Good | No | No | No | Conditional |
| CycloneDX CLI | Diff/validate | Strong | Strong | No | No | Best diff layer |
| sbom-utility | Validate/query/diff | Good | Good | No | No | Good secondary validator |
| Grype | Vulnerability overlay | Good | No | No | No | Best simple SCA overlay |
| dep-scan | Risk/SCA reporting | Good | Weak | Limited | No | Conditional |
| Dependency-Track | Portfolio UI | Strong | Moderate | Strong | Moderate | Best self-hosted UI |
| GUAC | Graph supply-chain | Strong | Query-level | Medium | Strong | Best graph-first platform |
| SBOMHub | Diff-focused UI | Strong | Strong | Strong | Weak | Best lighter diff dashboard |
| BOM Repo Server | Artifact storage | Good | No | No | No | Storage only |
| DISTRO2SBOM | System SBOM | Weak for Arch | No | No | No | Not fit |
| Dependency-Check | App dependency SCA | Weak for Arch | No | Report-only | No | Not fit |

## Best-Fit Candidates for `base` and `after-packages`

### Best generator

- **Syft** is the cleanest default for Arch/package snapshot generation.

### Best strict compare layer

- **CycloneDX CLI** is the strongest fit for explicit `base` vs
  `after-packages` diff/validate workflows.

### Best visual portfolio UI

- **Dependency-Track** is the strongest mainstream self-hosted UI for viewing
  BOM content, grouping, and higher-level portfolio/project views.

### Best graph-oriented platform

- **GUAC** is the most interesting graph-native option if relationship queries
  matter more than classic tabular dashboards.

### Best diff-focused self-hosted UI

- **SBOMHub** is the most directly relevant candidate for added/removed/updated
  BOM comparison in a lighter dashboard form.

## Shortlist

### 1. Syft + CycloneDX CLI + Dependency-Track

Why this stack stands out:

- strongest default fit for Arch package snapshots
- clear split between generation, strict diff, and self-hosted UI
- good balance between maturity and usability

### 2. Syft + CycloneDX CLI + GUAC

Why this stack stands out:

- best if the long-term direction is graph-native supply chain visibility
- stronger for relationship exploration than for classic version dashboards

### 3. cdxgen (OBOM) + CycloneDX CLI + Dependency-Track

Why this stack stands out:

- useful if the project wants a richer “system view” than a minimal package BOM
- still keeps a clear diff and UI layer

### 4. Syft or cdxgen + SBOMHub

Why this stack stands out:

- promising if the project values explicit BOM diff UI over a broader enterprise
  platform
- likely lighter to reason about than Dependency-Track

### 5. Syft + Grype + Dependency-Track

Why this stack stands out:

- practical split between SBOM generation, vulnerability overlay, and UI
- good if the project wants separate scanner and viewer responsibilities

## Bottom Line

If the next step is architecture work, the strongest default starting point is:

- **Syft + CycloneDX CLI + Dependency-Track**

If the project wants more graph-native supply-chain reasoning:

- **Syft + GUAC**

If the project wants a richer system BOM than a strict package-only baseline:

- **cdxgen (OBOM) + CycloneDX CLI + Dependency-Track**

## Sources

- Syft:
  - <https://github.com/anchore/syft>
  - <https://oss.anchore.com/docs/guides/sbom/catalogers/>
  - <https://oss.anchore.com/docs/reference/syft/json/16/>
- Trivy:
  - <https://github.com/aquasecurity/trivy>
  - <https://trivy.dev/docs/latest/supply-chain/sbom/>
  - <https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23>
- cdxgen:
  - <https://github.com/CycloneDX/cdxgen>
- CycloneDX CLI:
  - <https://github.com/CycloneDX/cyclonedx-cli>
- sbom-utility:
  - <https://github.com/CycloneDX/sbom-utility>
- Grype:
  - <https://github.com/anchore/grype>
  - <https://oss.anchore.com/docs/guides/vulnerability/scan-targets/>
- dep-scan:
  - <https://owasp.org/www-project-dep-scan/>
- Dependency-Track:
  - <https://dependencytrack.org/>
  - <https://github.com/DependencyTrack/dependency-track>
  - <https://docs.dependencytrack.org/usage/collection-projects/>
- GUAC:
  - <https://guac.sh/guac/>
  - <https://docs.guac.sh/guac/>
  - <https://github.com/guacsec/guac>
- SBOMHub:
  - <https://sbomhub.app/en>
  - <https://github.com/youichi-uda/sbomhub>
- CycloneDX BOM Repository Server:
  - <https://hub.docker.com/r/cyclonedx/cyclonedx-bom-repo-server>
  - <https://cyclonedx.org/news/owasp-cyclonedx-launches-sbom-exchange-api--standardizing-sbom-distribution/>
- SPDX/DISTRO2SBOM:
  - <https://spdx.dev/use/spdx-tools/>
  - <https://pypi.org/project/distro2sbom/>
- Dependency-Check:
  - <https://owasp.org/www-project-dependency-check/>
  - <https://dependency-check.github.io/DependencyCheck/general/dependency-check.pdf>
- Mermaid:
  - <https://github.com/mermaid-js/mermaid>
- Graphviz:
  - <https://graphviz.org/license/>
