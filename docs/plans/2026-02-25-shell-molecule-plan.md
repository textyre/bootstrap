# shell: Molecule Testing Plan

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### What the role does

The `shell` role (`ansible/roles/shell/`) provides system-level shell environment setup:

1. **Validation** (`tasks/validate.yml`) -- asserts supported OS family, valid `shell_type` (bash/zsh/fish), and non-empty `shell_user`.
2. **Install** (`tasks/install.yml`) -- installs the shell package via `ansible.builtin.package` using per-distro vars from `vars/{archlinux,debian,redhat,void,gentoo}.yml`.
3. **chsh** (`tasks/chsh.yml`) -- sets login shell for `shell_user` via `ansible.builtin.user` when `shell_set_login: true`.
4. **XDG directories** (`tasks/xdg.yml`) -- creates `~/.config`, `~/.local/share`, `~/.local/bin`, `~/.cache` under the user's home.
5. **Global config** (`tasks/global.yml`) -- deploys:
   - `/etc/profile.d/dev-paths.sh` (bash/zsh) -- PATH additions + env vars
   - `/etc/zsh/zshenv` (zsh only) -- sets ZDOTDIR to XDG location
   - `/etc/fish/conf.d/dev-paths.fish` (fish only) -- PATH + env vars
6. **Verify** (`tasks/verify.yml`) -- in-role assertions for login shell, XDG dirs, config files.
7. **Report** -- renders execution summary via `common` role (`skip-tags: report` in molecule).

Per-user dotfiles (`.bashrc`, `.zshrc`) are managed by chezmoi, NOT this role.

### Supported platforms (meta/main.yml + vars/main.yml)

- Archlinux, Debian, Ubuntu (EL in meta), RedHat, Void, Gentoo

### Existing tests

Single `molecule/default/` scenario:
- **Driver:** `default` (localhost, unmanaged)
- **converge.yml:** Arch-only assert, loads vault.yml, applies shell role with `shell_type: zsh`
- **verify.yml:** zsh installed, login shell set, XDG dirs exist, `/etc/profile.d/dev-paths.sh` content checks, `/etc/zsh/zshenv` contains ZDOTDIR
- **test_sequence:** syntax, converge, verify (no idempotence)
- **Limitation:** Arch-only; hardcoded `pre_tasks` assert blocks other distros

## 2. Cross-Platform Analysis

### Package names

All distros use the same package names except Gentoo:

| Distro    | zsh package       | fish package       | bash package |
|-----------|-------------------|--------------------|--------------|
| Archlinux | `zsh`             | `fish`             | (preinstalled) |
| Debian    | `zsh`             | `fish`             | (preinstalled) |
| RedHat    | `zsh`             | `fish`             | (preinstalled) |
| Void      | `zsh`             | `fish`             | (preinstalled) |
| Gentoo    | `app-shells/zsh`  | `app-shells/fish`  | (preinstalled) |

### Binary paths

Identical across all distros: `/usr/bin/zsh`, `/usr/bin/fish`, `/bin/bash`.

### Config file paths

All system-level config paths are portable:
- `/etc/profile.d/dev-paths.sh` -- standard on all Linux
- `/etc/zsh/zshenv` -- standard zsh global config location
- `/etc/fish/conf.d/dev-paths.fish` -- standard fish config dir
- XDG dirs (`~/.config`, etc.) -- home-relative, universal

### Arch-specific concerns

- No AUR packages required (no zsh-completions or similar from AUR in this role)
- No Arch-specific tasks in the role itself (all tasks are distro-agnostic via vars)
- Existing converge.yml has an Arch-only assert that must be removed for cross-platform use

### Ubuntu-specific concerns

- `chsh` may require the shell to be listed in `/etc/shells`. On Ubuntu, `apt install zsh` registers it in `/etc/shells` automatically -- no extra step needed.
- The `ansible.builtin.user` module's `shell:` parameter updates `/etc/passwd` directly, bypassing `chsh` validation anyway. No issue expected.

### Docker container concerns

- Default container images run as root. The role uses `shell_user` which defaults to `SUDO_USER` or the current user. In a container running as root, `SUDO_USER` is unset, so `shell_user` resolves to `root`.
- `getent passwd root` works. User home is `/root`. This is acceptable for testing.
- `/etc/shells` may be minimal in containers but `ansible.builtin.user` does not enforce it.

## 3. Shared Migration

### File structure after migration

```
ansible/roles/shell/molecule/
  shared/
    converge.yml      <-- NEW: role invocation, no vault, no arch assert
    verify.yml        <-- NEW: comprehensive cross-platform assertions
  default/
    molecule.yml      <-- UPDATED: references ../shared/, add idempotence
    (converge.yml)    <-- DELETE
    (verify.yml)      <-- DELETE
  docker/
    molecule.yml      <-- NEW
  vagrant/
    molecule.yml      <-- NEW
    prepare.yml       <-- NEW
```

