# Image Repo Housecleaning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean up `textyre/arch-images` and `textyre/ubuntu-images` — remove redundant `molecule` variants, unify naming, add OCI labels, CalVer tags, supply-chain security (Trivy/Cosign/Renovate), and document a standard in bootstrap.

**Architecture:** Three repos are touched in order: (1) bootstrap gets the standard doc; (2) arch-images and ubuntu-images get workflow + Dockerfile + contract + README overhauls; (3) bootstrap gets downstream reference updates. All changes are self-contained per repo and can be PRed independently.

**Tech Stack:** GitHub Actions, Docker Buildx, `docker/metadata-action@v5`, `docker/build-push-action@v6`, Trivy, Cosign (keyless), Renovate, Packer (HCL2), Vagrant

---

## Context You Need

**Repos:**
- `textyre/arch-images` — builds `ghcr.io/textyre/arch-base` Docker image + `arch-base-*.box` Vagrant box
- `textyre/ubuntu-images` — builds `ghcr.io/textyre/ubuntu-noble` Docker image (→ rename to `ubuntu-base`) + `ubuntu-noble-*.box` (→ rename to `ubuntu-base-*.box`)
- `textyre/bootstrap` — consumes both; has wiki/standards/ for infrastructure standards

**Current problems being fixed:**
- `ubuntu-noble` uses a codename, should be `ubuntu-base` (purpose-based, like `arch-base`)
- Both repos also publish `arch-molecule` / `ubuntu-molecule` Docker images and Vagrant boxes — these are redundant and being removed
- No OCI labels, no CalVer tags, no security scanning, no supply-chain controls

**GHCR package cleanup** (manual, one-time): After removing molecule image publishing from workflows, delete existing GHCR packages manually at `github.com/orgs/textyre/packages` or via API.

---

## Phase 1 — bootstrap: Write the Standard

### Task 1: Create image-repo-requirements.md

**Files:**
- Create: `wiki/standards/image-repo-requirements.md`

**Step 1: Create the standard document**

```markdown
# Image Repo Requirements

Every image repo (`arch-images`, `ubuntu-images`, etc.) must satisfy all requirements below
before images are considered production-ready for use in CI pipelines.

---

## REQ-01: Naming

- Repo name: `{os}-images` (e.g., `arch-images`, `ubuntu-images`)
- Docker image: `ghcr.io/textyre/{os}-base` — no codenames, no `molecule` variants
- Vagrant box: `{os}-base-YYYYMMDD.box` and `{os}-base-latest.box`
- Codenames (e.g., `noble`, `bookworm`) MUST NOT appear in image or box names

## REQ-02: Single Artifact Per OS

Each repo publishes exactly one Docker image and one Vagrant box variant.
No `molecule`, `ci`, `testing`, or other purpose-variants.
The base image must be sufficient for all Ansible/Molecule testing.

## REQ-03: GHCR Tags

Every Docker image push MUST produce all four tag types:

| Tag | Example | Purpose |
|-----|---------|---------|
| `:latest` | `arch-base:latest` | Floating, local convenience |
| `:YYYY.MM.DD` | `arch-base:2026.02.27` | CalVer, pinnable CI use |
| OS version | `ubuntu-base:24.04` / `arch-base:rolling` | Pinnable by OS version |
| `:sha-{short}` | `arch-base:sha-abc1234` | Immutable, forensics/rollback |

Tags are generated via `docker/metadata-action@v5` — not hardcoded.

## REQ-04: OCI Labels

All labels injected at build time (never hardcoded in Dockerfile):

Auto-generated (8) via `docker/metadata-action@v5`:
`title`, `description`, `url`, `source`, `version`, `created`, `revision`, `licenses`

Manually added (2):
- `org.opencontainers.image.vendor=textyre`
- `org.opencontainers.image.description=<one sentence purpose>`

OCI Index annotations also required:
`annotations: ${{ steps.meta.outputs.annotations }}` in `build-push-action`.

## REQ-05: No LABEL in Dockerfile

Dockerfiles MUST NOT contain `LABEL` instructions.
All labels are injected at build time via the workflow.

## REQ-06: Supply-Chain Security

All four controls are mandatory:

| Control | Implementation |
|---------|---------------|
| Vulnerability gate | Trivy scan before push; exit-code 1 on CRITICAL/HIGH (ignore-unfixed) |
| Keyless signing | Cosign OIDC keyless signing after push |
| SLSA L1 provenance | `provenance: true` in `build-push-action` |
| Base image digest pinning | `renovate.json` with `docker:pinDigests` preset |

SBOM (CycloneDX) generated via Trivy and attached to GitHub Release.

## REQ-07: Contract Verification

Every image MUST have `contracts/docker.sh` that verifies:
- Every binary installed by the Dockerfile (`test -x` or `command -v`)
- Every data file required at runtime (`test -f`)
- The script runs inside the image via `docker run --rm <image> bash contracts/docker.sh`
- Script MUST `set -euo pipefail` and exit non-zero on any failure

Vagrant boxes MUST have `contracts/vagrant.sh` with equivalent checks.

Contracts MUST be run in CI after every build, before the release step.

## REQ-08: CI Workflow Structure

```
build.yml
├── changes (dorny/paths-filter@v3)
├── build-docker (needs: changes)
│   ├── Trivy scan (before push)
│   ├── docker/metadata-action + build-push-action
│   └── Contract verify
├── build-vagrant (needs: changes, independent of build-docker)
│   ├── packer build
│   └── Contract verify
└── attest (needs: build-docker)
    └── Cosign keyless sign
