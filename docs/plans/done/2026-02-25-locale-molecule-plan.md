# Plan: locale role -- Vagrant KVM molecule scenario

**Date:** 2026-02-25
**Role:** `ansible/roles/locale/`
**Status:** Draft

## 1. Current State

### Existing Scenarios

| Scenario | Driver | Platforms | Prepare | Converge | Verify |
|----------|--------|-----------|---------|----------|--------|
| `default` | default (localhost) | Localhost only | none | shared/converge.yml | shared/verify.yml |
| `docker` | docker | Archlinux-systemd (custom image) | docker/prepare.yml | shared/converge.yml | shared/verify.yml |

No Vagrant scenario exists. Docker scenario tests Arch Linux only.

### What the Role Does

Execution pipeline: `validate -> generate -> verify -> configure`

1. **Validate** (`tasks/validate/main.yml`) -- checks that `locale_list` is non-empty, `locale_default` is in `locale_list`, all `locale_lc_overrides` values are in `locale_list`. Soft-fail via `locale_skip` fact.
2. **Generate** (`tasks/generate/{archlinux,debian,redhat,void}.yml`) -- distro-specific locale generation. Arch and Debian both use `community.general.locale_gen`. RedHat installs `glibc-langpack-*` packages. Void uses `lineinfile` + `xbps-reconfigure`.
3. **Verify** (`tasks/verify/glibc.yml`) -- runs `locale -a`, normalizes output, checks all requested locales are present. Soft-fail via `locale_verify_ok` fact.
4. **Configure** (`tasks/configure/glibc.yml`) -- templates `/etc/locale.conf` with `LANG` and `LC_*` overrides. Only runs if verify passed.

Report phases are emitted via the `common` role at each step (tagged `report`).

### Shared Test Files

**`molecule/shared/converge.yml`** applies the role with:
- `locale_list: ["en_US.UTF-8", "ru_RU.UTF-8"]`
- `locale_lc_overrides: {LC_TIME: "ru_RU.UTF-8"}`

**`molecule/shared/verify.yml`** checks:
1. `locale -a` output contains both locales (normalized comparison)
2. `/etc/locale.conf` contains `LANG=en_US.UTF-8`
3. `/etc/locale.conf` contains `LC_TIME=ru_RU.UTF-8`
4. Smoke test: runs `locale` with explicit env, asserts LANG and LC_TIME in output

### Docker Prepare

`molecule/docker/prepare.yml` does two things specific to the stripped Arch container image:
1. Seeds `/usr/share/i18n/SUPPORTED` with `en_US.UTF-8 UTF-8` and `ru_RU.UTF-8 UTF-8`
2. Seeds `/etc/locale.gen` with commented entries `#en_US.UTF-8 UTF-8` and `#ru_RU.UTF-8 UTF-8`

These are needed because the custom Docker image ships without locale definitions. Real VMs (Arch and Ubuntu) already have these files populated by their base install.

## 2. Cross-Platform Analysis

### Arch Linux Locale Mechanics

| Aspect | Details |
|--------|---------|
| Definition file | `/etc/locale.gen` -- uncomment lines to enable locales |
| Generation command | `locale-gen` (runs automatically when `community.general.locale_gen` uncomments a line) |
| System locale config | `/etc/locale.conf` -- `LANG=...` and `LC_*=...` |
| `localectl` | Available (systemd-based) |
| Python dependency | `locale-gen` is a shell script; no extra Python packages needed |
| Pre-installed locales | `generic/arch` Vagrant box: typically only `C`, `C.UTF-8`, `POSIX` |
| Package for locale support | `glibc` (always installed) |

### Ubuntu Locale Mechanics

