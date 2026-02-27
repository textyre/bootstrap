# Design: Image Repo Housecleaning (arch-images + ubuntu-images)

**Date:** 2026-02-27
**Repos in scope:** `textyre/arch-images`, `textyre/ubuntu-images`
**Downstream:** `textyre/bootstrap` (consumes images, hosts wiki/standards)

---

## Problem Statement

`arch-images` and `ubuntu-images` are functional but lack basic CI/image-repo hygiene:
inconsistent naming, redundant artifacts, no OCI labels, opaque versioning, no security
scanning, no supply-chain controls, and ubuntu-images has no README at all.

---

## Goals

1. Remove redundant `molecule` variants (Docker + Vagrant) — one image and one box per OS.
2. Unify naming: `ubuntu-noble` → `ubuntu-base` (codenames are not standard practice).
3. Add proper OCI metadata, CalVer tags, and image contracts.
4. Add supply-chain security baseline: Trivy, Renovate digest pinning, Cosign keyless signing.
5. Document the standard in `wiki/standards/image-repo-requirements.md` in bootstrap.
6. Update all downstream references in bootstrap to reflect new names.

---

## Design Decisions

### 1. Naming and Artifacts

Each repo publishes exactly one Docker image and one Vagrant box. No `molecule` variants.

| Artifact | arch-images | ubuntu-images |
|---|---|---|
| Docker (GHCR) | `ghcr.io/textyre/arch-base` | `ghcr.io/textyre/ubuntu-base` |
| Vagrant box | `arch-base-YYYYMMDD.box` + `arch-base-latest.box` | `ubuntu-base-YYYYMMDD.box` + `ubuntu-base-latest.box` |
| **Remove from GHCR** | `arch-molecule` | `ubuntu-molecule` |
| **Remove from Releases** | `arch-molecule-*.box` | `ubuntu-molecule-*.box` |

Rationale: zero of 5 studied community image repos (geerlingguy, hifis-net, marciopaiva,
buluma, CarloDePieri) split images into base/molecule variants. One systemd-ready image per
OS serves all Ansible/Molecule purposes. Codenames (`noble`) are not used in image names by
any studied project; numeric versions (`24.04`) or purpose-suffix (`base`) are standard.

### 2. GHCR Tags

Replace opaque `:latest + :<run_number>` with:

```
:latest          — floating, for local convenience
:2026.02.27      — CalVer, for pinnable CI use (matches Vagrant box naming)
:24.04           — OS version tag (ubuntu only)
:rolling         — arch only
:sha-abc1234     — immutable short SHA for rollback/forensics
```

All generated via `docker/metadata-action@v5`. Rationale: run numbers are opaque; date
tags give temporal context aligned with the existing Vagrant box naming convention.

### 3. CI Workflow Structure

```
trigger: schedule (Mon 02:00 UTC arch, 03:00 UTC ubuntu) + workflow_dispatch

jobs:
  changes:        dorny/paths-filter — skip unnecessary rebuilds
  build-docker:   matrix dropped (no more variants) → single job
                  steps: checkout → buildx → metadata → trivy scan → build+push → contract verify
  build-vagrant:  single job (packer build + contract verify)
  attest:         keyless Cosign sign (needs: build-docker)
```

Key changes from current:
- Matrix removed (was implicit, now explicitly not needed)
- `hashicorp/setup-packer@main` → pin to SHA
- `dorny/paths-filter` added as first job
- Trivy scan inserted before push (gate on CRITICAL+HIGH, ignore-unfixed)
- Attest job added after push

### 4. OCI Labels

Remove all `LABEL` from Dockerfiles. Inject at build time via `docker/metadata-action@v5`:

Auto-generated (8 labels): `title`, `description`, `url`, `source`, `version`, `created`,
`revision`, `licenses`.

Add manually: `org.opencontainers.image.vendor=textyre`,
`org.opencontainers.image.description=<purpose>`.

Also pass `annotations: ${{ steps.meta.outputs.annotations }}` for OCI Index annotation.

### 5. Supply Chain Security

| Control | Effort | What it does |
|---|---|---|
| `provenance: true` in build-push-action | 1 line | SLSA L1 provenance attestation |
| Trivy scan (CRITICAL+HIGH, ignore-unfixed) | ~10 lines | Gate push on known vulns |
| Keyless Cosign signing | ~10 lines | Signatures on GHCR, no key management |
| `renovate.json` with `docker:pinDigests` | 1 file | Pins base image digests, auto-PRs |
| CycloneDX SBOM via Trivy | ~10 lines | Attach to GitHub Release |

