# CI Requirements Specification

> Source of truth for Ansible role CI/CD pipelines. All roles MUST comply.
> Testing specification: [[Testing Requirements|standards/testing-requirements]]
> Role implementation standards: [[Role Requirements|standards/role-requirements]]
> README structure: [[README Requirements|standards/readme-requirements]]
> Reference implementation: `.github/workflows/molecule-vagrant.yml`

## Scope

This specification applies to all CI workflows that test Ansible roles in `ansible/roles/`.
CI enforces the testing requirements (TEST-0XX) automatically — no manual run should be needed for standard quality gates.

### Relationship to Other Standards

| Document | Answers | Depends on |
|----------|---------|------------|
| Testing Requirements (TEST-0XX) | **What** to test and **how** | CI runs the tests |
| CI Requirements (CI-0XX) | **When**, **where**, and **enforcement** of tests | Testing defines what CI runs |
| README Requirements (README-0XX) | **How to interpret** CI results for humans | CI defines what to document |

---

## Requirements

### CI-001: GitHub Actions as CI Platform

**Category:** Platform
**Priority:** MUST
**Rationale:** The project is hosted on GitHub. GitHub Actions provides native integration with PR checks, branch protection, caching, and matrix strategies. All workflows live in `.github/workflows/` and are version-controlled alongside the code they test.

**Implementation Pattern:**
```yaml
# .github/workflows/molecule-test.yml
name: Molecule Tests
on:
  push:
    branches: [master]
    paths:
      - 'ansible/roles/**'
      - '.github/workflows/molecule-*.yml'
  pull_request:
    branches: [master]
    paths:
      - 'ansible/roles/**'
      - '.github/workflows/molecule-*.yml'
  workflow_dispatch:
    inputs:
      role:
        description: 'Role name to test (e.g., ntp)'
        required: true
        type: string
  schedule:
    - cron: '0 4 * * 1'  # Weekly Monday 04:00 UTC
```

**Verification Criteria:**
- All CI workflows live in `.github/workflows/`
- Workflows trigger on: push to master, PR to master, manual dispatch, weekly schedule
- `paths` filter limits triggers to `ansible/roles/**` and workflow files — no CI run for wiki-only changes
- `workflow_dispatch` accepts role name as input for manual single-role testing
- Workflow files are YAML, named `molecule-*.yml`

**Anti-patterns:**
- CI workflows outside `.github/workflows/` (e.g., shell scripts in `scripts/ci/`)
- No `paths` filter — CI runs on every commit including docs-only changes
- No `workflow_dispatch` — can't manually test a single role without pushing a change
- No `schedule` — degradation from external changes (new OS releases, package removals) goes unnoticed

---

### CI-002: Workflow Structure (Detect + Matrix + Dispatch)

**Category:** Structure
**Priority:** MUST
**Rationale:** The project is a monorepo with 30+ roles. Running all tests on every push is wasteful. Detect-based dispatch identifies changed roles and builds a dynamic matrix — only changed roles are tested. For manual runs, the dispatched role overrides detection.

**Implementation Pattern:**
```yaml
jobs:
  detect:
    name: Detect changed roles
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.detect.outputs.matrix }}
      has_changes: ${{ steps.detect.outputs.has_changes }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for diff

      - name: Detect changed roles
        id: detect
        run: |
          if [ "${{ github.event_name }}" = "workflow_dispatch" ]; then
            # Manual dispatch — test specific role
            ROLES='["${{ github.event.inputs.role }}"]'
          elif [ "${{ github.event_name }}" = "schedule" ]; then
            # Scheduled — test all roles
            ROLES=$(ls -d ansible/roles/*/molecule 2>/dev/null | \
              sed 's|ansible/roles/||;s|/molecule||' | jq -R -s -c 'split("\n") | map(select(. != ""))')
          else
            # Push/PR — detect changed roles
            # Note: for robust PR detection with multi-commit PRs,
            # use tj-actions/changed-files or compare against base branch:
            #   git diff --name-only origin/${{ github.base_ref }}...HEAD
            # Simplified example for push events:
            ROLES=$(git diff --name-only ${{ github.event.before || 'origin/master' }} HEAD -- ansible/roles/ | \
              cut -d/ -f3 | sort -u | jq -R -s -c 'split("\n") | map(select(. != ""))')
          fi

          if [ "$ROLES" = "[]" ] || [ -z "$ROLES" ]; then
            echo "has_changes=false" >> "$GITHUB_OUTPUT"
            echo "matrix={}" >> "$GITHUB_OUTPUT"
          else
            echo "has_changes=true" >> "$GITHUB_OUTPUT"
            echo "matrix={\"role\":$ROLES}" >> "$GITHUB_OUTPUT"
          fi

  lint:
    needs: detect
    if: needs.detect.outputs.has_changes == 'true'
    # ... (see CI-003)

  test-docker:
    needs: [detect, lint]
    if: needs.detect.outputs.has_changes == 'true'
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.detect.outputs.matrix) }}
    # ... (see CI-004)

  test-vagrant:
    needs: [detect, lint]
    if: needs.detect.outputs.has_changes == 'true'
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.detect.outputs.matrix) }}
    # ... (see CI-005)
```