| Aspect | Details |
|--------|---------|
| Definition file | `/etc/locale.gen` -- same format as Arch, but managed by `locale-gen` from the `locales` package |
| Generation command | `locale-gen` (same behavior as Arch; `community.general.locale_gen` calls it) |
| System locale config | `/etc/default/locale` (written by `update-locale`), but this role writes `/etc/locale.conf` |
| `localectl` | Available (systemd-based, reads `/etc/locale.conf` if present) |
| Pre-installed locales | `bento/ubuntu-24.04` Vagrant box: typically `en_US.UTF-8` pre-generated |
| Package for locale support | `locales` package MUST be installed (provides `locale-gen`, `/etc/locale.gen`, `/usr/share/i18n/localedata`) |

### Key Differences Affecting Tests

| Concern | Arch | Ubuntu | Impact on Vagrant Scenario |
|---------|------|--------|---------------------------|
| `locale-gen` source | Built-in (glibc) | `locales` package | prepare.yml must install `locales` on Ubuntu |
| `/etc/locale.gen` | Present after install | Present only if `locales` package installed | prepare.yml dependency |
| `/etc/locale.conf` | Native systemd path | Non-standard (Ubuntu uses `/etc/default/locale`) | Role's `configure/glibc.yml` writes `/etc/locale.conf` on ALL distros -- this works on Ubuntu because systemd reads it, but is not the Ubuntu convention |
| `locale -a` output format | `en_US.utf8` (lowercase, no hyphen/dot) | `en_US.utf8` (same normalized form) | verify.yml normalization already handles this -- no change needed |
| `community.general.locale_gen` | Uncomments in `/etc/locale.gen`, runs `locale-gen` | Same behavior (detects Debian family, uses same approach) | Both use identical task file (`generate/debian.yml` = `generate/archlinux.yml`). Module internally handles distro differences |
| `ru_RU.UTF-8` availability | `/etc/locale.gen` has commented entries for all glibc locales | `/etc/locale.gen` also has all entries if `locales` package installed | No special handling needed |
| pacman keyring staleness | `generic/arch` box has stale keys | N/A | prepare.yml must refresh keyring on Arch |

### `/etc/locale.conf` on Ubuntu

The role writes `/etc/locale.conf` on all distros via `configure/glibc.yml`. On Ubuntu, the traditional file is `/etc/default/locale` (written by `update-locale`). However, systemd on Ubuntu reads `/etc/locale.conf` if it exists, and it takes priority over `/etc/default/locale`. The verify.yml reads `/etc/locale.conf` directly via `slurp`, so this works correctly on both platforms without changes.

## 3. Vagrant Scenario

### `molecule/vagrant/molecule.yml`

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: generic/arch
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: bento/ubuntu-24.04
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

**Notes:**
- `skip-tags: report` -- the `common` role (report_phase/report_render) is not under test and adds noise. Skipping keeps output clean and avoids needing the `common` role in the test path.
- No `inventory.host_vars` block needed -- Vagrant VMs are real SSH hosts, not localhost.
- Memory 2048 MB is sufficient for locale generation (no heavy compilation).

