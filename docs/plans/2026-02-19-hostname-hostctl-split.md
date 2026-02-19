# hostname/hostctl Role Split — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the `hostname` role into two independent roles: `hostname` (hostname + /etc/hosts) and `hostctl` (binary install + profile management), removing hardcoded values and adding proper validations.

**Architecture:** Clean split — no dependencies between roles. `hostname` sets the machine name and the `127.0.1.1` entry in `/etc/hosts`. `hostctl` is a standalone role that installs the hostctl binary and manages `/etc/hostctl/*.hosts` profiles. Both are listed independently in `workstation.yml`.

**Tech Stack:** Ansible, Molecule (ansible verifier, local driver), hostctl binary (GitHub releases / AUR / package manager)

---

## Reference files (read before starting)

- Design doc: `docs/plans/2026-02-19-hostname-hostctl-split-design.md`
- Current hostname tasks: `ansible/roles/hostname/tasks/` (all files)
- Current hostname template: `ansible/roles/hostname/templates/hostctl_profile.j2`
- Current hostname handler: `ansible/roles/hostname/handlers/main.yml`
- Molecule template: `ansible/roles/hostname/molecule/default/` (all 3 files — use as template for hostctl)
- Taskfile entry for hostname: `Taskfile.yml` (grep `test-hostname`)
- Playbook: `ansible/playbooks/workstation.yml` (lines 34-36)

---

## Task 1: Scaffold hostctl role structure

**Files:**
- Create: `ansible/roles/hostctl/defaults/main.yml`
- Create: `ansible/roles/hostctl/handlers/main.yml`
- Create: `ansible/roles/hostctl/meta/main.yml`
- Create: `ansible/roles/hostctl/vars/main.yml`
- Create: `ansible/roles/hostctl/tasks/main.yml`
- Create: `ansible/roles/hostctl/tasks/install.yml`
- Create: `ansible/roles/hostctl/tasks/download.yml`
- Create: `ansible/roles/hostctl/tasks/profiles.yml`
- Create: `ansible/roles/hostctl/templates/profile.j2`
- Create: `ansible/roles/hostctl/molecule/default/molecule.yml`
- Create: `ansible/roles/hostctl/molecule/default/converge.yml`
- Create: `ansible/roles/hostctl/molecule/default/verify.yml`

**Step 1: Use ansible-role-creator skill**

Run `/ansible-role-creator` with role name `hostctl`. This scaffolds the directory structure. If the skill creates placeholder files, overwrite them in subsequent tasks.

**Step 2: Verify scaffold**

```bash
ls ansible/roles/hostctl/
# Expected: defaults  handlers  meta  molecule  tasks  templates  vars
```

**Step 3: Commit scaffold**

```bash
git add ansible/roles/hostctl/
git commit -m "feat(hostctl): scaffold new role"
```

---

## Task 2: Write `hostctl` defaults and vars

**Files:**
- Modify: `ansible/roles/hostctl/defaults/main.yml`
- Modify: `ansible/roles/hostctl/vars/main.yml`
- Modify: `ansible/roles/hostctl/meta/main.yml`

**Step 1: Write `defaults/main.yml`**

```yaml
---
# === hostctl — profile-based /etc/hosts management ===

hostctl_enabled: true
hostctl_version: "latest"       # "latest" = GitHub API, or pinned "1.1.4"
hostctl_install_dir: /usr/local/bin
hostctl_github_repo: "guumaster/hostctl"
hostctl_github_api: "https://api.github.com"
hostctl_verify_checksum: true   # fail if no checksum file available in release

hostctl_profiles: {}
# Example:
#   hostctl_profiles:
#     dev:
#       - { ip: "127.0.0.1", host: "app.local" }
#       - { ip: "127.0.0.1", host: "api.local" }
#     docker:
#       - { ip: "172.17.0.1", host: "registry.local" }
```

**Step 2: Write `vars/main.yml`**

```yaml
---
# Internal mappings — not for users

_hostctl_arch_map:
  x86_64: amd64
  aarch64: arm64
  armv7l: armv6
```

**Step 3: Write `meta/main.yml`**