```yaml
# Reusable workflow for manual single-role testing
# .github/workflows/molecule-role.yml
name: Test Single Role
on:
  workflow_call:
    inputs:
      role:
        required: true
        type: string
      scenario:
        required: false
        type: string
        default: 'default'
```

**Verification Criteria:**
- Detect step identifies changed roles via `git diff` on push/PR
- Scheduled runs test ALL roles with molecule directories
- `workflow_dispatch` allows manual single-role testing
- Matrix built dynamically from detect output — no hardcoded role list
- `fail-fast: false` on all matrix strategies — see all failures, not just the first
- Reusable workflow available for `workflow_call` — roles can invoke it independently

**Anti-patterns:**
- Hardcoded list of roles in workflow matrix (falls behind as roles are added)
- `fail-fast: true` (default) — first failure cancels other matrix jobs, hiding additional failures
- No detect step — every push tests all 30+ roles (wastes 2+ hours of CI time)
- `fetch-depth: 1` in checkout — `git diff` fails without history

---

### CI-003: Lint Job

**Category:** Structure
**Priority:** MUST
**Rationale:** Static analysis is cheap and fast (< 1 minute). Running it before molecule saves 10-30 minutes of VM/container time when there's a syntax error. Lint job MUST be a separate job that blocks molecule jobs — fail fast on the cheapest check.

**Implementation Pattern:**
```yaml
  lint:
    name: Lint (${{ matrix.role }})
    needs: detect
    if: needs.detect.outputs.has_changes == 'true'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.detect.outputs.matrix) }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install lint tools
        run: pip install -r requirements-ci.txt

      - name: Run yamllint
        run: yamllint ansible/roles/${{ matrix.role }}/

      - name: Run ansible-lint
        run: ansible-lint ansible/roles/${{ matrix.role }}/
```

