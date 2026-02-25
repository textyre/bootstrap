# Teleport Role — Molecule Research Spec

**Date:** 2026-02-25  
**Purpose:** Full content snapshot of the teleport role for molecule design/improvement work.

---

## 1. Role File Tree

```
ansible/roles/teleport/
├── defaults/main.yml
├── handlers/main.yml
├── meta/main.yml
├── molecule/
│   └── default/
│       ├── converge.yml
│       ├── molecule.yml
│       └── verify.yml
├── README.md
├── tasks/
│   ├── ca_export.yml
│   ├── configure.yml
│   ├── install.yml
│   ├── join.yml
│   ├── main.yml
│   └── verify.yml
├── templates/
│   └── teleport.yaml.j2
└── vars/
    ├── archlinux.yml
    ├── debian.yml
    ├── gentoo.yml
    ├── redhat.yml
    └── void.yml
```

---

## 2. File Contents (Verbatim)

### defaults/main.yml

```yaml
---
# === teleport role defaults ===

# ROLE-003: Supported operating systems
teleport_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo

# Core configuration
teleport_enabled: true
teleport_version: "17.0.0"
teleport_auth_server: ""
teleport_join_token: ""
teleport_node_name: "{{ ansible_hostname }}"
teleport_labels: {}

# SSH features
teleport_ssh_enabled: true
teleport_proxy_mode: false
teleport_session_recording: "node"
teleport_enhanced_recording: false

# CA integration with ssh role
teleport_export_ca_key: true
teleport_ca_keys_file: /etc/ssh/teleport_user_ca.pub
```

---

### tasks/main.yml

```yaml
---
# === teleport: SSH access platform agent ===

- name: Teleport role
  when: teleport_enabled | bool
  tags: ['teleport']
  block:
    # ROLE-003: Validate supported OS
    - name: "Assert supported operating system"
      ansible.builtin.assert:
        that:
          - ansible_facts['os_family'] in teleport_supported_os
        fail_msg: >-
          OS family '{{ ansible_facts['os_family'] }}' is not supported.
          Supported: {{ teleport_supported_os | join(', ') }}
      tags: [teleport]

    # ROLE-001: OS-specific variables
    - name: "Include OS-specific variables"
      ansible.builtin.include_vars: "{{ ansible_facts['os_family'] | lower }}.yml"
      tags: [teleport]

    # Validate required variables
    - name: "Assert auth server is configured"
      ansible.builtin.assert:
        that:
          - teleport_auth_server | length > 0
        fail_msg: "teleport_auth_server must be set (e.g., 'auth.example.com:443')"
      tags: [teleport]

    # Validate join configuration
    - name: "Validate join configuration"
      ansible.builtin.include_tasks: join.yml
      tags: [teleport, security]

    # Install
    - name: "Install Teleport"
      ansible.builtin.include_tasks: install.yml
      tags: [teleport, install]

    # Configure
    - name: "Configure Teleport"
      ansible.builtin.include_tasks: configure.yml
      tags: [teleport]

    # Export CA key for ssh role integration
    - name: "Export CA public key"
      ansible.builtin.include_tasks: ca_export.yml
      when: teleport_export_ca_key | bool
      tags: [teleport, security]

    # Service management (ROLE-002)
    - name: "Enable and start teleport"
      ansible.builtin.service:
        name: "{{ teleport_service_name[ansible_facts['service_mgr']] | default('teleport') }}"
        enabled: true
        state: started
      tags: [teleport, service]

    # ROLE-005: Verification
    - name: "Verify Teleport"
      ansible.builtin.include_tasks: verify.yml
      tags: [teleport]

    # ROLE-008: Reporting
    - name: "Report: Teleport"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_phase.yml
      vars:
        common_rpt_fact: "_teleport_phases"
        common_rpt_phase: "Teleport agent"
        common_rpt_detail: >-
          auth={{ teleport_auth_server }}
          node={{ teleport_node_name }}
          recording={{ teleport_session_recording }}
      tags: [teleport, report]

    - name: "Teleport — Execution Report"
      ansible.builtin.include_role:
        name: common
        tasks_from: report_render.yml
      vars:
        common_rpt_fact: "_teleport_phases"
        common_rpt_title: "teleport"
      tags: [teleport, report]
```

