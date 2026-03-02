# Molecule Vagrant Workflow Optimization — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Improve `_molecule-vagrant.yml` across reliability (timeout, artifact upload, wget --fail),
performance (apt package cache, combined version step), and maintainability (pip requirements file
with `hashFiles`-based cache key).

**Architecture:** Two files change — a new `ansible/requirements-molecule-vagrant.txt` (extends
`requirements.txt` with vagrant-specific extras) and `_molecule-vagrant.yml` (inline changes only,
no new jobs or external actions beyond upload-artifact). Design doc:
`docs/plans/2026-03-01-molecule-vagrant-workflow-optimization-design.md`.

**Tech Stack:** GitHub Actions YAML, `actions/cache@v4`, `actions/upload-artifact@v4`, pip `-r` include syntax.

---

## Task 1: Create `ansible/requirements-molecule-vagrant.txt`

**Files:**
- Create: `ansible/requirements-molecule-vagrant.txt`

**Step 1: Create the file**

```
# Vagrant CI dependencies — extends requirements.txt with vagrant-specific extras.
# Install with: pip install -r ansible/requirements-molecule-vagrant.txt
-r requirements.txt
molecule-plugins[vagrant]==25.8.12
python-vagrant
```

**Step 2: Verify pip resolves it without conflicts**

```bash
cd /path/to/bootstrap
pip install --dry-run -r ansible/requirements-molecule-vagrant.txt 2>&1 | tail -20
```

