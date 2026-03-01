# Design: _molecule-vagrant.yml Workflow Optimization

**Date:** 2026-03-01
**Branch:** fix/hostctl-molecule-overhaul
**Scope:** `.github/workflows/_molecule-vagrant.yml` + new `ansible/requirements-molecule-vagrant.txt`

## Problem

The reusable Molecule Vagrant workflow has three categories of issues:

1. **Reliability**: no job timeout (hung VMs consume runner-hours indefinitely), no artifact
   upload on failure (logs lost), `wget` without `--fail` silently ignores HTTP errors.
2. **Performance**: `apt-get install libvirt + vagrant` downloads packages every run (~2-3 min),
   no apt package cache.
3. **Maintainability**: pip package versions are hardcoded inline in the workflow step AND
   duplicated in the cache key string — updating a version requires two edits and the cache key
   won't auto-invalidate.

## Design

### Files Changed

| File | Change |
|------|--------|
| `.github/workflows/_molecule-vagrant.yml` | Main workflow changes (see below) |
| `ansible/requirements-molecule-vagrant.txt` | **New** — pip requirements file |

---

### 1. Reliability

**Job timeout** — add at job level:
```yaml
timeout-minutes: 60
```
Prevents a hung VM from consuming runner-hours until the 6-hour GitHub Actions hard limit.

**Upload artifacts on failure** — add as final step:
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

**wget `--fail` + retry** — HashiCorp GPG download currently has no HTTP error checking:
```yaml
# Before
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor ...

# After
wget --fail --retry-connrefused --tries=3 -O- https://apt.releases.hashicorp.com/gpg | \
  sudo gpg --dearmor ...
```

---

### 2. Performance

**Combine version detection steps** — currently two separate steps for vagrant and libvirt versions.
Combine into a single step with two outputs to reduce runner overhead:
```yaml
- name: Get tool versions
  id: versions
  run: |
    echo "vagrant=$(vagrant --version | cut -d' ' -f2)" >> $GITHUB_OUTPUT
    echo "libvirt=$(dpkg -s libvirt-dev | grep '^Version:' | cut -d' ' -f2)" >> $GITHUB_OUTPUT
```
Cache key references change from `steps.vagrant-ver.outputs.version` → `steps.versions.outputs.vagrant`
and from `steps.libvirt-ver.outputs.version` → `steps.versions.outputs.libvirt`.

**Cache apt packages** — add a cache step before `apt-get install` to avoid re-downloading .deb files:
```yaml
- name: Cache apt packages
  uses: actions/cache@v4
  with:
    path: /var/cache/apt/archives
    key: apt-vagrant-${{ runner.os }}-${{ hashFiles('.github/workflows/_molecule-vagrant.yml') }}
    restore-keys: apt-vagrant-${{ runner.os }}-
```
Place this step immediately before "Install libvirt + vagrant". When cache hits, `apt-get install`
finds .deb files already present in the archive directory and skips downloading them — saving ~1.5-2 min.

The `apt-get update -qq` is still required (to update package metadata), but package download is skipped.

---

### 3. Maintainability

**Extract pip requirements to a file** — create `ansible/requirements-molecule-vagrant.txt`:
```
# Vagrant CI dependencies — extends requirements.txt with vagrant-specific extras.
-r requirements.txt
molecule-plugins[vagrant]==25.8.12
python-vagrant
```

> **Note:** Final structure uses `-r requirements.txt` base include so that shared dep changes
> (ansible-core, molecule version bumps) automatically invalidate the vagrant pip cache.
> `python-vagrant` was previously installed implicitly via `molecule-plugins`; it is now declared
> explicitly.

**Update pip cache step** to use `hashFiles`:
```yaml
- name: Cache pip packages
  uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: pip-vagrant-${{ runner.os }}-${{ hashFiles('ansible/requirements-molecule-vagrant.txt') }}
    restore-keys: pip-vagrant-${{ runner.os }}-
```

**Update pip install step**:
```yaml
- name: Install molecule + dependencies
  run: pip install -r ansible/requirements-molecule-vagrant.txt
```
The verification line `python -c "import vagrant; ..."` is removed — python-vagrant is now
declared explicitly in requirements, so import failure would already surface as pip install failure.

---

## Step Order After Changes

```
Checkout
Enable KVM
Install libvirt + vagrant   ← wget --fail added
Get tool versions           ← combined step (was 2 steps)
Cache vagrant plugins       ← uses steps.versions.outputs.*
Install vagrant-libvirt plugin
Cache apt packages          ← NEW, before apt install
Resolve box version
Cache Vagrant box
Add Vagrant box (if cache miss)
Set up Python 3.12
Cache pip packages          ← key = hashFiles(requirements-molecule-vagrant.txt)
Install molecule + deps     ← pip install -r requirements-molecule-vagrant.txt
Cache Ansible collections
Install Ansible Galaxy collections
Run Molecule
Upload logs on failure      ← NEW (if: failure())
```

Wait — the apt cache step must go BEFORE the apt-get install step. Step order corrected:

```
Checkout
Enable KVM
Cache apt packages          ← NEW (before install)
Install libvirt + vagrant   ← wget --fail added, uses /var/cache/apt from cache
Get tool versions           ← combined (was 2 steps)
Cache vagrant plugins       ← uses steps.versions.outputs.*
Install vagrant-libvirt plugin
Resolve box version
Cache Vagrant box
Add Vagrant box (if cache miss)
Set up Python 3.12
Cache pip packages          ← hashFiles key
Install molecule + deps     ← -r requirements file
Cache Ansible collections
Install Ansible Galaxy collections
Run Molecule
Upload logs on failure      ← NEW (if: failure())
```

## Non-Goals

- Custom runner image — not feasible for KVM-based tests on GitHub-hosted runners
  (KVM requires bare-metal, container-based runners can't access /dev/kvm)
- Vagrant box checksum verification — box URLs point to GitHub Releases, integrity is provided
  by HTTPS + GitHub's own infrastructure
- Parallelizing workflow steps — Actions doesn't support step-level parallelism

## Testing

After implementation, verify:
1. Cache-miss run completes successfully end-to-end
2. Cache-hit run shows apt packages restored from cache (check apt-get install output)
3. Intentional failure (bad converge.yml) produces artifact with logs
4. Hung test is cancelled at 60 min mark (manual verification via timeout)
