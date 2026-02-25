# Plan: firewall role -- Molecule testing + CRIT-01 bug fix

**Date:** 2026-02-25
**Status:** Draft
**Role path:** `ansible/roles/firewall/`

---

## 1. Current State

### What the role does

The `firewall` role deploys a minimal nftables-based firewall for workstations:

- Installs `nftables` via OS-specific task files (`install-archlinux.yml` using `community.general.pacman`, `install-debian.yml` using `ansible.builtin.apt`)
- Deploys `/etc/nftables.conf` from `nftables.conf.j2` template
- Enables and starts the `nftables` systemd service
- Handler restarts nftables on config changes (uses `listen: "restart nftables"`)

**Template rules** (`nftables.conf.j2`):
- Default policy: `input drop`, `forward drop`, `output accept`
- Loopback accepted, invalid packets dropped, established/related accepted
- ICMP rate-limited at 10/second (both IPv4 and IPv6)
- SSH with per-source-IP rate limiting via dynamic set (when `firewall_ssh_rate_limit_enabled`)
- Additional TCP/UDP ports from `firewall_allow_tcp_ports` / `firewall_allow_udp_ports`
- Forward chain allows established/related (Docker bridge support)
- Catch-all: log + counter + drop

**Variables** (`defaults/main.yml`):
- `firewall_enabled: true`
- `firewall_enable_service: true`
- `firewall_allow_ssh: true`
- `firewall_ssh_rate_limit_enabled: true`
- `firewall_ssh_rate_limit: "4/minute"`
- `firewall_ssh_rate_limit_burst: 2`
- `firewall_allow_tcp_ports: []`
- `firewall_allow_udp_ports: []`

**OS support declared:** ArchLinux only in `meta/main.yml`, but `install-debian.yml` already exists.

### What tests exist now

Single `molecule/default/` scenario:
- **Driver:** `default` (localhost, managed: false)
- **Provisioner:** Ansible with vault password, local connection
- **converge.yml:** Asserts `os_family == Archlinux`, then applies `firewall` role
- **verify.yml:** 5 checks:
  1. nftables package installed (check_mode idempotency)
  2. `/etc/nftables.conf` exists
  3. Config contains `table inet filter`
  4. nftables service enabled (check_mode idempotency)
  5. `nft list tables` shows `inet filter` loaded

**Gaps in current tests:**
- No cross-platform testing (converge asserts Arch-only)
- No verification of SSH rate limit rules
- No verification of dynamic set `ssh_ratelimit`
- No config permissions check (owner, group, mode)
- No idempotence check in test sequence
- Vault dependency in converge/verify (not needed -- role has no vault variables)
- No Docker or Vagrant scenarios

---

## 2. CRIT-01 Bug Fix Plan

### Status: ALREADY FIXED in current code

Reading the template at `ansible/roles/firewall/templates/nftables.conf.j2`, the CRIT-01 bug
has **already been fixed**. The current template uses the correct per-source-IP dynamic set pattern:

```nftables
{% if firewall_allow_ssh and firewall_ssh_rate_limit_enabled %}
    set ssh_ratelimit {
        type ipv4_addr
        flags dynamic,timeout
        timeout 1m
    }
{% endif %}

...

{% if firewall_ssh_rate_limit_enabled %}
        # SSH с per-source-IP rate limiting (защита от brute-force)
        tcp dport 22 ct state new add @ssh_ratelimit { ip saddr limit rate over {{ firewall_ssh_rate_limit }} burst {{ firewall_ssh_rate_limit_burst }} packets } log prefix "[nftables] ssh-rate: " drop
{% endif %}
        # SSH -- разрешить
        tcp dport 22 ct state new accept
```

The variables `firewall_ssh_rate_limit_enabled`, `firewall_ssh_rate_limit`, and
`firewall_ssh_rate_limit_burst` are already present in `defaults/main.yml`.

### Remaining work

No code fix needed. The verify.yml should **validate** the fix is working:

