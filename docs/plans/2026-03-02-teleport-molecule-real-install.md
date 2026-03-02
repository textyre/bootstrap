# Teleport Molecule Tests — Real Binary Install

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix teleport molecule tests to use real binary installation, make CI green, close PR #45 and merge PR #58.

**Architecture:** Docker and Vagrant both use `teleport_install_method: binary` (real download from cdn.teleport.dev). Handler is tagged `[teleport, service]` so it's skipped with `skip-tags: service`. Verify checks installation artifacts only (binary, config, dirs, unit file), NOT service state.

**Tech Stack:** Ansible 2.20, Molecule 25.12, Docker (CI), Vagrant/libvirt (optional)

**Branch:** `ci/track-teleport` (PR #58)

---

### Task 1: Update handler — add listen directive and service tag

The handler currently fires on config deployment, even when `skip-tags: service` is set. Handlers respect `--skip-tags` in Ansible 2.17+. Adding the `service` tag prevents the handler from firing when service management is skipped. Adding `listen:` follows project convention.

**Files:**
- Modify: `ansible/roles/teleport/handlers/main.yml`

**Step 1: Apply the change**

Replace the entire file with:

```yaml
---
- name: "Restart teleport"
  ansible.builtin.service:
    name: "{{ teleport_service_name[ansible_facts['service_mgr']] | default('teleport') }}"
    state: restarted
  tags: [teleport, service]
  listen: "restart teleport"
```

Note: `notify:` in `configure.yml` uses `"Restart teleport"` — Ansible handler matching is case-insensitive, so `listen: "restart teleport"` matches `notify: "Restart teleport"`.

Wait — actually Ansible handler name matching IS case-sensitive for `notify:` vs handler `name:`. But `listen:` is a separate mechanism. The `notify:` in configure.yml says `"Restart teleport"`. This matches the handler by `name: "Restart teleport"`. The `listen:` directive adds an ADDITIONAL trigger name. So both `notify: "Restart teleport"` (matched by name) and `notify: "restart teleport"` (matched by listen) work.

No, wait: if we change the handler name, we break the existing notify. Let me check: configure.yml has `notify: "Restart teleport"` and the handler name is `"Restart teleport"`. Keep the name exactly as-is. The `listen:` just adds an alias.

Final file:

```yaml
---
- name: "Restart teleport"
  ansible.builtin.service:
    name: "{{ teleport_service_name[ansible_facts['service_mgr']] | default('teleport') }}"
    state: restarted
  tags: [teleport, service]
  listen: "restart teleport"
```

**Step 2: Verify ansible-lint passes**

Run: `cd ansible/roles/teleport && ansible-lint handlers/main.yml`
Expected: no errors

**Step 3: Commit**

```bash
git add ansible/roles/teleport/handlers/main.yml
git commit -m "fix(teleport): tag handler with [service], add listen directive"
```

---

### Task 2: Update install.yml — stat check, unique filename, systemd unit

Current binary install has no idempotency (re-downloads every run) and no systemd unit file. Fix both.

**Files:**
- Modify: `ansible/roles/teleport/tasks/install.yml`

**Step 1: Apply changes to the binary install block**

Replace the binary install block (line 49 onwards — `"Install Teleport via binary download"` block) with:

```yaml
- name: "Install Teleport via binary download"
  when: teleport_install_method == 'binary'
  tags: [teleport, install]
  block:
    - name: "Set architecture mapping for Teleport download"
      ansible.builtin.set_fact:
        teleport_arch: >-
          {{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_architecture]
             | default(ansible_architecture) }}

    - name: "Check if teleport binary already installed"
      ansible.builtin.stat:
        path: /usr/local/bin/teleport
      register: _teleport_binary_stat

    - name: "Download Teleport binary"
      ansible.builtin.get_url:
        url: "https://cdn.teleport.dev/teleport-v{{ teleport_version }}-linux-{{ teleport_arch }}-bin.tar.gz"
        dest: "/tmp/teleport-{{ teleport_version }}-{{ teleport_arch }}.tar.gz"
        mode: "0644"
      when: not _teleport_binary_stat.stat.exists

    - name: "Extract Teleport binary"
      ansible.builtin.unarchive:
        src: "/tmp/teleport-{{ teleport_version }}-{{ teleport_arch }}.tar.gz"
        dest: /usr/local/bin/
        remote_src: true
        extra_opts: [--strip-components=1]
      when: not _teleport_binary_stat.stat.exists

    - name: "Deploy teleport systemd unit for binary install"
      ansible.builtin.copy:
        content: |
          [Unit]
          Description=Teleport SSH Access Platform
          After=network.target

          [Service]
          Type=simple
          ExecStart=/usr/local/bin/teleport start --config=/etc/teleport.yaml
          Restart=on-failure
          RestartSec=5

          [Install]
          WantedBy=multi-user.target
        dest: /etc/systemd/system/teleport.service
        mode: "0644"
      when: ansible_facts['service_mgr'] == 'systemd'
      register: _teleport_unit_result

    - name: "Reload systemd daemon after unit file change"
      ansible.builtin.systemd:
        daemon_reload: true
      when:
        - ansible_facts['service_mgr'] == 'systemd'
        - _teleport_unit_result is changed
```

**Step 2: Verify ansible-lint passes**

Run: `cd ansible/roles/teleport && ansible-lint tasks/install.yml`
Expected: no errors

**Step 3: Commit**

```bash
git add ansible/roles/teleport/tasks/install.yml
git commit -m "fix(teleport): add stat check, versioned filename, systemd unit for binary install"
```

---

### Task 3: Update Docker prepare.yml — ca-certificates, no mocks

Current prepare.yml is minimal (cache updates only). Ubuntu needs ca-certificates for SSL to cdn.teleport.dev.

**Files:**
- Modify: `ansible/roles/teleport/molecule/docker/prepare.yml`

**Step 1: Replace prepare.yml**

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: true
  tasks:
    - name: Update pacman package cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Install ca-certificates (Ubuntu)
      ansible.builtin.apt:
        name: ca-certificates
        state: present
      when: ansible_facts['os_family'] == 'Debian'
```

**Step 2: Verify ansible-lint passes**

Run: `cd ansible/roles/teleport && ansible-lint molecule/docker/prepare.yml`
Expected: no errors

**Step 3: Commit**

```bash
git add ansible/roles/teleport/molecule/docker/prepare.yml
git commit -m "fix(teleport): add ca-certificates to Docker prepare (no mocks)"
```

---

### Task 4: Update Vagrant molecule.yml — binary install for ubuntu-base

Current vagrant molecule.yml only sets `teleport_install_method: binary` for arch-vm, not ubuntu-base. Both should use binary install for consistency.

**Files:**
- Modify: `ansible/roles/teleport/molecule/vagrant/molecule.yml`

**Step 1: Add ubuntu-base host_vars**

In the `provisioner.inventory.host_vars` section, add `ubuntu-base`:

```yaml
  inventory:
    host_vars:
      arch-vm:
        teleport_install_method: binary
      ubuntu-base:
        teleport_install_method: binary
```

**Step 2: Verify YAML syntax**

Run: `python3 -c "import yaml; yaml.safe_load(open('ansible/roles/teleport/molecule/vagrant/molecule.yml'))"`
Expected: no errors

**Step 3: Commit**

```bash
git add ansible/roles/teleport/molecule/vagrant/molecule.yml
git commit -m "fix(teleport): set binary install for ubuntu-base in vagrant"
```

---

### Task 5: Update shared/verify.yml — comprehensive assertions

Rewrite verify.yml with correct checks:
- `command -v` instead of `which` (POSIX compliant)
- Add systemd unit file existence and content check
- Remove service enabled check (service is skipped in all molecule scenarios)
- Keep all config content checks

**Files:**
- Modify: `ansible/roles/teleport/molecule/shared/verify.yml`

**Step 1: Replace verify.yml with comprehensive version**

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true

  tasks:
    # -----------------------------------------------------------------------
    # 1. Teleport binary
    # -----------------------------------------------------------------------
    - name: Check teleport binary is in PATH
      ansible.builtin.command: command -v teleport
      register: _teleport_verify_which
      changed_when: false
      failed_when: _teleport_verify_which.rc != 0

    - name: Run teleport version
      ansible.builtin.command: teleport version
      register: _teleport_verify_version
      changed_when: false
      failed_when: false

    - name: Assert teleport version runs successfully
      ansible.builtin.assert:
        that:
          - _teleport_verify_version.rc == 0
        fail_msg: >
          'teleport version' failed with rc={{ _teleport_verify_version.rc }}:
          {{ _teleport_verify_version.stderr | default('') }}

    - name: Assert teleport version output contains Teleport
      ansible.builtin.assert:
        that:
          - _teleport_verify_version.stdout is regex('(?i)teleport')
        fail_msg: >
          'teleport version' output does not mention Teleport:
          {{ _teleport_verify_version.stdout }}
      when: _teleport_verify_version.rc == 0

    - name: Show teleport version output
      ansible.builtin.debug:
        msg: "{{ _teleport_verify_version.stdout }}"
      when: _teleport_verify_version.rc == 0

    # -----------------------------------------------------------------------
    # 2. Configuration file — existence and permissions
    # -----------------------------------------------------------------------
    - name: Stat /etc/teleport.yaml
      ansible.builtin.stat:
        path: /etc/teleport.yaml
      register: _teleport_verify_conf_stat

    - name: Assert /etc/teleport.yaml exists
      ansible.builtin.assert:
        that:
          - _teleport_verify_conf_stat.stat.exists
        fail_msg: "/etc/teleport.yaml does not exist"

    - name: Assert /etc/teleport.yaml owner and permissions
      ansible.builtin.assert:
        that:
          - _teleport_verify_conf_stat.stat.pw_name == 'root'
          - _teleport_verify_conf_stat.stat.gr_name == 'root'
          - _teleport_verify_conf_stat.stat.mode == '0600'
        fail_msg: >
          /etc/teleport.yaml has wrong owner/mode:
          owner={{ _teleport_verify_conf_stat.stat.pw_name }}
          group={{ _teleport_verify_conf_stat.stat.gr_name }}
          mode={{ _teleport_verify_conf_stat.stat.mode }}

    # -----------------------------------------------------------------------
    # 3. Configuration file — content validation
    # -----------------------------------------------------------------------
    - name: Slurp /etc/teleport.yaml
      ansible.builtin.slurp:
        src: /etc/teleport.yaml
      register: _teleport_verify_conf_raw
      when: _teleport_verify_conf_stat.stat.exists

    - name: Assert slurp succeeded
      ansible.builtin.assert:
        that:
          - "'content' in _teleport_verify_conf_raw"
        fail_msg: "Failed to slurp /etc/teleport.yaml"
      when: _teleport_verify_conf_stat.stat.exists

    - name: Decode teleport config
      ansible.builtin.set_fact:
        _teleport_verify_conf_content: "{{ _teleport_verify_conf_raw.content | b64decode }}"
      when:
        - _teleport_verify_conf_stat.stat.exists
        - "'content' in _teleport_verify_conf_raw"

    - name: Assert config contains version v3
      ansible.builtin.assert:
        that:
          - "'version: v3' in _teleport_verify_conf_content"
        fail_msg: "Config does not contain 'version: v3'"
      when: _teleport_verify_conf_content is defined

    - name: Assert config contains auth_server address
      ansible.builtin.assert:
        that:
          - _teleport_verify_conf_content is regex('auth_server:\s*.*localhost:3025')
        fail_msg: "Config does not contain auth_server with localhost:3025"
      when: _teleport_verify_conf_content is defined

    - name: Assert config contains nodename
      ansible.builtin.assert:
        that:
          - _teleport_verify_conf_content is regex('nodename:\s*.*molecule-test')
        fail_msg: "Config does not contain expected nodename 'molecule-test'"
      when: _teleport_verify_conf_content is defined

    - name: Assert config contains auth_token
      ansible.builtin.assert:
        that:
          - "'auth_token:' in _teleport_verify_conf_content"
        fail_msg: "Config does not contain 'auth_token:'"
      when: _teleport_verify_conf_content is defined

    - name: Assert config contains data_dir
      ansible.builtin.assert:
        that:
          - "'data_dir: /var/lib/teleport' in _teleport_verify_conf_content"
        fail_msg: "Config does not contain 'data_dir: /var/lib/teleport'"
      when: _teleport_verify_conf_content is defined

    - name: Assert ssh_service section present
      ansible.builtin.assert:
        that:
          - "'ssh_service:' in _teleport_verify_conf_content"
        fail_msg: "Config does not contain 'ssh_service:' section"
      when: _teleport_verify_conf_content is defined

    - name: Assert proxy_service section present
      ansible.builtin.assert:
        that:
          - "'proxy_service:' in _teleport_verify_conf_content"
        fail_msg: "Config does not contain 'proxy_service:' section"
      when: _teleport_verify_conf_content is defined

    - name: Assert auth_service section present
      ansible.builtin.assert:
        that:
          - "'auth_service:' in _teleport_verify_conf_content"
        fail_msg: "Config does not contain 'auth_service:' section"
      when: _teleport_verify_conf_content is defined

    - name: Assert session_recording mode
      ansible.builtin.assert:
        that:
          - _teleport_verify_conf_content is regex('mode:\s*["\x27]?node["\x27]?')
        fail_msg: >
          Config does not contain session recording mode 'node'.
          Content: {{ _teleport_verify_conf_content }}
      when: _teleport_verify_conf_content is defined

    - name: Assert Ansible managed header
      ansible.builtin.assert:
        that:
          - _teleport_verify_conf_content is regex('(?i)(ansible.managed|managed.by.ansible)')
        fail_msg: "Config does not contain Ansible managed header"
      when: _teleport_verify_conf_content is defined

    # -----------------------------------------------------------------------
    # 4. Data directory
    # -----------------------------------------------------------------------
    - name: Stat /var/lib/teleport
      ansible.builtin.stat:
        path: /var/lib/teleport
      register: _teleport_verify_datadir

    - name: Assert /var/lib/teleport exists and is a directory
      ansible.builtin.assert:
        that:
          - _teleport_verify_datadir.stat.exists
          - _teleport_verify_datadir.stat.isdir
        fail_msg: "/var/lib/teleport does not exist or is not a directory"

    - name: Assert /var/lib/teleport owner and permissions
      ansible.builtin.assert:
        that:
          - _teleport_verify_datadir.stat.pw_name == 'root'
          - _teleport_verify_datadir.stat.gr_name == 'root'
          - _teleport_verify_datadir.stat.mode == '0750'
        fail_msg: >
          /var/lib/teleport has wrong owner/mode:
          owner={{ _teleport_verify_datadir.stat.pw_name }}
          group={{ _teleport_verify_datadir.stat.gr_name }}
          mode={{ _teleport_verify_datadir.stat.mode }}

    # -----------------------------------------------------------------------
    # 5. Systemd unit file (binary install)
    # -----------------------------------------------------------------------
    - name: Stat teleport systemd unit
      ansible.builtin.stat:
        path: /etc/systemd/system/teleport.service
      register: _teleport_verify_unit

    - name: Assert teleport systemd unit exists
      ansible.builtin.assert:
        that:
          - _teleport_verify_unit.stat.exists
        fail_msg: "/etc/systemd/system/teleport.service does not exist"

    - name: Slurp teleport systemd unit
      ansible.builtin.slurp:
        src: /etc/systemd/system/teleport.service
      register: _teleport_verify_unit_raw
      when: _teleport_verify_unit.stat.exists

    - name: Decode teleport unit content
      ansible.builtin.set_fact:
        _teleport_verify_unit_content: "{{ _teleport_verify_unit_raw.content | b64decode }}"
      when:
        - _teleport_verify_unit.stat.exists
        - "'content' in _teleport_verify_unit_raw"

    - name: Assert unit contains correct ExecStart
      ansible.builtin.assert:
        that:
          - "'ExecStart=/usr/local/bin/teleport start --config=/etc/teleport.yaml' in _teleport_verify_unit_content"
        fail_msg: >
          Unit file missing correct ExecStart.
          Content: {{ _teleport_verify_unit_content }}
      when: _teleport_verify_unit_content is defined

    - name: Assert unit contains Restart policy
      ansible.builtin.assert:
        that:
          - "'Restart=on-failure' in _teleport_verify_unit_content"
        fail_msg: "Unit file missing Restart=on-failure"
      when: _teleport_verify_unit_content is defined

    # -----------------------------------------------------------------------
    # 6. Diagnostic notes
    # -----------------------------------------------------------------------
    - name: Note — service management skipped (skip-tags service)
      ansible.builtin.debug:
        msg: >
          Service start, enable, and runtime checks are skipped in molecule
          tests (skip-tags: service). Teleport requires a live auth cluster
          to start. This test validates installation artifacts only:
          binary, config, data directory, systemd unit file.
```

**Step 2: Verify ansible-lint passes**

Run: `cd ansible/roles/teleport && ansible-lint molecule/shared/verify.yml`
Expected: no errors

**Step 3: Commit**

```bash
git add ansible/roles/teleport/molecule/shared/verify.yml
git commit -m "test(teleport): rewrite verify with real binary checks, no mocks"
```

---

### Task 6: Push and verify CI

**Step 1: Push the branch**

```bash
git push origin ci/track-teleport
```

**Step 2: Monitor CI**

```bash
gh run list --branch ci/track-teleport --limit 3
```

Wait for the run to complete, then check:

```bash
gh run view <run-id> --log-failed
```

Expected: All checks pass (Docker Arch + Ubuntu).

**Step 3: Debug if needed**

If CI fails, use `superpowers:systematic-debugging` to diagnose.

---

### Task 7: Close PR #45 as superseded

**Step 1: Close PR #45 with comment**

```bash
gh pr close 45 --comment "Superseded by #58. Mocks replaced with real binary install."
```

---

### Task 8: Update PR #58 description and merge

**Step 1: Update PR description**

```bash
gh pr edit 58 --title "fix(teleport): real binary install, production-quality molecule tests" --body "$(cat <<'EOF'
## Summary

- Replace mock binaries with real Teleport binary download from cdn.teleport.dev
- Add stat-check for idempotent binary install (skip re-download)
- Create systemd unit file for binary install method
- Tag handler with [service] to prevent firing when service is skipped
- Add listen directive to handler (project convention)
- Add ca-certificates to Docker prepare for Ubuntu SSL
- Rewrite verify.yml: binary, config content, permissions, data dir, unit file
- Set binary install method for all molecule platforms (Docker + Vagrant)

## What's tested

- Binary: exists in PATH, `teleport version` runs, output mentions Teleport
- Config: /etc/teleport.yaml exists, root:root 0600, contains all sections
- Data dir: /var/lib/teleport exists, root:root 0750
- Systemd unit: /etc/systemd/system/teleport.service exists, correct ExecStart

## What's skipped (by design)

- Service start/enable (no auth cluster to connect to)
- CA export (requires live cluster with tctl)
- Cluster connectivity

## Closes

- Supersedes #45

## Test plan

- [x] Docker molecule: Archlinux-systemd passes
- [x] Docker molecule: Ubuntu-systemd passes
- [x] Idempotence check passes (no re-download)

Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 2: Merge when CI is green**

```bash
gh pr merge 58 --merge
```
