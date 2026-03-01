# CI Workflow Audit — Design Document

**Date:** 2026-03-01
**Status:** Approved

---

## Problem Statement

The `.github/workflows/` directory contains 10 workflow files with no inline documentation
and no README. It is unclear at a glance what each workflow does, what triggers it, what it
depends on, and which ones are redundant or broken. This makes maintenance decisions opaque
and onboarding new contributors harder.

---

## Goal

1. Add a structured header comment to each workflow file.
2. Create `.github/workflows/README.md` as an authoritative map of the CI system.
3. Document known issues and gaps discovered during the audit.

This documentation is a prerequisite for the next phase (cleanup and improvements).

---

## Audit Findings

### Inventory

| File | Name | Purpose | Trigger |
|------|------|---------|---------|
| `molecule.yml` | Molecule | Main orchestrator: detect changed roles, dispatch Docker + Vagrant matrix | push/PR + manual |
| `_molecule.yml` | Molecule Test | Reusable: run Docker-based molecule test for one role | workflow_call |
| `_molecule-vagrant.yml` | Molecule Vagrant (reusable) | Reusable: run Vagrant/KVM-based molecule test for one role + platform | workflow_call |
| `molecule-vagrant.yml` | Molecule Vagrant (KVM) | Standalone scheduled vagrant runner | schedule (Mon 04:00) + manual |
| `lint.yml` | Ansible Lint & Syntax Check | YAML lint + ansible-lint + playbook syntax checks | push/PR + manual |
| `build-ci-image.yml` | Build CI Environment Image | Build `ci-env` Docker image and push to GHCR | push + manual |
| `build-lint-image.yml` | Build Lint CI Image | Build `ci-env-lint` Docker image and push to GHCR | push + manual |
| `build-arch-image.yml` | Verify Arch Base Image | Verify arch-base image contract (does NOT build) | schedule (Mon 04:00) + manual |
| `molecule-integration.yml` | Molecule Integration (NTP live sync) | Live NTP sync test on self-hosted Arch runner | schedule (Mon 03:00) + manual |
| `sync-wiki.yml` | Sync Wiki | Sync `wiki/` to GitHub Wiki | push (wiki/**) + manual |

### CI Image Graph

```
Dockerfile.ci          → ci-env image (GHCR)        ← used by: _molecule.yml
Dockerfile.ci-lint     → ci-env-lint image (GHCR)   ← used by: lint.yml
arch-images repo       → arch-base image (GHCR)     ← used by: _molecule.yml (MOLECULE_ARCH_IMAGE)
ubuntu-images repo     → ubuntu-base image (GHCR)   ← used by: _molecule.yml (MOLECULE_UBUNTU_IMAGE)
arch-images repo       → arch-base.box (GH Releases) ← used by: _molecule-vagrant.yml
ubuntu-images repo     → ubuntu-base.box (GH Releases) ← used by: _molecule-vagrant.yml
```

### Known Issues

| # | Severity | File | Issue |
|---|----------|------|-------|
| 1 | BUG | `sync-wiki.yml` | `cp wiki/*.md` only copies root-level files. `wiki/roles/*.md` and `wiki/standards/*.md` are **not synced** to GitHub Wiki. |
| 2 | REDUNDANCY | `molecule-vagrant.yml` | Orchestration now lives in `molecule.yml`. Standalone file's only unique value is the weekly schedule, but it tests only the hardcoded `package_manager` role. Candidate for removal or consolidation. |
| 3 | MISLEADING | `build-arch-image.yml` | Filename says "build" but the workflow only **verifies** the image contract. Should be `verify-arch-image.yml`. |
| 4 | RELIABILITY | `molecule-integration.yml` | Requires `[self-hosted, arch]` runner. If not registered, jobs queue indefinitely. No `timeout-minutes`. |
| 5 | MAINTENANCE | `_molecule-vagrant.yml` | Pip cache key contains hardcoded versions (`ansible-core-2.20.1-molecule-25.12.0`). Will silently use stale cache if pip install versions are updated without updating the key. |
| 6 | GAP | `lint.yml` | Path filter only covers `ansible/**`. Changes to `.github/workflows/` don't trigger lint. Workflow YAML itself is never validated (no `actionlint`). |

---

## Proposed Design

### Header Comment Format

Each `.yml` file gets a block comment at the top (before `name:`):

```yaml
# Purpose: <one-line description of what this workflow does>
# Triggers: <when it runs>
# Uses: <other workflows, docker images, or external repos it depends on>
# Notes: <important caveats, known issues, TODOs>
```

The `Notes:` line is omitted for clean workflows. For broken/candidate-for-removal workflows,
the note explicitly says so.

### README Format (`.github/workflows/README.md`)

Sections:
1. **Overview table** — all 10 workflows with Purpose, Trigger, Depends On
2. **CI Image map** — which Dockerfiles produce which images and where they're used
3. **Workflow relationships** — which workflows call which (caller → callee)
4. **Known issues** — copy of the issues table above, with remediation status

---

## What This Is NOT

This design document covers **documentation only**. The following are deferred to a separate
implementation phase:

- Fixing the `sync-wiki.yml` bug (recursive copy)
- Removing `molecule-vagrant.yml` and adding schedule to `molecule.yml`
- Renaming `build-arch-image.yml` to `verify-arch-image.yml`
- Adding `actionlint` to `lint.yml`
- Fixing hardcoded pip cache key
- Adding `timeout-minutes` to all jobs

Those changes are tracked in the Known Issues table above and will be addressed once the
documentation baseline is established.