1. Assert `ssh_ratelimit` set definition exists in nftables.conf
2. Assert the rule uses `add @ssh_ratelimit { ip saddr limit rate over ...}` (per-source-IP)
3. Assert the set is loaded in nftables runtime (`nft list set inet filter ssh_ratelimit`)

These assertions are designed in Section 6 below.

---

## 3. Shared Migration

Move `molecule/default/converge.yml` and `molecule/default/verify.yml` to `molecule/shared/`
so all scenarios reuse them.

### molecule/shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: firewall
```

Changes from current `default/converge.yml`:
- **Removed** `vars_files` vault reference (role has no vault variables)
- **Removed** `os_family == Archlinux` assertion (role supports both Arch and Debian)

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
  config_options:
    defaults:
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
    - idempotence
    - verify
```

Changes from current:
- **Removed** `vault_password_file` (not needed)
- **Changed** playbook paths to `../shared/`
- **Changed** `ANSIBLE_ROLES_PATH` from `roles` to `../ ` (consistent with other roles)
- **Added** `idempotence` to test sequence

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

**nftables in Docker containers:**
- nftables requires the `nf_tables` kernel module loaded on the **host**
- The `privileged: true` flag grants access to netfilter subsystem
- `nft list tables` should work in privileged systemd containers
- If `nf_tables` is not loaded on the CI host, `nft` commands will fail with
  `Error: Could not process rule: No such file or directory`
- The `arch-systemd` image should already have the `nftables` package available in repos

**Mitigation:** The verify.yml wraps the `nft list tables` and `nft list set` checks
with `failed_when: false` + separate assertion, so failures produce clear messages
rather than cryptic errors. See Section 6.

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

### Cross-platform notes

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|-----------|--------------|
| Package name | `nftables` | `nftables` |
| Package manager | pacman | apt |
| Service name | `nftables.service` | `nftables.service` |
| Config path | `/etc/nftables.conf` | `/etc/nftables.conf` |
| Default state | Not installed, no rules | May have `iptables` active; nftables available |
| `os_family` fact | `Archlinux` | `Debian` |
| Install task file | `install-archlinux.yml` | `install-debian.yml` |

The role's `tasks/main.yml` dispatches via `ansible_facts['os_family'] | lower`, which maps:
- Arch -> `install-archlinux.yml`
- Ubuntu/Debian -> `install-debian.yml`

Both install task files already exist and work correctly.

### meta/main.yml update needed

The current `meta/main.yml` only lists ArchLinux. Ubuntu/Debian should be added:

```yaml
---
galaxy_info:
  role_name: firewall
  author: textyre
  description: Базовый firewall (nftables) для рабочей станции
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
    - name: Ubuntu
      versions: [all]
  galaxy_tags: [firewall, nftables, security]
dependencies: []
```

---

## 6. Verify.yml Design

### molecule/shared/verify.yml