### shared/converge.yml

Remove the Arch-only assert and vault dependency. The shell role does not use vault variables.

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: shell
      vars:
        shell_type: zsh
        shell_set_login: true
        shell_global_path:
          - "$HOME/.local/bin"
          - "$HOME/.cargo/bin"
          - "/usr/local/go/bin"
        shell_global_env:
          GOPATH: "$HOME/go"
        shell_zsh_zdotdir: true
```

Key decisions:
- **No `vars_files` for vault** -- role has no secrets.
- **No `pre_tasks` OS assertion** -- role itself validates OS via `tasks/validate.yml`.
- **Explicit `vars:`** -- matches current test coverage; tests zsh + ZDOTDIR + PATH + env vars.

### shared/verify.yml

See Section 6 for full design.

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
  playbooks:
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - converge
    - idempotence
    - verify
    - destroy
```

### prepare.yml -- NOT needed

The shell role needs only:
- `pacman` package cache (handled by the arch-systemd image, which is up-to-date)
- A user for `shell_user` (defaults to root in Docker -- acceptable)

No `prepare.yml` is required. If pacman cache staleness becomes an issue, add a minimal one:

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

Decision: **Start without prepare.yml.** Add it only if convergence fails due to stale cache.

### Idempotence considerations

All tasks in the role are idempotent:
- `ansible.builtin.package` with `state: present` -- idempotent
- `ansible.builtin.user` with `shell:` -- idempotent
- `ansible.builtin.file` with `state: directory` -- idempotent
- `ansible.builtin.template` -- idempotent (no change if content matches)

Expect zero changes on second run.

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

### molecule/vagrant/prepare.yml

Follows the package_manager vagrant prepare pattern:

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

    - name: Full system upgrade on Arch (ensures openssl/ssl compatibility)
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

This is a direct copy of `package_manager/molecule/vagrant/prepare.yml`. The Arch keyring refresh and system upgrade are necessary because `generic/arch` boxes ship with stale keys. Ubuntu only needs an apt cache refresh.

### Vagrant user context

Vagrant VMs run as the `vagrant` user with sudo. Molecule executes playbooks with `become: true`, so `SUDO_USER` is `vagrant`. The role's `shell_user` default (`SUDO_USER | default(user_id)`) will resolve to `vagrant`.

This is desirable -- it tests a realistic non-root user scenario that Docker cannot provide.

## 6. Verify.yml Design

### Approach

The verify playbook must work across Arch (Docker + Vagrant) and Ubuntu (Vagrant). Use `when:` guards for distro-specific checks. Follow the `package_manager/molecule/shared/verify.yml` pattern of `block` + `when` for grouped assertions.

### shared/verify.yml