**Verification Criteria:**
- Lint is a SEPARATE job, not a step inside molecule job
- Lint job runs BEFORE molecule jobs (`needs: [detect, lint]` on test jobs)
- Both `yamllint` and `ansible-lint` run
- Lint failure blocks molecule jobs (no point testing code that doesn't parse)
- Lint tool versions pinned via `requirements-ci.txt` (see CI-007)

**Anti-patterns:**
- Lint as a step inside molecule job (lint failure wastes container creation time)
- Only `yamllint` without `ansible-lint` (misses best-practice violations)
- Lint after molecule test (syntax error found after 15 minutes of testing)
- Lint tools installed without version pinning (`pip install ansible-lint` gets latest, may break)

---

### CI-004: Molecule Docker Job

**Category:** Execution
**Priority:** MUST
**Rationale:** Docker tests (molecule default scenario) are fast (2-5 minutes) and test logic correctness, idempotence, and basic verification. They run on every push and PR as the first line of defense. Matches TEST-002 requirement for mandatory Docker scenario.

**Implementation Pattern:**
```yaml
  test-docker:
    name: Docker (${{ matrix.role }})
    needs: [detect, lint]
    if: needs.detect.outputs.has_changes == 'true'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.detect.outputs.matrix) }}
    env:
      PY_COLORS: "1"
      ANSIBLE_FORCE_COLOR: "1"
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install dependencies
        run: pip install -r requirements-ci.txt

      - name: Run molecule (Docker)
        working-directory: ansible/roles/${{ matrix.role }}
        run: molecule test
        timeout-minutes: 15

      # SHOULD: retry once for transient failures (network, mirrors)
      - name: Retry on failure
        if: failure()
        working-directory: ansible/roles/${{ matrix.role }}
        run: molecule test
        timeout-minutes: 15
```

**Verification Criteria:**
- Docker job uses `ubuntu-latest` runner
- `PY_COLORS=1` and `ANSIBLE_FORCE_COLOR=1` set for readable output (TEST-014)
- `timeout-minutes` set (15 min default) — prevents hung jobs from consuming CI quota
- SHOULD: one automatic retry on failure (flaky test mitigation) — not required but recommended
- Working directory set to role root — molecule finds `molecule/default/` automatically
- `fail-fast: false` — all roles in matrix tested regardless of individual failures

**Anti-patterns:**
- No timeout — hung container blocks runner indefinitely
- No retry — transient network errors fail the build permanently
- More than 1 retry — masks real failures, wastes CI time
- Missing color env vars — CI output unreadable (TEST-014)
- `molecule test -s docker` instead of `molecule test` (default scenario IS Docker per TEST-002)

---

### CI-005: Molecule Vagrant Job

**Category:** Execution
**Priority:** MUST
**Rationale:** Vagrant tests (molecule vagrant scenario) use real VMs with real systemd, real packages, and cross-platform matrix (Arch + Ubuntu). They catch platform-specific bugs that Docker cannot. MUST pass for merge into master. Matches TEST-002 requirement for mandatory Vagrant scenario.

**Implementation Pattern:**
```yaml
  test-vagrant:
    name: Vagrant (${{ matrix.role }})
    needs: [detect, lint]
    if: needs.detect.outputs.has_changes == 'true'
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix: ${{ fromJson(needs.detect.outputs.matrix) }}
    env:
      PY_COLORS: "1"
      ANSIBLE_FORCE_COLOR: "1"
    steps:
      - uses: actions/checkout@v4

      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - uses: actions/setup-python@v5
        with:
          python-version: '3.12'

      - name: Install system dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y libvirt-dev libvirt-daemon-system ruby-dev build-essential pkg-config
          # Install Vagrant from HashiCorp APT repo (system package is outdated)
          wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
          echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list
          sudo apt-get update && sudo apt-get install -y vagrant
          sudo systemctl start libvirtd

      - name: Install Python dependencies
        run: pip install -r requirements-ci.txt

      - name: Install vagrant-libvirt (always reinstall)
        run: |
          vagrant plugin uninstall vagrant-libvirt || true
          vagrant plugin install vagrant-libvirt

      - name: Cache Vagrant boxes
        uses: actions/cache@v4
        with:
          path: ~/.vagrant.d/boxes
          key: vagrant-boxes-${{ hashFiles('ansible/roles/*/molecule/vagrant/molecule.yml') }}
          restore-keys: vagrant-boxes-

      - name: Cache vagrant-libvirt gems
        uses: actions/cache@v4
        with:
          path: ~/.vagrant.d/gems/cache
          key: vagrant-gems-${{ runner.os }}-${{ hashFiles('requirements-ci.txt') }}
          restore-keys: vagrant-gems-${{ runner.os }}-

      - name: Run molecule (Vagrant)
        working-directory: ansible/roles/${{ matrix.role }}
        run: molecule test -s vagrant
        timeout-minutes: 30

      # SHOULD: retry once for transient failures
      - name: Retry on failure
        if: failure()
        working-directory: ansible/roles/${{ matrix.role }}
        run: molecule test -s vagrant
        timeout-minutes: 30
```

**Verification Criteria:**
- KVM enabled via udev rules (GitHub runners support nested virtualization)
- `vagrant-libvirt` ALWAYS reinstalled — never skipped via cache-hit (native .so ABI incompatibility between runners)
- Vagrant boxes cached by content hash of molecule.yml files
- Vagrant gem download cache keyed by OS + lock file hash
- `timeout-minutes: 30` (Vagrant is slower than Docker)
- SHOULD: one automatic retry on failure
- `fail-fast: false` on matrix
- Vagrant job runs in parallel with Docker job (both `needs: [detect, lint]`, not sequential)

**Anti-patterns:**
- `vagrant-libvirt` installed only when cache misses (`.so` compiled on different runner = crash)
- No KVM setup — vagrant-libvirt falls back to QEMU TCG (10x slower)
- Vagrant job depends on Docker job (`needs: test-docker`) — unnecessary serialization
- No box cache — 500MB+ downloaded on every run
- `timeout-minutes` > 45 — indicates test or infrastructure problem, not slow test
- `vagrant box add` without idempotence guard (re-downloads on restore-key partial match)

---

### CI-006: Quality Gates

**Category:** Enforcement
**Priority:** MUST
**Rationale:** Quality gates without enforcement are suggestions. Branch protection rules MUST require CI to pass before merge. Without this, CI is advisory and gets ignored under deadline pressure. "It works on my machine" is not a quality gate.

**Implementation Pattern:**
```
GitHub Repository Settings → Branches → Branch protection rules → master:

✅ Require status checks to pass before merging
  ✅ Require branches to be up to date before merging
  Required status checks:
    - Lint (<role>)           — MUST pass
    - Docker (<role>)         — MUST pass
    - Vagrant (<role>)        — MUST pass

✅ Require pull request reviews before merging
  Required approving reviews: 1

✅ Do not allow bypassing the above settings
```

```yaml
# Enforcement in workflow: jobs must not have continue-on-error
# CORRECT:
  test-docker:
    # No continue-on-error — failure blocks merge

# WRONG:
  test-docker:
    continue-on-error: true  # Defeats the quality gate
```

**Verification Criteria:**
- Branch protection enabled on `master` with required status checks
- All three check types required: Lint, Docker, Vagrant
- `continue-on-error: true` NEVER used on required jobs
- PR reviews required (minimum 1 approver)
- Force push to master disabled
- Admins CANNOT bypass these settings (`Do not allow bypassing`)
- Scheduled run failures do NOT block PRs (separate workflow or `if: github.event_name != 'schedule'` on required checks)

**Anti-patterns:**
- Branch protection disabled ("we'll enable it later")
- `continue-on-error: true` on molecule jobs (CI always green, failures ignored)
- Only Docker required, Vagrant optional (platform bugs merge into master)
- Admins can bypass (becomes the default escape hatch)
- Scheduled failures block unrelated PRs (required check stays red from cron failure)

---

### CI-007: Dependency Version Pinning

**Category:** Reliability
**Priority:** MUST
**Rationale:** "It worked yesterday, broke today" is almost always a dependency update. CI dependencies (molecule, ansible-core, ansible-lint, yamllint) MUST be pinned to exact versions in a lock file. Updates happen through explicit PRs, not silent pip upgrades.

**Implementation Pattern:**
```
# requirements-ci.in — human-maintained input file
molecule>=24.12,<25
molecule-plugins[docker,vagrant]>=24.0,<25
ansible-core>=2.16,<2.18
ansible-lint>=24.0,<25
yamllint>=1.35,<2
```

```
# requirements-ci.txt — generated lock file (pip-compile output)
# DO NOT EDIT — generated by pip-compile from requirements-ci.in
ansible-core==2.16.14
ansible-lint==24.12.2
molecule==24.12.0
molecule-plugins==24.0.0
yamllint==1.35.1
# ... all transitive dependencies with hashes
```

```bash
# Update lock file (manual or via Renovate/Dependabot PR)
pip-compile requirements-ci.in -o requirements-ci.txt --generate-hashes

# CI installs from lock file
pip install -r requirements-ci.txt
```

```yaml
# .github/dependabot.yml — automated update PRs
version: 2
updates:
  - package-ecosystem: pip
    directory: /
    schedule:
      interval: weekly
    commit-message:
      prefix: "ci"
    labels:
      - dependencies
      - ci
```

**Verification Criteria:**
- `requirements-ci.in` exists with human-readable version constraints
- `requirements-ci.txt` exists as pip-compile output with exact versions and hashes
- CI workflow uses `pip install -r requirements-ci.txt` — never bare `pip install molecule`
- Dependabot or Renovate configured for weekly update PRs
- Lock file changes go through normal PR process (CI tests the update)
- GitHub Actions versions SHOULD be pinned by SHA for supply chain security: `actions/checkout@<sha>` not `actions/checkout@v4`. Tag pinning is acceptable for first-party GitHub actions (`actions/*`) but SHA pinning is strongly recommended for third-party actions.

**Anti-patterns:**
- `pip install molecule ansible-lint` in workflow without version constraints (breaks randomly)
- Pinned versions in workflow YAML instead of lock file (scattered, hard to update)
- No automated update mechanism (pinned versions rot, miss security fixes)
- Third-party actions pinned by tag only (supply chain risk — tags can be force-pushed)
- Lock file committed but never regenerated (dependencies drift from constraints)

---

### CI-008: Caching Strategy

**Category:** Performance
**Priority:** MUST
**Rationale:** Without caching, every CI run downloads 500MB+ of Vagrant boxes, rebuilds vagrant-libvirt native extensions, and re-downloads pip packages. Caching reduces Vagrant job time from 15+ minutes to 5-8 minutes. But incorrect caching (especially vagrant-libvirt) causes hard-to-debug native extension crashes.

**Implementation Pattern:**
```yaml
# Pip cache — safe, always use
- uses: actions/setup-python@v5
  with:
    python-version: '3.12'
    cache: 'pip'
    cache-dependency-path: requirements-ci.txt

# Vagrant box cache — safe, key by molecule.yml content
- uses: actions/cache@v4
  id: box-cache    # MUST have id for cache-hit check
  with:
    path: ~/.vagrant.d/boxes
    key: vagrant-boxes-${{ hashFiles('ansible/roles/*/molecule/vagrant/molecule.yml') }}
    restore-keys: vagrant-boxes-

# Vagrant box add — idempotent regardless of cache hit
- name: Add Vagrant boxes
  run: |
    vagrant box list | grep -q "^arch-base " || \
      vagrant box add arch-base https://github.com/textyre/arch-images/releases/latest/download/arch-base.box
    vagrant box list | grep -q "^ubuntu-base " || \
      vagrant box add ubuntu-base https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box

# Vagrant gem cache — speeds up download, does NOT skip install
- uses: actions/cache@v4
  with:
    path: ~/.vagrant.d/gems/cache
    key: vagrant-gems-${{ runner.os }}-${{ hashFiles('requirements-ci.txt') }}
    restore-keys: vagrant-gems-${{ runner.os }}-

# vagrant-libvirt — ALWAYS reinstall, never skip
- name: Install vagrant-libvirt (always)
  run: |
    vagrant plugin uninstall vagrant-libvirt || true
    vagrant plugin install vagrant-libvirt
```

**Verification Criteria:**
- Pip cache uses `actions/setup-python` built-in caching keyed by `requirements-ci.txt`
- Vagrant box cache has explicit `id:` for cache-hit output access
- Vagrant box add is unconditionally idempotent (`grep -q || add`) — never relies on `cache-hit` flag alone
- Vagrant gem cache stores `~/.vagrant.d/gems/cache/` (download cache only)
- `vagrant-libvirt` is ALWAYS uninstalled then reinstalled — NEVER skipped via cache-hit
- Cache keys include version-relevant inputs (lock file hash, molecule.yml hash)

**Anti-patterns:**
- `if: steps.cache.outputs.cache-hit != 'true'` on `vagrant plugin install` (native .so ABI mismatch between runners)
- Missing `id:` on cache step (`steps.box-cache.outputs.cache-hit` is undefined without it)
- `vagrant box add` without idempotence guard (re-downloads when restore-key partially matches)
- Caching `~/.vagrant.d/gems/` entirely (includes compiled .so files — ABI incompatible across runners)
- No `restore-keys` on box cache (full re-download on any molecule.yml change)

---

### CI-009: Scheduled Runs

**Category:** Maintenance
**Priority:** MUST
**Rationale:** Roles can break without any code change: upstream packages get renamed, mirrors go down, base images change, Vagrant boxes update. Scheduled weekly runs detect this drift before someone needs the role urgently. Without scheduled runs, rot accumulates silently.

**Implementation Pattern:**
```yaml
on:
  schedule:
    - cron: '0 4 * * 1'  # Every Monday at 04:00 UTC

jobs:
  detect:
    steps:
      - name: Detect roles
        id: detect
        run: |
          if [ "${{ github.event_name }}" = "schedule" ]; then
            # Test ALL roles on schedule
            ROLES=$(ls -d ansible/roles/*/molecule 2>/dev/null | \
              sed 's|ansible/roles/||;s|/molecule||' | \
              jq -R -s -c 'split("\n") | map(select(. != ""))')
          fi
          # ...

  # After all test jobs complete:
  notify-failure:
    name: Create issue on failure
    needs: [test-docker, test-vagrant]
    if: >-
      github.event_name == 'schedule' &&
      (needs.test-docker.result == 'failure' || needs.test-vagrant.result == 'failure')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const title = `CI scheduled run failed: ${new Date().toISOString().split('T')[0]}`;
            const body = [
              `## Scheduled CI Failure`,
              ``,
              `**Docker:** ${{ needs.test-docker.result }}`,
              `**Vagrant:** ${{ needs.test-vagrant.result }}`,
              ``,
              `[View workflow run](${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId})`,
              ``,
              `This issue was created automatically by scheduled CI.`
            ].join('\n');

            await github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title,
              body,
              labels: ['ci-failure', 'automated']
            });
