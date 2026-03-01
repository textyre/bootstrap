# CI Workflow Documentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add structured header comments to all 10 workflow files and create `.github/workflows/README.md` as the authoritative CI map.

**Architecture:** Each `.yml` gets a block comment (Purpose/Triggers/Uses/Notes) prepended before the `name:` field. The README links everything together with an overview table, image dependency graph, and known issues.

**Tech Stack:** YAML comments, Markdown, GitHub Actions conventions.

---

### Task 1: Document `molecule.yml` (main orchestrator)

**Files:**
- Modify: `.github/workflows/molecule.yml` (line 1, before `---`)

**Step 1: Prepend header comment**

Add at the very top of the file (before `---`):

```yaml
# Purpose: Main CI orchestrator for Molecule tests. Detects which roles changed
#          and dispatches Docker (fast) and Vagrant/KVM (realistic) test matrices.
# Triggers: push/PR to master (ansible/roles/**, requirements.txt, workflow files),
#           workflow_dispatch (role_filter input: specific role name or "all")
# Uses:    .github/workflows/_molecule.yml (Docker runner)
#          .github/workflows/_molecule-vagrant.yml (Vagrant runner)
# Notes:   Only roles with molecule/docker/molecule.yml are CI-ready.
#          Changes to ansible/roles/common/ trigger ALL CI-ready roles.
```

