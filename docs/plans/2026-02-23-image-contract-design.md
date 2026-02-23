# Design: Image Contract for arch-systemd

## Problem

`archlinux:base` Docker image strips locale data via `NoExtract` in `pacman.conf`. Our `Dockerfile.archlinux` restores it, but there is no automated verification that the built image satisfies the requirements of Molecule tests. This caused 6 CI iterations and ~45 minutes debugging locale failures (see `docs/troubleshooting/troubleshooting-history-2026-02-23-locale-ci.md`).

Additionally, `build-arch-image.yml` and `molecule.yml` run in parallel — when Dockerfile changes, Molecule tests use the old image.

## Solution

Three artifacts:

### 1. `ansible/molecule/README.md` — Image Contract Documentation

Documents what the arch-systemd image guarantees:
- systemd as PID 1
- python, sudo
- glibc with full locale data (`/usr/share/i18n/locales/*`, `SUPPORTED`)
- `locale-gen`

Explains why each guarantee exists and which roles depend on it.

### 2. Verify job in `build-arch-image.yml`

After `Build and push`, a `verify` job pulls the pushed image and runs contract checks:

```yaml
verify:
  needs: build
  runs-on: ubuntu-latest
  steps:
    - name: Verify image contract
      run: |
        docker run --rm ghcr.io/${{ github.repository }}/arch-systemd:latest \
          sh -c '
            set -e
            test -x /usr/lib/systemd/systemd
            python --version
            sudo --version > /dev/null
            test -f /usr/share/i18n/SUPPORTED
            test -f /usr/share/i18n/locales/ru_RU
            test -f /usr/share/i18n/locales/en_US
            which locale-gen
            echo "Image contract: OK"
          '
```

### 3. Conditional build-image job in `molecule.yml`

- `detect` job additionally outputs `dockerfile_changed`
- New `build-image` job: builds, pushes, and verifies (only when Dockerfile changed)
- `test` job: `needs: [detect, build-image]` with `if: always()` to not block when build-image is skipped

Flow:
```
detect ──→ build-image (if Dockerfile changed) ──→ test
   └──────────────────────────────────────────────→ test (if not)
```

## Trade-offs

- Build steps duplicated between `build-arch-image.yml` and `molecule.yml` — acceptable for correct ordering
- `build-arch-image.yml` remains for standalone builds and `workflow_dispatch`
- Verify runs in both workflows — belt and suspenders

## Not in scope

- Pre-check in locale role's generate tasks (verify.yml already catches failures)
- Smoke test as step in `_molecule.yml` (verify at build time is sufficient per user decision)