```yaml
---
- name: Verify firewall role
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

    - name: Assert nftables package is installed
      ansible.builtin.assert:
        that: "'nftables' in ansible_facts.packages"
        fail_msg: "nftables package not found"

    # ---- Configuration file ----

    - name: Stat /etc/nftables.conf
      ansible.builtin.stat:
        path: /etc/nftables.conf
      register: firewall_verify_conf

    - name: Assert nftables.conf exists with correct owner and mode
      ansible.builtin.assert:
        that:
          - firewall_verify_conf.stat.exists
          - firewall_verify_conf.stat.isreg
          - firewall_verify_conf.stat.pw_name == 'root'
          - firewall_verify_conf.stat.gr_name == 'root'
          - firewall_verify_conf.stat.mode == '0644'
        fail_msg: "/etc/nftables.conf missing or wrong permissions (expected root:root 0644)"

    - name: Read nftables.conf content
      ansible.builtin.slurp:
        src: /etc/nftables.conf
      register: firewall_verify_conf_raw

    - name: Set nftables.conf text fact
      ansible.builtin.set_fact:
        firewall_verify_conf_text: "{{ firewall_verify_conf_raw.content | b64decode }}"

    # ---- Core structure assertions ----

    - name: Assert config contains inet filter table
      ansible.builtin.assert:
        that: "'table inet filter' in firewall_verify_conf_text"
        fail_msg: "'table inet filter' not found in /etc/nftables.conf"

    - name: Assert input chain has drop policy
      ansible.builtin.assert:
        that: "'policy drop' in firewall_verify_conf_text"
        fail_msg: "Input chain default policy is not 'drop'"

    - name: Assert loopback is accepted
      ansible.builtin.assert:
        that: "'iifname \"lo\" accept' in firewall_verify_conf_text"
        fail_msg: "Loopback accept rule missing"

    - name: Assert established/related connections accepted
      ansible.builtin.assert:
        that: "'ct state established,related accept' in firewall_verify_conf_text"
        fail_msg: "Established/related accept rule missing"

    - name: Assert invalid packets dropped
      ansible.builtin.assert:
        that: "'ct state invalid drop' in firewall_verify_conf_text"
        fail_msg: "Invalid state drop rule missing"

    - name: Assert ICMP rate limiting present (IPv4)
      ansible.builtin.assert:
        that: "'ip protocol icmp limit rate' in firewall_verify_conf_text"
        fail_msg: "ICMP rate limit rule missing for IPv4"

    - name: Assert ICMP rate limiting present (IPv6)
      ansible.builtin.assert:
        that: "'ip6 nexthdr icmpv6 limit rate' in firewall_verify_conf_text"
        fail_msg: "ICMP rate limit rule missing for IPv6"

    # ---- SSH rules ----

    - name: Assert SSH accept rule present
      ansible.builtin.assert:
        that: "'tcp dport 22 ct state new accept' in firewall_verify_conf_text"
        fail_msg: "SSH accept rule missing from nftables.conf"
      when: firewall_allow_ssh

    # ---- CRIT-01 validation: per-source-IP rate limiting ----

    - name: Assert ssh_ratelimit dynamic set defined
      ansible.builtin.assert:
        that:
          - "'set ssh_ratelimit' in firewall_verify_conf_text"
          - "'type ipv4_addr' in firewall_verify_conf_text"
          - "'flags dynamic' in firewall_verify_conf_text"
        fail_msg: >-
          CRIT-01: ssh_ratelimit dynamic set not found in config.
          Per-source-IP rate limiting requires a named set with type ipv4_addr and flags dynamic.
      when: firewall_allow_ssh and firewall_ssh_rate_limit_enabled

    - name: Assert SSH rate limit rule uses per-source-IP pattern (add @ssh_ratelimit)
      ansible.builtin.assert:
        that: "'add @ssh_ratelimit { ip saddr limit rate over' in firewall_verify_conf_text"
        fail_msg: >-
          CRIT-01: SSH rate limit rule does not use per-source-IP pattern.
          Expected 'add @ssh_ratelimit { ip saddr limit rate over ...' but not found.
          This means rate limiting is global (shared across all IPs), not per-source.
      when: firewall_allow_ssh and firewall_ssh_rate_limit_enabled

    - name: Assert SSH rate limit values match defaults
      ansible.builtin.assert:
        that:
          - "firewall_ssh_rate_limit in firewall_verify_conf_text"
          - "('burst ' ~ firewall_ssh_rate_limit_burst | string ~ ' packets') in firewall_verify_conf_text"
        fail_msg: >-
          SSH rate limit values not found in config.
          Expected rate '{{ firewall_ssh_rate_limit }}' and burst '{{ firewall_ssh_rate_limit_burst }}'.
      when: firewall_allow_ssh and firewall_ssh_rate_limit_enabled

    # ---- Forward chain ----

    - name: Assert forward chain exists with drop policy
      ansible.builtin.assert:
        that: "'chain forward' in firewall_verify_conf_text"
        fail_msg: "Forward chain missing from nftables.conf"

    # ---- Output chain ----

    - name: Assert output chain has accept policy
      ansible.builtin.assert:
        that: "'chain output' in firewall_verify_conf_text"
        fail_msg: "Output chain missing from nftables.conf"

    # ---- Catch-all log + drop ----

    - name: Assert catch-all log and drop rule present
      ansible.builtin.assert:
        that: "'log prefix' in firewall_verify_conf_text"
        fail_msg: "Catch-all log+drop rule missing"

    # ---- Ansible managed marker ----

    - name: Assert Ansible managed marker present
      ansible.builtin.assert:
        that: "'Ansible' in firewall_verify_conf_text"
        fail_msg: "Ansible managed marker not found -- config may not be template-generated"

    # ---- Service state ----

    - name: Check nftables service is enabled
      ansible.builtin.command: systemctl is-enabled nftables.service
      register: firewall_verify_svc_enabled
      changed_when: false
      failed_when: false

    - name: Assert nftables service is enabled
      ansible.builtin.assert:
        that: firewall_verify_svc_enabled.stdout == 'enabled'
        fail_msg: >-
          nftables.service is not enabled (got '{{ firewall_verify_svc_enabled.stdout }}').
      when: firewall_enable_service

    - name: Check nftables service is active
      ansible.builtin.command: systemctl is-active nftables.service
      register: firewall_verify_svc_active
      changed_when: false
      failed_when: false

    - name: Assert nftables service is active
      ansible.builtin.assert:
        that: firewall_verify_svc_active.stdout == 'active'
        fail_msg: >-
          nftables.service is not active (got '{{ firewall_verify_svc_active.stdout }}').
          This may be expected in Docker containers without full netfilter support.
      when: firewall_enable_service

    # ---- Runtime rules loaded (requires nft binary and kernel support) ----

    - name: List loaded nftables tables
      ansible.builtin.command: nft list tables
      register: firewall_verify_nft_tables
      changed_when: false
      failed_when: false

    - name: Assert inet filter table loaded in runtime
      ansible.builtin.assert:
        that: "'inet filter' in firewall_verify_nft_tables.stdout"
        fail_msg: >-
          inet filter table not loaded in nftables runtime.
          nft list tables returned: {{ firewall_verify_nft_tables.stdout }}
          stderr: {{ firewall_verify_nft_tables.stderr | default('') }}
      when: firewall_verify_nft_tables.rc == 0

    - name: Warn if nft command failed (container without netfilter)
      ansible.builtin.debug:
        msg: >-
          WARNING: 'nft list tables' failed (rc={{ firewall_verify_nft_tables.rc }}).
          This is expected in containers without nf_tables kernel module.
          Runtime rule verification skipped.
      when: firewall_verify_nft_tables.rc != 0

    # ---- Runtime: verify dynamic set loaded (CRIT-01 runtime validation) ----

    - name: List ssh_ratelimit set in runtime
      ansible.builtin.command: nft list set inet filter ssh_ratelimit
      register: firewall_verify_nft_set
      changed_when: false
      failed_when: false
      when:
        - firewall_allow_ssh
        - firewall_ssh_rate_limit_enabled
        - firewall_verify_nft_tables.rc == 0

    - name: Assert ssh_ratelimit set exists in runtime
      ansible.builtin.assert:
        that:
          - firewall_verify_nft_set.rc == 0
          - "'ssh_ratelimit' in firewall_verify_nft_set.stdout"
        fail_msg: >-
          CRIT-01 runtime: ssh_ratelimit set not loaded.
          Expected per-source-IP dynamic set but nft returned:
          {{ firewall_verify_nft_set.stderr | default('') }}
      when:
        - firewall_allow_ssh
        - firewall_ssh_rate_limit_enabled
        - firewall_verify_nft_tables.rc == 0

    # ---- Diagnostic: dump full ruleset ----

    - name: Diagnostic -- full nftables ruleset
      ansible.builtin.command: nft list ruleset
      register: firewall_verify_ruleset_diag
      changed_when: false
      failed_when: false

    - name: Show nftables ruleset (diagnostic)
      ansible.builtin.debug:
        var: firewall_verify_ruleset_diag.stdout_lines
      when: firewall_verify_ruleset_diag.rc == 0

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          Firewall verify passed: nftables installed, /etc/nftables.conf deployed
          (root:root 0644), inet filter table with drop policy, SSH per-source-IP
          rate limiting (CRIT-01 validated), service enabled and active.
```