```yaml
---
galaxy_info:
  role_name: hostctl
  author: textyre
  description: >-
    Install hostctl binary and manage /etc/hosts profiles.
    Supports Arch Linux (AUR), Debian/Ubuntu (apt), and GitHub releases fallback.
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
    - name: Ubuntu
      versions: [all]
  galaxy_tags: [system, hosts, hostctl]
dependencies: []
```

**Step 4: Commit**

```bash
git add ansible/roles/hostctl/defaults/main.yml \
        ansible/roles/hostctl/vars/main.yml \
        ansible/roles/hostctl/meta/main.yml
git commit -m "feat(hostctl): add defaults, vars, meta"
```

---

## Task 3: Write `hostctl/handlers/main.yml`

**Files:**
- Modify: `ansible/roles/hostctl/handlers/main.yml`

**Step 1: Write handler with `listen:` directive**

```yaml
---
# Handlers for hostctl role

- name: Apply hostctl profiles
  ansible.builtin.command:
    cmd: "hostctl replace {{ item.key }} --from /etc/hostctl/{{ item.key }}.hosts"
  loop: "{{ hostctl_profiles | dict2items }}"
  listen: "apply hostctl profiles"
  changed_when: true
```

Note: `listen:` allows other roles to notify without tight coupling. The handler loops over all profiles and replaces each one.

**Step 2: Commit**

```bash
git add ansible/roles/hostctl/handlers/main.yml
git commit -m "feat(hostctl): add handler with listen directive"
```

---

## Task 4: Write `hostctl/templates/profile.j2`

**Files:**
- Read: `ansible/roles/hostname/templates/hostctl_profile.j2` (copy content)
- Modify: `ansible/roles/hostctl/templates/profile.j2`

**Step 1: Read the existing template from hostname role**

Read `ansible/roles/hostname/templates/hostctl_profile.j2` to get the exact content.

**Step 2: Write identical content to new location**

Copy the template content verbatim to `ansible/roles/hostctl/templates/profile.j2`.

**Step 3: Commit**

```bash
git add ansible/roles/hostctl/templates/profile.j2
git commit -m "feat(hostctl): add profile template (moved from hostname)"
```

---

## Task 5: Write `hostctl/tasks/download.yml`

This is the GitHub binary download fallback with block/rescue/always for guaranteed cleanup.

**Files:**
- Modify: `ansible/roles/hostctl/tasks/download.yml`

**Step 1: Write `download.yml`**

