# Plan: git role -- Molecule testing (shared + docker + vagrant)

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/git/`

---

## 1. Current State

### What the role does

The `git` role is a two-level configuration role:

**System layer (root):**
- Asserts supported OS family (Archlinux, Debian, RedHat, Void, Gentoo)
- Loads OS-specific variables from `vars/<os_family>.yml`
- Installs `git` and optionally `git-lfs` via `ansible.builtin.package`

**Per-user layer (become_user, looped over `[git_owner] + git_additional_users`):**
- Base config: `user.name`, `user.email`, `init.defaultBranch`, `core.editor`, `pull.rebase`, `push.autoSetupRemote`, `core.autocrlf`
- Extra config: arbitrary `git_config_extra` + `git_config_overwrite` dicts
- Commit signing: SSH (`gpg.format=ssh`) or GPG, with fail-fast validation
- Aliases: three-layer merge (preset -> extra -> overwrite)
- Credential helper: per-user override or shared default
- LFS: `git lfs install --skip-repo`
- Global hooks: directory creation + `core.hooksPath`
- Safe directories: CVE-2022-24765 multi-value `safe.directory` entries

**Report tasks** use `common` role's `report_phase.yml` / `report_render.yml` (tagged `report`).

**Variables** (`defaults/main.yml`):
- `git_owner`: primary user dict with `name`, `user_name`, `user_email`, `signing_method`, `signing_key`, `credential_helper`
- `git_additional_users: []`
- Shared defaults: `git_default_branch: main`, `git_editor: vim`, `git_pull_rebase: true`, `git_push_autosetup_remote: true`, `git_core_autocrlf: input`
- Profile-aware: `git_commit_sign`, `git_manage_signing` (driven by `workstation_profiles`)
- Toggles: `git_manage_aliases: true`, `git_manage_credential: true`, `git_manage_hooks: false`, `git_lfs_enabled: true`
- Aliases: `git_aliases_preset` (8 built-in), `git_aliases_extra: {}`, `git_aliases_overwrite: {}`
- `git_credential_helper: "cache --timeout=3600"`
- `git_config_extra: {}`, `git_config_overwrite: {}`
- `git_safe_directories: []`

**OS-specific package names** (`vars/`):

| OS family | `git_packages` | `git_lfs_package` |
|-----------|---------------|-------------------|
| Archlinux | `[git]` | `git-lfs` |
| Debian | `[git]` | `git-lfs` |
| RedHat | `[git]` | `git-lfs` |
| Void | `[git]` | `git-lfs` |
| Gentoo | `[dev-vcs/git]` | `dev-vcs/git-lfs` |

### What tests exist now

Single `molecule/default/` scenario:
- **Driver:** `default` (localhost, managed: false)
- **Provisioner:** Ansible with vault password, local connection
- **Host vars:** `git_owner` with `name: $USER`, `user_name: "Test User"`, `user_email: "test@example.com"`, plus `git_manage_hooks: true`, `git_hooks_path: "/tmp/test-git-hooks"`, `git_config_extra`, and `git_safe_directories`
- **converge.yml:** Asserts `os_family == Archlinux`, loads vault, applies `git` role
- **verify.yml:** 17 checks covering git installed, base config (7 settings), extra config (2 settings), safe.directory, aliases (2), credential helper, git-lfs, hooks directory, summary debug
- **test_sequence:** syntax, converge, idempotence, verify (no create/prepare/destroy -- localhost)

**Gaps in current tests:**
- Arch-only: converge hard-asserts `os_family == Archlinux`
- Vault dependency in converge (the git role has no vault variables)
- No Docker or Vagrant scenarios
- No cross-platform testing (Debian/Ubuntu)
- verify.yml does not check `_git_current_user.user_name` vs `git_current_user.user_name` inconsistency (see Bug Note below)
- verify.yml hardcodes expected values (`'main'`, `'vim'`, `'true'`) instead of referencing variables
- No `vars_files: ../../defaults/main.yml` in verify -- relies entirely on host_vars from molecule.yml

### Bug Note: `_git_current_user` vs `git_current_user` variable name inconsistency

The `main.yml` loop sets `loop_var: _git_current_user` (with leading underscore), but several task files reference `git_current_user` (without underscore):
- `configure_user.yml` line 6: `{{ git_current_user.name }}` (label + become_user)
- `config_base.yml` line 10/18: `{{ git_current_user.user_name }}` / `{{ git_current_user.user_email }}`
- `credential.yml` line 7: `{{ git_current_user.credential_helper ... }}`
- `signing.yml` lines 11-12, 30, 46: multiple `git_current_user.*` references
- `main.yml` line 70: label uses `{{ git_current_user.name }}`

Meanwhile, the `when:` guards correctly use `_git_current_user`:
- `config_base.yml` lines 12, 20: `_git_current_user.user_name`, `_git_current_user.user_email`
- `signing.yml` lines 9, 14, 18, 40: `_git_current_user.signing_key`, `_git_current_user.signing_method`

This means the `value:` expressions and `label:` references use `git_current_user` which may resolve to an undefined variable or a stale value, while the `when:` conditions use the correct `_git_current_user`. This is a pre-existing bug outside the scope of this testing plan, but the molecule tests should be designed to exercise and catch it (by running with explicit `user_name`/`user_email` values).

---

## 2. Cross-Platform Analysis

### Package names

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| git package | `git` | `git` |
| git-lfs package | `git-lfs` | `git-lfs` |
| Package manager | pacman | apt |
| `os_family` fact | `Archlinux` | `Debian` |

Package names are identical. The role uses `ansible.builtin.package` (generic), so no OS-specific install task files are needed -- `install.yml` works on both.

### git config paths

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| Global gitconfig | `~/.gitconfig` | `~/.gitconfig` |
| System gitconfig | `/etc/gitconfig` | `/etc/gitconfig` |
| XDG config | `~/.config/git/config` | `~/.config/git/config` |
| git binary path | `/usr/bin/git` | `/usr/bin/git` |
| `community.general.git_config` | scope: global | scope: global |

All paths are identical. `community.general.git_config` with `scope: global` writes to `~/.gitconfig` on both platforms.

### Arch-specific concerns

None. The git role has no Arch-specific task files, handlers, or templates. Everything is generic via `ansible.builtin.package` and `community.general.git_config`. The only OS dispatch is `include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"` which loads package names.

