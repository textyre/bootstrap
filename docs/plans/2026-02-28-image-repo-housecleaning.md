# Image Repo Housecleaning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Clean up `textyre/arch-images` and `textyre/ubuntu-images` — remove molecule variants, rename `ubuntu-noble` → `ubuntu-base`, add OCI labels + CalVer tags, supply-chain security (Trivy/Cosign/Renovate/SBOM), real Vagrant boot-verification, and document a standard in bootstrap.

**Architecture:** Four phases across three repos. Phase 1 (bootstrap standard doc) is independent and can land anytime. Phases 2–3 (image repos) are the bulk of the work and can run in parallel. Phase 4 (bootstrap downstream) is **blocked** until new image releases exist — do not start it until CI passes and `arch-base-latest.box` + `ubuntu-base-latest.box` are live in GitHub Releases.

**Tech Stack:** GitHub Actions, Docker Buildx, `docker/metadata-action@v5`, `docker/build-push-action@v6`, `aquasecurity/trivy-action` (pinned tag — see Task 6 Step 1), `sigstore/cosign-installer@v3`, `dorny/paths-filter@v3`, Packer (HCL2), Vagrant (libvirt)

---

## Context

**Repos:**
- `textyre/arch-images` — builds `ghcr.io/textyre/arch-base` Docker image + `arch-base-*.box` Vagrant box
- `textyre/ubuntu-images` — builds `ghcr.io/textyre/ubuntu-noble` Docker image (→ rename to `ubuntu-base`) + `ubuntu-noble-*.box` (→ rename to `ubuntu-base-*.box`)
- `textyre/bootstrap` — consumes both; hosts `wiki/standards/` for infrastructure standards

**Current state (2026-02-28):**
- `arch-molecule` → `arch-base` rename in bootstrap molecule scenarios: **DONE** (commits ace8463, 623fefc)
- `ubuntu-molecule` → `ubuntu-noble` rename in bootstrap molecule scenarios: **DONE** (commit ace8463)
- `ubuntu-noble` → `ubuntu-base` rename: **TODO** (Phase 4)
- Supply-chain security (Trivy/Cosign/Renovate/SBOM): **TODO** (Phases 2–3)
- `wiki/standards/image-repo-requirements.md`: **TODO** (Phase 1)

**GHCR cleanup (manual, one-time):** After removing molecule publishing from workflows, delete old GHCR packages manually: `github.com/orgs/textyre/packages`.

---

## Order dependency

```
Phase 1 (bootstrap: standard doc)  ─────────────────────────────────────────┐
                                                                              │
Phase 2 (arch-images: overhaul)  ──┐                                        │
                                    ├── push + CI green + releases exist ──► │
Phase 3 (ubuntu-images: overhaul) ─┘                    BLOCKING GATE       │
                                                                              ↓
                                         Phase 4 (bootstrap: downstream refs, AFTER gate)
```

---

## Phase 0 — State Check (5 minutes, no commit)

Before touching anything, verify current bootstrap state so you don't redo completed work.

### Task 0: Verify current state in bootstrap

**Step 1: Check arch-molecule refs**

```bash
grep -rn "arch-molecule" .github/ ansible/ wiki/ \
  --include="*.yml" --include="*.yaml" --include="*.md"
```

Expected: **zero matches** (already done).

**Step 2: Check ubuntu-noble refs (these are the Phase 4 target)**

```bash
grep -rn "ubuntu-noble" .github/ ansible/ wiki/ \
  --include="*.yml" --include="*.yaml" --include="*.md"
```

Record the count — these will all be renamed in Phase 4.

**Step 3: Check ubuntu-molecule refs**

```bash
grep -rn "ubuntu-molecule" .github/ ansible/ wiki/ \
  --include="*.yml" --include="*.yaml" --include="*.md"
```

Expected: **zero matches** (already done).

---

## Phase 1 — bootstrap: Write the Standard

### Task 1: Create `wiki/standards/image-repo-requirements.md`

**Files:**
- Create: `wiki/standards/image-repo-requirements.md`