```

No action version MAY use a floating branch reference (e.g., `@main`, `@master`).
`hashicorp/setup-packer` MUST be pinned to a SHA.

## REQ-09: README Structure

Every repo MUST have a README.md with these sections in order:

1. **Purpose** — one sentence
2. **What this image contains** — table: package, version, why
3. **Guarantees** — bullet list matching `contracts/docker.sh`
4. **Contract tests** — link to `contracts/docker.sh` and `contracts/vagrant.sh`
5. **Usage** — how to use in `molecule.yml` and `Vagrantfile`
6. **Not suitable for** — explicit non-goals (production use, etc.)
7. **Update schedule** — when and how images are rebuilt
8. **Tags** — table of available tags and their semantics

## REQ-10: Renovate

`renovate.json` MUST exist at repo root:

```json
{
  "extends": [
    "config:best-practices",
    "docker:pinDigests",
    ":automergeDigest"
  ]
}
```

---

## Post-Creation Checklist

Before marking an image repo as compliant, verify all 10 requirements:

- [ ] REQ-01: Naming uses `{os}-base`, no codenames
- [ ] REQ-02: Single Docker image + single Vagrant box per repo
- [ ] REQ-03: All four GHCR tag types present after push
- [ ] REQ-04: OCI labels present on image (`docker inspect <image>`)
- [ ] REQ-05: No `LABEL` in Dockerfile
- [ ] REQ-06: Trivy + Cosign + SLSA L1 + Renovate all active
- [ ] REQ-07: `contracts/docker.sh` covers every installed package
- [ ] REQ-08: Workflow uses `changes` → `build-docker` → `build-vagrant` → `attest`
- [ ] REQ-09: README has all 8 required sections
- [ ] REQ-10: `renovate.json` present with `docker:pinDigests`
```

**Step 2: Verify the file looks correct**

Open `wiki/standards/image-repo-requirements.md` and confirm all 10 REQ sections render cleanly.

**Step 3: Commit**

```bash
git add wiki/standards/image-repo-requirements.md
git commit -m "docs(standards): add image-repo-requirements (10 REQs)"
```

---

## Phase 2 — arch-images: Cleanup and Harden

All steps below are in the `textyre/arch-images` repo.

### Task 2: Remove molecule artifacts from Packer and workflow

**Background:** `arch-molecule-*.box` appears in GitHub Releases. This means either
(a) there are two Packer templates, or (b) the workflow builds a second artifact.
Locate and remove whatever produces the `arch-molecule` box.

**Files:**
- Modify: `packer/*.pkr.hcl` (find any molecule-specific template)
- Modify: `.github/workflows/build.yml`

**Step 1: Find the molecule Packer config**

```bash
grep -r "arch-molecule\|molecule" packer/ .github/
```

**Step 2: Delete or comment out** any `build {}` block or workflow step that produces
`arch-molecule-*.box`. Keep only the `arch-base` build.

**Step 3: In `build.yml`, remove** any step that uploads `arch-molecule-*.box` to GitHub Releases.

**Step 4: Commit**

```bash
git add packer/ .github/workflows/build.yml
git commit -m "chore: remove arch-molecule variant (box + packer config)"
```

---

### Task 3: Clean up Dockerfile

**Files:**
- Modify: `docker/Dockerfile`

**Step 1: Read the current Dockerfile**

```bash
cat docker/Dockerfile
```

**Step 2: Remove any `LABEL` instructions** (OCI labels will be injected at build time).

The Dockerfile MUST NOT contain `LABEL` lines after this step.

**Step 3: Verify Dockerfile has no LABEL lines**

```bash
grep -n "LABEL" docker/Dockerfile
```

Expected: no output.

**Step 4: Commit**