```

**Verification Criteria:**
- Schedule runs weekly (Monday early morning UTC recommended)
- Scheduled runs test ALL roles, not just changed ones
- Scheduled failures create a GitHub Issue automatically with run link and job results
- Scheduled failures do NOT block unrelated PRs (separate status check context or conditional)
- Issue title includes date for easy dedup/tracking
- Issue has `ci-failure` label for filtering

**Anti-patterns:**
- No scheduled runs (rot accumulates for months)
- Scheduled runs that only test a subset of roles (gaps in coverage)
- Scheduled failure with no notification (nobody checks the Actions tab manually)
- Scheduled failure that blocks PR merges (unrelated PRs stuck on stale failure)
- Creating duplicate issues on every scheduled failure (no dedup by date/title)

---

### CI-010: CI Health Observability

**Category:** Observability
**Priority:** SHOULD
**Rationale:** CI is infrastructure. Like all infrastructure, it needs monitoring. Success rate drops, increasing run times, and flaky tests are signals that CI health is degrading. Without visibility, engineers lose trust in CI ("it's always flaky, I'll just retry") and quality gates become meaningless.

**Implementation Pattern:**
```yaml
# Badge in README — immediate status visibility
# README.md (at the top, after role header)
![CI](https://github.com/textyre/bootstrap/actions/workflows/molecule-test.yml/badge.svg)

# Artifact: test timing report
- name: Upload test timing
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: timing-${{ matrix.role }}-${{ github.run_id }}
    path: ansible/roles/${{ matrix.role }}/.molecule/**/profile_tasks.log
    retention-days: 30
```

```markdown
# Monitoring checklist (manual review, weekly)
- [ ] CI success rate > 95% over last 30 days
- [ ] Average Docker job time < 10 minutes
- [ ] Average Vagrant job time < 25 minutes
- [ ] No role with > 2 flaky failures in last 30 days
- [ ] Scheduled run issues resolved within 1 week
```

**Verification Criteria:**
- CI status badge present in repository root README
- `profile_tasks` callback enabled in all molecule scenarios (TEST-014) — timing data available
- Test artifacts (timing, logs) uploaded on failure with 30-day retention
- Flaky tests identified: same test fails intermittently across multiple runs without code changes
- Scheduled failure issues tracked and resolved within 1 week

**Anti-patterns:**
- No badge (nobody sees CI status without clicking into Actions tab)
- No artifact retention (failure logs lost after run completes)
- Flaky tests tolerated indefinitely ("just retry it")
- No timing tracking (test that takes 25 minutes today, 45 minutes next month — nobody notices)
- CI success rate drops below 80% with no action taken

---

## Post-Creation Checklist

Use this checklist when setting up or reviewing CI for a role.

### Platform

- [ ] CI-001: GitHub Actions workflow exists with push/PR/dispatch/schedule triggers

### Structure

- [ ] CI-002: Detect step identifies changed roles, dynamic matrix, `fail-fast: false`
- [ ] CI-003: Lint job separate from molecule, runs yamllint + ansible-lint, blocks molecule jobs

### Execution

- [ ] CI-004: Docker job with timeout, retry, color env vars, runs `molecule test`
- [ ] CI-005: Vagrant job with KVM setup, vagrant-libvirt always reinstall, box cache, timeout, retry

### Enforcement

- [ ] CI-006: Branch protection requires Lint + Docker + Vagrant pass; no `continue-on-error`; admins cannot bypass

### Reliability

- [ ] CI-007: `requirements-ci.txt` lock file exists, CI installs from it, Dependabot/Renovate configured
- [ ] CI-008: Pip cached, Vagrant boxes cached, gem download cached, vagrant-libvirt NEVER cached

### Maintenance

- [ ] CI-009: Weekly scheduled run tests all roles, failures create GitHub Issue automatically
- [ ] CI-010: Badge in README, test artifacts uploaded on failure, flaky tests tracked

---

Back to [[Testing Requirements|standards/testing-requirements]] | [[Role Requirements|standards/role-requirements]] | [[Home]]