```yaml
---
# === hostctl — download binary from GitHub releases ===
# Fallback when package manager did not install hostctl.
# Uses block/rescue/always to guarantee cleanup of temp files.

- name: Install hostctl from GitHub releases
  block:

    # ---- Resolve version ----

    - name: Query latest hostctl release from GitHub API
      ansible.builtin.uri:
        url: "{{ hostctl_github_api }}/repos/{{ hostctl_github_repo }}/releases/latest"
        return_content: true
        headers:
          Accept: application/vnd.github.v3+json
      register: _hostctl_release
      when: hostctl_version == "latest"

    - name: Query specific hostctl release from GitHub API
      ansible.builtin.uri:
        url: "{{ hostctl_github_api }}/repos/{{ hostctl_github_repo }}/releases/tags/v{{ hostctl_version | regex_replace('^v', '') }}"
        return_content: true
        headers:
          Accept: application/vnd.github.v3+json
      register: _hostctl_release_pinned
      when: hostctl_version != "latest"

    - name: Set hostctl release facts
      ansible.builtin.set_fact:
        _hostctl_release_data: "{{ (hostctl_version == 'latest') | ternary(_hostctl_release, _hostctl_release_pinned) }}"

    # ---- Map architecture ----

    - name: Map system architecture to hostctl naming
      ansible.builtin.set_fact:
        _hostctl_arch: "{{ _hostctl_arch_map[ansible_facts['architecture']] | default(omit) }}"

    - name: Fail on unsupported architecture
      ansible.builtin.fail:
        msg: >-
          Unsupported architecture '{{ ansible_facts['architecture'] }}' for hostctl.
          Supported: x86_64, aarch64, armv7l.
      when: _hostctl_arch is not defined

    # ---- Find asset URLs ----

    - name: Find tarball asset URL
      ansible.builtin.set_fact:
        _hostctl_tarball_url: >-
          {{ _hostctl_release_data.json.assets
             | selectattr('name', 'match', '.*linux_' ~ _hostctl_arch ~ '\.tar\.gz$')
             | map(attribute='browser_download_url')
             | first }}
        _hostctl_tarball_name: >-
          {{ _hostctl_release_data.json.assets
             | selectattr('name', 'match', '.*linux_' ~ _hostctl_arch ~ '\.tar\.gz$')
             | map(attribute='name')
             | first }}

    - name: Find checksums asset URL
      ansible.builtin.set_fact:
        _hostctl_checksums_url: >-
          {{ _hostctl_release_data.json.assets
             | selectattr('name', 'match', '.*checksum.*')
             | map(attribute='browser_download_url')
             | first | default('') }}

    # ---- Checksum verification ----

    - name: Fail if checksum required but unavailable
      ansible.builtin.fail:
        msg: >-
          hostctl_verify_checksum is true but no checksum file found in release assets.
          Set hostctl_verify_checksum: false to skip verification.
      when:
        - hostctl_verify_checksum
        - _hostctl_checksums_url | length == 0

    - name: Download checksums file
      ansible.builtin.uri:
        url: "{{ _hostctl_checksums_url }}"
        return_content: true
      register: _hostctl_checksums
      when: _hostctl_checksums_url | length > 0

    - name: Extract SHA256 checksum for target asset
      ansible.builtin.set_fact:
        _hostctl_checksum: >-
          sha256:{{ _hostctl_checksums.content
             | regex_search('([a-f0-9]{64})\s+' ~ _hostctl_tarball_name, '\1')
             | first }}
      when: _hostctl_checksums is not skipped

    # ---- Download archive ----

    - name: Download hostctl archive (with checksum)
      ansible.builtin.get_url:
        url: "{{ _hostctl_tarball_url }}"
        dest: /tmp/hostctl.tar.gz
        checksum: "{{ _hostctl_checksum }}"
        mode: '0644'
      when: _hostctl_checksum is defined

    - name: Download hostctl archive (no checksum available)
      ansible.builtin.get_url:
        url: "{{ _hostctl_tarball_url }}"
        dest: /tmp/hostctl.tar.gz
        mode: '0644'
      when: _hostctl_checksum is not defined

    - name: Verify archive was downloaded
      ansible.builtin.stat:
        path: /tmp/hostctl.tar.gz
      register: _hostctl_archive_stat

    - name: Assert archive exists
      ansible.builtin.assert:
        that: _hostctl_archive_stat.stat.exists
        fail_msg: "hostctl archive /tmp/hostctl.tar.gz was not downloaded successfully"

    # ---- Extract and install ----

    - name: Create temporary extraction directory
      ansible.builtin.tempfile:
        state: directory
        prefix: hostctl_
      register: _hostctl_tmpdir

    - name: Extract hostctl archive
      ansible.builtin.unarchive:
        src: /tmp/hostctl.tar.gz
        dest: "{{ _hostctl_tmpdir.path }}"
        remote_src: true

    - name: Verify binary was extracted
      ansible.builtin.stat:
        path: "{{ _hostctl_tmpdir.path }}/hostctl"
      register: _hostctl_bin_stat

    - name: Assert binary exists and is executable
      ansible.builtin.assert:
        that:
          - _hostctl_bin_stat.stat.exists
          - _hostctl_bin_stat.stat.executable
        fail_msg: "hostctl binary was not found or is not executable after extraction"

    - name: Install hostctl binary
      ansible.builtin.copy:
        src: "{{ _hostctl_tmpdir.path }}/hostctl"
        dest: "{{ hostctl_install_dir }}/hostctl"
        remote_src: true
        owner: root
        group: root
        mode: '0755'

    - name: Verify hostctl installation
      ansible.builtin.command: "{{ hostctl_install_dir }}/hostctl --version"
      register: _hostctl_install_verify
      changed_when: false
      failed_when: _hostctl_install_verify.rc != 0

  always:
    - name: Cleanup hostctl temporary files
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /tmp/hostctl.tar.gz
        - "{{ _hostctl_tmpdir.path | default('') }}"
      when: item | length > 0
```

**Step 2: Commit**

```bash
git add ansible/roles/hostctl/tasks/download.yml
git commit -m "feat(hostctl): add GitHub download task with block/rescue/always cleanup"
```

---