```bash
git add docker/Dockerfile
git commit -m "chore(dockerfile): remove hardcoded LABEL instructions"
```

---

### Task 4: Add `renovate.json`

**Files:**
- Create: `renovate.json`

**Step 1: Create the file**

```json
{
  "extends": [
    "config:best-practices",
    "docker:pinDigests",
    ":automergeDigest"
  ]
}
```

**Step 2: Commit**

```bash
git add renovate.json
git commit -m "chore: add renovate config for Docker digest pinning"
```

---

### Task 5: Rewrite `contracts/docker.sh`

**Background:** The contract script verifies the image satisfies its promise.
Every package in the Dockerfile must be checked.

Current Dockerfile installs: `python`, `sudo`, `glibc`, `base-devel`, `git`
(which includes `gcc`, `make`, etc.) and creates user `aur_builder`.

**Files:**
- Modify: `contracts/docker.sh`

**Step 1: Read current script**

```bash
cat contracts/docker.sh
```

**Step 2: Rewrite to verify ALL installed packages**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== arch-base Docker image contract ==="

# Core tools
echo -n "systemd:          " && test -x /usr/lib/systemd/systemd && echo "OK"
echo -n "python:           " && python --version
echo -n "sudo:             " && sudo --version | head -1
echo -n "gcc (base-devel): " && gcc --version | head -1
echo -n "make (base-devel):" && make --version | head -1
echo -n "git:              " && git --version

# AUR builder user
echo -n "aur_builder user: " && id aur_builder
echo -n "aur_builder sudo: " && test -f /etc/sudoers.d/aur_builder && echo "OK"

# Locale data (required for en_US/ru_RU locale generation in bootstrap roles)
echo -n "locale SUPPORTED: " && test -f /usr/share/i18n/SUPPORTED && echo "OK"
echo -n "locale en_US:     " && test -f /usr/share/i18n/locales/en_US && echo "OK"
echo -n "locale ru_RU:     " && test -f /usr/share/i18n/locales/ru_RU && echo "OK"
echo -n "locale-gen:       " && command -v locale-gen

# Systemd minimal (required for Molecule systemd driver)
echo -n "systemd-tmpfiles: " && test -f /usr/lib/systemd/system/systemd-tmpfiles-setup.service && echo "OK"

echo "=== arch-base contract: PASS ==="
```

**Step 3: Test locally (if Docker available)**

```bash
docker build -t arch-base-test docker/
docker run --rm arch-base-test bash contracts/docker.sh
```

Expected: all lines print "OK" or version string, final line: `=== arch-base contract: PASS ===`

**Step 4: Commit**

```bash
git add contracts/docker.sh
git commit -m "fix(contracts): verify all installed packages in docker.sh"
```

---

### Task 6: Rewrite `.github/workflows/build.yml`

This is the main task. The rewrite adds: `docker/metadata-action`, CalVer tags, Trivy,
Cosign keyless signing, SLSA L1 provenance, `dorny/paths-filter`, pinned packer action.

**Files:**
- Modify: `.github/workflows/build.yml`

**Step 1: Read the current workflow**

```bash
cat .github/workflows/build.yml
```

**Step 2: Find the pinned SHA for `hashicorp/setup-packer`**

```bash
# Check latest release SHA at github.com/hashicorp/setup-packer/releases
# Then pin to: hashicorp/setup-packer@<sha>  # vX.Y.Z
```

Use `curl -s https://api.github.com/repos/hashicorp/setup-packer/releases/latest | jq -r '.tag_name'`
to find latest version, then look up its SHA.

**Step 3: Write the new workflow**