**Step 1: Create the file**

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
| Keyless signing | Cosign OIDC keyless signing after push (sigstore/cosign-installer@v3) |
| SLSA L1 provenance | `provenance: true` in `build-push-action` |
| Base image digest pinning | `renovate.json` with `docker:pinDigests` preset |

SBOM (CycloneDX) generated via Trivy and uploaded as a build artifact.

## REQ-07: Contract Verification

Every image MUST have `contracts/docker.sh` that verifies:
- Every binary installed by the Dockerfile (`test -x` or `command -v`)
- Every data file required at runtime (`test -f`)
- The script runs inside the image via `docker run --rm <image> bash contracts/docker.sh`
- Script MUST `set -euo pipefail` and exit non-zero on any failure

Vagrant boxes MUST have `contracts/vagrant.sh` with equivalent checks.
The vagrant contract MUST be run inside a booted VM (not as a host-side archive check):
`vagrant ssh -c "bash -s" < contracts/vagrant.sh`

Contracts MUST be run in CI after every build, before the release step.

## REQ-08: CI Workflow Structure

```
build.yml
├── changes (dorny/paths-filter@v3)
├── build-docker (needs: changes)
│   ├── Trivy scan (before push — gate, not archive check)
│   ├── docker/metadata-action + build-push-action
│   └── Contract verify (docker run --rm)
├── build-vagrant (needs: changes, independent of build-docker)
│   ├── packer build
│   ├── vagrant up + vagrant ssh -c contract verify
│   └── Publish to GitHub Releases
└── attest (needs: build-docker)
    └── Cosign keyless sign (by digest)
```