### Assertion summary table

| # | Assertion | Cross-platform | When guard |
|---|-----------|---------------|------------|
| 1 | nftables package installed | Both | always |
| 2 | /etc/nftables.conf exists, root:root 0644 | Both | always |
| 3 | Config: `table inet filter` | Both | always |
| 4 | Config: input `policy drop` | Both | always |
| 5 | Config: loopback accept | Both | always |
| 6 | Config: established/related accept | Both | always |
| 7 | Config: invalid drop | Both | always |
| 8 | Config: ICMP v4 rate limit | Both | always |
| 9 | Config: ICMP v6 rate limit | Both | always |
| 10 | Config: SSH accept rule | Both | `firewall_allow_ssh` |
| 11 | Config: ssh_ratelimit set defined | Both | `firewall_allow_ssh and firewall_ssh_rate_limit_enabled` |
| 12 | Config: per-source-IP `add @ssh_ratelimit` | Both | `firewall_allow_ssh and firewall_ssh_rate_limit_enabled` |
| 13 | Config: rate/burst values match | Both | `firewall_allow_ssh and firewall_ssh_rate_limit_enabled` |
| 14 | Config: forward chain exists | Both | always |
| 15 | Config: output chain exists | Both | always |
| 16 | Config: catch-all log | Both | always |
| 17 | Config: Ansible managed marker | Both | always |
| 18 | Service: nftables enabled | Both | `firewall_enable_service` |
| 19 | Service: nftables active | Both | `firewall_enable_service` |
| 20 | Runtime: inet filter table loaded | Both | `nft rc == 0` |
| 21 | Runtime: ssh_ratelimit set loaded | Both | `nft rc == 0 and rate_limit vars` |
| 22 | Diagnostic: full ruleset dump | Both | `nft rc == 0` |

