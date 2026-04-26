# Research Index

This directory stores research artifacts that feed later design and
implementation work.

## Current Artifacts

### BOOT-009

- [2026-04-25-supply-chain-sbom-tooling-research.md](D:/projects/bootstrap/docs/research/2026-04-25-supply-chain-sbom-tooling-research.md)
  - landscape research for open-source/self-hosted SBOM, SCA, supply-chain UI,
    diff, and graph tooling
  - includes candidate categories, strengths, weaknesses, and shortlist stacks

- [2026-04-25-canvas-ux-tooling-research.md](D:/projects/bootstrap/docs/research/2026-04-25-canvas-ux-tooling-research.md)
  - UX-focused research for a spatial canvas with movable groups, rich embedded
    content, and relationship arrows
  - compares ready-made workspace tools and graph/canvas SDK foundations

### BOOT-010

- [2026-04-26-supply-chain-reference-implementations-research.md](D:/projects/bootstrap/docs/research/2026-04-26-supply-chain-reference-implementations-research.md)
  - practical implementation research for SBOM and supply-chain references:
    roles, playbooks, self-hosted services, automation repos, and walkthroughs
  - evaluates what can be adapted for the project's `base` and
    `after-packages` snapshot workflow
  - includes strongest references and BOOT-011 shortlist candidates

## How To Use These Documents

- Use the SBOM/SCA tooling research as input for BOOT-010 and BOOT-011.
- Use the BOOT-010 reference-implementations research as the practical input
  for BOOT-011 architecture work.
- Use the canvas UX research when choosing between:
  - ready-made self-hosted workspace products
  - custom graph/canvas SDK foundations
- Treat these documents as research inputs, not final architecture decisions.

## Naming Convention

Research artifacts in this directory should use:

- `YYYY-MM-DD-topic.md`

This keeps the research history chronological and easy to scan.
