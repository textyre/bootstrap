# Design: CalVer Releases for arch-images and ubuntu-images

**Date:** 2026-02-28
**Status:** Approved

## Problem

The current rolling `boxes` release in both image repos accumulates versioned assets
(`arch-base-20260228.box`, `arch-base-latest.box`, etc.) under a single release tag.
This produces a cluttered UI and makes it unclear which build corresponds to which
commit. The user wants clean, classic CalVer releases.

## Goal

- One GitHub Release per Vagrant build, tagged with CalVer (`v2026.02.28`)
- A single asset per release (`arch-base.box` / `ubuntu-base.box`) — versioning lives in the tag
- Bootstrap `box_url` auto-resolves to the latest release without any manual updates

## Decision

**Approach A: CalVer release tags + `/releases/latest/download/` redirect**

GitHub automatically redirects `releases/latest/download/FILENAME` to the same
filename in the most recent non-prerelease release. Bootstrap uses this stable URL
and always gets the newest box when a new CalVer release is published.

## Design

### Release structure

Each Vagrant build in both image repos creates a new GitHub Release:

| Field   | Value                                               |
|---------|-----------------------------------------------------|
| Tag     | `v2026.02.28` (CalVer `vYYYY.MM.DD`)               |
| Title   | `arch-base v2026.02.28`                             |
| Asset   | `arch-base.box` (single file, constant name)        |
| Notes   | "Vagrant box built from commit `${{ github.sha }}`" |

No `--clobber`, no dated copies, no rolling `boxes` release.

### Workflow changes (arch-images and ubuntu-images)

Replace the "Publish to GitHub Releases" step:

```yaml
- name: Publish to GitHub Releases
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  run: |
    VERSION="${{ steps.version.outputs.date }}"
    gh release create "v${VERSION}" \
      --title "arch-base v${VERSION}" \
      --notes "Vagrant box built from commit ${{ github.sha }}." \
      arch-base.box
```

Same pattern for ubuntu-images, substituting `ubuntu-base`.

### Bootstrap changes

In all vagrant `molecule.yml` files (22+ across ansible/roles), update `box_url`:

```yaml
# arch-images
box_url: https://github.com/textyre/arch-images/releases/latest/download/arch-base.box

# ubuntu-images
box_url: https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box
```

### Cleanup

Delete the existing `boxes` rolling release from both repos (via `gh release delete boxes`).

## Why this works

`/releases/latest/download/FILENAME` is a stable GitHub redirect to the same
filename in the most recent non-prerelease release. When a new CalVer release is
published, it automatically becomes the "latest", and bootstrap picks it up on the
next `vagrant up` without any config changes.

## Out of scope

- Keeping dated assets per release (YAGNI — versioning is in the tag)
- Prerelease / draft releases
- Renovate auto-bumping box_url in bootstrap (box is fetched at runtime, not pinned)
