# CalVer Releases Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace rolling `boxes` releases in arch-images and ubuntu-images with per-build CalVer GitHub Releases (`v2026.02.28`), and update all 27 bootstrap `box_url` references to use GitHub's `/releases/latest/download/` redirect.

**Architecture:** Each Vagrant build creates a new `gh release create "v${VERSION}"` with a single asset `arch-base.box` / `ubuntu-base.box`. Bootstrap always points to `/releases/latest/download/BOXNAME.box`, which GitHub automatically redirects to the same-named asset in the most recent non-prerelease release.

**Tech Stack:** GitHub Actions (`gh` CLI), YAML (`sed` replace), GitHub Releases API

---

## Execution order matters

Bootstrap `box_url` must NOT be updated until a CalVer release actually exists in both
image repos (otherwise `vagrant up` breaks). Order:

1. Update arch-images workflow → push → CI creates first CalVer release
2. Update ubuntu-images workflow → push → CI creates first CalVer release
3. Update bootstrap box_urls → commit → push
4. Delete old `boxes` rolling releases

---

### Task 1: Update arch-images publish step

**Files:**
- Modify: `/Users/umudrakov/Documents/arch-images/.github/workflows/build.yml:237-255`

**Step 1: Replace the "Publish to GitHub Releases" run block**

Open `/Users/umudrakov/Documents/arch-images/.github/workflows/build.yml`.
Replace the entire `run: |` block under `- name: Publish to GitHub Releases` (lines 241–255):

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

The old block had `cp *-latest.box`, `gh release view boxes || gh release create boxes`, and `gh release upload ... --clobber`. All of that is replaced by a single `gh release create` with the box file as a positional argument (which uploads it as an asset automatically).

**Step 2: Commit and push**

```bash
cd /Users/umudrakov/Documents/arch-images
git add .github/workflows/build.yml
git commit -m "feat(releases): switch to CalVer releases (v2026.02.28)"
git push origin main
```

**Step 3: Trigger CI and confirm CalVer release created**

```bash
cd /Users/umudrakov/Documents/arch-images
gh workflow run build.yml --field artifact=vagrant
```

Wait for the workflow to complete:

```bash
gh run list --workflow=build.yml --limit=3
# Watch until status = completed / success
gh run watch $(gh run list --workflow=build.yml --limit=1 --json databaseId -q '.[0].databaseId')
```

Confirm a CalVer release was created:

```bash
gh release list
# Expected: "arch-base v2026.02.28   Latest   v2026.02.28   ..."
gh release view v2026.02.28
# Expected: one asset "arch-base.box"
```

---

### Task 2: Update ubuntu-images publish step

**Files:**
- Modify: `/Users/umudrakov/Documents/ubuntu-images/.github/workflows/build.yml:238-256`

**Step 1: Replace the "Publish to GitHub Releases" run block**

Open `/Users/umudrakov/Documents/ubuntu-images/.github/workflows/build.yml`.
Replace the entire `run: |` block under `- name: Publish to GitHub Releases`:

```yaml
      - name: Publish to GitHub Releases
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          VERSION="${{ steps.version.outputs.date }}"
          gh release create "v${VERSION}" \
            --title "ubuntu-base v${VERSION}" \
            --notes "Vagrant box built from commit ${{ github.sha }}." \
            ubuntu-base.box
```

**Step 2: Commit and push**

```bash
cd /Users/umudrakov/Documents/ubuntu-images
git add .github/workflows/build.yml
git commit -m "feat(releases): switch to CalVer releases (v2026.02.28)"
git push origin main
```

**Step 3: Trigger CI and confirm CalVer release created**

```bash
cd /Users/umudrakov/Documents/ubuntu-images
gh workflow run build.yml --field artifact=vagrant
gh run watch $(gh run list --workflow=build.yml --limit=1 --json databaseId -q '.[0].databaseId')
```

Confirm:

```bash
gh release list
# Expected: "ubuntu-base v2026.02.28   Latest   v2026.02.28   ..."
gh release view v2026.02.28
# Expected: one asset "ubuntu-base.box"
```

