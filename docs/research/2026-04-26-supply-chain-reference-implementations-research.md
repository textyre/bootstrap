# BOOT-010: Practical SBOM / Supply Chain Reference Implementations Research

## Goal

This report closes `BOOT-010` by collecting practical, reusable references for a
future `supply-chain` contour around two snapshot states:

- `base`: clean post-install baseline
- `after-packages`: package state after `reflector`, `package_manager`, and
  `packages`

The target is not another tool landscape. `BOOT-009` already covered the tool
classes. This document focuses on ready-made implementations and reference
patterns that can be adapted in `BOOT-011`.

## Scope

Included:

- Ansible roles and deployment playbooks
- self-hosted/containerized services
- end-to-end practical repositories and automation assets
- technical walkthroughs with commands, APIs, or reproducible outputs
- only references with concrete artifacts worth adapting

Explicitly excluded:

- generic product overviews
- architecture design for the final `supply-chain` playbook
- long lists of links without adaptation analysis
- redoing `BOOT-009`

## Snapshot Context

The key constraint is that the project is not tracking a normal application
dependency tree first. It is tracking package-oriented host snapshots:

- `base` is the clean VM package baseline
- `after-packages` is the package state after the first package-management
  roles
- the inventory source is primarily OS/package state, not only language-level
  dependencies

That means the strongest references are the ones that can be adapted to:

- generate SBOM for host/package state
- store multiple snapshot artifacts
- diff `base` vs `after-packages`
- visualize the results in tables or grouped views
- fit a self-hosted workflow

## Fit Legend

The `Fit` column uses `B/O/G/D/T/U/A`:

- `B`: snapshot baseline model
- `O`: OS/package inventory
- `G`: SBOM generation
- `D`: SBOM diff
- `T`: visual tables/grouping
- `U`: self-hosted UI
- `A`: automated diagram generation

Values:

- `Y`: strong fit
- `P`: partial fit
- `N`: no meaningful fit

## Ansible Roles / Playbooks