## Task 6: Write `hostctl/tasks/install.yml`

Handles pkg manager → AUR → GitHub fallback with version idempotency.

**Files:**
- Modify: `ansible/roles/hostctl/tasks/install.yml`

**Step 1: Write `install.yml`**

```yaml
---
# === hostctl — installation ===
# Strategy: package manager (non-Arch) → AUR (Arch) → GitHub releases fallback
# Idempotent: skips re-download if pinned version already installed.

# ---- Version idempotency check ----

- name: Get installed hostctl version
  ansible.builtin.command: "{{ hostctl_install_dir }}/hostctl --version"
  register: _hostctl_installed_ver
  changed_when: false
  failed_when: false

- name: Set skip flag if pinned version already installed
  ansible.builtin.set_fact:
    _hostctl_skip_install: >-
      {{ _hostctl_installed_ver.rc == 0
         and hostctl_version != "latest"
         and hostctl_version in (_hostctl_installed_ver.stdout | default('')) }}

- name: "Report: hostctl already at requested version"
  ansible.builtin.debug:
    msg: "hostctl {{ hostctl_version }} already installed — skipping"
  when: _hostctl_skip_install | bool

# ---- Package manager install (non-Arch) ----

- name: Install hostctl via package manager
  ansible.builtin.package:
    name: hostctl
    state: present
  when:
    - not (_hostctl_skip_install | bool)
    - ansible_facts['os_family'] not in ['Archlinux']
  register: _hostctl_pkg
  failed_when: false   # allow fallback to GitHub

- name: "Report: hostctl package install result"
  ansible.builtin.debug:
    msg: >-
      hostctl package install {{ 'succeeded' if (_hostctl_pkg is not failed) else 'failed — will try GitHub fallback.' }}
  when:
    - _hostctl_pkg is defined
    - not (_hostctl_pkg is skipped)

# ---- AUR install (Arch Linux) ----

- name: Install hostctl via AUR (Arch Linux)
  kewlfft.aur.aur:
    name: hostctl-bin
    use: yay
    state: present
  become: true
  become_user: "{{ yay_build_user | default('aur_builder') }}"
  when:
    - not (_hostctl_skip_install | bool)
    - ansible_facts['os_family'] == 'Archlinux'

# ---- GitHub fallback ----

- name: Check if hostctl available after package/AUR install
  ansible.builtin.command: command -v hostctl
  register: _hostctl_which
  changed_when: false
  failed_when: false
  when: not (_hostctl_skip_install | bool)

- name: Install hostctl from GitHub releases (fallback)
  ansible.builtin.include_tasks: download.yml
  when:
    - not (_hostctl_skip_install | bool)
    - _hostctl_which.rc | default(1) != 0
    - not ansible_check_mode

- name: "Note: hostctl GitHub download skipped in check mode"
  ansible.builtin.debug:
    msg: "hostctl GitHub download skipped — running in check mode"
  when:
    - not (_hostctl_skip_install | bool)
    - _hostctl_which.rc | default(1) != 0
    - ansible_check_mode

# ---- Final verification ----

- name: Verify hostctl is installed and working
  ansible.builtin.command: hostctl --version
  register: _hostctl_version_check
  changed_when: false
  failed_when: _hostctl_version_check.rc != 0
```

**Step 2: Commit**

```bash
git add ansible/roles/hostctl/tasks/install.yml
git commit -m "feat(hostctl): add install task with version idempotency and GitHub fallback"
```

---

## Task 7: Write `hostctl/tasks/profiles.yml`

**Files:**
- Modify: `ansible/roles/hostctl/tasks/profiles.yml`

**Step 1: Write `profiles.yml`**

```yaml
---
# === hostctl — profile deployment ===
# Deploys /etc/hostctl/<name>.hosts files and applies them via handler.

- name: Create /etc/hostctl directory
  ansible.builtin.file:
    path: /etc/hostctl
    state: directory
    owner: root
    group: root
    mode: '0755'

- name: Deploy hostctl profile files
  ansible.builtin.template:
    src: profile.j2
    dest: "/etc/hostctl/{{ item.key }}.hosts"
    owner: root
    group: root
    mode: '0644'
  loop: "{{ hostctl_profiles | dict2items }}"
  notify: apply hostctl profiles

- name: Verify profile files deployed
  ansible.builtin.stat:
    path: "/etc/hostctl/{{ item.key }}.hosts"
  register: _hostctl_profile_stat
  loop: "{{ hostctl_profiles | dict2items }}"

- name: Assert all profile files exist
  ansible.builtin.assert:
    that: item.stat.exists
    fail_msg: "hostctl profile file missing: /etc/hostctl/{{ item.item.key }}.hosts"
  loop: "{{ _hostctl_profile_stat.results }}"
```

