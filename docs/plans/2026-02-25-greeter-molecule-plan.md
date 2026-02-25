# Plan: greeter role -- Molecule Testing (Docker + Vagrant)

**Date:** 2026-02-25
**Status:** Draft
**Role:** `ansible/roles/greeter/`

---

## 1. Current State

### What the Role Does

The `greeter` role deploys a custom **ctOS** login theme for **LightDM + web-greeter** on Arch Linux. It is a configuration-only role -- it does NOT install packages (lightdm, web-greeter). The role assumes both are already installed (web-greeter is AUR-only).

**Actions performed (tasks/main.yml):**

1. Deploy `/etc/lightdm/web-greeter.yml` config (from `web-greeter.yml.j2`)
2. Assert greeter dist directory exists locally (`$REPO_ROOT/greeter/dist`)
3. Create theme directory `/usr/share/web-greeter/themes/ctos/`
4. Clean stale assets from theme directory (shell `rm -rf`)
5. Copy built theme files from `greeter_dist_dir` to theme directory (`remote_src: true`)
6. Copy `index.yml` metadata to theme directory (`remote_src: true`)
7. Gather system info: timezone, systemd version, display name/resolution, SSH fingerprint
8. Generate `system-info.json` from template into theme directory
9. Fix permissions on theme directory (shell `chown -R`, `find -exec chmod`)
10. Copy wallpapers from user directory to `/usr/share/backgrounds/` (conditional)

**Templates:**
- `web-greeter.yml.j2` -- web-greeter daemon config (theme name, debug mode, screensaver timeout, secure mode, background images dir)
- `system-info.json.j2` -- JSON metadata displayed in the greeter UI (kernel, hostname, IP, timezone, display info, SSH fingerprint)

**Dependencies:** None declared in `meta/main.yml`. In practice, requires lightdm + web-greeter already installed and `$REPO_ROOT/greeter/dist` to contain built assets.

**Platform support (meta/main.yml):** ArchLinux only.

### Existing Tests

| Scenario | Driver | Platforms | Playbooks |
|----------|--------|-----------|-----------|
| `default/` | default (localhost) | Localhost | Own `converge.yml`, own `verify.yml` |

**converge.yml:**
- Asserts `os_family == Archlinux`
- Loads vault vars from `$MOLECULE_PROJECT_DIRECTORY/inventory/group_vars/all/vault.yml`
- Applies `role: greeter`

**molecule.yml:**
- `driver: default` (unmanaged localhost)
- `vault_password_file` configured
- Test sequence: syntax, converge, verify (no idempotence)
- `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"`

**verify.yml:**
- Check `/etc/lightdm/web-greeter.yml` exists
- Check `/usr/share/web-greeter/themes/ctos` directory exists
- Check `system-info.json` exists and is valid JSON
- Check `index.yml` exists
- Debug summary message

### Known Bug: Template Variable Naming Mismatch

The tasks register variables as `greeter_timezone`, `greeter_systemd_ver`, `greeter_display_name`, `greeter_display_res`, `greeter_ssh_fp_hash`. However, the `system-info.json.j2` template references them with underscore prefix: `_greeter_timezone`, `_greeter_systemd_ver`, `_greeter_display_name`, `_greeter_display_res`, `_greeter_ssh_fp_hash`.

This means `system-info.json` will render all these fields as their default fallback values ("UTC", "unknown", etc.) regardless of actual system state. The existing verify only checks that the JSON file exists and is parseable, not that its values are correct. This bug exists in production but is not exposed by tests.

**Impact on molecule testing:** The template will render successfully (default values are valid JSON), so converge will not fail. Verify should be designed to catch this if/when the bug is fixed.

---

## 2. Display Limitation

**web-greeter requires a running X11 display server (LightDM).** In Docker containers and headless VMs, there is no display server. The greeter binary cannot be launched or functionally tested.

### Test Scope (Config-Only)

All molecule scenarios will test:
- Config file deployment (`/etc/lightdm/web-greeter.yml`)
- Theme directory creation and structure
- `system-info.json` generation and JSON validity
- File permissions and ownership
- Template content correctness

**NOT testable in molecule:**
- Actual greeter rendering
- LightDM integration
- Authentication flow (PAM/lightdm JS API)
- Theme visual appearance

### Additional Docker Constraint: No Built Theme Assets