```yaml
---
name: Build arch-base

on:
  push:
    branches: [main, master]
    paths:
      - 'docker/**'
      - 'packer/**'
      - 'contracts/**'
      - '.github/workflows/build.yml'
  schedule:
    - cron: '0 2 * * 1'   # Weekly Monday 02:00 UTC
  workflow_dispatch:
    inputs:
      artifact:
        description: 'Which artifact to build'
        required: false
        default: 'all'
        type: choice
        options: [all, docker, vagrant]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository_owner }}/arch-base

jobs:
  changes:
    runs-on: ubuntu-latest
    outputs:
      docker: ${{ steps.filter.outputs.docker }}
      vagrant: ${{ steps.filter.outputs.vagrant }}
    steps:
      - uses: actions/checkout@v4
      - uses: dorny/paths-filter@v3
        id: filter
        with:
          filters: |
            docker:
              - 'docker/**'
              - 'contracts/docker.sh'
            vagrant:
              - 'packer/**'
              - 'contracts/vagrant.sh'

  build-docker:
    name: Build and push arch-base Docker image
    needs: changes
    if: |
      github.event_name == 'schedule' ||
      github.event_name == 'workflow_dispatch' && (inputs.artifact == 'all' || inputs.artifact == 'docker') ||
      needs.changes.outputs.docker == 'true'
    runs-on: ubuntu-latest
    permissions:
      packages: write
      id-token: write   # required for keyless Cosign signing
      attestations: write  # required for SLSA provenance

    steps:
      - uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Extract metadata (tags + labels)
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=raw,value=latest
            type=raw,value={{date 'YYYY.MM.DD'}}
            type=raw,value=rolling
            type=sha,prefix=sha-,format=short
          labels: |
            org.opencontainers.image.vendor=textyre
            org.opencontainers.image.description=Arch Linux base image with systemd for Ansible/Molecule testing

      - name: Build image (local, for scanning)
        uses: docker/build-push-action@v6
        with:
          context: docker/
          load: true
          tags: arch-base:scan
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Scan with Trivy (gate on CRITICAL/HIGH)
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: arch-base:scan
          severity: CRITICAL,HIGH
          exit-code: '1'
          ignore-unfixed: true

      - name: Verify image contract
        run: docker run --rm arch-base:scan bash contracts/docker.sh

      - name: Build and push (with provenance + SBOM)
        id: push
        uses: docker/build-push-action@v6
        with:
          context: docker/
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          annotations: ${{ steps.meta.outputs.annotations }}
          cache-from: type=gha
          provenance: true
          sbom: true

      - name: Generate CycloneDX SBOM for release attachment
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          format: cyclonedx
          output: sbom.cyclonedx.json

      - name: Upload SBOM as artifact
        uses: actions/upload-artifact@v4
        with:
          name: sbom-docker
          path: sbom.cyclonedx.json

  attest:
    name: Sign image with Cosign (keyless)
    needs: build-docker
    runs-on: ubuntu-latest
    permissions:
      packages: write
      id-token: write

    steps:
      - name: Install Cosign
        uses: sigstore/cosign-installer@v3

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Sign image
        env:
          COSIGN_EXPERIMENTAL: "1"
        run: |
          cosign sign --yes \
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest

  build-vagrant:
    name: Build arch-base Vagrant box
    needs: changes
    if: |
      github.event_name == 'schedule' ||
      github.event_name == 'workflow_dispatch' && (inputs.artifact == 'all' || inputs.artifact == 'vagrant') ||
      needs.changes.outputs.vagrant == 'true'
    runs-on: ubuntu-latest
    permissions:
      contents: write

    steps:
      - uses: actions/checkout@v4

      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' | \
            sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Install libvirt + vagrant
        run: |
          wget -O- https://apt.releases.hashicorp.com/gpg | \
            sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
          echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
            https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
            sudo tee /etc/apt/sources.list.d/hashicorp.list
          sudo apt-get update -qq
          sudo apt-get install -y libvirt-daemon-system libvirt-dev qemu-kvm \
            vagrant ruby-dev build-essential pkg-config
          sudo systemctl start libvirtd
          sudo chmod a+rw /var/run/libvirt/libvirt-sock
          vagrant plugin install vagrant-libvirt

      - name: Set up Packer
        uses: hashicorp/setup-packer@<PIN-TO-SHA>   # TODO: replace with SHA of latest release

      - name: Packer init
        run: packer init packer/archlinux.pkr.hcl

      - name: Packer build (arch-base only)
        timeout-minutes: 60
        run: packer build packer/archlinux.pkr.hcl

      - name: Verify Vagrant contract
        run: bash contracts/vagrant.sh

      - name: Compute version
        id: version
        run: echo "date=$(date +%Y%m%d)" >> "$GITHUB_OUTPUT"

      - name: Publish to GitHub Releases
        uses: softprops/action-gh-release@v2
        with:
          tag_name: boxes
          name: Vagrant Boxes
          files: |
            arch-base-${{ steps.version.outputs.date }}.box
            arch-base-latest.box
          body: "Built ${{ steps.version.outputs.date }}"
```

**Step 4: Replace `<PIN-TO-SHA>` with the actual SHA** from step 2.

**Step 5: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "feat: overhaul workflow — metadata-action, Trivy, Cosign, CalVer tags, paths-filter"
```

---

### Task 7: Write arch-images README.md

**Files:**
- Modify: `README.md`

**Step 1: Replace the README entirely**

```markdown
# arch-images

Arch Linux base image with systemd for Ansible/Molecule testing.

## What this image contains