---

### Task 3: Update all bootstrap box_url references

**Files:**
- Modify: 25 files matching `ansible/roles/*/molecule/vagrant/molecule.yml` (arch-base URL)
- Modify: 2 files matching `ansible/roles/*/molecule/vagrant/molecule.yml` (ubuntu-base URL)

**Step 1: Verify current state (count lines to change)**

```bash
cd /Users/umudrakov/Documents/bootstrap
grep -r "releases/download/boxes" ansible --include="*.yml" | wc -l
# Expected: 27
```

**Step 2: Replace arch-base box_url (25 files)**

```bash
cd /Users/umudrakov/Documents/bootstrap
find ansible -name "molecule.yml" -exec sed -i '' \
  's|releases/download/boxes/arch-base-latest\.box|releases/latest/download/arch-base.box|g' \
  {} +
```

**Step 3: Replace ubuntu-base box_url (2 files)**

```bash
find ansible -name "molecule.yml" -exec sed -i '' \
  's|releases/download/boxes/ubuntu-base-latest\.box|releases/latest/download/ubuntu-base.box|g' \
  {} +
```

**Step 4: Verify all replacements were applied**

```bash
grep -r "releases/download/boxes" ansible --include="*.yml" | wc -l
# Expected: 0  (no old URLs remaining)

grep -r "releases/latest/download/arch-base.box" ansible --include="*.yml" | wc -l
# Expected: 25

grep -r "releases/latest/download/ubuntu-base.box" ansible --include="*.yml" | wc -l
# Expected: 2
```

**Step 5: Spot-check one file**

```bash
cat ansible/roles/locale/molecule/vagrant/molecule.yml
# box_url line should read:
# box_url: https://github.com/textyre/arch-images/releases/latest/download/arch-base.box
```

**Step 6: Commit and push**

```bash
git add ansible/
git commit -m "fix(molecule): update box_url to CalVer releases/latest/download"
git push origin master
```

---

### Task 4: Delete old rolling `boxes` releases

**Prerequisite:** CalVer releases exist in both repos AND bootstrap is updated (Tasks 1–3 complete).

**Step 1: Delete boxes release from arch-images**

```bash
cd /Users/umudrakov/Documents/arch-images
gh release delete boxes --yes --cleanup-tag
```

Expected: no error, `boxes` release removed.

**Step 2: Delete boxes release from ubuntu-images**

```bash
cd /Users/umudrakov/Documents/ubuntu-images
gh release delete boxes --yes --cleanup-tag
```

**Step 3: Confirm no boxes release remains**

```bash
cd /Users/umudrakov/Documents/arch-images && gh release list
# Should show only CalVer releases (e.g. v2026.02.28)

cd /Users/umudrakov/Documents/ubuntu-images && gh release list
# Same
```

---

### Task 5: Verify end-to-end

**Step 1: Confirm /releases/latest/download/ redirects resolve**

```bash
curl -sI "https://github.com/textyre/arch-images/releases/latest/download/arch-base.box" \
  | grep -i "location:"
# Expected: Location: .../releases/download/v2026.02.28/arch-base.box
```

```bash
curl -sI "https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box" \
  | grep -i "location:"
# Expected: Location: .../releases/download/v2026.02.28/ubuntu-base.box
```

**Step 2: Verify next CI run in arch-images creates a new CalVer release (not boxes)**

When the next weekly cron or manual dispatch runs, confirm `gh release list` shows a new dated release, not an asset added to an existing one.

**Step 3: Update post-mortem**

Add a note to `docs/troubleshooting/troubleshooting-history-2026-02-28-image-repo-housecleaning.md` section 6 "Known remaining issues" — mark the rolling release design as resolved.

```bash
cd /Users/umudrakov/Documents/bootstrap
git add docs/troubleshooting/troubleshooting-history-2026-02-28-image-repo-housecleaning.md
git commit -m "docs(troubleshooting): note CalVer release migration complete"
git push origin master
```