### `molecule/vagrant/prepare.yml`

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Bootstrap Python on Arch (raw -- no Python required)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts
      ansible.builtin.gather_facts:

    - name: Refresh pacman keyring on Arch (generic/arch box has stale keys)
      ansible.builtin.shell: |
        sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
        pacman -Sy --noconfirm archlinux-keyring
        sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
        pacman-key --populate archlinux
      args:
        executable: /bin/bash
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade on Arch (ensures glibc/locale-gen compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Ensure locales package is installed (Ubuntu)
      ansible.builtin.apt:
        name: locales
        state: present
      when: ansible_facts['os_family'] == 'Debian'
```

**Why each task exists:**

1. **Bootstrap Python on Arch** -- `generic/arch` box may not have Python installed. `raw` module does not require Python on the target. The `|| true` ensures it is a no-op on Ubuntu.
2. **Gather facts** -- needed after Python bootstrap for `ansible_facts['os_family']` conditionals.
3. **Refresh pacman keyring** -- `generic/arch` Vagrant boxes have stale PGP keys that prevent package installs. Temporarily disabling `SigLevel` allows refreshing the keyring itself.
4. **Full system upgrade on Arch** -- ensures glibc and locale-gen are current. Stale Arch installs may have broken locale generation due to library mismatches.
5. **Update apt cache on Ubuntu** -- standard apt preparation step.
6. **Ensure locales package on Ubuntu** -- `community.general.locale_gen` requires `locale-gen` binary and `/etc/locale.gen`, both provided by the `locales` package. The `bento/ubuntu-24.04` box likely has it installed, but this is a safety net. Without it, `locale-gen` would not exist and the role would fail.

## 4. Shared verify.yml Cross-Platform Fixes

The existing `molecule/shared/verify.yml` is **already cross-platform compatible**. No changes are required. Here is the analysis:

### Task-by-task review

| # | Task | Arch | Ubuntu | Cross-platform? |
|---|------|------|--------|-----------------|
| 1 | `locale -a` | Works | Works | Yes |
| 2 | Assert locales in `locale -a` (normalized) | `en_US.utf8` normalized to `enus utf8` | Same format | Yes -- normalization handles both |
| 3 | `slurp /etc/locale.conf` | Native path | Non-standard but file exists (role creates it) | Yes |
| 4 | Assert `LANG=` in locale.conf | String match | String match | Yes |
| 5 | Assert `LC_TIME=` in locale.conf | String match | String match | Yes |
| 6 | `locale` command with explicit env | Works | Works | Yes |
| 7 | Assert LANG in locale output | String match | String match | Yes |
| 8 | Assert LC_TIME in locale output | String match | String match | Yes |

**Why no platform guards are needed:**
- The role writes `/etc/locale.conf` on all distros (not `/etc/default/locale`), so the slurp target is consistent.
- The `locale -a` command output format is glibc-standard across both Arch and Ubuntu.
- The smoke test uses explicit `environment:` to set LANG/LC_TIME, so it does not depend on system-level locale activation (which would differ between `/etc/locale.conf` and `/etc/default/locale`).

### One consideration: `/etc/locale.conf` existence on Ubuntu

On a fresh Ubuntu install, `/etc/locale.conf` does not exist until the role creates it. The verify task that does `slurp /etc/locale.conf` will only run after converge, so the file will always exist. This is safe.

If a future test adds a "pre-converge verify" step, it would need a `stat` + `when` guard on Ubuntu. Currently not needed.

## 5. Converge.yml Updates

**No changes needed to `molecule/shared/converge.yml`.**

The converge playbook passes:
- `locale_list: ["en_US.UTF-8", "ru_RU.UTF-8"]`
- `locale_lc_overrides: {LC_TIME: "ru_RU.UTF-8"}`

These values are distro-agnostic. The role's `tasks/main.yml` dispatches to the correct `generate/*.yml` file via `with_first_found` on `ansible_facts['os_family']`:
- Arch -> `generate/archlinux.yml` (uses `community.general.locale_gen`)
- Ubuntu -> `generate/debian.yml` (uses `community.general.locale_gen`)

Both task files are identical in content. The `community.general.locale_gen` module internally detects the distro and adjusts behavior (e.g., calling `dpkg-reconfigure locales` vs `locale-gen` directly).

## 6. Implementation Order

1. **Create directory** `ansible/roles/locale/molecule/vagrant/`

2. **Create `molecule/vagrant/molecule.yml`** -- copy from Section 3 above.

3. **Create `molecule/vagrant/prepare.yml`** -- copy from Section 3 above.

4. **Local smoke test** (if KVM available):
   ```bash
   cd ansible/roles/locale
   molecule create -s vagrant
   molecule converge -s vagrant
   molecule verify -s vagrant
   molecule destroy -s vagrant
   ```
   If no local KVM, skip to step 5 and rely on CI.

5. **Run full test sequence**:
   ```bash
   cd ansible/roles/locale
   molecule test -s vagrant
   ```
   This runs: syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy.

6. **Verify idempotence passes** -- the `community.general.locale_gen` module should be idempotent (no changes on second run). If idempotence fails on Ubuntu, investigate whether `locale_gen` re-runs `locale-gen` unnecessarily. Known issue: some versions of the module report `changed` even when the locale is already generated. If this occurs, the fix would be to add `changed_when` logic, but this is a role code change, not a test change.

7. **Commit** the two new files:
   - `ansible/roles/locale/molecule/vagrant/molecule.yml`
   - `ansible/roles/locale/molecule/vagrant/prepare.yml`

## 7. Risks / Notes

### locale-gen in containers vs VMs

The Docker prepare.yml (`molecule/docker/prepare.yml`) seeds `/usr/share/i18n/SUPPORTED` and `/etc/locale.gen` manually because the custom Arch Docker image is stripped. **Vagrant VMs do not need this** -- both `generic/arch` and `bento/ubuntu-24.04` ship with full glibc locale infrastructure. The Vagrant prepare.yml should NOT replicate the Docker prepare tasks.

### `community.general.locale_gen` idempotence on Ubuntu

The `community.general.locale_gen` module checks `/etc/locale.gen` for the requested locale and runs `locale-gen` only if the locale is not already generated. On Ubuntu, `en_US.UTF-8` is typically pre-generated. The module should report `ok` (not `changed`) for `en_US.UTF-8` on second run, and `changed` only for `ru_RU.UTF-8` on first run. Idempotence test should pass on second full converge.

### `/etc/locale.conf` vs `/etc/default/locale` on Ubuntu

The role writes `/etc/locale.conf` on Ubuntu. This is non-standard for Ubuntu but functional because systemd reads this file. It does NOT write `/etc/default/locale`. This means:
- `localectl status` will show the correct locale (reads `/etc/locale.conf`).
- `cat /etc/default/locale` may show a stale or different locale.
- The verify.yml tests `slurp /etc/locale.conf`, so this is not a test problem.
- This is a **role design decision**, not a test gap. If the role should also update `/etc/default/locale` on Debian-family, that is a separate enhancement.

### Encoding edge cases

The `locale -a` output normalizes encoding names differently across systems:
- `en_US.UTF-8` appears as `en_US.utf8` in `locale -a` output on both Arch and Ubuntu.
- The verify.yml normalization (`regex_replace('[\\-\\.]', '')`) strips dots and hyphens, producing `enus utf8` vs `enus utf8` -- identical on both platforms.
- No edge case exists for the two test locales (`en_US.UTF-8`, `ru_RU.UTF-8`).

### Vagrant box availability

| Box | Provider | Status |
|-----|----------|--------|
| `generic/arch` | libvirt | Maintained by Vagrant `generic` project. Updated monthly. |
| `bento/ubuntu-24.04` | libvirt | Maintained by Chef Bento project. Stable. |

If `generic/arch` becomes unavailable, `archlinux/archlinux` (official Arch Vagrant box) is an alternative. The `package_manager` role design doc used `archlinux/archlinux`, but the actual implementation uses `generic/arch`. Either works; `generic/arch` is chosen here for consistency with the existing codebase.

### No Void Linux or RedHat testing

Void Linux has no maintained Vagrant box. RedHat/Fedora could be added later by extending the `platforms` list. Neither is in scope for this plan.

### `common` role dependency

The locale role includes `common` role tasks for report rendering. The `skip-tags: report` option in molecule.yml ensures these tasks are skipped during testing. The `common` role does NOT need to be present in `ANSIBLE_ROLES_PATH` for the skipped tasks -- Ansible skips the entire `include_role` when all its tags are excluded.

**Correction:** Actually, `include_role` with `tags` may still attempt to resolve the role even when tags are skipped, depending on Ansible version. If `common` role is not found, the syntax check may fail. Since `ANSIBLE_ROLES_PATH` is set to `${MOLECULE_PROJECT_DIRECTORY}/../` (which is `ansible/roles/`), the `common` role IS available at `ansible/roles/common/`. No issue.