| Package | Version | Why |
|---------|---------|-----|
| systemd | latest (rolling) | Molecule systemd driver + service testing |
| python | latest (rolling) | Ansible connection + modules |
| sudo | latest (rolling) | Privilege escalation in test playbooks |
| base-devel (gcc, make, ...) | latest (rolling) | AUR build toolchain |
| git | latest (rolling) | AUR cloning |
| glibc (with locale data) | latest (rolling) | Locale generation roles (en_US, ru_RU) |

Non-root user `aur_builder` with passwordless `pacman` sudo is pre-created.

## Guarantees

Every image push is contract-tested. The following are always true:

- `/usr/lib/systemd/systemd` is executable
- `python`, `sudo`, `gcc`, `make`, `git`, `locale-gen` are on PATH
- `aur_builder` user exists with `/etc/sudoers.d/aur_builder`
- `/usr/share/i18n/locales/en_US` and `ru_RU` are present
- `/usr/share/i18n/SUPPORTED` exists

See [`contracts/docker.sh`](contracts/docker.sh) for the machine-readable contract.

## Usage

### In molecule.yml (Docker driver)

```yaml
platforms:
  - name: arch-instance
    image: ghcr.io/textyre/arch-base:rolling
    command: /usr/lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    privileged: true
    pre_build_image: true
```

### As a Vagrant box

```
# Vagrantfile
config.vm.box = "arch-base"
config.vm.box_url = "https://github.com/textyre/arch-images/releases/download/boxes/arch-base-latest.box"
```

### In molecule.yml (Vagrant driver)

```yaml
platforms:
  - name: arch-vm
    box: arch-base
    box_url: https://github.com/textyre/arch-images/releases/download/boxes/arch-base-latest.box
```

## Not suitable for

- Production deployments of any kind
- Environments without Docker privileged mode
- Images where a minimal footprint is required (this includes base-devel, ~1 GB)

## Update schedule

Rebuilt every Monday at 02:00 UTC from the latest `archlinux:base` upstream.
Rolling release — the image always reflects the current Arch package state.

## Image tags

| Tag | Example | Use |
|-----|---------|-----|
| `:latest` | `arch-base:latest` | Local development |
| `:YYYY.MM.DD` | `arch-base:2026.02.27` | Pin to a specific weekly build |
| `:rolling` | `arch-base:rolling` | Semantically "latest Arch rolling" |
| `:sha-{short}` | `arch-base:sha-abc1234` | Immutable pin for rollback |
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README with full structure (contents, guarantees, usage, tags)"
```

---

### Task 8: Delete arch-molecule from GHCR (manual)

**This step requires manual action in the GitHub UI or via API.**

**Step 1: Go to** `https://github.com/orgs/textyre/packages?repo_name=arch-images`

**Step 2: Find** the `arch-molecule` package. Click into it.

**Step 3: Delete** all versions of `arch-molecule`. GitHub will ask for confirmation.

**Step 4: Delete** the package itself once all versions are removed.

**Step 5: Verify** `ghcr.io/textyre/arch-molecule` no longer resolves:

```bash
docker pull ghcr.io/textyre/arch-molecule:latest
# Expected: error - manifest unknown
```

---

## Phase 3 — ubuntu-images: Cleanup, Rename, Harden

All steps below are in the `textyre/ubuntu-images` repo.
`ubuntu-noble` → `ubuntu-base` is a breaking rename. Bootstrap refs are updated in Phase 4.

### Task 9: Remove molecule artifacts from Packer and workflow

Same pattern as Task 2 but for ubuntu-images.

**Step 1: Find molecule Packer configs**

```bash
grep -r "ubuntu-molecule\|molecule" packer/ .github/
```

**Step 2: Delete** any build block or workflow step producing `ubuntu-molecule-*.box`.

**Step 3: Commit**

```bash
git add packer/ .github/workflows/build.yml
git commit -m "chore: remove ubuntu-molecule variant (box + packer config)"
```

---

### Task 10: Clean up Dockerfile

Same as Task 3. Remove any `LABEL` instructions.

```bash
grep -n "LABEL" docker/Dockerfile   # must return nothing after edit
git add docker/Dockerfile
git commit -m "chore(dockerfile): remove hardcoded LABEL instructions"
```

---

### Task 11: Add `renovate.json`

Same as Task 4. Identical content.

```bash
git add renovate.json
git commit -m "chore: add renovate config for Docker digest pinning"
```

---

### Task 12: Expand `contracts/docker.sh` to full parity

**Background:** Current ubuntu contract checks only 3 items (systemd, python3, sudo).
Dockerfile also installs: `systemd-sysv`, `dbus`, `udev`, `kmod`, `python3-apt`.

**Files:**
- Modify: `contracts/docker.sh`

**Step 1: Read current script and Dockerfile**

```bash
cat contracts/docker.sh
cat docker/Dockerfile
```