No assertions require `ansible_distribution`-specific guards because the nftables
configuration, service name, and config path are identical on Arch and Ubuntu.

---

## 7. Implementation Order

### Step 1: Create shared directory and move files

```
mkdir -p ansible/roles/firewall/molecule/shared/
```

Create `molecule/shared/converge.yml` (new, simplified -- no vault, no Arch assertion).
Create `molecule/shared/verify.yml` (new, comprehensive -- from Section 6).

### Step 2: Update molecule/default/molecule.yml

- Remove `vault_password_file`
- Point playbooks to `../shared/converge.yml` and `../shared/verify.yml`
- Update `ANSIBLE_ROLES_PATH` to `${MOLECULE_PROJECT_DIRECTORY}/../`
- Add `idempotence` to test sequence

### Step 3: Delete old converge.yml and verify.yml from default/

```
rm ansible/roles/firewall/molecule/default/converge.yml
rm ansible/roles/firewall/molecule/default/verify.yml
```

### Step 4: Create Docker scenario

```
mkdir -p ansible/roles/firewall/molecule/docker/
```

Create `molecule/docker/molecule.yml` and `molecule/docker/prepare.yml` per Section 4.

### Step 5: Create Vagrant scenario

```
mkdir -p ansible/roles/firewall/molecule/vagrant/
```

Create `molecule/vagrant/molecule.yml` and `molecule/vagrant/prepare.yml` per Section 5.

### Step 6: Update meta/main.yml

Add Debian and Ubuntu platforms to `galaxy_info.platforms`.

### Step 7: Test locally

```bash
# Default scenario (localhost, Arch only)
cd ansible && molecule test -s default -- --tags firewall

# Docker scenario
cd ansible/roles/firewall && molecule test -s docker

# Vagrant scenario (requires libvirt)
cd ansible/roles/firewall && molecule test -s vagrant
```

### Step 8: Verify idempotence

The role should be idempotent:
- First run: installs nftables, deploys config, enables service
- Second run: no changes (all tasks report `ok`)