**Step 2: Commit**

```bash
git add ansible/roles/hostctl/tasks/profiles.yml
git commit -m "feat(hostctl): add profiles task with post-deploy verification"
```

---

## Task 8: Write `hostctl/tasks/main.yml`

The orchestrator — asserts, then calls install and profiles.

**Files:**
- Modify: `ansible/roles/hostctl/tasks/main.yml`

**Step 1: Write `main.yml`**

```yaml
---
# === hostctl — install binary + manage /etc/hosts profiles ===
# Entry point: asserts → install → profiles

# ---- Guard ----

- name: Assert hostctl_enabled is true
  ansible.builtin.assert:
    that: hostctl_enabled | bool
    fail_msg: "hostctl_enabled is false — include this role only when hostctl is needed"

# ---- Install ----

- name: Install hostctl binary
  ansible.builtin.include_tasks: install.yml
  tags: ['hostctl', 'hostctl:install']

# ---- Profiles ----

- name: Deploy hostctl profiles
  ansible.builtin.include_tasks: profiles.yml
  when: hostctl_profiles | length > 0
  tags: ['hostctl', 'hostctl:profiles']
```

**Step 2: Commit**

```bash
git add ansible/roles/hostctl/tasks/main.yml
git commit -m "feat(hostctl): add orchestrator main.yml"
```

---

## Task 9: Write `hostctl` Molecule tests

**Files:**
- Modify: `ansible/roles/hostctl/molecule/default/molecule.yml`
- Modify: `ansible/roles/hostctl/molecule/default/converge.yml`
- Modify: `ansible/roles/hostctl/molecule/default/verify.yml`

**Step 1: Write `molecule.yml`** (copy structure from hostname role)

```yaml
---
driver:
  name: default
  options:
    managed: false

platforms:
  - name: localhost

provisioner:
  name: ansible
  config_options:
    defaults:
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
  playbooks:
    converge: converge.yml
    verify: verify.yml
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Step 2: Write `converge.yml`**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  roles:
    - role: hostctl
      vars:
        hostctl_version: "latest"
        hostctl_verify_checksum: false   # CI may not have internet for checksum
        hostctl_profiles:
          test:
            - { ip: "127.0.0.1", host: "molecule.local" }
```

**Step 3: Write `verify.yml`**

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true

  tasks:
    - name: Verify hostctl binary is installed
      ansible.builtin.command: hostctl --version
      register: _verify_version
      changed_when: false
      failed_when: _verify_version.rc != 0

    - name: Assert hostctl responds to --version
      ansible.builtin.assert:
        that: _verify_version.stdout | length > 0
        fail_msg: "hostctl --version returned empty output"

    - name: Check test profile file exists
      ansible.builtin.stat:
        path: /etc/hostctl/test.hosts
      register: _verify_profile

    - name: Assert test profile was deployed
      ansible.builtin.assert:
        that: _verify_profile.stat.exists
        fail_msg: "/etc/hostctl/test.hosts was not deployed"

    - name: Verify profile contains expected entry
      ansible.builtin.command: grep -q "molecule.local" /etc/hostctl/test.hosts
      register: _verify_entry
      changed_when: false
      failed_when: _verify_entry.rc != 0

    - name: Verify profile is applied to /etc/hosts
      ansible.builtin.command: grep -q "molecule.local" /etc/hosts
      register: _verify_applied
      changed_when: false
      failed_when: _verify_applied.rc != 0

    - name: Verify base /etc/hosts entries were not overwritten by hostctl
      ansible.builtin.command: grep -q "127.0.0.1" /etc/hosts
      register: _verify_base
      changed_when: false
      failed_when: _verify_base.rc != 0

    - name: Show result
      ansible.builtin.debug:
        msg:
          - "hostctl version: {{ _verify_version.stdout }}"
          - "Profile /etc/hostctl/test.hosts: present"
          - "Entry molecule.local in /etc/hostctl/test.hosts: found"
          - "Entry molecule.local applied to /etc/hosts: found"
          - "Base 127.0.0.1 entry in /etc/hosts: intact"