No action version MAY use a floating branch reference (e.g., `@main`, `@master`).
`hashicorp/setup-packer` MUST be pinned to a commit SHA.
All other actions MUST use a pinned semver tag (e.g., `@v3`, `@v5`).

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
- [ ] REQ-07: `contracts/docker.sh` covers every installed package; vagrant contract runs inside booted VM
- [ ] REQ-08: Workflow uses `changes` → `build-docker` → `build-vagrant` → `attest`; no floating action refs
- [ ] REQ-09: README has all 8 required sections
- [ ] REQ-10: `renovate.json` present with `docker:pinDigests`
```

**Step 2: Verify**

Open `wiki/standards/image-repo-requirements.md` and confirm all 10 REQ sections render cleanly.

**Step 3: Commit**

```bash
git add wiki/standards/image-repo-requirements.md
git commit -m "docs(standards): add image-repo-requirements (10 REQs)"
```

---

## Phase 2 — arch-images: Cleanup and Harden

All work is in the `textyre/arch-images` repo.

### Task 2: Remove arch-molecule variant from Packer and workflow

**Background:** Locate and remove whatever produces `arch-molecule-*.box`. There may be a second
Packer template or a second workflow step.

**Files:**
- Modify: `packer/*.pkr.hcl` (find any molecule-specific template)
- Modify: `.github/workflows/build.yml`

**Step 1: Find molecule references**

```bash
grep -rn "arch-molecule\|molecule" packer/ .github/
```

**Step 2: Delete or comment out** any `build {}` block that produces `arch-molecule-*.box`. Keep only the `arch-base` build.

**Step 3: Remove** any workflow step that uploads `arch-molecule-*.box` to GitHub Releases.

**Step 4: Verify no molecule remnants**

```bash
grep -rn "arch-molecule\|molecule" packer/ .github/
# Expected: no output
```

**Step 5: Commit**

```bash
git add packer/ .github/workflows/build.yml
git commit -m "chore: remove arch-molecule variant (box + packer config)"
```

---

### Task 3: Remove LABEL from Dockerfile

**Files:**
- Modify: `docker/Dockerfile`

**Step 1: Read the Dockerfile**

```bash
cat docker/Dockerfile
```

**Step 2: Remove all `LABEL` instructions** — OCI labels are injected at build time by the workflow.

**Step 3: Verify no LABEL lines remain**

```bash
grep -n "LABEL" docker/Dockerfile
# Expected: no output
```

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

**Background:** Every package in the Dockerfile must be checked. arch-base includes:
`python`, `sudo`, `glibc`, `base-devel` (gcc, make, etc.), `git`, and pre-created user `aur_builder`.

**Files:**
- Modify: `contracts/docker.sh`

**Step 1: Read current script and Dockerfile**

```bash
cat contracts/docker.sh
cat docker/Dockerfile
```

Identify every package installed. The contract must verify ALL of them.

**Step 2: Rewrite to verify all installed packages**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== arch-base Docker image contract ==="

# Core tools
echo -n "systemd:           " && test -x /usr/lib/systemd/systemd && echo "OK"
echo -n "python:            " && python --version
echo -n "sudo:              " && sudo --version | head -1
echo -n "gcc (base-devel):  " && gcc --version | head -1
echo -n "make (base-devel): " && make --version | head -1
echo -n "git:               " && git --version

# AUR builder user
echo -n "aur_builder user:  " && id aur_builder
echo -n "aur_builder sudo:  " && test -f /etc/sudoers.d/aur_builder && echo "OK"

# Locale data (required for en_US/ru_RU locale generation in bootstrap roles)
echo -n "locale SUPPORTED:  " && test -f /usr/share/i18n/SUPPORTED && echo "OK"
echo -n "locale en_US:      " && test -f /usr/share/i18n/locales/en_US && echo "OK"
echo -n "locale ru_RU:      " && test -f /usr/share/i18n/locales/ru_RU && echo "OK"
echo -n "locale-gen:        " && command -v locale-gen

# Systemd minimal (required for Molecule systemd driver)
echo -n "systemd-tmpfiles:  " && test -f /usr/lib/systemd/system/systemd-tmpfiles-setup.service && echo "OK"

echo "=== arch-base contract: PASS ==="
```

**Step 3: Test locally (if Docker available)**

```bash
docker build -t arch-base-test docker/
docker run --rm arch-base-test bash contracts/docker.sh
```

Expected: all lines print "OK" or a version string, final line: `=== arch-base contract: PASS ===`

**Step 4: Commit**

```bash
git add contracts/docker.sh
git commit -m "fix(contracts): verify all installed packages in docker.sh"
```

---

### Task 6: Rewrite `.github/workflows/build.yml`

This is the main task. Adds: `docker/metadata-action`, CalVer tags, Trivy (pinned tag, not @master),
Cosign keyless signing (without deprecated COSIGN_EXPERIMENTAL), SLSA L1 provenance, `dorny/paths-filter`,
pinned packer action SHA, and real Vagrant boot-verification.

**Files:**
- Modify: `.github/workflows/build.yml`

**Step 1: Look up pinned SHA for `hashicorp/setup-packer`**

```bash
# Find the latest release tag
gh release list --repo hashicorp/setup-packer --limit 1

# Get the SHA for that tag (replace vX.Y.Z with the actual tag)
gh api repos/hashicorp/setup-packer/git/refs/tags/vX.Y.Z | jq -r '.object.sha'
# If it's an annotated tag, dereference it:
gh api repos/hashicorp/setup-packer/git/tags/<sha-from-above> | jq -r '.object.sha'
```

**Step 2: Look up the latest pinned tag for `aquasecurity/trivy-action`**

```bash
# Find the latest release tag (e.g., v0.30.0)
gh release list --repo aquasecurity/trivy-action --limit 1
```

Note: Do NOT use `@master`. Use the actual tag from this lookup.

**Step 3: Read the current workflow**

```bash
cat .github/workflows/build.yml
```

**Step 4: Write the new workflow** (replace `<PACKER-SHA>` and `<TRIVY-TAG>` with values from Steps 1–2)

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
      (github.event_name == 'workflow_dispatch' && (inputs.artifact == 'all' || inputs.artifact == 'docker')) ||
      needs.changes.outputs.docker == 'true'
    runs-on: ubuntu-latest
    permissions:
      packages: write
      id-token: write      # required for keyless Cosign signing
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
        uses: aquasecurity/trivy-action@<TRIVY-TAG>   # Replace with tag from Step 2
        with:
          image-ref: arch-base:scan
          severity: CRITICAL,HIGH
          exit-code: '1'
          ignore-unfixed: true

      - name: Verify Docker image contract
        run: docker run --rm arch-base:scan bash contracts/docker.sh

      - name: Build and push (with SLSA L1 provenance + SBOM)
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

      - name: Generate CycloneDX SBOM
        uses: aquasecurity/trivy-action@<TRIVY-TAG>   # Same tag as above
        with:
          image-ref: arch-base:scan
          format: cyclonedx
          output: sbom.cyclonedx.json

      - name: Upload SBOM as build artifact
        uses: actions/upload-artifact@v4
        with:
          name: sbom-arch-base-docker
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

      - name: Sign image by digest
        # Sign by digest (covers all tags; COSIGN_EXPERIMENTAL is not needed in cosign v2+)
        run: |
          IMAGE_DIGEST=$(docker buildx imagetools inspect \
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest \
            --format '{{.Manifest.Digest}}')
          cosign sign --yes \
            "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${IMAGE_DIGEST}"

  build-vagrant:
    name: Build arch-base Vagrant box
    needs: changes
    if: |
      github.event_name == 'schedule' ||
      (github.event_name == 'workflow_dispatch' && (inputs.artifact == 'all' || inputs.artifact == 'vagrant')) ||
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
        uses: hashicorp/setup-packer@<PACKER-SHA>   # vX.Y.Z — replace with SHA from Step 1

      - name: Packer init
        run: packer init packer/archlinux.pkr.hcl

      - name: Packer build (arch-base only)
        timeout-minutes: 60
        run: packer build packer/archlinux.pkr.hcl

      - name: Verify Vagrant box contract (boot test)
        # Real boot verification — not an archive check. Runs contract inside the booted VM.
        run: |
          vagrant box add --name verify-box arch-base.box
          mkdir /tmp/verify-vm && cd /tmp/verify-vm
          cat > Vagrantfile <<'EOF'
          Vagrant.configure("2") do |config|
            config.vm.box = "verify-box"
            config.vm.provider :libvirt do |l|
              l.memory = 1024
              l.cpus   = 1
            end
          end
          EOF
          vagrant up --provider libvirt --no-provision
          vagrant ssh -c "bash -s" < "$GITHUB_WORKSPACE/contracts/vagrant.sh"
          vagrant destroy -f

      - name: Compute CalVer date
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

**Step 5: Verify no floating action refs remain**

```bash
grep -n "@master\|@main\|@latest" .github/workflows/build.yml
# Expected: no output
```

**Step 6: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "feat: overhaul workflow — metadata-action, Trivy, Cosign, CalVer tags, boot-verify, paths-filter"
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
- `/usr/lib/systemd/system/systemd-tmpfiles-setup.service` exists

See [`contracts/docker.sh`](contracts/docker.sh) for the machine-readable contract.

## Contract tests

- Docker: [`contracts/docker.sh`](contracts/docker.sh) — runs inside the built image
- Vagrant: [`contracts/vagrant.sh`](contracts/vagrant.sh) — runs inside a booted VM via `vagrant ssh`

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

```ruby
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

**Step 1: Go to** `https://github.com/orgs/textyre/packages?repo_name=arch-images`

**Step 2: Find** the `arch-molecule` package. Click into it.

**Step 3: Delete** all versions of `arch-molecule`. GitHub asks for confirmation per version.

**Step 4: Delete** the package itself once all versions are removed.

**Step 5: Verify** `arch-molecule` no longer resolves:

```bash
docker pull ghcr.io/textyre/arch-molecule:latest
# Expected: error response from daemon: manifest unknown
```

---

## Phase 3 — ubuntu-images: Cleanup, Rename, Harden

All work is in the `textyre/ubuntu-images` repo.
`ubuntu-noble` → `ubuntu-base` is a breaking rename. Bootstrap refs are updated in Phase 4 after CI passes.

### Task 9: Remove ubuntu-molecule variant

Same pattern as Task 2.

**Step 1: Find molecule references**

```bash
grep -rn "ubuntu-molecule\|molecule" packer/ .github/
```

**Step 2: Delete** any Packer build block or workflow step producing `ubuntu-molecule-*.box`.

**Step 3: Verify**

```bash
grep -rn "ubuntu-molecule\|molecule" packer/ .github/
# Expected: no output
```

**Step 4: Commit**

```bash
git add packer/ .github/workflows/build.yml
git commit -m "chore: remove ubuntu-molecule variant (box + packer config)"
```

---

### Task 10: Remove LABEL from Dockerfile

Same as Task 3.

```bash
grep -n "LABEL" docker/Dockerfile   # find what exists
# Remove all LABEL lines
grep -n "LABEL" docker/Dockerfile   # must return nothing after edit

git add docker/Dockerfile
git commit -m "chore(dockerfile): remove hardcoded LABEL instructions"
```

---

### Task 11: Add `renovate.json`

Identical content to Task 4.

```bash
git add renovate.json
git commit -m "chore: add renovate config for Docker digest pinning"
```

---

### Task 12: Expand `contracts/docker.sh` to full parity

**Background:** Current ubuntu contract likely checks only 3 items (systemd, python3, sudo).
The Dockerfile also installs: `systemd-sysv`, `dbus`, `udev`, `kmod`, `python3-apt`.

**Files:**
- Modify: `contracts/docker.sh`

**Step 1: Read current script and Dockerfile**

```bash
cat contracts/docker.sh
cat docker/Dockerfile
```

Identify every package installed. The contract must verify ALL of them.

**Step 2: Rewrite to verify all installed packages**

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== ubuntu-base Docker image contract ==="

# Core binaries
echo -n "systemd:          " && test -x /lib/systemd/systemd && echo "OK"
echo -n "python3:          " && python3 --version
echo -n "sudo:             " && sudo --version | head -1

# Explicitly installed packages (adjust to match actual Dockerfile — read it first)
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

### Task 13: Update Packer template for ubuntu-base rename

**Files:**
- Modify: `packer/ubuntu.pkr.hcl` (or `packer/ubuntu.pkrvars.hcl` — read to find out)

**Step 1: Search for noble/ubuntu-noble references in packer/**

```bash
grep -rn "ubuntu-noble\|noble" packer/
```

**Step 2: Replace** `ubuntu-noble` with `ubuntu-base` in box output filename variable(s).

**Step 3: Verify**

```bash
grep -rn "ubuntu-noble" packer/
# Expected: no output
```

**Step 4: Commit**

```bash
git add packer/
git commit -m "chore: rename ubuntu-noble → ubuntu-base in packer template"
```

---

### Task 14: Rewrite `.github/workflows/build.yml`

Same structure as Task 6, with ubuntu-specific substitutions. Use the SHA/tag values already looked up in Task 6.

**Files:**
- Modify: `.github/workflows/build.yml`

**Step 1: Apply ubuntu-specific substitutions** to the arch workflow:

| Find | Replace |
|------|---------|
| `IMAGE_NAME: .../arch-base` | `IMAGE_NAME: .../ubuntu-base` |
| `type=raw,value=rolling` | `type=raw,value=24.04` |
| `Arch Linux base image...` | `Ubuntu 24.04 base image with systemd for Ansible/Molecule testing` |
| `arch-base:scan` | `ubuntu-base:scan` |
| `archlinux.pkr.hcl` | `ubuntu.pkr.hcl` |
| `arch-base.box` | `ubuntu-base.box` |
| `arch-base-*.box` | `ubuntu-base-*.box` |
| `/usr/lib/systemd/systemd` | `/lib/systemd/systemd` (Ubuntu path) |
| schedule `cron: '0 2 * * 1'` | `cron: '0 3 * * 1'` (03:00 UTC, 1 hour after arch) |

**Step 2: Verify no ubuntu-noble refs remain**

```bash
grep -n "ubuntu-noble\|ubuntu-molecule" .github/workflows/build.yml
# Expected: no output
```

**Step 3: Verify no floating action refs**

```bash
grep -n "@master\|@main\|@latest" .github/workflows/build.yml
# Expected: no output
```

**Step 4: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "feat: overhaul workflow — rename ubuntu-noble→ubuntu-base, metadata-action/Trivy/Cosign"
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

## Contract tests

- Docker: [`contracts/docker.sh`](contracts/docker.sh) — runs inside the built image
- Vagrant: [`contracts/vagrant.sh`](contracts/vagrant.sh) — runs inside a booted VM via `vagrant ssh`

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

```ruby
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

### Task 16: Delete ubuntu-noble and ubuntu-molecule from GHCR (manual)

**Step 1: Go to** `https://github.com/orgs/textyre/packages?repo_name=ubuntu-images`

**Step 2: Delete** all versions of both `ubuntu-noble` and `ubuntu-molecule` packages.

**Step 3: Verify** old names no longer resolve:

```bash
docker pull ghcr.io/textyre/ubuntu-noble:latest
docker pull ghcr.io/textyre/ubuntu-molecule:latest
# Expected: both return "manifest unknown"
```

---

## Blocking Gate — Push image repos and verify CI

**Do not start Phase 4 until this completes successfully.**

### Task 17: Push both image repos and wait for green releases

**Step 1: Push arch-images**

```bash
# In textyre/arch-images working directory
git push origin main
```

**Step 2: Push ubuntu-images**

```bash
# In textyre/ubuntu-images working directory
git push origin main
```

**Step 3: Trigger builds**

```bash
gh workflow run build.yml --repo textyre/arch-images   --field artifact=all
gh workflow run build.yml --repo textyre/ubuntu-images --field artifact=all
```

**Step 4: Watch until complete**

```bash
gh run watch --repo textyre/arch-images \
  $(gh run list --repo textyre/arch-images --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch --repo textyre/ubuntu-images \
  $(gh run list --repo textyre/ubuntu-images --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected: both complete with green checkmarks.

**Step 5: Verify new releases exist**

```bash
gh release view boxes --repo textyre/arch-images   --json assets --jq '.assets[].name'
gh release view boxes --repo textyre/ubuntu-images --json assets --jq '.assets[].name'
```

Expected output (arch):
```
arch-base-YYYYMMDD.box
arch-base-latest.box
```

Expected output (ubuntu):
```
ubuntu-base-YYYYMMDD.box
ubuntu-base-latest.box
```

If either `arch-base-latest.box` or `ubuntu-base-latest.box` is missing, **do not proceed to Phase 4**.

---

## Phase 4 — bootstrap: Update Downstream References

All work is in `textyre/bootstrap` (this repo).

**What changed upstream:**
- `ghcr.io/textyre/arch-molecule` → `ghcr.io/textyre/arch-base` (already done in molecule scenarios)
- Vagrant box `ubuntu-noble` → `ubuntu-base` (TODO)
- Platform name `ubuntu-noble` in molecule.yml → `ubuntu-base` (TODO)
- `molecule-vagrant.yml` matrix `ubuntu-noble` → `ubuntu-base` (TODO)

### Task 18: Update `build-arch-image.yml`

**Files:**
- Modify: `.github/workflows/build-arch-image.yml`

**Step 1: Read the file**

```bash
cat .github/workflows/build-arch-image.yml
```

**Step 2: Replace all arch-molecule references**

| Old | New |
|-----|-----|
| `arch-molecule` image name | `arch-base` |
| `=== arch-molecule image contract ===` | `=== arch-base image contract ===` |
| Any comment mentioning arch-molecule | Update to arch-base |

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

### Task 19: Update `molecule-vagrant.yml` matrix

**Files:**
- Modify: `.github/workflows/molecule-vagrant.yml`

**Step 1: Read the file and find the platform matrix**

```bash
grep -n "ubuntu-noble\|platform" .github/workflows/molecule-vagrant.yml
```

**Step 2: Change platform matrix**

```yaml
# Old
platform: [arch-vm, ubuntu-noble]

# New
platform: [arch-vm, ubuntu-base]
```

**Step 3: Verify**

```bash
grep -n "ubuntu-noble" .github/workflows/molecule-vagrant.yml
# Expected: no output
```

**Step 4: Commit**

```bash
git add .github/workflows/molecule-vagrant.yml
git commit -m "fix(ci): rename ubuntu-noble platform → ubuntu-base in vagrant matrix"
```

---

### Task 20: Update box definitions in 2 explicit molecule.yml files

**Files:**
- Modify: `ansible/roles/package_manager/molecule/vagrant/molecule.yml`
- Modify: `ansible/roles/pam_hardening/molecule/vagrant/molecule.yml`

**Step 1: In each file, update the ubuntu platform**

```yaml
# Old
- name: ubuntu-noble
  box: ubuntu-noble
  box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-noble-latest.box

# New
- name: ubuntu-base
  box: ubuntu-base
  box_url: https://github.com/textyre/ubuntu-images/releases/download/boxes/ubuntu-base-latest.box
```

**Step 2: Verify**

```bash
grep -rn "ubuntu-noble" \
  ansible/roles/package_manager/molecule/vagrant/ \
  ansible/roles/pam_hardening/molecule/vagrant/
# Expected: no output
```

**Step 3: Commit**

```bash
git add ansible/roles/package_manager/molecule/vagrant/molecule.yml \
        ansible/roles/pam_hardening/molecule/vagrant/molecule.yml
git commit -m "fix(molecule): update vagrant box refs ubuntu-noble → ubuntu-base"
```

---

### Task 21: Update platform name in all vagrant molecule.yml files

**Background:** All vagrant scenarios have `- name: ubuntu-noble`. This must match
the `--platform-name ubuntu-base` argument from the updated workflow matrix in Task 19.

**Step 1: Find all affected files**

```bash
grep -rn "name: ubuntu-noble" ansible/roles/
```

Expected: ~26 files.

**Step 2: Bulk rename**

```bash
find ansible/roles -path "*/molecule/vagrant/molecule.yml" \
  -exec sed -i 's/- name: ubuntu-noble/- name: ubuntu-base/g' {} +