**Step 2: Verify the file is valid YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/molecule.yml'))" && echo OK
```

Expected: `OK`

**Step 3: Commit**

```bash
git add .github/workflows/molecule.yml
git commit -m "docs(ci): add header comment to molecule.yml"
```

---

### Task 2: Document `_molecule.yml` (reusable Docker runner)

**Files:**
- Modify: `.github/workflows/_molecule.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Reusable workflow — runs molecule test for a single role using Docker.
#          Tests both Arch (systemd) and Ubuntu images in one container run.
# Triggers: workflow_call only (called by molecule.yml)
# Uses:    ghcr.io/<repo>/ci-env:latest  (built by build-ci-image.yml)
#          ghcr.io/textyre/arch-base:latest
#          ghcr.io/textyre/ubuntu-base:latest
# Notes:   Mounts /var/run/docker.sock — requires Docker-in-Docker access on runner.
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_molecule.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/_molecule.yml
git commit -m "docs(ci): add header comment to _molecule.yml"
```

---

### Task 3: Document `_molecule-vagrant.yml` (reusable Vagrant runner)

**Files:**
- Modify: `.github/workflows/_molecule-vagrant.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Reusable workflow — runs molecule test for a single role using Vagrant/KVM.
#          Provides a realistic systemd environment closer to production than Docker.
# Triggers: workflow_call only (called by molecule.yml and molecule-vagrant.yml)
# Uses:    arch-base.box (github.com/textyre/arch-images releases)
#          ubuntu-base.box (github.com/textyre/ubuntu-images releases)
# Notes:   KVM is enabled via udev rules. vagrant-libvirt is always reinstalled
#          fresh (native .so must be compiled against the runner's libvirt).
#          Pip cache key contains HARDCODED versions — update key when bumping deps.
#          [KNOWN ISSUE #5] Cache key: pip-vagrant-${{ runner.os }}-ansible-core-2.20.1-molecule-25.12.0
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_molecule-vagrant.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/_molecule-vagrant.yml
git commit -m "docs(ci): add header comment to _molecule-vagrant.yml"
```

---

### Task 4: Document `molecule-vagrant.yml` (standalone scheduled runner)

**Files:**
- Modify: `.github/workflows/molecule-vagrant.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Standalone scheduled runner — weekly regression test of vagrant scenarios.
#          Predates the molecule.yml orchestrator; now partially redundant.
# Triggers: schedule (every Monday 04:00 UTC), workflow_dispatch (role input)
# Uses:    .github/workflows/_molecule-vagrant.yml
# Notes:   [CANDIDATE FOR REMOVAL] molecule.yml now handles vagrant on PR/push.
#          Unique value of this file: the weekly schedule.
#          Currently tests only 'package_manager' by default — not all vagrant roles.
#          Consider: merge schedule into molecule.yml + delete this file.
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/molecule-vagrant.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/molecule-vagrant.yml
git commit -m "docs(ci): add header comment to molecule-vagrant.yml (candidate for removal)"
```

---

### Task 5: Document `lint.yml`

**Files:**
- Modify: `.github/workflows/lint.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Fast quality gate — yamllint, ansible-lint, and playbook syntax checks.
#          Runs before molecule tests to catch formatting and structure errors cheaply.
# Triggers: push/PR to master (ansible/**), workflow_dispatch
# Uses:    ghcr.io/<repo>/ci-env-lint:latest  (built by build-lint-image.yml)
# Notes:   [KNOWN ISSUE #6] Path filter only covers ansible/**. Changes to
#          .github/workflows/ do NOT trigger this workflow. Workflow YAML itself
#          is never validated (no actionlint step).
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/lint.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/lint.yml
git commit -m "docs(ci): add header comment to lint.yml"
```

---

### Task 6: Document `build-ci-image.yml`

**Files:**
- Modify: `.github/workflows/build-ci-image.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Build and push the ci-env Docker image to GHCR.
#          This image is used by _molecule.yml for Docker-based molecule tests.
# Triggers: push to master (ansible/requirements.txt, ansible/requirements.yml,
#           .github/docker/Dockerfile.ci, this workflow file), workflow_dispatch
# Uses:    .github/docker/Dockerfile.ci
# Produces: ghcr.io/<repo>/ci-env:latest
# Notes:   Rebuild is triggered by ANY change to requirements.txt or Dockerfile.
#          There is no sequencing guarantee between this build and molecule.yml runs.
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-ci-image.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/build-ci-image.yml
git commit -m "docs(ci): add header comment to build-ci-image.yml"
```

---

### Task 7: Document `build-lint-image.yml`

**Files:**
- Modify: `.github/workflows/build-lint-image.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Build and push the ci-env-lint Docker image to GHCR.
#          This image is used by lint.yml for ansible-lint and yamllint runs.
# Triggers: push to master (ansible/requirements-lint.txt, ansible/requirements.yml,
#           .github/docker/Dockerfile.ci-lint, this workflow file), workflow_dispatch
# Uses:    .github/docker/Dockerfile.ci-lint
# Produces: ghcr.io/<repo>/ci-env-lint:latest
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-lint-image.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/build-lint-image.yml
git commit -m "docs(ci): add header comment to build-lint-image.yml"
```

---

### Task 8: Document `build-arch-image.yml`

**Files:**
- Modify: `.github/workflows/build-arch-image.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Verify that the external arch-base Docker image satisfies the image contract.
#          Does NOT build the image — it is built in github.com/textyre/arch-images.
# Triggers: schedule (every Monday 04:00 UTC, after arch-images build at 02:00 UTC),
#           workflow_dispatch
# Uses:    ghcr.io/textyre/arch-base:latest  (external, built by textyre/arch-images)
#          contracts/docker.sh  (image contract verification script)
# Notes:   [MISLEADING NAME] Filename says "build" but this only verifies.
#          Rename candidate: verify-arch-image.yml
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-arch-image.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/build-arch-image.yml
git commit -m "docs(ci): add header comment to build-arch-image.yml (rename candidate)"
```

---

### Task 9: Document `molecule-integration.yml`

**Files:**
- Modify: `.github/workflows/molecule-integration.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Run integration molecule scenario for roles that require real network access
#          (e.g., ntp live sync). Cannot run in Docker — needs real systemd + network.
# Triggers: schedule (every Monday 03:00 UTC), workflow_dispatch (role input)
# Uses:    [self-hosted, arch] runner  — must be pre-configured with Ansible venv
# Notes:   [RELIABILITY RISK] Requires self-hosted Arch runner to be registered and
#          online. If runner is unavailable, jobs queue indefinitely (no timeout).
#          No timeout-minutes set on the job. Only ntp has an integration scenario.
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/molecule-integration.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/molecule-integration.yml
git commit -m "docs(ci): add header comment to molecule-integration.yml"
```

---

### Task 10: Document `sync-wiki.yml`

**Files:**
- Modify: `.github/workflows/sync-wiki.yml` (line 1)

**Step 1: Prepend header comment**

```yaml
# Purpose: Sync the wiki/ directory from the main repo to the GitHub Wiki.
#          Keeps documentation co-located with code, versioned in git.
# Triggers: push to master (wiki/**), workflow_dispatch
# Notes:   [BUG] Uses `cp wiki/*.md` — only copies ROOT-LEVEL .md files.
#          wiki/roles/*.md and wiki/standards/*.md are NOT synced to GitHub Wiki.
#          Fix: replace with `cp -r wiki/. "$WIKI_DIR/"` or rsync.
```

**Step 2: Verify YAML**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/sync-wiki.yml'))" && echo OK
```

**Step 3: Commit**

```bash
git add .github/workflows/sync-wiki.yml
git commit -m "docs(ci): add header comment to sync-wiki.yml (documents known bug)"
```

---

### Task 11: Create `.github/workflows/README.md`

**Files:**
- Create: `.github/workflows/README.md`

**Step 1: Write README**