```

**Step 4: Commit**

```bash
git add ansible/roles/hostctl/molecule/
git commit -m "test(hostctl): add molecule tests for install and profile deployment"
```

---

## Task 10: Run syntax check on `hostctl` role

**Step 1: Run ansible syntax check via `/ansible` skill**

Use `/ansible` skill with command:
```
ansible-playbook --syntax-check <path to converge.yml>
```
Or run `molecule syntax` inside `ansible/roles/hostctl/`.

Expected: No errors.

**Step 2: If errors — fix before continuing**

Do not proceed to hostname refactoring until hostctl passes syntax check.

---

## Task 11: Refactor `hostname` — remove hostctl code

**Files:**
- Modify: `ansible/roles/hostname/defaults/main.yml`
- Modify: `ansible/roles/hostname/tasks/main.yml`
- Modify: `ansible/roles/hostname/tasks/hosts.yml`
- Delete: `ansible/roles/hostname/tasks/hostctl.yml`
- Delete: `ansible/roles/hostname/tasks/hostctl_download.yml`
- Delete: `ansible/roles/hostname/templates/hostctl_profile.j2`
- Modify: `ansible/roles/hostname/handlers/main.yml`

**Step 1: Write new `hostname/defaults/main.yml`**

```yaml
---
# === Hostname + /etc/hosts ===

hostname_name: ""    # REQUIRED — role will assert this is set
hostname_domain: ""  # Optional FQDN suffix: "example.com" → 127.0.1.1 host.example.com host
```

**Step 2: Add assert at top of `hostname/tasks/main.yml`**

Read the current file first, then insert this block BEFORE the "Set hostname" task (before line 10):

```yaml
# ---- Input validation ----

- name: Assert hostname_name is provided
  ansible.builtin.assert:
    that:
      - hostname_name is defined
      - hostname_name | length > 0
    fail_msg: >-
      hostname_name is required and must not be empty.
      Set it in group_vars, host_vars, or playbook vars.
  tags: ['hostname']
```

**Step 3: Clean up `hostname/tasks/hosts.yml`**

Read the current file. Remove the two blocks at the bottom:
- `# ---- hostctl — установка ----` block (the `include_tasks: hostctl.yml` task)
- Both `# ---- Логирование ----` tasks that reference `hostname_hostctl_enabled`

Keep only:
- `Build hostname line for /etc/hosts`
- `Ensure /etc/hosts contains hostname`
- `Verify hostname is present in /etc/hosts`

Replace the logging section with a single unconditional report:
```yaml
- name: "Report: Hosts"
  ansible.builtin.include_role:
    name: common
    tasks_from: report_phase.yml
  vars:
    _rpt_fact: "_hostname_phases"
    _rpt_phase: "Configure /etc/hosts"
    _rpt_detail: "127.0.1.1 {{ hostname_name }}{{ ('.' ~ hostname_domain ~ ' ' ~ hostname_name) if hostname_domain else '' }}"
  tags: ['hostname', 'report']
```

**Step 4: Write empty `hostname/handlers/main.yml`**

```yaml
---
# No handlers needed — hostname role has no async side effects
```

**Step 5: Delete obsolete files**

```bash
rm ansible/roles/hostname/tasks/hostctl.yml
rm ansible/roles/hostname/tasks/hostctl_download.yml
rm ansible/roles/hostname/templates/hostctl_profile.j2
```

**Step 6: Commit**

```bash
git add ansible/roles/hostname/
git commit -m "refactor(hostname): remove hostctl code, make hostname_name required"
```

---

## Task 12: Update `hostname` Molecule

**Files:**
- Modify: `ansible/roles/hostname/molecule/default/converge.yml`

**Step 1: Read current converge.yml**

Read `ansible/roles/hostname/molecule/default/converge.yml`.

**Step 2: Remove hostctl vars**

