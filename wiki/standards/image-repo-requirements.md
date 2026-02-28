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
| Keyless signing | Cosign OIDC keyless signing after push (`sigstore/cosign-installer@v3`) |
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