The role copies built theme files from `greeter_dist_dir` (default: `$REPO_ROOT/greeter/dist`). This directory:
- Exists only on the build host (where `yarn build` has been run)
- Uses `remote_src: true` (copies from target filesystem, NOT controller)
- The Docker container will NOT have these files

**This means tasks 2-6 and 8-9 will FAIL in Docker** unless we either:
1. **Skip theme copy tasks** (use `--skip-tags` or add a molecule-specific tag)
2. **Create stub dist directory in prepare.yml** with minimal fake files
3. **Override `greeter_dist_dir`** to point to a prepared directory inside the container

**Recommended approach:** Option 2 -- create a minimal stub in `prepare.yml`. This allows the full task flow to execute and be tested for idempotence, while using fake asset data. The verify assertions remain meaningful (directory exists, permissions correct, JSON valid).

---

## 3. Cross-Platform Analysis

### Platform Support Decision

The role's `meta/main.yml` declares Arch Linux only. web-greeter is an AUR package with no Debian/Ubuntu equivalent in official repos.

| | Arch Linux | Ubuntu 24.04 |
|---|---|---|
| lightdm | `extra/lightdm` (official) | `apt: lightdm` (universe) |
| web-greeter | AUR: `web-greeter` | Not packaged (build from source or use nody-greeter) |
| Config path | `/etc/lightdm/web-greeter.yml` | Same (if manually installed) |
| Theme path | `/usr/share/web-greeter/themes/` | Same (if manually installed) |

**Verdict:** The Vagrant Ubuntu VM is **not meaningful** for this role. web-greeter is not available on Ubuntu without manual compilation, and the role does not install it. Even the config file path (`/etc/lightdm/web-greeter.yml`) only makes sense when web-greeter is installed.

**Recommendation:** Vagrant scenario should be **Arch-only** (single VM). If Ubuntu support is ever added to the role, it should be a separate effort that includes package installation tasks.

---

## 4. Shared Migration

Move existing `molecule/default/converge.yml` and `molecule/default/verify.yml` to `molecule/shared/`.

### shared/converge.yml (new)