```

**Step 3: Verify no ubuntu-noble platform names remain**

```bash
grep -rn "name: ubuntu-noble" ansible/roles/
# Expected: no output
```

**Step 4: Commit**

```bash
git add ansible/roles/
git commit -m "fix(molecule): rename ubuntu-noble platform → ubuntu-base across all vagrant scenarios"
```

---

### Task 22: Update chezmoi README.md

**Files:**
- Modify: `ansible/roles/chezmoi/README.md`

**Step 1: Find the line**

```bash
grep -n "ubuntu-noble" ansible/roles/chezmoi/README.md
```

**Step 2: Update** `ubuntu-noble` → `ubuntu-base` in the table.

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

### Task 23: Final verification sweep

**Step 1: Sweep bootstrap for all stale references**

```bash
grep -rn "ubuntu-noble\|arch-molecule\|ubuntu-molecule" \
  .github/ ansible/roles/ wiki/ \
  --include="*.yml" --include="*.yaml" --include="*.md"
```

Expected: **zero matches** (historical docs in `docs/` are OK to leave).

**Step 2: Run a docker molecule test on the remote VM** to confirm nothing is broken

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && \
  cd ansible/roles/package_manager && molecule test -s docker"
```

Expected: converge + verify pass.

**Step 3: Final commit (if any files were missed)**