---

### tasks/install.yml

```yaml
---
# === Install Teleport agent ===

- name: "Install Teleport via package manager"
  ansible.builtin.package:
    name: "{{ teleport_packages }}"
    state: present
  when: teleport_install_method == 'package'
  tags: [teleport, install]

- name: "Install Teleport via official repository (Debian/RedHat)"
  when: teleport_install_method == 'repo'
  tags: [teleport, install]
  block:
    - name: "Set Teleport major version for repository URL"
      ansible.builtin.set_fact:
        teleport_major_version: "{{ teleport_version.split('.')[0] }}"

    - name: "Add Teleport GPG key"
      ansible.builtin.get_url:
        url: "https://apt.releases.teleport.dev/gpg"
        dest: /usr/share/keyrings/teleport-archive-keyring.asc
        mode: "0644"
      when: ansible_facts['os_family'] == 'Debian'

    - name: "Add Teleport APT repository"
      ansible.builtin.apt_repository:
        repo: >-
          deb [signed-by=/usr/share/keyrings/teleport-archive-keyring.asc]
          https://apt.releases.teleport.dev/{{ ansible_distribution | lower }}
          {{ ansible_distribution_release }} stable/v{{ teleport_major_version }}
        state: present
      when: ansible_facts['os_family'] == 'Debian'

    - name: "Add Teleport YUM repository"
      ansible.builtin.yum_repository:
        name: teleport
        description: Teleport
        baseurl: "https://yum.releases.teleport.dev/$basearch/stable/v{{ teleport_major_version }}"
        gpgcheck: true
        gpgkey: "https://yum.releases.teleport.dev/gpg"
      when: ansible_facts['os_family'] == 'RedHat'

    - name: "Install Teleport from repository"
      ansible.builtin.package:
        name: teleport
        state: present

- name: "Install Teleport via binary download (Void/Gentoo)"
  when: teleport_install_method == 'binary'
  tags: [teleport, install]
  block:
    - name: "Set architecture mapping for Teleport download"
      ansible.builtin.set_fact:
        teleport_arch: >-
          {{ {'x86_64': 'amd64', 'aarch64': 'arm64'}[ansible_architecture]
             | default(ansible_architecture) }}

    - name: "Download Teleport binary"
      ansible.builtin.get_url:
        url: "https://cdn.teleport.dev/teleport-v{{ teleport_version }}-linux-{{ teleport_arch }}-bin.tar.gz"
        dest: "/tmp/teleport.tar.gz"
        mode: "0644"

    - name: "Extract Teleport binary"
      ansible.builtin.unarchive:
        src: "/tmp/teleport.tar.gz"
        dest: /usr/local/bin/
        remote_src: true
        extra_opts: [--strip-components=1]
```

---

### molecule/default/molecule.yml

```yaml
---
driver:
  name: default
platforms:
  - name: Instance
    managed: false
provisioner:
  name: ansible
  inventory:
    host_vars:
      instance:
        ansible_connection: local
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
    ANSIBLE_VAULT_PASSWORD_FILE: "${MOLECULE_PROJECT_DIRECTORY}/../../vault-pass.sh"
verifier:
  name: ansible
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Notable issues vs NTP reference pattern:**
- Uses `driver.name: default` with `platforms[].managed: false` — but `managed` is nested under `platforms` rather than `driver.options` (NTP puts it under `driver.options`)
- Platform name is `Instance` — host_vars key must match; but `host_vars` key is `instance` (lowercase) — mismatch risk
- No `idempotency` step in `test_sequence`
- No `config_options` block (no `vault_password_file` in provisioner config; uses env `ANSIBLE_VAULT_PASSWORD_FILE` instead)
- No `playbooks` key pointing to shared files — converge/verify are inline in default/
- Vault password file path differs: uses `../../vault-pass.sh` (two levels up) vs NTP's `vault-pass.sh` (relative)

---

### molecule/default/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  vars:
    teleport_enabled: true
    teleport_auth_server: "localhost:3025"
    teleport_join_token: "test-token-molecule"
    teleport_node_name: "molecule-test"
    teleport_session_recording: "node"
    teleport_export_ca_key: false
  roles:
    - role: teleport
```