| Reference | Type | Source | OSS / self-hosted | What is implemented | Fit | What to reuse | Required adaptation | Verdict |
|---|---|---|---|---|---|---|---|---|
| `darkwizard242/ansible-role-syft` | role | [GitHub](https://github.com/darkwizard242/ansible-role-syft) | OSS role | Installs `syft`; role README explicitly positions it as an install role for a tool that generates SBOM from container images and filesystems | `P/P/Y/N/N/N/N` | Good starter pattern for a pinned generator-install role | Only Debian/Ubuntu and EL are supported in the published role; no built-in snapshot archive, diff, or UI | Partially useful |
| `bodsch/ansible-trivy` | role | [GitHub](https://github.com/bodsch/ansible-trivy) | OSS role | Installs `trivy`; tested on Arch Linux, Debian, and Ubuntu | `P/P/Y/N/N/N/N` | Better fit than many roles because Arch is already in the tested matrix | Still only an installer role, not a full supply-chain contour | Partially useful |
| Red Hat Trusted Profile Analyzer deployment guide | playbook / deployment reference | [Red Hat docs](https://docs.redhat.com/en/documentation/red_hat_trusted_profile_analyzer/latest/html-single/deployment_guide/index) | Self-hosted, but vendor-packaged | RHTPA can be deployed on RHEL via a vendor-provided Ansible playbook with PostgreSQL, OIDC, and S3-style storage | `P/Y/P/P/Y/Y/N` | Useful reference for packaging a supply-chain service as an Ansible-managed deployment with external dependencies | RHEL-specific, not a clean OSS role repo, and not snapshot-first | Partially useful |

## Container / Self-Hosted Services

| Reference | Type | Source | OSS / self-hosted | What is implemented | Fit | What to reuse | Required adaptation | Verdict |
|---|---|---|---|---|---|---|---|---|
| Dependency-Track | self-hosted service | [GitHub](https://github.com/DependencyTrack/dependency-track), [docs](https://docs.dependencytrack.org/) | OSS, self-hosted | Mature SBOM analysis platform with Docker Compose quickstart, portfolio/project/version model, API-first design, VEX support, and collection projects for grouped views | `P/Y/N/P/Y/Y/P` | Strongest archive + UI candidate; can model `base` and `after-packages` as project versions or tagged projects; collection projects are useful for grouped rollups | Strict BOM-to-BOM diff still wants an external tool; host snapshot semantics have to be imposed by your workflow | Useful reference |
| Trustify | self-hosted service | [GitHub](https://github.com/guacsec/trustify) | OSS, self-hosted | Searchable abstraction over CycloneDX/SPDX SBOMs with advisory correlation, GUI, REST API, upload flows, importers, and a single PostgreSQL-backed data model | `P/Y/N/P/Y/Y/N` | Strong reference for long-lived SBOM archive plus advisory intelligence; direct upload flow is reusable | Heavier than a simple snapshot viewer; no obvious first-class `base` vs `after-packages` diff UX | Useful reference |
| SBOMHub | self-hosted dashboard | [GitHub](https://github.com/youichi-uda/sbomhub) | OSS, self-hosted | Imports CycloneDX/SPDX from Syft/cdxgen/Trivy, correlates with NVD/JVN, exposes VEX, EPSS, SSVC, KEV, license policy, notifications, and Docker Compose self-hosting | `P/Y/N/N/Y/Y/N` | Good lightweight dashboard pattern for upload, prioritization, and policy views | No clear built-in snapshot diff; ecosystem is younger than Dependency-Track | Useful reference |
| BOM View | static self-hosted viewer | [GitHub](https://github.com/hristiy4n/bom-view) | OSS, self-hosted static site | Static UI for CycloneDX/SPDX JSON with searchable table, dynamic loading from `sboms/index.json`, OSV lookups, and easy Pages-style hosting | `Y/Y/N/N/Y/Y/N` | Best lightweight visualization reference for publishing `base.json` and `after-packages.json` without a heavy backend | No archive semantics, no auth, no first-class diff | Useful reference |
| GUAC | graph-based platform | [GitHub](https://github.com/guacsec/guac), [docs](https://docs.guac.sh/guac/) | OSS, self-hosted | Aggregates software security metadata into a graph database; has docs, demos, and Docker Compose quickstart | `P/Y/N/P/P/P/P` | Strong graph/data-model reference if relationships between snapshots, packages, advisories, and attestations matter | More graph-first than snapshot-review-first; more complex than needed for a first cut | Partially useful |
| OpenClarity | VM/cloud security platform | [GitHub](https://github.com/openclarity/openclarity) | OSS, self-hosted | Agentless VM-focused platform for SBOM analysis plus OS/package vulnerabilities, exploits, secrets, malware, rootkits, misconfigurations; normalizes and visualizes multiple scanner outputs | `P/Y/Y/P/Y/Y/N` | Best practical reference for VM-oriented scanning and normalized multi-tool UI over host-level findings | Broader than the immediate `base`/`after-packages` need and operationally heavier | Partially useful |

## End-to-End Practical Repositories / Automation Assets

| Reference | Type | Source | OSS / self-hosted | What is implemented | Fit | What to reuse | Required adaptation | Verdict |
|---|---|---|---|---|---|---|---|---|
| CycloneDX CLI | repository / CLI | [GitHub](https://github.com/CycloneDX/cyclonedx-cli) | OSS CLI | Explicit `diff`, `merge`, `validate`, `sign`, and format conversion workflows; `cyclonedx diff <from> <to>` is directly documented | `Y/N/N/Y/N/N/N` | Strongest ready-made diff engine for `base` vs `after-packages` | Needs a separate generator and separate UI/archive layer | Useful reference |
| `sbom-utility` | repository / CLI utility | [GitHub](https://github.com/CycloneDX/sbom-utility) | OSS CLI/API utility | Validates BOMs and has report/query commands that can extract, filter, summarize, and emit CSV-friendly outputs | `Y/N/N/P/Y/N/N` | Strong helper for turning SBOM content into tables and review-ready reports | Diff is not the primary reason to adopt it; no UI/archive | Partially useful |
| `sbom-observer/observer-cli` | repository / CLI workflow | [GitHub](https://github.com/sbom-observer/observer-cli) | OSS CLI | Generates CycloneDX SBOMs, supports `fs`, `image`, `diff`, `k8s`, and `upload`; has a command-oriented workflow that already thinks in terms of snapshots and uploadable artifacts | `Y/P/Y/Y/N/P/N` | Good reference for command UX and for separating generation, diff, and upload steps | Package-manager coverage is stronger for app ecosystems than for Arch host package inventory | Useful reference |
| `anchore/sbom-examples` | repository / examples | [GitHub](https://github.com/anchore/sbom-examples) | OSS examples repo | Repository of generated SBOM examples and source/image-oriented BOM artifacts | `Y/P/Y/N/N/N/N` | Useful naming/layout reference for storing multiple BOM artifacts per state or source | More example corpus than full workflow | Partially useful |
| `DependencyTrack/gh-upload-sbom` | automation repo / action | [GitHub](https://github.com/DependencyTrack/gh-upload-sbom) | OSS automation | Uploads BOMs to Dependency-Track and supports `projectName`, `projectVersion`, `projectTags`, `autoCreate`, and parent project linkage | `Y/N/N/N/P/Y/N` | Very good reference for how to model `base` and `after-packages` as versions/tags/children in a UI backend | GitHub Actions-specific wrapper; needs local adaptation into Task/Ansible/remote workflow | Useful reference |

## Tutorials / Articles With Full Walkthrough

| Reference | Type | Source | OSS / self-hosted | What is implemented | Fit | What to reuse | Required adaptation | Verdict |
|---|---|---|---|---|---|---|---|---|
| How to Structure an SBOM Review Process | walkthrough article | [Safeguard](https://safeguard.sh/resources/blog/how-to-structure-an-sbom-review-process) | Public technical walkthrough | Step-by-step review loop: generate SBOM with Syft, store artifacts in repo, diff with `cyclonedx-cli`, extract changes with `jq`, review licenses, commit a Markdown sign-off record | `Y/P/Y/Y/Y/N/N` | Closest process template to the project's snapshot workflow; directly reusable for `base` and `after-packages` review records | Does not provide a self-hosted UI or service layer | Very useful reference |
| A Practical Approach to SBOM in CI/CD Part III - Tracking SBOMs with Dependency-Track | walkthrough article | [DevSec Blog](https://devsec-blog.com/2024/03/a-practical-approach-to-sbom-in-ci-cd-part-iii-tracking-sboms-with-dependency-track/) | Public technical walkthrough | Shows a concrete flow: generate CycloneDX BOM, optionally modify/sign it, create service account permissions, and upload to Dependency-Track via API | `P/P/Y/N/Y/Y/N` | Strong upload/API pattern for turning generated snapshot SBOMs into trackable objects in a self-hosted UI | CI/CD framing is app-centric; snapshot naming and versioning must be adapted | Useful reference |

## Courses / Training

No course-grade reference made the shortlist.

Reason:

- most course/training materials found were either vendor marketing or too
  high-level
- they were weaker than the repositories and walkthroughs above
- none materially improved the BOOT-011 design input

## Strongest References For This Project

### 1. Dependency-Track

Why it matters:

- strongest mature self-hosted archive and UI
- has project/version/tag/parent-child structures that can represent snapshot
  states
- works well as the long-lived place to publish and inspect SBOM artifacts

Best reuse:

- treat `base` and `after-packages` as separate project versions or tagged
  sibling projects
- use collection projects when a grouped rollup is useful

### 2. CycloneDX CLI

Why it matters:

- clearest practical diff layer for `base` vs `after-packages`
- simple enough to wrap in future roles or tasks

Best reuse:

- canonical diff command
- validation and signing hooks for later hardening

### 3. Safeguard SBOM review walkthrough

Why it matters:

- best operational pattern, not just a product reference
- explicitly shows how to store SBOM artifacts, diff them, triage them, and
  keep a review record

Best reuse:

- repository layout for snapshot BOMs
- review checklist and sign-off artifact

### 4. BOM View

Why it matters:

- strongest lightweight visualization reference
- static hosting model is much easier than adopting a heavier backend first

Best reuse:

- publish `base.json`, `after-packages.json`, and future state BOMs through
  `sboms/index.json`
- searchable tables without having to build a backend

### 5. Trustify

Why it matters:

- strongest "archive + advisory intelligence" reference
- useful if BOOT-011 needs more than a viewer and wants a searchable data hub

Best reuse:

- GUI/API upload model
- archive semantics around SBOMs and advisories

### 6. `sbom-observer/observer-cli`

Why it matters:

- practical command-oriented reference for generation, diff, and upload
- closer to a workflow implementation than plain tool documentation

Best reuse:

- CLI UX ideas for future `supply-chain` task wrappers
- step separation between generate, diff, and publish

## Comparative Table Of Best Implementations

| Reference | Best role in BOOT-011 | Why it stands out | Main caveat |
|---|---|---|---|
| Dependency-Track | archive + self-hosted UI | mature, API-first, grouped portfolio views, easy BOM upload patterns | no native best-in-class strict diff |
| CycloneDX CLI | diff engine | simplest and strongest `base` vs `after-packages` comparator | no storage, no UI |
| Safeguard walkthrough | process template | most directly reusable snapshot-review workflow | article, not a deployable service |
| BOM View | lightweight visualization | easiest path to searchable self-hosted tables from static files | no archive semantics and no diff |
| Trustify | searchable archive + advisory overlay | richer long-term knowledge hub than a simple viewer | heavier to deploy and operate |
| `sbom-observer/observer-cli` | workflow inspiration | generation/diff/upload flow already exists in one CLI | package-manager assumptions need adaptation |

## Shortlist For BOOT-011

### Shortlist A: most pragmatic

- generator install via Ansible role pattern from `ansible-role-syft` or
  `ansible-trivy`
- diff via CycloneDX CLI
- archive/UI via Dependency-Track

Why this is strong:

- best maturity balance
- easiest to explain operationally
- clean separation between generation, comparison, and presentation

### Shortlist B: lightweight first iteration

- generator install via Syft/Trivy role pattern
- diff via CycloneDX CLI
- visualization via BOM View

Why this is strong:

- smallest operational footprint
- enough to prove the snapshot workflow before adopting a heavier platform

### Shortlist C: archive plus advisory intelligence

- generator install via Syft/Trivy role pattern
- diff via CycloneDX CLI
- storage/search/UI via Trustify

Why this is strong:

- better long-term archival and advisory model than a pure viewer
- strongest fit if future work expands beyond simple snapshot comparison

### Shortlist D: graph-first exploration

- generator install via Syft/Trivy role pattern
- publish results into GUAC

Why this is strong:

- useful only if the future direction values graph relationships and
  attestations more than a classic review dashboard

Why it is not the default:

- too heavy and abstract for the first BOOT-011 cut

## Key Gaps In The Reference Landscape

- No single OSS reference cleanly covers all of:
  snapshot baseline, OS/package inventory, SBOM generation, SBOM diff, visual
  grouping, self-hosted UI, and diagram generation.
- Ready-made Ansible references are weak. The role landscape is mostly
  installer roles, not full supply-chain contours.
- Automated diagram generation is still the least covered requirement. GUAC can
  inspire relationship modeling, but a direct "generate diagrams from snapshot
  BOM states" reference was not found.

## Bottom Line

If `BOOT-011` wants the lowest-risk starting point, the strongest design input
is:

1. Safeguard walkthrough as the process template
2. CycloneDX CLI as the diff layer
3. Dependency-Track as the primary archive/UI candidate
4. BOM View as the lightweight visualization fallback
5. Trustify as the richer archive/intelligence alternative

## Sources

- [darkwizard242/ansible-role-syft](https://github.com/darkwizard242/ansible-role-syft)
- [bodsch/ansible-trivy](https://github.com/bodsch/ansible-trivy)
- [Red Hat Trusted Profile Analyzer deployment guide](https://docs.redhat.com/en/documentation/red_hat_trusted_profile_analyzer/latest/html-single/deployment_guide/index)
- [Dependency-Track repository](https://github.com/DependencyTrack/dependency-track)
- [Dependency-Track documentation](https://docs.dependencytrack.org/)
- [Dependency-Track collection projects](https://docs.dependencytrack.org/usage/collection-projects/)
- [DependencyTrack/gh-upload-sbom](https://github.com/DependencyTrack/gh-upload-sbom)
- [Trustify repository](https://github.com/guacsec/trustify)
- [SBOMHub repository](https://github.com/youichi-uda/sbomhub)
- [BOM View repository](https://github.com/hristiy4n/bom-view)
- [GUAC repository](https://github.com/guacsec/guac)
- [GUAC documentation](https://docs.guac.sh/guac/)
- [OpenClarity repository](https://github.com/openclarity/openclarity)
- [CycloneDX CLI](https://github.com/CycloneDX/cyclonedx-cli)
- [`sbom-utility`](https://github.com/CycloneDX/sbom-utility)
- [`sbom-observer/observer-cli`](https://github.com/sbom-observer/observer-cli)
- [`anchore/sbom-examples`](https://github.com/anchore/sbom-examples)
- [How to Structure an SBOM Review Process](https://safeguard.sh/resources/blog/how-to-structure-an-sbom-review-process)
- [A Practical Approach to SBOM in CI/CD Part III - Tracking SBOMs with Dependency-Track](https://devsec-blog.com/2024/03/a-practical-approach-to-sbom-in-ci-cd-part-iii-tracking-sboms-with-dependency-track/)