Expected: resolves cleanly, no version conflicts. `molecule-plugins[docker]` and
`molecule-plugins[vagrant]` can coexist (they're the same package, different extras).

**Step 3: Commit**

```bash
git add ansible/requirements-molecule-vagrant.txt
git commit -m "feat(ci): add requirements-molecule-vagrant.txt for pip pinning"
```

---

## Task 2: Reliability — `timeout-minutes` + `wget --fail`

**Files:**
- Modify: `.github/workflows/_molecule-vagrant.yml`

**Step 1: Add `timeout-minutes: 60` to the job**

In `.github/workflows/_molecule-vagrant.yml`, find the `test:` job block (line ~22).
After `runs-on: ubuntu-latest`, add:

```yaml
    timeout-minutes: 60
```

Full context after change:
```yaml
jobs:
  test:
    name: "${{ inputs.role_name }} — ${{ inputs.platform }}"
    runs-on: ubuntu-latest
    timeout-minutes: 60

    concurrency:
```

**Step 2: Add `--fail --retry-connrefused --tries=3` to wget**

Find the "Install libvirt + vagrant" step (line ~41). Change:
```yaml
          wget -O- https://apt.releases.hashicorp.com/gpg | \
```
to:
```yaml
          wget --fail --retry-connrefused --tries=3 -O- https://apt.releases.hashicorp.com/gpg | \
```

**Step 3: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_molecule-vagrant.yml'))"
```

Expected: no output (clean parse).

**Step 4: Commit**

```bash
git add .github/workflows/_molecule-vagrant.yml
git commit -m "fix(ci): add job timeout and wget --fail to molecule-vagrant workflow"
```

---

## Task 3: Performance — apt package cache + combined version step

**Files:**
- Modify: `.github/workflows/_molecule-vagrant.yml`

**Step 1: Add apt cache step before "Install libvirt + vagrant"**

Insert a new step between "Enable KVM" (line ~34) and "Install libvirt + vagrant" (line ~41):

```yaml
      - name: Cache apt packages
        uses: actions/cache@v4
        with:
          path: /var/cache/apt/archives
          key: apt-vagrant-${{ runner.os }}-${{ hashFiles('.github/workflows/_molecule-vagrant.yml') }}
          restore-keys: apt-vagrant-${{ runner.os }}-
```

**Step 2: Combine the two version steps into one**

Remove these two steps (lines ~55-61):
```yaml
      - name: Get Vagrant version
        id: vagrant-ver
        run: echo "version=$(vagrant --version | cut -d' ' -f2)" >> $GITHUB_OUTPUT

      - name: Get libvirt version
        id: libvirt-ver
        run: echo "version=$(dpkg -s libvirt-dev | grep '^Version:' | cut -d' ' -f2)" >> $GITHUB_OUTPUT
```

Replace with a single combined step:
```yaml
      - name: Get tool versions
        id: versions
        run: |
          echo "vagrant=$(vagrant --version | cut -d' ' -f2)" >> $GITHUB_OUTPUT
          echo "libvirt=$(dpkg -s libvirt-dev | grep '^Version:' | cut -d' ' -f2)" >> $GITHUB_OUTPUT
```

**Step 3: Update the vagrant plugins cache key to use the new step id**

Find the "Cache vagrant plugins" step (line ~63). Change:
```yaml
          key: vagrant-gems-${{ runner.os }}-${{ steps.vagrant-ver.outputs.version }}-libvirt${{ steps.libvirt-ver.outputs.version }}
          restore-keys: |
            vagrant-gems-${{ runner.os }}-${{ steps.vagrant-ver.outputs.version }}-
            vagrant-gems-${{ runner.os }}-
```
to:
```yaml
          key: vagrant-gems-${{ runner.os }}-${{ steps.versions.outputs.vagrant }}-libvirt${{ steps.versions.outputs.libvirt }}
          restore-keys: |
            vagrant-gems-${{ runner.os }}-${{ steps.versions.outputs.vagrant }}-
            vagrant-gems-${{ runner.os }}-
```

**Step 4: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_molecule-vagrant.yml'))"
```

Expected: clean.

**Step 5: Commit**

```bash
git add .github/workflows/_molecule-vagrant.yml
git commit -m "perf(ci): add apt cache and combine version steps in molecule-vagrant"
```

---

## Task 4: Maintainability — pip requirements file + cache key

**Files:**
- Modify: `.github/workflows/_molecule-vagrant.yml`

**Step 1: Update the pip cache key**

Find the "Cache pip packages" step (line ~116). Change:
```yaml
          key: pip-vagrant-${{ runner.os }}-ansible-core-2.20.1-molecule-25.12.0
```
to:
```yaml
          key: pip-vagrant-${{ runner.os }}-${{ hashFiles('ansible/requirements.txt', 'ansible/requirements-molecule-vagrant.txt') }}
```

**Step 2: Update the pip install step**

Find the "Install molecule + dependencies" step (line ~123). Replace the entire `run:` block:
```yaml
        run: |
          pip install \
            "ansible-core==2.20.1" \
            "molecule==25.12.0" \
            "molecule-plugins[vagrant]==25.8.12" \
            "jmespath" "rich"
          python -c "import vagrant; print('python-vagrant OK:', vagrant.__file__)"
```
with:
```yaml
        run: pip install -r ansible/requirements-molecule-vagrant.txt
```

**Step 3: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_molecule-vagrant.yml'))"
```

Expected: clean.

**Step 4: Commit**

```bash
git add .github/workflows/_molecule-vagrant.yml
git commit -m "refactor(ci): use requirements-molecule-vagrant.txt for pip install and cache key"
```

---

## Task 5: Reliability — artifact upload on failure

**Files:**
- Modify: `.github/workflows/_molecule-vagrant.yml`

**Step 1: Add artifact upload step at the end of the steps list**

After the "Run Molecule" step (line ~142), add:

```yaml
      - name: Upload logs on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: molecule-logs-${{ inputs.role_name }}-${{ inputs.platform }}
          path: |
            ansible/roles/${{ inputs.role_name }}/.molecule/
            ~/.vagrant.d/logs/
          retention-days: 7
```

**Step 2: Validate YAML syntax**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_molecule-vagrant.yml'))"
```

Expected: clean.

**Step 3: Verify final file structure matches intended step order**

Read the file and confirm this step order:
1. Checkout
2. Enable KVM
3. Cache apt packages ← NEW
4. Install libvirt + vagrant (wget --fail) ← MODIFIED
5. Get tool versions (combined) ← MODIFIED (was 2 steps)
6. Cache vagrant plugins (uses `steps.versions.*`) ← MODIFIED
7. Install vagrant-libvirt plugin
8. Resolve box version
9. Cache Vagrant box
10. Add Vagrant box (if cache miss)
11. Set up Python 3.12
12. Cache pip packages (hashFiles key) ← MODIFIED
13. Install molecule + deps (`-r requirements file`) ← MODIFIED
14. Cache Ansible collections
15. Install Ansible Galaxy collections
16. Run Molecule
17. Upload logs on failure ← NEW

**Step 4: Commit**

```bash
git add .github/workflows/_molecule-vagrant.yml
git commit -m "feat(ci): upload molecule logs as artifact on failure"
```

---

## Task 6: Update design doc and verify

**Step 1: Check that `molecule-vagrant.yml` (the caller) still works**

Read `.github/workflows/molecule-vagrant.yml` — it only passes `role_name`, `platform`, `scenario`
inputs. No changes needed there, all inputs are unchanged.

**Step 2: Check `molecule.yml` (the main dispatch)**

Read `.github/workflows/molecule.yml` — it calls `_molecule-vagrant.yml` with the same three inputs.
No changes needed.

**Step 3: Final YAML lint pass on all three files**

```bash
python3 -c "
import yaml
for f in [
    '.github/workflows/_molecule-vagrant.yml',
    '.github/workflows/molecule-vagrant.yml',
    '.github/workflows/molecule.yml',
]:
    yaml.safe_load(open(f))
    print(f'OK: {f}')
"
```

Expected:
```
OK: .github/workflows/_molecule-vagrant.yml
OK: .github/workflows/molecule-vagrant.yml
OK: .github/workflows/molecule.yml
```

**Step 4: Update design doc to reflect final requirements structure choice**

In `docs/plans/2026-03-01-molecule-vagrant-workflow-optimization-design.md`, update the
`requirements-molecule-vagrant.txt` section to show `-r requirements.txt` include pattern
(the design was written before the user clarified the requirements structure preference).

```bash
# Edit the design doc to correct the requirements file content shown
```

Add after the existing code block:
```markdown
> **Note:** Final structure uses `-r requirements.txt` base include so that
> shared dep changes (ansible-core, molecule version bumps) automatically
> invalidate the vagrant pip cache.
```

**Step 5: Commit**

```bash
git add docs/plans/2026-03-01-molecule-vagrant-workflow-optimization-design.md
git commit -m "docs(plans): update molecule-vagrant optimization design — requirements include pattern"
```