**Step 2: Rewrite to verify all installed packages**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== ubuntu-base Docker image contract ==="

# Core binaries
echo -n "systemd:          " && test -x /lib/systemd/systemd && echo "OK"
echo -n "python3:          " && python3 --version
echo -n "sudo:             " && sudo --version | head -1

# Explicitly installed packages (per Dockerfile)
echo -n "dbus:             " && command -v dbus-daemon && echo "OK"
echo -n "udev:             " && command -v udevadm && echo "OK"
echo -n "kmod:             " && command -v kmod && echo "OK"
echo -n "python3-apt:      " && python3 -c "import apt; print('OK')"

# Systemd sysv compatibility
echo -n "init (sysv):      " && test -f /sbin/init && echo "OK"

# Systemd minimal (required for Molecule systemd driver)
echo -n "systemd-tmpfiles: " && test -f /lib/systemd/system/systemd-tmpfiles-setup.service && echo "OK"

echo "=== ubuntu-base contract: PASS ==="
```

**Step 3: Test locally (if Docker available)**

```bash
docker build -t ubuntu-base-test docker/
docker run --rm ubuntu-base-test bash contracts/docker.sh
```

**Step 4: Commit**

```bash
git add contracts/docker.sh
git commit -m "fix(contracts): expand ubuntu contract to verify all installed packages"
```

---

### Task 13: Rewrite `.github/workflows/build.yml`

Same structure as Task 6 but for ubuntu. Key differences:
- `IMAGE_NAME: ${{ github.repository_owner }}/ubuntu-base` (not `ubuntu-noble`)
- Tags include `type=raw,value=24.04` instead of `rolling`
- `description=Ubuntu 24.04 base image with systemd for Ansible/Molecule testing`
- Packer template is `packer/ubuntu.pkr.hcl`
- Box files are named `ubuntu-base-*.box` (not `ubuntu-noble-*.box`)

**Files:**
- Modify: `.github/workflows/build.yml`

**Step 1: Copy the arch workflow from Task 6 and apply ubuntu-specific substitutions:**

Replace every occurrence of:
- `arch-base` → `ubuntu-base`
- `archlinux.pkr.hcl` → `ubuntu.pkr.hcl`
- `rolling` → `24.04`
- `/usr/lib/systemd/systemd` → `/lib/systemd/systemd`
- `arch-base:scan` → `ubuntu-base:scan`
- Arch Linux description → Ubuntu description

Also update the Packer template file name and box output name in the packer config
(check `packer/ubuntu.pkr.hcl` for the output box filename variable).

**Step 2: Verify the workflow file references `ubuntu-base` consistently**

```bash
grep -n "ubuntu-noble" .github/workflows/build.yml
# Expected: no output
```

**Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "feat: overhaul workflow — rename ubuntu-noble→ubuntu-base, add metadata-action/Trivy/Cosign"
```

---

### Task 14: Update Packer template for ubuntu-base rename

**Background:** The Packer template may hardcode the box output filename as `ubuntu-noble`.

**Files:**
- Modify: `packer/ubuntu.pkr.hcl`

**Step 1: Search for hardcoded noble references**

```bash
grep -n "ubuntu-noble\|noble" packer/ubuntu.pkr.hcl
```

**Step 2: Replace** `ubuntu-noble` with `ubuntu-base` in the output box filename variable.

**Step 3: Commit**

```bash
git add packer/ubuntu.pkr.hcl
git commit -m "chore: rename ubuntu-noble → ubuntu-base in packer template"
```

---

### Task 15: Create ubuntu-images README.md from scratch

**Files:**
- Create: `README.md`

```markdown
# ubuntu-images

Ubuntu 24.04 base image with systemd for Ansible/Molecule testing.

## What this image contains

| Package | Version | Why |
|---------|---------|-----|
| systemd + systemd-sysv | 24.04 LTS | Molecule systemd driver + service testing |
| python3 | 24.04 LTS | Ansible connection + modules |
| python3-apt | 24.04 LTS | Ansible `apt` module support |
| sudo | 24.04 LTS | Privilege escalation in test playbooks |
| dbus | 24.04 LTS | systemd dbus socket (required for systemctl) |
| udev | 24.04 LTS | Device management (required for network roles) |
| kmod | 24.04 LTS | Kernel module management |

## Guarantees

Every image push is contract-tested. The following are always true:

- `/lib/systemd/systemd` is executable
- `python3`, `sudo`, `udevadm`, `kmod`, `dbus-daemon` are on PATH
- `python3 -c "import apt"` succeeds
- `/lib/systemd/system/systemd-tmpfiles-setup.service` exists

See [`contracts/docker.sh`](contracts/docker.sh) for the machine-readable contract.

## Usage

### In molecule.yml (Docker driver)

```yaml
platforms:
  - name: ubuntu-instance
    image: ghcr.io/textyre/ubuntu-base:24.04
    command: /lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    privileged: true
    pre_build_image: true