Simplified from current -- remove vault dependency and Arch assertion (let the scenario control platform):

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: greeter
```

**Changes from current default/converge.yml:**
- Removed `vars_files` vault reference (the greeter role has no vault-encrypted variables; the current converge loads it unnecessarily)
- Removed `pre_tasks` Arch assertion (platform enforcement is the scenario's responsibility via platform selection)

### shared/verify.yml (new)

Enhanced from current -- adds content assertions, permissions checks, cross-platform facts:

```yaml
---
- name: Verify greeter role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/defaults/main.yml"

  tasks:

    # ---- web-greeter.yml config ----

    - name: Stat web-greeter.yml
      ansible.builtin.stat:
        path: /etc/lightdm/web-greeter.yml
      register: _greeter_verify_config

    - name: Assert web-greeter.yml exists with correct permissions
      ansible.builtin.assert:
        that:
          - _greeter_verify_config.stat.exists
          - _greeter_verify_config.stat.isreg
          - _greeter_verify_config.stat.pw_name == 'root'
          - _greeter_verify_config.stat.gr_name == 'root'
          - _greeter_verify_config.stat.mode == '0644'
        fail_msg: "/etc/lightdm/web-greeter.yml missing or wrong permissions"

    - name: Read web-greeter.yml content
      ansible.builtin.slurp:
        src: /etc/lightdm/web-greeter.yml
      register: _greeter_verify_config_raw

    - name: Set web-greeter.yml text fact
      ansible.builtin.set_fact:
        _greeter_verify_config_text: "{{ _greeter_verify_config_raw.content | b64decode }}"

    - name: Assert web-greeter.yml contains expected theme
      ansible.builtin.assert:
        that:
          - "'theme: ' ~ greeter_theme in _greeter_verify_config_text"
        fail_msg: "web-greeter.yml does not reference theme '{{ greeter_theme }}'"

    - name: Assert web-greeter.yml contains screensaver_timeout
      ansible.builtin.assert:
        that:
          - "'screensaver_timeout:' in _greeter_verify_config_text"
        fail_msg: "web-greeter.yml missing screensaver_timeout directive"

    - name: Assert web-greeter.yml contains background_images_dir
      ansible.builtin.assert:
        that:
          - "'background_images_dir:' in _greeter_verify_config_text"
        fail_msg: "web-greeter.yml missing background_images_dir directive"

    # ---- Theme directory ----

    - name: Stat ctOS theme directory
      ansible.builtin.stat:
        path: "/usr/share/web-greeter/themes/{{ greeter_theme }}"
      register: _greeter_verify_theme_dir

    - name: Assert theme directory exists
      ansible.builtin.assert:
        that:
          - _greeter_verify_theme_dir.stat.exists
          - _greeter_verify_theme_dir.stat.isdir
          - _greeter_verify_theme_dir.stat.pw_name == 'root'
          - _greeter_verify_theme_dir.stat.mode == '0755'
        fail_msg: "Theme directory /usr/share/web-greeter/themes/{{ greeter_theme }} missing or wrong permissions"

    # ---- system-info.json ----

    - name: Stat system-info.json
      ansible.builtin.stat:
        path: "/usr/share/web-greeter/themes/{{ greeter_theme }}/system-info.json"
      register: _greeter_verify_sysinfo

    - name: Assert system-info.json exists with correct permissions
      ansible.builtin.assert:
        that:
          - _greeter_verify_sysinfo.stat.exists
          - _greeter_verify_sysinfo.stat.isreg
          - _greeter_verify_sysinfo.stat.pw_name == 'root'
          - _greeter_verify_sysinfo.stat.mode == '0644'
        fail_msg: "system-info.json missing or wrong permissions"

    - name: Validate system-info.json is valid JSON
      ansible.builtin.command: python3 -m json.tool "/usr/share/web-greeter/themes/{{ greeter_theme }}/system-info.json"
      changed_when: false

    - name: Read system-info.json content
      ansible.builtin.slurp:
        src: "/usr/share/web-greeter/themes/{{ greeter_theme }}/system-info.json"
      register: _greeter_verify_sysinfo_raw

    - name: Parse system-info.json
      ansible.builtin.set_fact:
        _greeter_verify_sysinfo_data: "{{ _greeter_verify_sysinfo_raw.content | b64decode | from_json }}"

    - name: Assert system-info.json contains required keys
      ansible.builtin.assert:
        that:
          - "'kernel' in _greeter_verify_sysinfo_data"
          - "'hostname' in _greeter_verify_sysinfo_data"
          - "'project_version' in _greeter_verify_sysinfo_data"
          - "'ip_address' in _greeter_verify_sysinfo_data"
          - "'timezone' in _greeter_verify_sysinfo_data"
          - "'machine_id' in _greeter_verify_sysinfo_data"
        fail_msg: "system-info.json missing required keys"

    - name: Assert project_version matches configured version
      ansible.builtin.assert:
        that:
          - "_greeter_verify_sysinfo_data.project_version == greeter_ctos_version"
        fail_msg: >-
          system-info.json project_version '{{ _greeter_verify_sysinfo_data.project_version }}'
          does not match greeter_ctos_version '{{ greeter_ctos_version }}'

    # ---- index.yml ----

    - name: Stat index.yml
      ansible.builtin.stat:
        path: "/usr/share/web-greeter/themes/{{ greeter_theme }}/index.yml"
      register: _greeter_verify_index

    - name: Assert index.yml exists
      ansible.builtin.assert:
        that:
          - _greeter_verify_index.stat.exists
          - _greeter_verify_index.stat.isreg
          - _greeter_verify_index.stat.mode == '0644'
        fail_msg: "index.yml missing or wrong permissions in theme directory"

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Greeter offline verify passed: web-greeter.yml deployed (root:root 0644,
          theme={{ greeter_theme }}), theme directory exists with correct permissions,
          system-info.json valid with required keys, index.yml present.