The current file has `hostname_name: "archbox"` — that's fine for tests. Just ensure there are no `hostname_hostctl_*` vars. The file should only pass `hostname_name`:

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  pre_tasks:
    - name: Ensure we're running on Arch Linux
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] == 'Archlinux'
        fail_msg: "This test requires Arch Linux"

  roles:
    - role: hostname
      vars:
        hostname_name: "archbox"
```

**Step 3: Commit**

```bash
git add ansible/roles/hostname/molecule/default/converge.yml
git commit -m "test(hostname): remove hostctl vars from molecule converge"
```

---

## Task 13: Update `workstation.yml` and `Taskfile`

**Files:**
- Modify: `ansible/playbooks/workstation.yml`
- Modify: `Taskfile.yml`

**Step 1: Add `hostctl` role to `workstation.yml`**

Read `ansible/playbooks/workstation.yml`. Find the `hostname` entry (around line 34-35). Add `hostctl` immediately after:

```yaml
    - role: hostname
      tags: [system, hostname]

    - role: hostctl
      tags: [system, hostctl]
```

**Step 2: Add `test-hostctl` task to `Taskfile.yml`**

Find the `test-hostname:` task block (grep for it). Add a new `test-hostctl:` task immediately after, following the same structure:

```yaml
  test-hostctl:
    desc: "Run molecule tests for hostctl"
    deps: [_ensure-venv, _check-vault]
    dir: '{{.ANSIBLE_DIR}}/roles/hostctl'
    env:
      MOLECULE_PROJECT_DIRECTORY: '{{.TASKFILE_DIR}}/{{.ANSIBLE_DIR}}'
    cmds:
      - 'echo "==> Testing hostctl role..."'
      - '{{.PREFIX}} molecule test'
```

**Step 3: Add `test-hostctl` to the `test:` task's command list**

In the `test:` task, find `- task: test-hostname` and add `- task: test-hostctl` immediately after.

**Step 4: Commit**

```bash
git add ansible/playbooks/workstation.yml Taskfile.yml
git commit -m "feat: add hostctl role to workstation playbook and Taskfile"
```

---

## Task 14: Final syntax check — both roles

**Step 1: Run syntax check on both roles via `/ansible` skill**

```bash
# In ansible/ directory:
ansible-playbook playbooks/workstation.yml --syntax-check
```

Expected: `playbook: playbooks/workstation.yml` with no errors.

**Step 2: Run ansible-lint on both roles**

```bash
ansible-lint roles/hostname/ roles/hostctl/
```

Fix any lint warnings before declaring done.

**Step 3: Commit any lint fixes**

```bash
git add ansible/roles/hostname/ ansible/roles/hostctl/
git commit -m "fix: address ansible-lint warnings in hostname and hostctl roles"
```

---

## Task 15: Run molecule for `hostname` role

**Step 1: Run via `/ansible` skill or Taskfile**

```bash
task test-hostname
```

Expected: syntax → converge → verify all PASS.

If fails: the assert for `hostname_name` is present in tests — converge.yml already passes `hostname_name: "archbox"` so it should pass.

---

## Task 16: Verify `hostctl` role on remote VM

Since molecule for hostctl requires internet access to download the binary, run via `/ansible` skill:

```bash
task test-hostctl
```

Or run molecule directly on the remote VM. Expected: syntax → converge → verify all PASS.

---

## Done criteria

- [ ] `ansible/roles/hostctl/` exists with all files
- [ ] `ansible/roles/hostname/tasks/hostctl.yml` does not exist
- [ ] `ansible/roles/hostname/tasks/hostctl_download.yml` does not exist
- [ ] `ansible/roles/hostname/templates/hostctl_profile.j2` does not exist
- [ ] `hostname_name` has no default in `hostname/defaults/main.yml`
- [ ] Assert for `hostname_name` is at top of `hostname/tasks/main.yml`
- [ ] All `hostctl_*` variables documented in `hostctl/defaults/main.yml`
- [ ] No hardcoded GitHub URLs in task files (all via `hostctl_github_*` vars)
- [ ] Handler in hostctl has `listen:` directive
- [ ] `workstation.yml` has both `hostname` and `hostctl` roles
- [ ] `Taskfile.yml` has `test-hostctl` task
- [ ] `task check` passes (syntax check)
- [ ] `task lint` passes (ansible-lint)
- [ ] `task test-hostname` molecule passes
- [ ] `task test-hostctl` molecule passes