If the sweep in Step 1 found anything, fix it and commit:

```bash
git add <files>
git commit -m "fix: final cleanup of stale ubuntu-noble/arch-molecule refs"
```

---

## Summary

| Phase | Repo | Tasks | Key outcome |
|-------|------|-------|-------------|
| 0 | bootstrap | State check | Confirm current state, skip completed work |
| 1 | bootstrap | 1 | Standard documented (10 REQs) |
| 2 | arch-images | 2–8 | Molecule removed, Trivy/Cosign/Renovate added, boot-verify |
| 3 | ubuntu-images | 9–16 | Renamed ubuntu-noble→ubuntu-base, same hardening |
| Gate | both image repos | 17 | CI green, new releases published — blocking |
| 4 | bootstrap | 18–23 | All downstream refs updated |

**Definition of done:** `grep -rn "ubuntu-noble\|arch-molecule\|ubuntu-molecule"` across `.github/`, `ansible/roles/`, `wiki/` returns zero matches.

---

## Out of scope

- SLSA L3 (slsa-github-generator reusable workflow) — overkill for internal CI images
- Multi-arch builds (linux/arm64) — no ARM runners in use
- GitHub CODEOWNERS, issue templates — low-priority
- Dependabot (Renovate covers Docker; Actions pinning is manual via SHA)
- OCI SBOM attachment (`cosign attach sbom`) — file-based artifact upload is sufficient