```

**Key improvements over current verify.yml:**
- Uses `_greeter_verify_*` register prefix (project convention)
- Loads `defaults/main.yml` to get `greeter_theme` and `greeter_ctos_version` as variables instead of hardcoding `"ctos"`
- Checks file permissions (owner, group, mode) not just existence
- Validates config file content (theme name, key directives)
- Parses `system-info.json` and checks required keys and `project_version` value
- Uses `from_json` for structured JSON validation

---

## 5. Docker Scenario

### Greeter-Specific Challenges in Docker

1. **No `$REPO_ROOT/greeter/dist`** inside the container -- the built theme assets are on the host
2. **No display hardware** -- `/sys/class/drm/card*` does not exist; display detection commands return empty
3. **No SSH host keys by default** -- `ssh-keygen -lf` will fail
4. **`timedatectl` may not work** in container (depends on systemd in container)

All of these are handled gracefully by the role (`failed_when: false` on all info-gathering tasks, templates use `| default('unknown')` fallbacks). The only hard failure is the `greeter_dist_dir` assertion (task 2: "Assert greeter dist directory exists").

### prepare.yml Strategy

Create a minimal stub directory structure that satisfies the role's assertions and copy tasks:

```yaml
---
- name: Prepare greeter environment
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Update pacman package cache
      community.general.pacman:
        update_cache: true

    - name: Install python3 (required for JSON validation in verify)
      community.general.pacman:
        name: python
        state: present

    - name: Create stub greeter dist directory
      ansible.builtin.file:
        path: /opt/greeter-stub/dist/assets
        state: directory
        mode: '0755'

    - name: Create stub index.html
      ansible.builtin.copy:
        content: |
          <!DOCTYPE html>
          <html><head><title>ctOS Greeter Stub</title></head>
          <body>Stub for molecule testing</body></html>
        dest: /opt/greeter-stub/dist/index.html
        mode: '0644'

    - name: Create stub index.yml
      ansible.builtin.copy:
        content: |
          primary_html: "index.html"
          secondary_html: "index.html"
        dest: /opt/greeter-stub/index.yml
        mode: '0644'

    - name: Create lightdm config directory
      ansible.builtin.file:
        path: /etc/lightdm
        state: directory
        mode: '0755'
```

### molecule/docker/molecule.yml

```yaml
---
driver:
  name: docker

platforms:
  - name: Archlinux-systemd
    image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/bootstrap/arch-systemd:latest}"
    pre_build_image: true
    command: /usr/lib/systemd/systemd
    cgroupns_mode: host
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      - /run
      - /tmp
    privileged: true
    dns_servers:
      - 8.8.8.8
      - 8.8.4.4

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
    REPO_ROOT: "/opt/greeter-stub"
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

**Key design decisions:**
- `REPO_ROOT: "/opt/greeter-stub"` -- overrides the environment variable so `greeter_dist_dir` and `greeter_index_yml` resolve to the stub paths created in `prepare.yml`
- `skip-tags: report` -- skips the debug report task at end of role
- Includes `idempotence` in test sequence (the current default scenario does not)

### Idempotence Concern

Task "Clean ctOS theme before deploy" uses `changed_when: true` (always reports changed). This **will break idempotence**. Two options:

1. **Tag it for skip in molecule** -- add a `molecule-notest` tag to the clean task and add it to `skip-tags`
2. **Fix the task** -- use `ansible.builtin.file: state: absent` instead of shell, which is properly idempotent

The clean task also uses shell `rm -rf` which is a code smell for Ansible. However, this is an existing role design decision (cleaning stale hashed webpack bundles where filenames are unpredictable). For the testing plan, recommend adding `molecule-notest` tag or accepting that idempotence will show 1 changed task on the clean step.

**Additionally**, the "Fix ctOS theme file permissions" task (shell with `chown`/`find`/`chmod`) also uses `changed_when: true` and will break idempotence for the same reason.

**Recommendation for molecule:** Either skip `idempotence` in test sequence, or accept 2 "changed" tasks as known false positives from shell tasks. Alternatively, both shell tasks could be tagged `molecule-notest`.

---

## 6. Vagrant Scenario

### Platform Selection

Arch-only (see Section 3 analysis). web-greeter is not available on Ubuntu, making Ubuntu testing meaningless for this role.

### molecule/vagrant/molecule.yml

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

provisioner:
  name: ansible
  options:
    skip-tags: report
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
    REPO_ROOT: "/opt/greeter-stub"
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

**Differences from Docker scenario:**
- `driver: vagrant` with `provider: libvirt`
- Single platform (no Ubuntu)
- Same `REPO_ROOT` stub approach as Docker

