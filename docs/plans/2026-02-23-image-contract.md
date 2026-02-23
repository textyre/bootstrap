# Image Contract Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add automated verification that the arch-systemd Docker image satisfies Molecule test requirements, and ensure molecule tests wait for image rebuild when Dockerfile changes.

**Architecture:** Three changes: (1) README documenting image contract, (2) verify job in build-arch-image.yml, (3) conditional build-image job in molecule.yml with test dependency.

**Tech Stack:** GitHub Actions, Docker, shell

---

### Task 1: Image Contract README

**Files:**
- Create: `ansible/molecule/README.md`

**Step 1: Write README**

```markdown
# Molecule Test Infrastructure

## arch-systemd Image Contract

The `Dockerfile.archlinux` builds an image used by all Docker-based Molecule scenarios.
The image MUST provide these capabilities:

| Guarantee | Path / Command | Needed by |
|-----------|---------------|-----------|
| systemd as PID 1 | `/usr/lib/systemd/systemd` | All roles (systemd services, timers) |
| python | `python --version` | Ansible connection |
| sudo | `sudo --version` | `become: true` in playbooks |
| locale definition files | `/usr/share/i18n/locales/ru_RU`, `en_US` | `locale` role (`community.general.locale_gen`) |
| SUPPORTED list | `/usr/share/i18n/SUPPORTED` | `locale` role (availability check) |
| locale-gen | `which locale-gen` | `locale` role (compilation) |

### Why locale data needs explicit restoration

`archlinux:base` strips `/usr/share/i18n/*` via `NoExtract` in `pacman.conf` to reduce image size.
The Dockerfile removes `NoExtract` rules and reinstalls `glibc` to restore full locale data.
See `docs/troubleshooting/troubleshooting-history-2026-02-23-locale-ci.md` for the full post-mortem.

### Modifying the Dockerfile

Before changing `Dockerfile.archlinux`:
1. Check this contract — will your change remove any guaranteed capability?
2. The `build-arch-image.yml` workflow verifies the contract after every build
3. The `molecule.yml` workflow rebuilds the image when Dockerfile changes before running tests

### CI Workflows

- `build-arch-image.yml` — builds, pushes to GHCR, then verifies contract
- `molecule.yml` — detects Dockerfile changes, rebuilds image if needed, then runs tests
- `_molecule.yml` — reusable workflow that runs `molecule test` for a single role
```

**Step 2: Commit**

```bash
git add ansible/molecule/README.md
git commit -m "docs(molecule): add arch-systemd image contract README"
```

---

### Task 2: Verify job in build-arch-image.yml

**Files:**
- Modify: `.github/workflows/build-arch-image.yml`

**Step 1: Add verify job after build**

Add this job after the existing `build` job:

```yaml
  verify:
    name: Verify image contract
    needs: build
    runs-on: ubuntu-latest
    steps:
      - name: Verify image contract
        env:
          IMAGE: ghcr.io/${{ github.repository }}/arch-systemd:latest
        run: |
          docker run --rm "$IMAGE" sh -c '
            set -e
            echo "=== Image Contract Verification ==="
            echo -n "systemd: "   && test -x /usr/lib/systemd/systemd && echo OK
            echo -n "python: "    && python --version
            echo -n "sudo: "      && sudo --version | head -1
            echo -n "SUPPORTED: " && test -f /usr/share/i18n/SUPPORTED && echo OK
            echo -n "en_US: "     && test -f /usr/share/i18n/locales/en_US && echo OK
            echo -n "ru_RU: "     && test -f /usr/share/i18n/locales/ru_RU && echo OK
            echo -n "locale-gen: " && which locale-gen
            echo "=== Image contract: PASS ==="
          '
```

**Step 2: Commit**

```bash
git add .github/workflows/build-arch-image.yml
git commit -m "ci(image): add contract verification after build"
```

---

### Task 3: Conditional build-image job in molecule.yml

**Files:**
- Modify: `.github/workflows/molecule.yml`

**Step 1: Add dockerfile_changed output to detect job**

In the `detect` job, add `dockerfile_changed` to `outputs`:

```yaml
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
      empty: ${{ steps.build.outputs.empty }}
      dockerfile_changed: ${{ steps.build.outputs.dockerfile_changed }}
```

In the `build` step script, add this block **before** the MATRIX line (after the `fi` that closes the main if/else):

```bash
          # Check if Dockerfile changed (only meaningful on push/PR, not dispatch)
          if echo "$CHANGED" | tr ' ' '\n' | grep -q "^ansible/molecule/Dockerfile"; then
            echo "dockerfile_changed=true" >> "$GITHUB_OUTPUT"
          else
            echo "dockerfile_changed=false" >> "$GITHUB_OUTPUT"
          fi
```

**Step 2: Add build-image job**

Add this job between `detect` and `test`:

```yaml
  build-image:
    name: Rebuild arch-systemd image
    needs: detect
    if: needs.detect.outputs.dockerfile_changed == 'true' && github.event_name == 'push'
    runs-on: ubuntu-latest
    permissions:
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v6
        with:
          context: ansible/molecule
          file: ansible/molecule/Dockerfile.archlinux
          push: true
          tags: ghcr.io/${{ github.repository }}/arch-systemd:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Verify image contract
        env:
          IMAGE: ghcr.io/${{ github.repository }}/arch-systemd:latest
        run: |
          docker run --rm "$IMAGE" sh -c '
            set -e
            echo "=== Image Contract Verification ==="
            echo -n "systemd: "   && test -x /usr/lib/systemd/systemd && echo OK
            echo -n "python: "    && python --version
            echo -n "sudo: "      && sudo --version | head -1
            echo -n "SUPPORTED: " && test -f /usr/share/i18n/SUPPORTED && echo OK
            echo -n "en_US: "     && test -f /usr/share/i18n/locales/en_US && echo OK
            echo -n "ru_RU: "     && test -f /usr/share/i18n/locales/ru_RU && echo OK
            echo -n "locale-gen: " && which locale-gen
            echo "=== Image contract: PASS ==="
          '
```

**Step 3: Update test job dependency**

Change the `test` job from:

```yaml
  test:
    needs: detect
    if: needs.detect.outputs.empty == 'false'
```

To:

```yaml
  test:
    needs: [detect, build-image]
    if: always() && needs.detect.outputs.empty == 'false' && needs.build-image.result != 'failure'
```

This ensures:
- `test` runs when `build-image` is **skipped** (no Dockerfile change) — `always()` overrides the default skip-on-skipped-dependency
- `test` does NOT run when `build-image` **fails** — broken image = no point testing
- `test` does NOT run when no roles changed — `empty == 'false'` check

**Step 4: Commit**

```bash
git add .github/workflows/molecule.yml
git commit -m "ci(molecule): rebuild image before tests when Dockerfile changes"
```

---

### Task 4: Update memory — mark TODOs as done

**Files:**
- Modify: `/Users/umudrakov/.claude/projects/-Users-umudrakov-Documents-bootstrap/memory/MEMORY.md`

**Step 1: Update memory**

Change the three TODO lines:
- `Image contract (TODO)` → `Image contract` — implemented in `ansible/molecule/README.md`
- `Image smoke test (TODO)` → `Image smoke test` — verify job in `build-arch-image.yml` and `molecule.yml`
- `Build→test dependency (TODO)` → `Build→test dependency` — conditional `build-image` job in `molecule.yml`

**Step 2: Commit (not needed — memory is not in git)**