```

### As a Vagrant box

```
# Vagrantfile
config.vm.box = "ubuntu-base"
config.vm.box_url = "https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-base-latest.box"
```

### In molecule.yml (Vagrant driver)

```yaml
platforms:
  - name: ubuntu-base
    box: ubuntu-base
    box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-base-latest.box
```

## Not suitable for

- Production deployments of any kind
- Environments without Docker privileged mode
- Images where a minimal footprint is required

## Update schedule

Rebuilt every Monday at 03:00 UTC (1 hour after arch-images, 02:00 UTC).
Based on `ubuntu:24.04` LTS — rebuilt to pick up upstream security patches.

## Image tags

| Tag | Example | Use |
|-----|---------|-----|
| `:latest` | `ubuntu-base:latest` | Local development |
| `:YYYY.MM.DD` | `ubuntu-base:2026.02.27` | Pin to a specific weekly build |
| `:24.04` | `ubuntu-base:24.04` | Semantic Ubuntu LTS version |
| `:sha-{short}` | `ubuntu-base:sha-abc1234` | Immutable pin for rollback |
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: create README with full structure (ubuntu-base)"
```

---

### Task 16: Delete ubuntu-molecule and ubuntu-noble from GHCR (manual)

**Step 1: Go to** `https://github.com/orgs/textyre/packages?repo_name=ubuntu-images`

**Step 2: Delete** all versions of `ubuntu-noble` and `ubuntu-molecule` packages.
The new image will be published as `ubuntu-base`.

**Step 3: Verify** old names no longer resolve:

```bash
docker pull ghcr.io/textyre/ubuntu-noble:latest
docker pull ghcr.io/textyre/ubuntu-molecule:latest
# Expected: both return "manifest unknown"
```

---

## Phase 4 — bootstrap: Update Downstream References

All steps below are in the `textyre/bootstrap` repo (this repo).

**What changed in image repos:**
- `ghcr.io/textyre/arch-molecule` → `ghcr.io/textyre/arch-base`
- Vagrant box `ubuntu-noble` → `ubuntu-base`
- Platform name `ubuntu-noble` in molecule.yml → `ubuntu-base`
- `molecule-vagrant.yml` matrix value `ubuntu-noble` → `ubuntu-base`

**Reference inventory (from search):**
1. `.github/workflows/build-arch-image.yml` — 4 refs to `arch-molecule`
2. `.github/workflows/molecule-vagrant.yml` — line 21: `platform: [arch-vm, ubuntu-noble]`
3. `ansible/roles/package_manager/molecule/vagrant/molecule.yml` — `box: ubuntu-noble`, `box_url: .../ubuntu-noble-latest.box`
4. `ansible/roles/pam_hardening/molecule/vagrant/molecule.yml` — same
5. 26 vagrant `molecule.yml` files — `- name: ubuntu-noble` (platform name)
6. `ansible/roles/chezmoi/README.md` — reference to `ubuntu-noble` in table

### Task 17: Update `build-arch-image.yml`

**Files:**
- Modify: `.github/workflows/build-arch-image.yml`

**Step 1: Read the file**

**Step 2: Make replacements**

| Old | New |
|-----|-----|
| `# The arch-molecule image is built...` | `# The arch-base image is built...` |
| `name: Verify arch-molecule image contract` | `name: Verify arch-base image contract` |
| `ghcr.io/textyre/arch-molecule:latest` | `ghcr.io/textyre/arch-base:latest` |
| `=== arch-molecule image contract ===` | `=== arch-base image contract ===` |

**Step 3: Verify no arch-molecule refs remain**

```bash
grep -n "arch-molecule" .github/workflows/build-arch-image.yml
# Expected: no output
```

**Step 4: Commit**

```bash
git add .github/workflows/build-arch-image.yml
git commit -m "fix(ci): update arch image verify to use arch-base (was arch-molecule)"
```

---

### Task 18: Update `molecule-vagrant.yml` matrix

**Files:**
- Modify: `.github/workflows/molecule-vagrant.yml`

**Step 1: Change platform matrix**

Line 21: `platform: [arch-vm, ubuntu-noble]`
→ `platform: [arch-vm, ubuntu-base]`

**Step 2: Verify**

```bash
grep -n "ubuntu-noble\|ubuntu-molecule" .github/workflows/molecule-vagrant.yml
# Expected: no output
```