```yaml
---
- name: Verify shell role
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "../../defaults/main.yml"

  tasks:

    # ==========================================================
    # Resolve user context (mirrors role's own resolution)
    # ==========================================================

    - name: Resolve shell_user
      ansible.builtin.set_fact:
        _verify_user: "{{ shell_user }}"

    - name: Get user info from passwd
      ansible.builtin.getent:
        database: passwd
        key: "{{ _verify_user }}"

    - name: Set user home fact
      ansible.builtin.set_fact:
        _verify_home: "{{ getent_passwd[_verify_user][4] }}"

    # ==========================================================
    # Shell package installed
    # ==========================================================

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto

    - name: Assert zsh package is installed
      ansible.builtin.assert:
        that: "'zsh' in ansible_facts.packages"
        fail_msg: "zsh package not found in installed packages"

    # ==========================================================
    # Login shell is /usr/bin/zsh
    # ==========================================================

    - name: Assert login shell is /usr/bin/zsh
      ansible.builtin.assert:
        that:
          - "getent_passwd[_verify_user][5] == '/usr/bin/zsh'"
        fail_msg: >-
          Login shell for {{ _verify_user }} is
          '{{ getent_passwd[_verify_user][5] }}' but expected '/usr/bin/zsh'.

    # ==========================================================
    # XDG directories exist
    # ==========================================================

    - name: Check XDG directories exist
      ansible.builtin.stat:
        path: "{{ _verify_home }}/{{ item }}"
      register: _verify_xdg
      loop:
        - ".config"
        - ".local/share"
        - ".local/bin"
        - ".cache"

    - name: Assert all XDG directories exist and are directories
      ansible.builtin.assert:
        that:
          - item.stat.exists
          - item.stat.isdir
        fail_msg: "XDG directory '{{ item.item }}' missing or not a directory"
      loop: "{{ _verify_xdg.results }}"
      loop_control:
        label: "{{ item.item }}"

    # ==========================================================
    # /etc/profile.d/dev-paths.sh (bash + zsh)
    # ==========================================================

    - name: Verify /etc/profile.d/dev-paths.sh
      block:

        - name: Stat /etc/profile.d/dev-paths.sh
          ansible.builtin.stat:
            path: /etc/profile.d/dev-paths.sh
          register: _verify_profiled

        - name: Assert /etc/profile.d/dev-paths.sh exists
          ansible.builtin.assert:
            that:
              - _verify_profiled.stat.exists
              - _verify_profiled.stat.isreg
              - _verify_profiled.stat.mode == '0644'
              - _verify_profiled.stat.pw_name == 'root'
            fail_msg: >-
              /etc/profile.d/dev-paths.sh missing or wrong permissions
              (expected root 0644)

        - name: Read /etc/profile.d/dev-paths.sh
          ansible.builtin.slurp:
            src: /etc/profile.d/dev-paths.sh
          register: _verify_profiled_raw

        - name: Set profile.d text fact
          ansible.builtin.set_fact:
            _verify_profiled_text: "{{ _verify_profiled_raw.content | b64decode }}"

        - name: Assert profile.d contains Ansible managed marker
          ansible.builtin.assert:
            that: "'Ansible' in _verify_profiled_text"
            fail_msg: "/etc/profile.d/dev-paths.sh missing Ansible managed marker"

        - name: Assert profile.d contains PATH entries
          ansible.builtin.assert:
            that:
              - "'.local/bin' in _verify_profiled_text"
              - "'.cargo/bin' in _verify_profiled_text"
              - "'go/bin' in _verify_profiled_text"
            fail_msg: "/etc/profile.d/dev-paths.sh missing expected PATH entries"

        - name: Assert profile.d contains GOPATH env var
          ansible.builtin.assert:
            that: "'GOPATH' in _verify_profiled_text"
            fail_msg: "/etc/profile.d/dev-paths.sh missing GOPATH env var"

    # ==========================================================
    # /etc/zsh/zshenv (zsh only)
    # ==========================================================

    - name: Verify /etc/zsh/zshenv
      block:

        - name: Stat /etc/zsh directory
          ansible.builtin.stat:
            path: /etc/zsh
          register: _verify_zshdir

        - name: Assert /etc/zsh directory exists
          ansible.builtin.assert:
            that:
              - _verify_zshdir.stat.exists
              - _verify_zshdir.stat.isdir
            fail_msg: "/etc/zsh directory does not exist"

        - name: Stat /etc/zsh/zshenv
          ansible.builtin.stat:
            path: /etc/zsh/zshenv
          register: _verify_zshenv

        - name: Assert /etc/zsh/zshenv exists with correct permissions
          ansible.builtin.assert:
            that:
              - _verify_zshenv.stat.exists
              - _verify_zshenv.stat.isreg
              - _verify_zshenv.stat.mode == '0644'
              - _verify_zshenv.stat.pw_name == 'root'
            fail_msg: >-
              /etc/zsh/zshenv missing or wrong permissions
              (expected root 0644)

        - name: Read /etc/zsh/zshenv
          ansible.builtin.slurp:
            src: /etc/zsh/zshenv
          register: _verify_zshenv_raw

        - name: Set zshenv text fact
          ansible.builtin.set_fact:
            _verify_zshenv_text: "{{ _verify_zshenv_raw.content | b64decode }}"

        - name: Assert zshenv contains ZDOTDIR
          ansible.builtin.assert:
            that: "'ZDOTDIR' in _verify_zshenv_text"
            fail_msg: "/etc/zsh/zshenv missing ZDOTDIR setting"

        - name: Assert zshenv sets ZDOTDIR to XDG path
          ansible.builtin.assert:
            that: "'XDG_CONFIG_HOME' in _verify_zshenv_text"
            fail_msg: "/etc/zsh/zshenv ZDOTDIR not referencing XDG_CONFIG_HOME"

        - name: Assert zshenv contains Ansible managed marker
          ansible.builtin.assert:
            that: "'Ansible' in _verify_zshenv_text"
            fail_msg: "/etc/zsh/zshenv missing Ansible managed marker"

    # ==========================================================
    # Summary
    # ==========================================================

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          shell role verify passed on
          {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}:
          zsh installed, login shell set to /usr/bin/zsh,
          XDG dirs created, /etc/profile.d/dev-paths.sh deployed,
          /etc/zsh/zshenv deployed with ZDOTDIR.
```

### Assertion summary

| Check | What is asserted | Cross-platform? |
|-------|-----------------|-----------------|
| zsh package installed | `'zsh' in ansible_facts.packages` | Yes (package name is `zsh` on Arch + Ubuntu) |
| Login shell | `getent_passwd[user][5] == '/usr/bin/zsh'` | Yes (binary path same on all distros) |
| XDG directories | `.config`, `.local/share`, `.local/bin`, `.cache` exist as dirs | Yes |
| `/etc/profile.d/dev-paths.sh` | exists, 0644/root, Ansible marker, PATH entries, GOPATH | Yes |
| `/etc/zsh/zshenv` | exists, 0644/root, ZDOTDIR, XDG_CONFIG_HOME, Ansible marker | Yes |