```markdown
# CI Workflows

This directory contains all GitHub Actions workflows for the bootstrap project.

## Overview

| File | Purpose | Trigger | Depends On |
|------|---------|---------|------------|
| `molecule.yml` | **Orchestrator** — detect changed roles, dispatch Docker + Vagrant matrix | push/PR (ansible/roles/**), manual | `_molecule.yml`, `_molecule-vagrant.yml` |
| `_molecule.yml` | **Reusable** — Docker-based molecule test for one role | workflow_call | `ci-env` image |
| `_molecule-vagrant.yml` | **Reusable** — Vagrant/KVM molecule test for one role + platform | workflow_call | `arch-base.box`, `ubuntu-base.box` |
| `molecule-vagrant.yml` | **Standalone scheduled** — weekly vagrant regression (⚠ candidate for removal) | schedule Mon 04:00, manual | `_molecule-vagrant.yml` |
| `lint.yml` | YAML lint + ansible-lint + playbook syntax check | push/PR (ansible/**), manual | `ci-env-lint` image |
| `build-ci-image.yml` | Build `ci-env` image → GHCR | push (Dockerfile.ci, requirements.txt) | — |
| `build-lint-image.yml` | Build `ci-env-lint` image → GHCR | push (Dockerfile.ci-lint, requirements-lint.txt) | — |
| `build-arch-image.yml` | Verify arch-base image contract (⚠ misnamed — does not build) | schedule Mon 04:00, manual | arch-images repo |
| `molecule-integration.yml` | Live integration tests on self-hosted Arch runner | schedule Mon 03:00, manual | `[self-hosted, arch]` runner |
| `sync-wiki.yml` | Sync `wiki/` to GitHub Wiki (⚠ has bug — subdirs not synced) | push (wiki/**), manual | — |

## Workflow Relationships

```
molecule.yml (orchestrator)
├── calls → _molecule.yml          (Docker, per changed role)
├── calls → _molecule-vagrant.yml  (Vagrant, per changed role × platform)
└── calls → _molecule-vagrant.yml  (Vagrant-laptop scenario)

molecule-vagrant.yml (standalone, scheduled)
└── calls → _molecule-vagrant.yml  (hardcoded: package_manager only)

lint.yml
└── uses → ci-env-lint image

_molecule.yml
└── uses → ci-env image
         → arch-base image (Arch tests)
         → ubuntu-base image (Ubuntu tests)

_molecule-vagrant.yml
└── uses → arch-base.box (libvirt)
         → ubuntu-base.box (libvirt)
```

## CI Image Map

| Image | Built By | Used By | Dockerfile |
|-------|---------|---------|------------|
| `ghcr.io/<repo>/ci-env:latest` | `build-ci-image.yml` | `_molecule.yml` | `.github/docker/Dockerfile.ci` |
| `ghcr.io/<repo>/ci-env-lint:latest` | `build-lint-image.yml` | `lint.yml` | `.github/docker/Dockerfile.ci-lint` |
| `ghcr.io/textyre/arch-base:latest` | textyre/arch-images repo | `_molecule.yml` | external |
| `ghcr.io/textyre/ubuntu-base:latest` | textyre/ubuntu-images repo | `_molecule.yml` | external |
| `arch-base.box` (libvirt) | textyre/arch-images releases | `_molecule-vagrant.yml` | external |
| `ubuntu-base.box` (libvirt) | textyre/ubuntu-images releases | `_molecule-vagrant.yml` | external |

## Known Issues

| # | Severity | File | Issue | Fix |
|---|----------|------|-------|-----|
| 1 | 🔴 BUG | `sync-wiki.yml` | `cp wiki/*.md` skips `wiki/roles/` and `wiki/standards/` subdirectories | Replace with `cp -r wiki/. "$WIKI_DIR/"` |
| 2 | 🟡 REDUNDANCY | `molecule-vagrant.yml` | Orchestration is now in `molecule.yml`; this file only adds a weekly schedule but tests only `package_manager` | Merge schedule into `molecule.yml`, delete this file |
| 3 | 🟡 MISLEADING | `build-arch-image.yml` | Filename says "build"; workflow only verifies | Rename to `verify-arch-image.yml` |
| 4 | 🟡 RELIABILITY | `molecule-integration.yml` | Requires `[self-hosted, arch]` runner with no timeout; hangs if runner offline | Add `timeout-minutes: 30`, investigate runner status |
| 5 | 🟢 MAINTENANCE | `_molecule-vagrant.yml` | Pip cache key has hardcoded versions; stale on dep upgrade | Use `hashFiles` on pip requirements or dynamic key |
| 6 | 🟢 GAP | `lint.yml` | `.github/workflows/**` not in path filter; no `actionlint` step | Expand filter, add actionlint |

## Molecule Role Coverage

CI-ready roles (have `molecule/docker/molecule.yml`): 32 roles
Vagrant-capable roles (also have `molecule/vagrant/molecule.yml`): 27 roles
Vagrant-laptop roles (have `molecule/vagrant-laptop/molecule.yml`): 1 role (power_management)
Integration scenario roles (have `molecule/integration/molecule.yml`): 1 role (ntp)
```

**Step 2: Verify the file renders correctly (inspect manually)**

Open `.github/workflows/README.md` and check that the tables are aligned and the code blocks look right.

**Step 3: Commit**

```bash
git add .github/workflows/README.md
git commit -m "docs(ci): add README with workflow overview, image map, and known issues"
```

---

### Task 12: Final verification

**Step 1: Confirm all 10 workflows have header comments**

```bash
for f in .github/workflows/*.yml; do
  if head -1 "$f" | grep -q "^#"; then
    echo "OK  $f"
  else
    echo "MISSING $f"
  fi
done
```

Expected: all 10 files print `OK`.

**Step 2: Confirm README exists**

```bash
ls -la .github/workflows/README.md && wc -l .github/workflows/README.md
```

Expected: file exists, ~80+ lines.

**Step 3: Final commit (if any stragglers)**

```bash
git status
# If nothing untracked, you're done.
```