**Notes:**
- `teleport_export_ca_key: false` — skips the CA export task (depends on `ssh` role)
- No `gather_facts: true` explicit (defaults to true, fine)
- No OS-family override — will use whatever localhost reports (`Archlinux` on the dev VM)
- `teleport_install_method` not overridden — will be loaded from `vars/archlinux.yml` → `package`; on localhost Arch this means `teleport-bin` must be in AUR/pacman

---

### molecule/default/verify.yml

```yaml
---
- name: Verify teleport role
  hosts: all
  become: true
  tasks:
    - name: "Verify teleport configuration exists"
      ansible.builtin.stat:
        path: /etc/teleport.yaml
      register: teleport_verify_config

    - name: "Assert config exists with correct permissions"
      ansible.builtin.assert:
        that:
          - teleport_verify_config.stat.exists
          - teleport_verify_config.stat.mode == '0600'
          - teleport_verify_config.stat.pw_name == 'root'

    - name: "Verify config contains auth server"
      ansible.builtin.command:
        cmd: "grep 'auth_server: localhost:3025' /etc/teleport.yaml"
      register: teleport_verify_auth_server
      changed_when: false
      failed_when: teleport_verify_auth_server.rc != 0

    - name: "Verify config contains node name"
      ansible.builtin.command:
        cmd: "grep 'nodename: molecule-test' /etc/teleport.yaml"
      register: teleport_verify_node_name
      changed_when: false
      failed_when: teleport_verify_node_name.rc != 0

    - name: "Verify data directory exists"
      ansible.builtin.stat:
        path: /var/lib/teleport
      register: teleport_verify_datadir

    - name: "Assert data directory exists"
      ansible.builtin.assert:
        that:
          - teleport_verify_datadir.stat.exists
          - teleport_verify_datadir.stat.isdir
```

**Gaps vs NTP's verify pattern:**
- Uses `ansible.builtin.command` + `grep` for content checks — NTP uses `slurp` + `set_fact` + `assert` (pure Ansible, no shell)
- Does NOT verify: package installed, service enabled/running, template version directive (`version: v3`), SSH service enabled flag
- No diagnostic task at end (NTP has a `debug` summary)
- No `failed_when: false` fallback on diagnostic tasks

---

### templates/teleport.yaml.j2

```jinja2
# {{ ansible_managed }}
# Teleport node configuration

version: v3
teleport:
  nodename: "{{ teleport_node_name }}"
  data_dir: /var/lib/teleport
  auth_token: "{{ teleport_join_token }}"
  auth_server: "{{ teleport_auth_server }}"
  log:
    output: stderr
    severity: INFO

ssh_service:
  enabled: {{ teleport_ssh_enabled | lower }}
{% if teleport_labels %}
  labels:
{% for key, value in teleport_labels.items() %}
    {{ key }}: "{{ value }}"
{% endfor %}
{% endif %}

proxy_service:
  enabled: {{ teleport_proxy_mode | lower }}

auth_service:
  enabled: false

{% if teleport_session_recording != 'off' %}
session_recording:
  mode: "{{ teleport_session_recording }}"
{% if teleport_enhanced_recording %}
  enhanced_recording:
    enabled: true
{% endif %}
{% endif %}
```

---

### vars/archlinux.yml

```yaml
---
teleport_packages:
  - teleport-bin
teleport_install_method: package
teleport_service_name:
  systemd: teleport
  runit: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport
```

### vars/debian.yml