Renovate config:
```json
{ "extends": ["config:best-practices", "docker:pinDigests", ":automergeDigest"] }
```

### 6. Contract Scripts

`contracts/docker.sh` — mandatory minimum:
- systemd binary present and executable
- python3 present
- sudo present
- All packages listed in Dockerfile `RUN` are verified by name
- locale data present (arch-base only)

`contracts/vagrant.sh` — TBD per existing pattern.

Ubuntu contract currently only checks 3 items vs 9 for Arch. Bring ubuntu contract to
parity: add dbus, udev, kmod, python3-apt verification.

### 7. README Structure (both repos)

1. **Purpose** — one sentence describing what the image is for
2. **What this image contains** — table: package, version, why
3. **Guarantees** — bullet list of runtime invariants (what contract enforces)
4. **Contract tests** — link to `contracts/docker.sh` and `contracts/vagrant.sh`
5. **Usage** — how to reference in `molecule.yml` and `Vagrantfile`
6. **Not suitable for** — explicit non-goals (production, non-Molecule use)
7. **Update schedule** — weekly Monday rebuild
8. **Image tags** — table of available tags and their semantics

arch-images README: fix stale `arch-molecule` reference → `arch-base`.
ubuntu-images README: create from scratch.

### 8. bootstrap Downstream Updates

- `.github/workflows/build-arch-image.yml`: `arch-molecule:latest` → `arch-base:latest`
- Vagrant platform configs: `ubuntu-noble` → `ubuntu-base` wherever it's a box name
- `wiki/standards/image-repo-requirements.md`: new file (see below)

---

## Standard: Image Repo Requirements

New file: `wiki/standards/image-repo-requirements.md`

Mirrors `wiki/standards/role-requirements.md` structure. Defines criteria every image repo
must satisfy:

**Naming:**
- Repo name: `{os}-images` (e.g., `arch-images`, `ubuntu-images`)
- Image name: `ghcr.io/textyre/{os}-base`
- No codenames in image names; use numeric versions or `base`/`rolling`

**Artifacts per repo:**
- One Docker image (GHCR)
- One Vagrant box (GitHub Releases)
- No `molecule` variants

**Required GHCR tags:** `:latest`, `:YYYY.MM.DD`, OS-version (`:24.04` / `:rolling`), `:sha-{short}`

**OCI Labels:** 8 auto via `docker/metadata-action` + vendor + description

**Security (mandatory):**
- Trivy scan before push, gate CRITICAL+HIGH, ignore-unfixed
- `renovate.json` with `docker:pinDigests`
- SLSA L1 (`provenance: true`)
- Keyless Cosign signing
- CycloneDX SBOM attached to GitHub Release

**Contract:**
- `contracts/docker.sh` verifying every package installed by Dockerfile
- `contracts/vagrant.sh`
- Contract run in CI after build, before release

**README:** structured per Section 7 above.

**Workflow:**
- `changes` (dorny/paths-filter) → `build-docker` → `build-vagrant` → `attest`
- No floating action versions (`@main` or bare `@latest`)
- `hashicorp/setup-packer` pinned to SHA

---

## Affected Files

### arch-images
- `docker/Dockerfile` — remove LABEL lines
- `.github/workflows/build.yml` — restructure (metadata-action, trivy, cosign, tags, pin packer)
- `contracts/docker.sh` — verify all installed packages
- `README.md` — fix arch-molecule reference, add full structure
- `renovate.json` — new file

### ubuntu-images
- `docker/Dockerfile` — remove LABEL lines (if any)
- `.github/workflows/build.yml` — same as arch
- `contracts/docker.sh` — expand to parity with arch (dbus, udev, kmod, python3-apt)
- `README.md` — create from scratch
- `renovate.json` — new file

### bootstrap
- `.github/workflows/build-arch-image.yml` — `arch-molecule` → `arch-base`
- Vagrant platform configs referencing `ubuntu-noble` as box name → `ubuntu-base`
- `wiki/standards/image-repo-requirements.md` — new file

---

## Out of Scope

- SLSA L3 (slsa-github-generator reusable workflow) — overkill for internal CI images
- Multi-arch builds (linux/arm64) — no ARM runners in use
- GitHub CODEOWNERS, issue templates — low-priority repo hygiene
- Dependabot (Renovate covers Docker; Actions pinning is manual)