**Step 3: Commit**

```bash
git add .github/workflows/molecule-vagrant.yml
git commit -m "fix(ci): rename ubuntu-noble platform → ubuntu-base in vagrant matrix"
```

---

### Task 19: Update box definitions in 2 explicit molecule.yml files

**Files:**
- Modify: `ansible/roles/package_manager/molecule/vagrant/molecule.yml`
- Modify: `ansible/roles/pam_hardening/molecule/vagrant/molecule.yml`

**Step 1: In each file, change**

```yaml
# Old
box: ubuntu-noble
box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-noble-latest.box

# New
box: ubuntu-base
box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-base-latest.box
```

**Step 2: Verify**

```bash
grep -rn "ubuntu-noble" ansible/roles/package_manager/molecule/ ansible/roles/pam_hardening/molecule/
# Expected: no output
```

**Step 3: Commit**

```bash
git add ansible/roles/package_manager/molecule/vagrant/molecule.yml \
        ansible/roles/pam_hardening/molecule/vagrant/molecule.yml
git commit -m "fix(molecule): update vagrant box refs ubuntu-noble → ubuntu-base"
```

---

### Task 20: Update platform name in all 26 vagrant molecule.yml files

**Background:** All 26 vagrant scenarios have `- name: ubuntu-noble`. This must match
the `--platform-name ubuntu-base` argument from the updated workflow matrix.

**Step 1: Find all affected files**

```bash
grep -rn "name: ubuntu-noble" ansible/roles/*/molecule/vagrant/molecule.yml
```

Expected: ~26 files.

**Step 2: Bulk rename using sed**

```bash
find ansible/roles -path "*/molecule/vagrant/molecule.yml" -exec \
  sed -i 's/- name: ubuntu-noble/- name: ubuntu-base/g' {} +
```

**Step 3: Verify no ubuntu-noble platform names remain**

```bash
grep -rn "ubuntu-noble" ansible/roles/*/molecule/vagrant/molecule.yml
# Expected: no output (only box_url refs from Tasks 18-19 should be gone already)
```

**Step 4: Do a final sweep across all ansible/ files**

```bash
grep -rn "ubuntu-noble" ansible/
# Expected: no output
```

**Step 5: Commit**

```bash
git add ansible/roles/
git commit -m "fix(molecule): rename ubuntu-noble platform → ubuntu-base across all 26 vagrant scenarios"
```

---

### Task 21: Update chezmoi README.md

**Files:**
- Modify: `ansible/roles/chezmoi/README.md`

**Step 1: Find the line**

```bash
grep -n "ubuntu-noble" ansible/roles/chezmoi/README.md
```

**Step 2: Update** the table cell `ubuntu-noble` → `ubuntu-base`.

**Step 3: Verify**

```bash
grep -n "ubuntu-noble" ansible/roles/chezmoi/README.md
# Expected: no output
```

**Step 4: Commit**

```bash
git add ansible/roles/chezmoi/README.md
git commit -m "docs(chezmoi): update platform name ubuntu-noble → ubuntu-base"
```

---

### Task 22: Verify the full rename is complete

**Step 1: Final sweep across entire bootstrap repo**

```bash
grep -rn "ubuntu-noble\|arch-molecule\|ubuntu-molecule" \
  .github/ ansible/roles/ wiki/ \
  --include="*.yml" --include="*.yaml" --include="*.md" \
  --exclude-dir=".git"
```

Expected: zero matches (historical docs in `docs/troubleshooting/` and `docs/plans/` are OK to leave).

**Step 2: Run existing molecule tests (docker scenarios) to confirm nothing broken**

```bash
# On remote VM, for a role with vagrant scenario:
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && \
  cd ansible/roles/package_manager && molecule test -s docker"
```

Expected: converge + verify pass.

**Step 3: Final commit for the design document (already written in Phase 1)**

```bash
git add docs/plans/2026-02-27-image-repo-housecleaning-design.md \
        docs/plans/2026-02-27-image-repo-housecleaning.md
git commit -m "docs(plans): add image-repo housecleaning design + implementation plan"
```

---

## Summary

| Phase | Repo | Tasks | Key outcome |
|-------|------|-------|-------------|
| 1 | bootstrap | 1 | Standard documented |
| 2 | arch-images | 2–8 | Molecule removed, Trivy/Cosign/Renovate added |
| 3 | ubuntu-images | 9–16 | Renamed ubuntu-noble→ubuntu-base, same hardening |
| 4 | bootstrap | 17–22 | All downstream refs updated |

**Verification that work is complete:** `grep -rn "ubuntu-noble\|arch-molecule\|ubuntu-molecule"` across all active code files returns zero results.