```yaml
---
teleport_packages: []
teleport_install_method: repo
teleport_service_name:
  systemd: teleport
  runit: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport
```

### vars/gentoo.yml

```yaml
---
teleport_packages: []
teleport_install_method: binary
teleport_service_name:
  openrc: teleport
  systemd: teleport
  runit: teleport
  s6: teleport
  dinit: teleport
```

### vars/redhat.yml

```yaml
---
teleport_packages: []
teleport_install_method: repo
teleport_service_name:
  systemd: teleport
  runit: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport
```

### vars/void.yml

```yaml
---
teleport_packages: []
teleport_install_method: binary
teleport_service_name:
  runit: teleport
  systemd: teleport
  openrc: teleport
  s6: teleport
  dinit: teleport
```

---

## 3. NTP Role Molecule Pattern (Reference)

### Directory Structure

```
ansible/roles/ntp/molecule/
├── default/
│   └── molecule.yml
├── docker/
│   ├── molecule.yml
│   └── prepare.yml
├── integration/
│   ├── molecule.yml
│   └── verify.yml
└── shared/
    ├── converge.yml
    └── verify.yml
```

### Pattern: Three scenarios + shared playbooks

- **`default/`** — localhost/offline smoke test (no service start). Points converge+verify to `../shared/`
- **`docker/`** — Docker container with systemd. Also uses `../shared/` for converge+verify; adds `prepare.yml` for cache update
- **`integration/`** — Localhost with live NTP sync checks. Uses `../shared/converge.yml` + local `verify.yml` (which imports shared verify then adds live sync assertions)
- **`shared/`** — Single source of truth for converge + base verify; avoids duplication across scenarios

### ntp/molecule/default/molecule.yml

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
  config_options:
    defaults:
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
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
    - idempotency
    - verify
```

**Key differences from teleport's molecule.yml:**
- `driver.options.managed: false` (correct location) vs teleport's `platforms[].managed: false`
- `config_options.defaults.vault_password_file` (provisioner config) vs teleport's env var `ANSIBLE_VAULT_PASSWORD_FILE`
- `playbooks.converge` + `playbooks.verify` keys pointing to `../shared/` (DRY)
- Platform named `Localhost` with `host_vars.localhost` (matching case) vs teleport's `Instance`/`instance` (case mismatch)
- `idempotency` step included in `test_sequence`

### ntp/molecule/docker/molecule.yml

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

### ntp/molecule/shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  roles:
    - role: ntp
```

### ntp/molecule/shared/verify.yml (summary)

Full offline assertions using `ansible.builtin.package_facts`, `service_facts`, `stat`, `slurp`+`set_fact`+`assert` for content checks. Ends with a diagnostic `command: chronyc tracking` + `debug` (no failure on diagnostic).

---

## 4. Gap Analysis Summary

| Area | Teleport Current | NTP Reference | Gap |
|------|-----------------|---------------|-----|
| Scenarios | 1 (default only) | 3 (default/docker/integration) | Missing docker + integration |
| Shared playbooks | No | Yes (`shared/`) | Duplication if scenarios added |
| `driver.options.managed` | Under `platforms[]` | Under `driver.options` | Structural error |
| Platform name case | `Instance`/`instance` mismatch | `Localhost`/`localhost` match | Host var lookup may fail |
| `idempotency` step | Missing | Present | ROLE-005 requirement |
| Vault config | Env var | `config_options.defaults` | Inconsistent with standard |
| Verify: content checks | `command: grep` | `slurp`+`assert` | Shell dependency |
| Verify: package check | Missing | `package_facts` assert | ROLE-005 incomplete |
| Verify: service check | Missing | `service_facts` assert | ROLE-005 incomplete |
| Verify: diagnostic | Missing | `debug` with `failed_when: false` | Observability |
| converge: `gather_facts` | Implicit (default true) | Explicit `gather_facts: true` | Style consistency |
| Install on localhost | Requires `teleport-bin` in pacman | chrony in standard repos | Molecule may fail on dry runs |