### What is NOT tested (and why)

- **Interactive shell session** -- cannot source `.zshrc` or verify `$PATH` expansion in molecule (no TTY, no login session). The role only deploys system-level files; user dotfiles are chezmoi's concern.
- **fish shell config** -- converge uses `shell_type: zsh`. Testing fish would require a separate converge variant or a second play. Out of scope for initial implementation; can add a `shell_type: fish` second-play later.
- **bash config** -- bash is preinstalled; the role only adds `/etc/profile.d/dev-paths.sh` (already tested). No bash-specific config beyond that.

## 7. Implementation Order

1. **Create `molecule/shared/converge.yml`** -- new file, content from Section 3.
2. **Create `molecule/shared/verify.yml`** -- new file, content from Section 6.
3. **Update `molecule/default/molecule.yml`** -- point playbooks to `../shared/`, remove vault_password_file, add `ANSIBLE_ROLES_PATH`, add `idempotence` to test_sequence.
4. **Delete `molecule/default/converge.yml`** -- replaced by shared.
5. **Delete `molecule/default/verify.yml`** -- replaced by shared.
6. **Create `molecule/docker/molecule.yml`** -- content from Section 4.
7. **Run `molecule test -s docker`** -- validate syntax, converge, idempotence, verify pass.
8. **Create `molecule/vagrant/molecule.yml`** -- content from Section 5.
9. **Create `molecule/vagrant/prepare.yml`** -- content from Section 5.
10. **Run `molecule test -s vagrant`** -- validate on Arch VM + Ubuntu VM.
11. **Fix any issues** -- adjust verify assertions if needed for Ubuntu differences.

## 8. Risks and Notes

### Testing shell config without interactive sessions

The role deploys **system-level** files (`/etc/profile.d/`, `/etc/zsh/zshenv`). These are validated by checking file existence, permissions, ownership, and content (via `slurp` + string assertions). Actual shell sourcing behavior cannot be tested in molecule -- this is acceptable because the role explicitly documents that per-user dotfiles are chezmoi's domain.

### User context in Docker containers

Docker runs as root. `shell_user` resolves to `root`. This means:
- XDG dirs are created under `/root/` (not `/home/user/`)
- Login shell is set for root
- This is valid for testing the role's mechanics but does not test the production path where `shell_user` is a non-root user

The Vagrant scenario compensates for this: `shell_user` resolves to `vagrant` (a real non-root user), testing the production-like path.

### `common` role dependency

The shell role includes `common` role for report tasks. The `skip-tags: report` in molecule provisioner config ensures these tasks are skipped, but the `common` role must still be resolvable. The `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"` setting makes all sibling roles available, including `common`. No issue expected.

### Idempotence of `ansible.builtin.user` shell change

On some systems, `ansible.builtin.user` reports a change even when the shell is already set correctly if other user attributes trigger a modification. This is unlikely with only the `shell:` parameter but worth noting. If idempotence fails on this task, investigate whether `name:` + `shell:` alone causes spurious changes.

### Gentoo not tested

Gentoo uses `app-shells/zsh` as the package name. Neither Docker nor Vagrant scenarios include Gentoo. This is acceptable -- Gentoo is listed in `meta/main.yml` but is a low-priority target. The role's Gentoo vars exist for completeness.

### Vault removal from default scenario

The current `molecule/default/converge.yml` loads `vault.yml`. The shell role does not use any vault variables. Removing the vault dependency simplifies the shared converge and eliminates the need for `vault_password_file` in molecule config. Verified by inspecting all defaults, vars, and tasks files -- no vault references.

### `package_facts` on Arch containers

`ansible.builtin.package_facts` with `manager: auto` detects `pacman` on Arch. The `zsh` package name appears as-is in `ansible_facts.packages`. On Ubuntu, `apt` is detected and `zsh` also appears as the package key. Verified compatible.

## 9. Success Criteria

1. `molecule test -s default` passes (syntax, converge, idempotence, verify) on localhost.
2. `molecule test -s docker` passes (syntax, create, converge, idempotence, verify, destroy) on Arch systemd container.
3. `molecule test -s vagrant` passes on both `arch-vm` and `ubuntu-noble` platforms.
4. No playbook duplication between scenarios (all reference `../shared/`).
5. Verify assertions cover: package installed, login shell, XDG dirs, `/etc/profile.d/` content, `/etc/zsh/zshenv` content.
6. Zero changes on idempotence run in all scenarios.