### Debian-specific concerns

- The `git_supported_os` list in `defaults/main.yml` includes `Debian` (Ubuntu's `os_family`). Good.
- `vars/debian.yml` exists with correct package names. Good.
- The `community.general.git_config` module requires `git` to be installed first. The role handles this (install.yml runs before configure_user.yml).

### User creation in test environment

The role uses `become_user: {{ git_current_user.name }}` for per-user config. In molecule test environments:
- **Docker:** The container runs as root. The test user must be created in prepare.yml or the converge must use `root` as the git_owner name.
- **Vagrant:** The vagrant user exists by default. Can be used as `git_owner.name`.
- **Default (localhost):** Uses `$USER` from environment.

**Decision:** For Docker, use `root` as `git_owner.name` (simplest -- no user creation needed). For Vagrant, use `vagrant`. This avoids needing prepare.yml logic to create test users.

### `common` role dependency

The `main.yml` includes the `common` role for report tasks (tagged `report`). In molecule scenarios:
- **Docker/Vagrant:** The `ANSIBLE_ROLES_PATH` includes `../../` so `common` is available. The `skip-tags: report` option in provisioner config skips these tasks entirely.
- **Default:** Same approach with `ANSIBLE_ROLES_PATH`.

### `workstation_profiles` dependency

The defaults for `git_commit_sign` and `git_manage_signing` reference `workstation_profiles` which is undefined in test environments. The Jinja2 expressions use `default([])` so they safely resolve to `false`. No action needed.

---

## 3. Shared Migration

Move `molecule/default/converge.yml` and `molecule/default/verify.yml` to `molecule/shared/` so all scenarios reuse them.

### molecule/shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: git
```

Changes from current `default/converge.yml`:
- **Removed** `vars_files` vault reference (role has no vault variables)
- **Removed** `os_family == Archlinux` assertion (role supports Arch + Debian)

### molecule/shared/verify.yml

Full content designed in Section 6 below.

### molecule/default/molecule.yml (updated)

```yaml
---
driver:
  name: default
  options:
    managed: false

platforms:
  - name: Localhost

provisioner:
  name: ansible
  options:
    skip-tags: report
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
        git_owner:
          name: "{{ lookup('env', 'USER') }}"
          user_name: "Test User"
          user_email: "test@example.com"
          signing_method: none
          signing_key: ""
          credential_helper: ""
        git_manage_hooks: true
        git_hooks_path: "/tmp/test-git-hooks"
        git_config_extra:
          color.ui: auto
          diff.colorMoved: zebra
        git_safe_directories:
          - /tmp/test-safe-dir
  playbooks:
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - converge
    - idempotence
    - verify
```

Changes from current:
- **Removed** `vault_password_file` (not needed)
- **Added** `skip-tags: report` (common role not needed for testing)
- **Changed** playbook paths to `../shared/`
- **Retained** all `host_vars` (test-specific overrides)
- **Retained** `idempotence` in test sequence

---

## 4. Docker Scenario

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
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      Archlinux-systemd:
        git_owner:
          name: root
          user_name: "Test User"
          user_email: "test@example.com"
          signing_method: none
          signing_key: ""
          credential_helper: ""
        git_manage_hooks: true
        git_hooks_path: "/tmp/test-git-hooks"
        git_config_extra:
          color.ui: auto
          diff.colorMoved: zebra
        git_safe_directories:
          - /tmp/test-safe-dir
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

**Key difference from default:** `git_owner.name: root` because the Arch systemd container runs as root and no other users exist by default.

### molecule/docker/prepare.yml

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Update pacman package cache
      community.general.pacman:
        update_cache: true
```

### Docker-specific concerns

**No systemd dependency:** The git role does not manage any systemd services. The systemd container is used for consistency with other roles, but a simpler container would also work. Keeping the systemd image for uniformity across the project.

**`community.general.git_config` module:** Requires the `git` binary to be installed. The role installs git as its first task, so this is fine. The module also requires the target user's home directory to exist (for `~/.gitconfig`). Root's home (`/root`) exists by default in the Arch container.

**`git lfs install --skip-repo`:** Requires `git-lfs` binary. Installed by the role. Writes LFS hooks config to `~/.gitconfig`. Should work in the container without issues.

---

## 5. Vagrant Scenario

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
  inventory:
    host_vars:
      arch-vm:
        git_owner:
          name: vagrant
          user_name: "Test User"
          user_email: "test@example.com"
          signing_method: none
          signing_key: ""
          credential_helper: ""
        git_manage_hooks: true
        git_hooks_path: "/tmp/test-git-hooks"
        git_config_extra:
          color.ui: auto
          diff.colorMoved: zebra
        git_safe_directories:
          - /tmp/test-safe-dir
      ubuntu-noble:
        git_owner:
          name: vagrant
          user_name: "Test User"
          user_email: "test@example.com"
          signing_method: none
          signing_key: ""
          credential_helper: ""
        git_manage_hooks: true
        git_hooks_path: "/tmp/test-git-hooks"
        git_config_extra:
          color.ui: auto
          diff.colorMoved: zebra
        git_safe_directories:
          - /tmp/test-safe-dir
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

**Key difference:** `git_owner.name: vagrant` because both Vagrant boxes have a `vagrant` user by default.

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

    - name: Full system upgrade on Arch (ensures compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

Identical to the `package_manager` vagrant prepare pattern.

### Cross-platform notes

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| git package | `git` (pacman) | `git` (apt) |
| git-lfs package | `git-lfs` (pacman) | `git-lfs` (apt) |
| `os_family` fact | `Archlinux` | `Debian` |
| vars file loaded | `vars/archlinux.yml` | `vars/debian.yml` |
| Test user | `vagrant` | `vagrant` |
| Home directory | `/home/vagrant` | `/home/vagrant` |
| gitconfig path | `/home/vagrant/.gitconfig` | `/home/vagrant/.gitconfig` |
| git pre-installed | No | Maybe (minimal image) |
| git-lfs pre-installed | No | No |

No distro-specific `when:` guards are needed in verify.yml because the git role's behavior is identical across Arch and Ubuntu. Package names differ only at the `vars/` layer, which is loaded automatically by `include_vars`.

---

## 6. Verify.yml Design

### molecule/shared/verify.yml

```yaml
---
- name: Verify git role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - ../../defaults/main.yml

  tasks:

    # ---- Package installed ----

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    - name: Assert git package is installed
      ansible.builtin.assert:
        that: "'git' in ansible_facts.packages"
        fail_msg: "git package not found in installed packages"

    # ---- git binary works ----

    - name: Verify git --version  # noqa: command-instead-of-module
      ansible.builtin.command:
        cmd: git --version
      register: git_verify_version
      changed_when: false
      failed_when: git_verify_version.rc != 0

    - name: Assert git version output is sane
      ansible.builtin.assert:
        that: "'git version' in git_verify_version.stdout"
        fail_msg: "git --version did not return expected output: {{ git_verify_version.stdout }}"

    # ---- Base config ----

    - name: Check git user.name  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get user.name
      register: git_verify_username
      changed_when: false

    - name: Assert git user.name matches expected
      ansible.builtin.assert:
        that: git_verify_username.stdout == git_owner.user_name
        fail_msg: >-
          git user.name mismatch: expected '{{ git_owner.user_name }}',
          got '{{ git_verify_username.stdout }}'
      when: (git_owner.user_name | default('')) | length > 0

    - name: Check git user.email  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get user.email
      register: git_verify_email
      changed_when: false

    - name: Assert git user.email matches expected
      ansible.builtin.assert:
        that: git_verify_email.stdout == git_owner.user_email
        fail_msg: >-
          git user.email mismatch: expected '{{ git_owner.user_email }}',
          got '{{ git_verify_email.stdout }}'
      when: (git_owner.user_email | default('')) | length > 0

    - name: Check git init.defaultBranch  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get init.defaultBranch
      register: git_verify_branch
      changed_when: false

    - name: Assert git init.defaultBranch matches expected
      ansible.builtin.assert:
        that: git_verify_branch.stdout == git_default_branch
        fail_msg: >-
          init.defaultBranch mismatch: expected '{{ git_default_branch }}',
          got '{{ git_verify_branch.stdout }}'

    - name: Check git core.editor  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get core.editor
      register: git_verify_editor
      changed_when: false

    - name: Assert git core.editor matches expected
      ansible.builtin.assert:
        that: git_verify_editor.stdout == git_editor
        fail_msg: >-
          core.editor mismatch: expected '{{ git_editor }}',
          got '{{ git_verify_editor.stdout }}'

    - name: Check git pull.rebase  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get pull.rebase
      register: git_verify_rebase
      changed_when: false

    - name: Assert git pull.rebase matches expected
      ansible.builtin.assert:
        that: git_verify_rebase.stdout == (git_pull_rebase | string | lower)
        fail_msg: >-
          pull.rebase mismatch: expected '{{ git_pull_rebase | string | lower }}',
          got '{{ git_verify_rebase.stdout }}'

    - name: Check git push.autoSetupRemote  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get push.autoSetupRemote
      register: git_verify_autosetup
      changed_when: false

    - name: Assert git push.autoSetupRemote matches expected
      ansible.builtin.assert:
        that: git_verify_autosetup.stdout == (git_push_autosetup_remote | string | lower)
        fail_msg: >-
          push.autoSetupRemote mismatch: expected '{{ git_push_autosetup_remote | string | lower }}',
          got '{{ git_verify_autosetup.stdout }}'

    - name: Check git core.autocrlf  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get core.autocrlf
      register: git_verify_autocrlf
      changed_when: false

    - name: Assert git core.autocrlf matches expected
      ansible.builtin.assert:
        that: git_verify_autocrlf.stdout == git_core_autocrlf
        fail_msg: >-
          core.autocrlf mismatch: expected '{{ git_core_autocrlf }}',
          got '{{ git_verify_autocrlf.stdout }}'

    # ---- Extra config ----

    - name: Check extra config entries  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: "git config --global --get {{ item.key }}"
      register: git_verify_extra
      changed_when: false
      failed_when: git_verify_extra.stdout != (item.value | string)
      loop: "{{ git_config_extra | combine(git_config_overwrite) | dict2items }}"
      loop_control:
        label: "{{ item.key }}"
      when: (git_config_extra | combine(git_config_overwrite)) | length > 0

    # ---- Safe directories ----

    - name: Check safe.directory entries  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get-all safe.directory
      register: git_verify_safe_dirs
      changed_when: false
      failed_when: false
      when: git_safe_directories | length > 0

    - name: Assert safe.directory entries are present
      ansible.builtin.assert:
        that: item in (git_verify_safe_dirs.stdout_lines | default([]))
        fail_msg: "safe.directory '{{ item }}' not found in git config"
      loop: "{{ git_safe_directories }}"
      when: git_safe_directories | length > 0

    # ---- Aliases ----

    - name: Check alias.st  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get alias.st
      register: git_verify_alias_st
      changed_when: false
      when: git_manage_aliases | bool

    - name: Assert alias.st is 'status'
      ansible.builtin.assert:
        that: git_verify_alias_st.stdout == 'status'
        fail_msg: "alias.st mismatch: expected 'status', got '{{ git_verify_alias_st.stdout }}'"
      when:
        - git_manage_aliases | bool
        - "'st' in (git_aliases_preset | combine(git_aliases_extra) | combine(git_aliases_overwrite))"

    - name: Check alias.lg exists  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get alias.lg
      register: git_verify_alias_lg
      changed_when: false
      failed_when: false
      when: git_manage_aliases | bool

    - name: Assert alias.lg is set
      ansible.builtin.assert:
        that: git_verify_alias_lg.rc == 0
        fail_msg: "alias.lg not found in git config"
      when:
        - git_manage_aliases | bool
        - "'lg' in (git_aliases_preset | combine(git_aliases_extra) | combine(git_aliases_overwrite))"

    # ---- Credential helper ----

    - name: Check credential.helper  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get credential.helper
      register: git_verify_credential
      changed_when: false
      when: git_manage_credential | bool

    - name: Assert credential.helper contains expected value
      ansible.builtin.assert:
        that: "'cache' in git_verify_credential.stdout"
        fail_msg: >-
          credential.helper mismatch: expected 'cache' substring,
          got '{{ git_verify_credential.stdout }}'
      when:
        - git_manage_credential | bool
        - git_verify_credential is not skipped

    # ---- git-lfs ----

    - name: Check git-lfs is installed
      ansible.builtin.command:
        cmd: git lfs version
      register: git_verify_lfs
      changed_when: false
      failed_when: false
      when: git_lfs_enabled | bool

    - name: Assert git-lfs is installed
      ansible.builtin.assert:
        that: git_verify_lfs.rc == 0
        fail_msg: "git lfs version failed (rc={{ git_verify_lfs.rc }})"
      when: git_lfs_enabled | bool

    - name: Assert git-lfs version output is sane
      ansible.builtin.assert:
        that: "'git-lfs' in git_verify_lfs.stdout"
        fail_msg: "git lfs version output unexpected: {{ git_verify_lfs.stdout }}"
      when:
        - git_lfs_enabled | bool
        - git_verify_lfs.rc == 0

    # ---- LFS filter config (written by `git lfs install --skip-repo`) ----

    - name: Check LFS filter.lfs.clean config  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get filter.lfs.clean
      register: git_verify_lfs_filter
      changed_when: false
      failed_when: false
      when: git_lfs_enabled | bool

    - name: Assert LFS filter is configured in gitconfig
      ansible.builtin.assert:
        that: git_verify_lfs_filter.rc == 0
        fail_msg: "filter.lfs.clean not found in user gitconfig -- git lfs install may not have run"
      when: git_lfs_enabled | bool

    # ---- Hooks directory ----

    - name: Check hooks directory exists
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.stat:
        path: "{{ git_hooks_path }}"
      register: git_verify_hooks
      when: git_manage_hooks | bool

    - name: Assert hooks directory exists
      ansible.builtin.assert:
        that:
          - git_verify_hooks.stat.exists
          - git_verify_hooks.stat.isdir
        fail_msg: "Global hooks directory '{{ git_hooks_path }}' does not exist or is not a directory"
      when:
        - git_manage_hooks | bool
        - git_verify_hooks is not skipped

    - name: Check core.hooksPath config  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get core.hooksPath
      register: git_verify_hookspath
      changed_when: false
      when: git_manage_hooks | bool

    - name: Assert core.hooksPath matches expected
      ansible.builtin.assert:
        that: git_verify_hookspath.stdout == git_hooks_path
        fail_msg: >-
          core.hooksPath mismatch: expected '{{ git_hooks_path }}',
          got '{{ git_verify_hookspath.stdout }}'
      when:
        - git_manage_hooks | bool
        - git_verify_hookspath is not skipped

    # ---- gitconfig file exists ----

    - name: Stat user gitconfig file
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.stat:
        path: "~/.gitconfig"
      register: git_verify_gitconfig_file

    - name: Assert gitconfig file exists
      ansible.builtin.assert:
        that:
          - git_verify_gitconfig_file.stat.exists
          - git_verify_gitconfig_file.stat.isreg
        fail_msg: "~/.gitconfig does not exist for user {{ git_owner.name }}"

    # ---- Signing (conditional) ----

    - name: Check commit signing config  # noqa: command-instead-of-module
      become: true
      become_user: "{{ git_owner.name }}"
      ansible.builtin.command: git config --global --get commit.gpgSign
      register: git_verify_signing
      changed_when: false
      failed_when: false
      when:
        - git_manage_signing | bool
        - (git_owner.signing_method | default('none')) != 'none'

    - name: Assert commit signing matches expected
      ansible.builtin.assert:
        that: git_verify_signing.stdout == (git_commit_sign | string | lower)
        fail_msg: >-
          commit.gpgSign mismatch: expected '{{ git_commit_sign | string | lower }}',
          got '{{ git_verify_signing.stdout }}'
      when:
        - git_manage_signing | bool
        - (git_owner.signing_method | default('none')) != 'none'
        - git_verify_signing is not skipped

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Git role verify passed on {{ ansible_facts['distribution'] }}
          {{ ansible_facts['distribution_version'] }}:
          git installed ({{ git_verify_version.stdout }}),
          user.name={{ git_verify_username.stdout }},
          user.email={{ git_verify_email.stdout }},
          init.defaultBranch={{ git_verify_branch.stdout }},
          core.editor={{ git_verify_editor.stdout }},
          pull.rebase={{ git_verify_rebase.stdout }},
          push.autoSetupRemote={{ git_verify_autosetup.stdout }},
          core.autocrlf={{ git_verify_autocrlf.stdout }},
          aliases={{ git_manage_aliases }},
          credential={{ git_manage_credential }},
          lfs={{ git_lfs_enabled }},
          hooks={{ git_manage_hooks }},
          ~/.gitconfig exists.
```

### Assertion summary table

| # | Assertion | Cross-platform | When guard |
|---|-----------|---------------|------------|
| 1 | git package installed | Both | always |
| 2 | `git --version` works | Both | always |
| 3 | `git version` in output | Both | always |
| 4 | `user.name` matches | Both | `user_name` set |
| 5 | `user.email` matches | Both | `user_email` set |
| 6 | `init.defaultBranch` matches | Both | always |
| 7 | `core.editor` matches | Both | always |
| 8 | `pull.rebase` matches | Both | always |
| 9 | `push.autoSetupRemote` matches | Both | always |
| 10 | `core.autocrlf` matches | Both | always |
| 11 | Extra config entries match | Both | `git_config_extra` non-empty |
| 12 | `safe.directory` entries present | Both | `git_safe_directories` non-empty |
| 13 | `alias.st` = status | Both | `git_manage_aliases` |
| 14 | `alias.lg` exists | Both | `git_manage_aliases` |
| 15 | `credential.helper` contains cache | Both | `git_manage_credential` |
| 16 | `git lfs version` works | Both | `git_lfs_enabled` |
| 17 | `git-lfs` in version output | Both | `git_lfs_enabled` |
| 18 | `filter.lfs.clean` in gitconfig | Both | `git_lfs_enabled` |
| 19 | Hooks directory exists | Both | `git_manage_hooks` |
| 20 | `core.hooksPath` matches | Both | `git_manage_hooks` |
| 21 | `~/.gitconfig` file exists | Both | always |
| 22 | `commit.gpgSign` matches | Both | `git_manage_signing` + signing_method != none |

No assertions require `ansible_distribution`-specific `when:` guards because the git
role's behavior and paths are identical on Arch and Ubuntu/Debian.

---

## 7. Implementation Order

### Step 1: Create shared directory and move files

```
mkdir -p ansible/roles/git/molecule/shared/
```

Create `molecule/shared/converge.yml` (new, simplified -- no vault, no Arch assertion).
Create `molecule/shared/verify.yml` (new, comprehensive -- from Section 6).

### Step 2: Update molecule/default/molecule.yml

- Remove `vault_password_file`
- Add `skip-tags: report`
- Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`
- Retain all `host_vars` test overrides
- Retain `idempotence` in test sequence

### Step 3: Delete old converge.yml and verify.yml from default/

```
rm ansible/roles/git/molecule/default/converge.yml
rm ansible/roles/git/molecule/default/verify.yml
```

### Step 4: Create Docker scenario

```
mkdir -p ansible/roles/git/molecule/docker/
```

Create `molecule/docker/molecule.yml` (with `git_owner.name: root`) and `molecule/docker/prepare.yml` per Section 4.

### Step 5: Create Vagrant scenario

```
mkdir -p ansible/roles/git/molecule/vagrant/
```

Create `molecule/vagrant/molecule.yml` (with `git_owner.name: vagrant` for both VMs) and `molecule/vagrant/prepare.yml` per Section 5.

### Step 6: Test locally

```bash
# Default scenario (localhost, Arch only)
cd ansible/roles/git && molecule test -s default

# Docker scenario (Arch systemd container)
cd ansible/roles/git && molecule test -s docker

# Vagrant scenario (Arch + Ubuntu VMs, requires libvirt)
cd ansible/roles/git && molecule test -s vagrant
```

### Step 7: Verify idempotence

The role should be idempotent on second run:
- Package tasks: `ok` (already installed)
- `community.general.git_config` tasks: `ok` (same values)
- `git lfs install --skip-repo`: `changed_when: false` (always `ok`)
- `safe.directory` tasks: `ok` (idempotent check prevents re-adding)
- Hooks directory: `ok` (already exists)

**Potential idempotence issue:** The `safe.directory` task uses `changed_when: true` on the `ansible.builtin.command` that adds entries. The `when:` guard (`item not in _git_current_safe_dirs.stdout_lines`) should prevent the command from running on second pass, but this depends on the variable name bug being fixed. If `_git_current_safe_dirs` is correctly referenced, idempotence should pass.

---

## 8. Risks / Notes

### `_git_current_user` variable name bug

As documented in Section 1, there is an inconsistency between `_git_current_user` (the actual loop_var) and `git_current_user` (used in `value:` expressions and labels). This may cause:
- `git_current_user` resolving to `undefined` and triggering Jinja2 errors
- Or `git_current_user` resolving to a default/magic variable and silently producing wrong values

**Impact on testing:** The molecule tests use `git_owner` directly in verify assertions, not `_git_current_user`. The converge will either succeed (if Ansible somehow resolves the variable) or fail with a clear error. Either outcome is valuable -- it surfaces the bug.

**Recommendation:** Fix the variable name inconsistency before or during the molecule migration. All references to `git_current_user` should be `_git_current_user` to match the `loop_var` declaration in `main.yml` line 69.

### `common` role required on ANSIBLE_ROLES_PATH

The `main.yml` includes the `common` role for report tasks. Without `skip-tags: report`, molecule would fail if the `common` role is not available. The `skip-tags: report` setting in all molecule scenarios ensures these tasks are skipped.

**If `skip-tags: report` is accidentally removed:** The `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"` points to `ansible/roles/`, which contains the `common` role. So even without skip-tags, the role would be found. However, the common role may have its own dependencies or assumptions, so skip-tags is the safer approach.

### No vault variables

The current `molecule/default/molecule.yml` includes `vault_password_file` and the converge loads `vault.yml`. The git role has no vault-encrypted variables. This dependency should be removed in the migration to avoid needing `vault-pass.sh` in CI environments.

### `workstation_profiles` not set in test environments

The defaults for `git_commit_sign` and `git_manage_signing` use Jinja2 expressions referencing `workstation_profiles`, which is undefined in molecule runs. The expressions use `| default([])`, so they safely evaluate to `false`. This means:
- `git_commit_sign` = `false`
- `git_manage_signing` = `false`

The signing-related verify assertions are gated with `when: git_manage_signing | bool`, so they will be skipped in molecule tests. This is correct behavior -- signing is not configured, so it should not be verified.

To test signing in the future, add explicit `git_manage_signing: true` and `git_owner.signing_method: ssh/gpg` host vars to a dedicated molecule scenario.

### Docker: root user as git_owner

Using `root` as `git_owner.name` in the Docker scenario means `~/.gitconfig` is `/root/.gitconfig`. This is a valid test path. If testing with a non-root user is desired in the future, add a prepare.yml task to create the user:

```yaml
- name: Create test user
  ansible.builtin.user:
    name: testuser
    create_home: true
```

### Vagrant: memory and CPU allocation

Both VMs are configured with 2048 MB RAM and 2 CPUs. For the git role (no compilation, no heavy services), 1024 MB would be sufficient. The 2048 MB setting matches the project standard from `package_manager/molecule/vagrant/molecule.yml`.

### Idempotence: `safe.directory` variable reference

The `safe.directory` add task in `config_base.yml` line 79 uses `_git_current_safe_dirs` (with leading underscore) for the register variable, but the register on line 62 stores in `git_current_safe_dirs` (without underscore). This is another instance of the `_` prefix inconsistency. The `when:` guard references `_git_current_safe_dirs.stdout_lines` which would be undefined, causing the condition to evaluate as truthy (via `| default([])` being absent), and the command would re-run every time -- breaking idempotence.

**Impact:** The idempotence test may fail on the `safe.directory` tasks. This is a real bug that the molecule test would catch.

### No `ansible_managed` concerns

Unlike the firewall role's `nftables.conf.j2`, the git role does not use templates with `{{ ansible_managed }}`. All configuration is done via `community.general.git_config` which writes individual key-value pairs. No timestamp-based idempotence issues.

---

## File tree after implementation

```
ansible/roles/git/
  defaults/main.yml              (unchanged)
  meta/main.yml                  (unchanged)
  tasks/
    main.yml                     (unchanged -- bug noted, not fixed here)
    install.yml                  (unchanged)
    config_base.yml              (unchanged)
    config_extra.yml             (unchanged)
    configure_user.yml           (unchanged)
    credential.yml               (unchanged)
    aliases.yml                  (unchanged)
    signing.yml                  (unchanged)
    lfs_user.yml                 (unchanged)
    verify.yml                   (unchanged)
  vars/
    archlinux.yml                (unchanged)
    debian.yml                   (unchanged)
    redhat.yml                   (unchanged)
    void.yml                     (unchanged)
    gentoo.yml                   (unchanged)
  molecule/
    shared/
      converge.yml               (NEW -- simplified, no vault, no Arch assertion)
      verify.yml                 (NEW -- 22 assertions, variable-driven, cross-platform)
    default/
      molecule.yml               (UPDATED -- point to shared/, remove vault, add skip-tags)
    docker/
      molecule.yml               (NEW -- arch-systemd container, git_owner=root)
      prepare.yml                (NEW -- pacman update_cache)
    vagrant/
      molecule.yml               (NEW -- Arch + Ubuntu VMs, git_owner=vagrant)
      prepare.yml                (NEW -- Python bootstrap, keyring refresh, apt cache)
```