Potential idempotence issue: the `ansible.builtin.service` task with `state: started`
will show `ok` on second run (not `changed`) since the service is already running. This is correct.

---

## 8. Risks / Notes

### nftables in Docker containers

**Risk:** nftables requires kernel-level netfilter support (`nf_tables` module). Docker
containers share the host kernel, so `nft` commands only work if the host has `nf_tables`
loaded.

**Mitigation:** The verify.yml checks `nft list tables` with `failed_when: false` and
gates all runtime assertions on `rc == 0`. If the kernel module is unavailable, verify
prints a warning and skips runtime checks. Config file assertions still run.

**CI consideration:** GitHub Actions `ubuntu-latest` runners have `nf_tables` loaded by
default. The `privileged: true` container flag grants access. This should work in CI.

### nftables service in Docker

**Risk:** `systemctl start nftables` loads rules via `nft -f /etc/nftables.conf`. If the
container lacks netfilter access, the service will fail to start.

**Mitigation:** The service active/enabled checks use `failed_when: false` + assertion
pattern. The enabled check (just a symlink) should always work. The active check may
fail in restricted containers.

### Vagrant Arch box stale keyring

**Risk:** `generic/arch` Vagrant boxes ship with stale pacman keyring. Package installs
fail with signature errors.

**Mitigation:** `prepare.yml` temporarily disables signature checking, updates the
keyring, then re-enables signatures. This is the established pattern from the
`package_manager` vagrant scenario.

### Idempotence with nftables.conf template

The `nftables.conf.j2` template uses `{{ ansible_managed }}` which includes a timestamp.
This could cause idempotence failures if the comment changes between runs.

**Mitigation:** Ansible's `ansible_managed` string is deterministic within a single
molecule run (same timestamp). Between separate `molecule test` runs the template is
re-evaluated, but within the idempotence check (two consecutive converge runs), the
timestamp should be identical. If it is not, set `ansible_managed` to a static string
in molecule provisioner config:

```yaml
provisioner:
  config_options:
    defaults:
      ansible_managed: "Managed by Ansible"
```

### Forward chain and Docker interaction

The forward chain has `policy drop` with only `ct state established,related accept`.
This is designed for workstations where Docker manages its own iptables/nftables rules.
In a test environment without Docker, the forward chain simply drops everything (which
is fine -- no forwarding expected in test VMs/containers).

### No IPv6 in ssh_ratelimit set

The `ssh_ratelimit` set uses `type ipv4_addr`, meaning IPv6 SSH connections are not
rate-limited. This is a known limitation but not a blocker for testing. A future
enhancement could add a parallel `ssh_ratelimit6` set with `type ipv6_addr`.

### Ubuntu nftables default config

Ubuntu 24.04 ships without nftables installed by default but may have `iptables`
(which on modern Ubuntu uses the nft backend). The role's `flush ruleset` directive
at the top of `nftables.conf.j2` will clear any existing rules. This is intentional
and correct for a workstation firewall role that owns the entire ruleset.

---

## File tree after implementation

```
ansible/roles/firewall/
  defaults/main.yml              (unchanged)
  handlers/main.yml              (unchanged)
  meta/main.yml                  (updated: add Debian/Ubuntu platforms)
  tasks/
    main.yml                     (unchanged)
    install-archlinux.yml        (unchanged)
    install-debian.yml           (unchanged)
  templates/
    nftables.conf.j2             (unchanged -- CRIT-01 already fixed)
  molecule/
    shared/
      converge.yml               (NEW -- simplified, no vault, no Arch assertion)
      verify.yml                 (NEW -- 22 assertions, cross-platform)
    default/
      molecule.yml               (UPDATED -- point to shared/, remove vault)
    docker/
      molecule.yml               (NEW -- arch-systemd container)
      prepare.yml                (NEW -- pacman update_cache)
    vagrant/
      molecule.yml               (NEW -- Arch + Ubuntu VMs)
      prepare.yml                (NEW -- Python bootstrap, keyring refresh, apt cache)
```