### molecule/vagrant/prepare.yml

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

    - name: Full system upgrade on Arch
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Create stub greeter dist directory
      ansible.builtin.file:
        path: /opt/greeter-stub/dist/assets
        state: directory
        mode: '0755'

    - name: Create stub index.html
      ansible.builtin.copy:
        content: |
          <!DOCTYPE html>
          <html><head><title>ctOS Greeter Stub</title></head>
          <body>Stub for molecule testing</body></html>
        dest: /opt/greeter-stub/dist/index.html
        mode: '0644'

    - name: Create stub index.yml
      ansible.builtin.copy:
        content: |
          primary_html: "index.html"
          secondary_html: "index.html"
        dest: /opt/greeter-stub/index.yml
        mode: '0644'

    - name: Create lightdm config directory
      ansible.builtin.file:
        path: /etc/lightdm
        state: directory
        mode: '0755'
```

**Notes:**
- Includes full keyring refresh + system upgrade (proven pattern from `package_manager` vagrant prepare)
- Python bootstrap via raw module (generic/arch boxes may not have Python)
- Same stub directory creation as Docker prepare
- `/etc/lightdm` directory must be created manually since we are not installing the lightdm package

---

## 7. Verify.yml Design -- Detailed Assertion Matrix

### Assertions by Category

| # | Category | Assertion | Path / Check | Fail Message |
|---|----------|-----------|-------------|-------------|
| 1 | Config | File exists | `/etc/lightdm/web-greeter.yml` | Missing |
| 2 | Config | Permissions | `root:root 0644` | Wrong perms |
| 3 | Config | Content: theme | `theme: ctos` in content | Wrong theme |
| 4 | Config | Content: screensaver_timeout | Directive present | Missing directive |
| 5 | Config | Content: background_images_dir | Directive present | Missing directive |
| 6 | Theme dir | Directory exists | `/usr/share/web-greeter/themes/ctos/` | Missing |
| 7 | Theme dir | Permissions | `root 0755` | Wrong perms |
| 8 | JSON | File exists | `themes/ctos/system-info.json` | Missing |
| 9 | JSON | Permissions | `root:root 0644` | Wrong perms |
| 10 | JSON | Valid JSON | `python3 -m json.tool` | Invalid JSON |
| 11 | JSON | Required keys | kernel, hostname, project_version, ip_address, timezone, machine_id | Missing keys |
| 12 | JSON | project_version value | Matches `greeter_ctos_version` | Version mismatch |
| 13 | Metadata | index.yml exists | `themes/ctos/index.yml` | Missing |
| 14 | Metadata | Permissions | `0644` | Wrong perms |

### What is NOT Asserted (by design)

- **Package installation** -- role does not install packages
- **Service state** -- lightdm is not started/enabled by this role
- **Wallpaper deployment** -- conditional on user wallpaper directory existing (not present in stub)
- **system-info.json value correctness** beyond `project_version` -- display, SSH, timezone values depend on hardware/services not present in test environment

### Variable Loading

The verify playbook includes `vars_files: defaults/main.yml` to access `greeter_theme` and `greeter_ctos_version` without hardcoding them. This ensures verify stays correct if defaults change.

---

## 8. Implementation Order

### Phase 1: Create shared/ directory and migrate playbooks

1. Create `ansible/roles/greeter/molecule/shared/` directory
2. Write `molecule/shared/converge.yml` (simplified, no vault)
3. Write `molecule/shared/verify.yml` (enhanced assertions from Section 4)

### Phase 2: Docker scenario

4. Create `ansible/roles/greeter/molecule/docker/` directory
5. Write `molecule/docker/molecule.yml` (from Section 5)
6. Write `molecule/docker/prepare.yml` (stub dist + pacman cache update)
7. Run `molecule test -s docker` and debug

### Phase 3: Update default/ scenario to use shared playbooks

8. Update `molecule/default/molecule.yml` to reference `../shared/converge.yml` and `../shared/verify.yml`
9. Delete `molecule/default/converge.yml` and `molecule/default/verify.yml` (now in shared/)
10. Run `molecule test -s default` to verify migration (localhost scenario still works)

### Phase 4: Vagrant scenario

11. Create `ansible/roles/greeter/molecule/vagrant/` directory
12. Write `molecule/vagrant/molecule.yml` (from Section 6)
13. Write `molecule/vagrant/prepare.yml` (from Section 6)
14. Run `molecule test -s vagrant` and debug

### Phase 5: Validation

15. Run all scenarios sequentially and confirm all pass:
    ```bash
    cd ansible/roles/greeter
    molecule test -s docker
    molecule test -s vagrant
    ```
16. Review idempotence results for the 2 shell tasks (clean + fix permissions)

---

## 9. Risks / Notes

### Risk 1: REPO_ROOT Override May Mask Real Failures

By setting `REPO_ROOT=/opt/greeter-stub` in the provisioner env, we bypass the role's assertion that `greeter_dist_dir` exists with real built assets. If the role's path logic changes or the dist directory structure changes, the stub may no longer be representative.

**Mitigation:** The stub mirrors the real dist structure (`dist/index.html`, `dist/assets/`, `index.yml`). Keep the stub updated if the greeter project's build output changes. Add a comment in `prepare.yml` documenting what the stub represents.

### Risk 2: Shell Tasks Break Idempotence

Two tasks use `shell` with `changed_when: true`:
- "Clean ctOS theme before deploy" (line 41-47)
- "Fix ctOS theme file permissions" (line 140-146)

These will always report `changed`, causing the idempotence check to fail.

**Options:**
1. Remove `idempotence` from `test_sequence` (accept the limitation)
2. Tag both tasks with `molecule-notest` and add to `skip-tags`
3. Refactor the tasks to use proper Ansible modules (out of scope for this plan)

**Recommendation:** Option 1 for now (remove idempotence from test sequence). Refactoring shell tasks to Ansible modules is a separate improvement that should be done when the role itself is updated. If idempotence is kept, expect exactly 2 false-positive "changed" results.

### Risk 3: python3 Not Available in Arch Container

The verify uses `python3 -m json.tool` to validate JSON. The arch-systemd Docker image may not have python3. The Docker `prepare.yml` installs it explicitly. Vagrant's `generic/arch` box includes Python after the bootstrap step.

**Mitigation:** Both prepare.yml files ensure Python is available before converge/verify.

### Risk 4: Template Variable Naming Bug (Pre-existing)

As documented in Section 1, `system-info.json.j2` references `_greeter_*` variables but tasks register `greeter_*` (no underscore prefix). This means the JSON will contain default/fallback values for all system info fields.

**Impact on testing:** The verify assertions check for key presence and JSON validity, not value correctness (except `project_version` which comes from a default variable, not a registered task result). The bug does not cause test failures, but it means the tests do not catch the bug either.

**Recommendation:** Document the bug. When it is fixed (either rename registers to `_greeter_*` or update template to match current names), the verify can be extended to check that values like `hostname` and `kernel` are not "unknown".

### Risk 5: No Vault Dependency (Simplification)

The current `default/converge.yml` loads vault vars, but the greeter role uses zero vault-encrypted variables. The shared converge removes this dependency, which simplifies the molecule config (no `vault_password_file` needed). If vault variables are ever added to the role, the converge and molecule.yml will need updating.

### Risk 6: Wallpaper Tasks Not Tested

The wallpaper copy block (tasks lines 150-176) is conditional on `greeter_wallpaper_source_dir` existing. In the test environment, no user wallpaper directory exists, so these tasks are skipped. This is acceptable -- the wallpaper tasks are simple `ansible.builtin.copy` with no complex logic.

If coverage of wallpaper tasks is desired in the future, `prepare.yml` can create a stub wallpaper directory and set `greeter_wallpaper_source_dir` to point to it.

### Note: No Ubuntu in Vagrant

Unlike most other roles in this project, the greeter Vagrant scenario is Arch-only. web-greeter is an AUR package with no Ubuntu equivalent. Adding Ubuntu testing would require either packaging web-greeter for Debian or refactoring the role to support alternative greeters (e.g., lightdm-webkit2-greeter from Ubuntu repos, which uses a different config format and theme structure).

### Note: File Structure After Implementation

```
ansible/roles/greeter/molecule/
  shared/
    converge.yml        # Minimal: apply role: greeter
    verify.yml          # Full assertions (14 checks)
  default/
    molecule.yml        # Updated: references ../shared/ playbooks
  docker/
    molecule.yml        # Arch systemd container
    prepare.yml         # Stub dist + pacman cache + python3
  vagrant/
    molecule.yml        # Arch VM only (generic/arch)
    prepare.yml         # Keyring refresh + stub dist + lightdm dir
```
