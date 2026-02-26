# Plan: ntp role -- Vagrant Molecule Scenario (Arch + Ubuntu KVM)

**Date:** 2026-02-25
**Status:** Draft
**Role:** `ansible/roles/ntp/`

---

## 1. Current State

### Existing Scenarios

| Scenario | Driver | Platforms | Playbooks |
|----------|--------|-----------|-----------|
| `default/` | default (localhost) | Localhost | `shared/converge.yml`, `shared/verify.yml` |
| `docker/` | docker | Archlinux-systemd (custom image) | `shared/converge.yml`, `shared/verify.yml` + own `prepare.yml` |
| `integration/` | default (localhost) | Localhost | `shared/converge.yml`, own `verify.yml` (imports shared + adds live NTS/sync checks) |

### shared/converge.yml

Minimal -- applies `role: ntp` with `become: true` and `gather_facts: true`. No extra vars overrides, so defaults apply (NTS servers: Cloudflare, NIST, PTB; `ntp_auto_detect: true`).

### shared/verify.yml -- Full Assertion List

1. **Package**: `chrony` in `ansible_facts.packages`
2. **Service**: `chronyd.service` running + enabled (systemd only)
3. **Config file**: `/etc/chrony.conf` exists, `root:root`, mode `0644`
4. **Config content**: `nts`, `minsources`, `driftfile`, `dumpdir`, `ntsdumpdir`, `log measurements statistics tracking`, `# Environment:` comment
5. **Directories**:
   - `/var/log/chrony` -- owner `chrony`, mode `0755`
   - `/var/lib/chrony/nts-data` -- owner `chrony`, mode `0700`
6. **Competitor**: `systemd-timesyncd.service` not running
7. **Diagnostic**: `chronyc tracking` output (informational, no assertion)

### docker/prepare.yml

Single task: `community.general.pacman: update_cache: true` (Arch-only).

---

## 2. Cross-Platform Analysis: Arch vs Ubuntu

### Package

| | Arch Linux | Ubuntu 24.04 |
|---|---|---|
| Package name | `chrony` | `chrony` |
| Install method | `pacman -S chrony` | `apt install chrony` |
| In default repos | Yes | Yes (main) |

Package name is `chrony` on both -- no issue. The role's `ntp_package` map already has `Debian: chrony`.

### Service Name

| | Arch Linux | Ubuntu 24.04 |
|---|---|---|
| systemd unit | `chronyd.service` | `chrony.service` |
| Binary | `/usr/bin/chronyd` | `/usr/sbin/chronyd` |

**This is the critical cross-platform difference.** On Ubuntu/Debian, the chrony package ships a systemd unit named `chrony.service`, NOT `chronyd.service`. There is no `chronyd.service` unit.

The role's `vars/main.yml` maps `ntp_service: {systemd: chronyd}` -- this resolves to `chronyd`, which Ansible's `service` module will find on Arch (where the unit is `chronyd.service`) but will FAIL on Ubuntu (where the unit is `chrony.service`).

**Role fix required**: The `ntp_service` mapping needs to be per-OS-family, not per-init-system:

```yaml
# Current (broken for Ubuntu):
ntp_service:
  systemd: chronyd

# Needed (per-OS approach):
ntp_service_name:
  Archlinux: chronyd
  Debian: chrony        # Ubuntu uses os_family == Debian
  RedHat: chronyd
  Alpine: chronyd
  Void: chronyd
```

Alternatively, change the service lookup in `tasks/main.yml` and `handlers/main.yml` to use `ansible_facts['os_family']` instead of `ansible_facts['service_mgr']`.

### Config File Path

| | Arch Linux | Ubuntu 24.04 |
|---|---|---|
| Default config | `/etc/chrony.conf` | `/etc/chrony/chrony.conf` |
| Our deployed path | `/etc/chrony.conf` | `/etc/chrony.conf` |

The role deploys to `/etc/chrony.conf` (hardcoded at `tasks/main.yml:113`). On Ubuntu, chrony's default is `/etc/chrony/chrony.conf`, but the `chrony.service` unit on Ubuntu 24.04 starts chronyd with `-f /etc/chrony/chrony.conf`.

**Two options:**

**Option A (preferred)**: Add an OS-family-keyed `ntp_conf_path` variable to `vars/main.yml`:

```yaml
ntp_conf_path:
  Archlinux: /etc/chrony.conf
  Debian: /etc/chrony/chrony.conf
  RedHat: /etc/chrony.conf
  Alpine: /etc/chrony.conf
  Void: /etc/chrony.conf
```

Then use `{{ ntp_conf_path[ansible_facts['os_family']] | default('/etc/chrony.conf') }}` in `tasks/main.yml` template dest, and in `shared/verify.yml`.

**Option B**: Keep deploying to `/etc/chrony.conf` and override the systemd unit `ExecStart` on Debian to pass `-f /etc/chrony.conf`. This fights the distro packaging and is fragile.

**Recommendation:** Option A. It respects each distro's packaging conventions and avoids systemd unit overrides.

### Chrony System User

| | Arch Linux | Ubuntu 24.04 |
|---|---|---|
| User | `chrony` | `_chrony` |
| Group | `chrony` | `_chrony` |

Already handled by `vars/main.yml`: `ntp_user: {Debian: _chrony, ...}`. The role uses this for directory ownership. No change needed in the role itself.

**But `shared/verify.yml` hardcodes `chrony`** in directory ownership checks (lines 110, 124):
```yaml
- ntp_verify_logdir.stat.pw_name == 'chrony'
- ntp_verify_ntsdumpdir.stat.pw_name == 'chrony'
```
These will FAIL on Ubuntu where the owner is `_chrony`. Needs cross-platform fix.

### Driftfile Path

| | Arch Linux | Ubuntu 24.04 |
|---|---|---|
| Default driftfile | `/var/lib/chrony/drift` | `/var/lib/chrony/chrony.drift` |
| Our configured | `/var/lib/chrony/drift` | `/var/lib/chrony/drift` |

The role sets `ntp_driftfile: "/var/lib/chrony/drift"` in defaults. chrony writes to wherever `driftfile` points in the config. As long as the config is deployed, chrony uses our path. No issue -- the role controls this via template.

### NTS Support

| | Arch Linux | Ubuntu 24.04 |
|---|---|---|
| chrony version | 4.6+ (rolling) | 4.5 (noble) |
| NTS support | Yes (since 4.0) | Yes (since 4.0) |
| GnuTLS | Available | Available (`libgnutls30t64`) |

NTS works on both. Ubuntu 24.04 ships chrony 4.5 which fully supports NTS (RFC 8915 support landed in chrony 4.0).

### Dumpdir / Ntsdumpdir

Both distros use `/var/lib/chrony` as base. Our `ntp_dumpdir` and `ntp_ntsdumpdir` are absolute paths set in defaults, deployed via template. No cross-platform issue -- the role creates these directories explicitly.

---

## 3. Vagrant Scenario

### 3.1 molecule/vagrant/molecule.yml

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
- `skip-tags: report` -- the `common` role's `report_phase.yml` / `report_render.yml` are not available in isolated molecule runs (no `common` role in `ANSIBLE_ROLES_PATH`). Skipping `report` tag avoids this.
- No `vault_password_file` needed -- the ntp role has no vault-encrypted variables.
- Box choices: `generic/arch` (widely used, libvirt-compatible), `bento/ubuntu-24.04` (Bento project, reliable libvirt support).

### 3.2 molecule/vagrant/prepare.yml

Reuse the pattern from `package_manager/molecule/vagrant/prepare.yml`:

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

This is identical to the `package_manager` vagrant prepare, which is already proven. The Arch keyring refresh is essential because `generic/arch` boxes ship with stale GPG keys.

---

## 4. Shared verify.yml Cross-Platform Fixes

The current `shared/verify.yml` has **four** Arch-specific hardcodings that will fail on Ubuntu:

### Fix 4.1: Service Name

**Current (lines 26-33):**
```yaml
- name: Assert chronyd.service is running and enabled
  ansible.builtin.assert:
    that:
      - "'chronyd.service' in ansible_facts.services"
      - "ansible_facts.services['chronyd.service'].state == 'running'"
      - "ansible_facts.services['chronyd.service'].status == 'enabled'"
    fail_msg: "chronyd.service is not running or not enabled"
  when: ansible_facts['service_mgr'] == 'systemd'
```

**Fix:** Use a variable for the service unit name.

```yaml
- name: Set expected chrony service name
  ansible.builtin.set_fact:
    _ntp_verify_service: >-
      {{ 'chrony.service' if ansible_facts['os_family'] == 'Debian'
         else 'chronyd.service' }}

- name: Assert chrony service is running and enabled
  ansible.builtin.assert:
    that:
      - "_ntp_verify_service in ansible_facts.services"
      - "ansible_facts.services[_ntp_verify_service].state == 'running'"
      - "ansible_facts.services[_ntp_verify_service].status == 'enabled'"
    fail_msg: "{{ _ntp_verify_service }} is not running or not enabled"
  when: ansible_facts['service_mgr'] == 'systemd'
```

### Fix 4.2: Config File Path

**Current (lines 37-50):** Hardcodes `/etc/chrony.conf`

**Fix:** Use a variable for config path.

```yaml
- name: Set expected chrony config path
  ansible.builtin.set_fact:
    _ntp_verify_conf_path: >-
      {{ '/etc/chrony/chrony.conf' if ansible_facts['os_family'] == 'Debian'
         else '/etc/chrony.conf' }}
```

Then replace all occurrences of `/etc/chrony.conf` in stat, slurp, and fail_msg with `{{ _ntp_verify_conf_path }}`.

### Fix 4.3: Directory Ownership

**Current (lines 110, 124):** Hardcodes `pw_name == 'chrony'`

**Fix:** Use a variable for the expected user.

```yaml
- name: Set expected chrony system user
  ansible.builtin.set_fact:
    _ntp_verify_user: >-
      {{ '_chrony' if ansible_facts['os_family'] == 'Debian'
         else 'chrony' }}
```

Then replace:
```yaml
# Lines 110, 124: change from
- ntp_verify_logdir.stat.pw_name == 'chrony'
- ntp_verify_ntsdumpdir.stat.pw_name == 'chrony'
# To:
- ntp_verify_logdir.stat.pw_name == _ntp_verify_user
- ntp_verify_ntsdumpdir.stat.pw_name == _ntp_verify_user
```

### Fix 4.4: Summary Message

**Current (line 155-157):** References "chronyd" and "/etc/chrony.conf" in debug message.

**Fix:** Use the variables in the message string:

```yaml
- name: Show verify result
  ansible.builtin.debug:
    msg: >-
      NTP offline verify passed: chrony installed,
      {{ _ntp_verify_service }} running,
      {{ _ntp_verify_conf_path }} correct (root:root 0644), directives present,
      directories exist with correct ownership and mode.
```

### Verify Fix Summary

Add a **new block** near the top of `shared/verify.yml` (after `gather_facts`, before the first assertion) that sets three facts:

```yaml
    # ---- Cross-platform facts ----

    - name: Set cross-platform verify facts
      ansible.builtin.set_fact:
        _ntp_verify_service: >-
          {{ 'chrony.service' if ansible_facts['os_family'] == 'Debian'
             else 'chronyd.service' }}
        _ntp_verify_conf_path: >-
          {{ '/etc/chrony/chrony.conf' if ansible_facts['os_family'] == 'Debian'
             else '/etc/chrony.conf' }}
        _ntp_verify_user: >-
          {{ '_chrony' if ansible_facts['os_family'] == 'Debian'
             else 'chrony' }}
```

Then update all downstream references. This keeps the fix contained and explicit.

---

## 5. Converge.yml Updates

### Does converge.yml need changes?

The current `shared/converge.yml` applies `role: ntp` with no overrides. The role itself is designed to be cross-platform via `vars/main.yml` mappings. **However**, the role has a bug:

**Bug: `ntp_service` is keyed by init system, not OS family.**

```yaml
# vars/main.yml
ntp_service:
  systemd: chronyd    # <-- Ubuntu uses systemd but service is 'chrony', not 'chronyd'
```

This means `tasks/main.yml` line 126 (`name: "{{ ntp_service[ansible_facts['service_mgr']] }}"`) will try to manage service `chronyd` on Ubuntu, which does not exist. The converge will **fail** on Ubuntu at the "Enable and start chronyd" task.

### Required Role Fix (prerequisite for vagrant scenario)

Change `vars/main.yml` to key the service name by OS family:

```yaml
# Replace ntp_service with:
ntp_service_name:
  Archlinux: chronyd
  Debian: chrony
  RedHat: chronyd
  Alpine: chronyd
  Void: chronyd
```

Then update all references in the role:

| File | Line | Current | New |
|------|------|---------|-----|
| `tasks/main.yml` | 126 | `ntp_service[ansible_facts['service_mgr']]` | `ntp_service_name[ansible_facts['os_family']] \| default('chronyd')` |
| `tasks/main.yml` | 151 | same pattern | same fix |
| `handlers/main.yml` | 6 | same pattern | same fix |

**Also update config dest path** in `tasks/main.yml`:

```yaml
# vars/main.yml -- add:
ntp_conf_path:
  Archlinux: /etc/chrony.conf
  Debian: /etc/chrony/chrony.conf
  RedHat: /etc/chrony.conf
  Alpine: /etc/chrony.conf
  Void: /etc/chrony.conf
```

Update `tasks/main.yml` line 113:
```yaml
# From:
dest: /etc/chrony.conf
# To:
dest: "{{ ntp_conf_path[ansible_facts['os_family']] | default('/etc/chrony.conf') }}"
```

### Converge.yml itself

No changes needed to `shared/converge.yml`. It remains the minimal `role: ntp` invocation. The role's internal cross-platform logic handles the rest once the `vars/main.yml` fixes are in place.

---

## 6. Implementation Order

### Phase 1: Role Cross-Platform Fixes (prerequisite)

1. **Update `ansible/roles/ntp/vars/main.yml`**
   - Replace `ntp_service` (keyed by init system) with `ntp_service_name` (keyed by OS family)
   - Add `ntp_conf_path` mapping (keyed by OS family)

2. **Update `ansible/roles/ntp/tasks/main.yml`**
   - Line 113: Use `ntp_conf_path[ansible_facts['os_family']]` for config dest
   - Line 126: Use `ntp_service_name[ansible_facts['os_family']]` for service name
   - Line 151: Same fix in report phase

3. **Update `ansible/roles/ntp/handlers/main.yml`**
   - Line 6: Use `ntp_service_name[ansible_facts['os_family']]` for service name

4. **Update `ansible/roles/ntp/templates/chrony.conf.j2`**
   - Line 3: No change needed (uses `_ntp_virt_type`, not service name)

5. **Run existing docker scenario** to verify Arch is not broken:
   ```bash
   cd ansible/roles/ntp && molecule test -s docker
   ```

### Phase 2: Shared Verify Cross-Platform Fixes

6. **Update `ansible/roles/ntp/molecule/shared/verify.yml`**
   - Add cross-platform facts block (`_ntp_verify_service`, `_ntp_verify_conf_path`, `_ntp_verify_user`)
   - Replace hardcoded `chronyd.service` with `_ntp_verify_service`
   - Replace hardcoded `/etc/chrony.conf` with `_ntp_verify_conf_path`
   - Replace hardcoded `chrony` user with `_ntp_verify_user`
   - Update summary debug message

7. **Run docker scenario again** to verify shared verify changes work on Arch:
   ```bash
   cd ansible/roles/ntp && molecule test -s docker
   ```

### Phase 3: Vagrant Scenario Creation

8. **Create `ansible/roles/ntp/molecule/vagrant/molecule.yml`** (content from Section 3.1)

9. **Create `ansible/roles/ntp/molecule/vagrant/prepare.yml`** (content from Section 3.2)

10. **Run vagrant scenario locally**:
    ```bash
    cd ansible/roles/ntp && molecule test -s vagrant
    ```

### Phase 4: Integration Verify Cross-Platform Fixes

11. **Update `ansible/roles/ntp/molecule/integration/verify.yml`**
    - Line 69: Use variable for chrony.conf path (same as shared verify)
    - The rest of integration verify uses `chronyc` commands which are binary-name-consistent across distros

### Phase 5: Verification

12. **Run all three scenarios sequentially**:
    ```bash
    cd ansible/roles/ntp
    molecule test -s docker       # Arch container
    molecule test -s vagrant      # Arch VM + Ubuntu VM
    ```

13. **Verify idempotence on both platforms** -- the vagrant scenario includes `idempotence` in `test_sequence`. Both VMs must show zero changed tasks on second run.

---

## 7. Risks / Notes

### Risk 1: NTS Connectivity in KVM VMs

NTS requires outbound TLS (port 4460) to time servers. Vagrant/libvirt VMs use NAT networking by default, which permits outbound connections. **Low risk** -- but if the CI runner has restrictive egress firewall rules, NTS handshakes will fail.

**Mitigation:** The role's `tasks/verify.yml` checks NTP sync (`chronyc tracking`, `chronyc sources`). If NTS servers are unreachable, `chronyc sources` will show `?` status. The role's verify task asserts a synced source (`^*` marker), which will fail if no server is reachable.

However, the **molecule shared verify** (`molecule/shared/verify.yml`) does NOT check sync status -- it only checks config content and directory state. It will PASS even without NTS connectivity. This is by design (offline assertions). The **integration** scenario is the one that checks live sync.

### Risk 2: chrony Version on Ubuntu 24.04

Ubuntu 24.04 ships chrony 4.5. NTS is fully supported since chrony 4.0. The `ntsdumpdir` directive was added in chrony 4.0. **No risk** from version differences.

### Risk 3: generic/arch Box Staleness

The `generic/arch` Vagrant box is community-maintained and can have stale packages / expired GPG keys. The `prepare.yml` handles this with the keyring refresh + full upgrade sequence (proven pattern from `package_manager` role). **Low risk** with mitigation in place.

### Risk 4: Ubuntu chrony.service Auto-Start

On Ubuntu, `apt install chrony` automatically starts and enables the `chrony.service`. The role's converge will then try to "Enable and start" it again (idempotent). The role also deploys a new config and notifies the handler to restart. **No risk** -- standard Ansible idempotent behavior.

One subtlety: the first converge run may show `changed` for the service task (it restarts due to config change notification). The idempotence check on second run should show zero changes because the config is already deployed. This is correct behavior.

### Risk 5: /var/lib/chrony Ownership Mismatch

On Ubuntu, `/var/lib/chrony` is created by the `chrony` package with owner `_chrony:_chrony`. On Arch, it is created with owner `chrony:chrony`. The role's directory task uses `ntp_user[ansible_facts['os_family']]` which correctly resolves to `_chrony` on Debian-family systems. **No risk** -- already handled.

### Risk 6: leapsectz Directive

The template includes `leapsectz right/UTC`. On Ubuntu, the `tzdata` package provides `/usr/share/zoneinfo/right/UTC`. On Arch, same. Both have it. **No risk.**

### Note: common Role Dependency

The ntp role includes tasks from `common` role (`report_phase.yml`, `report_render.yml`, `check_internet.yml`). In molecule, `ANSIBLE_ROLES_PATH` is set to `${MOLECULE_PROJECT_DIRECTORY}/../` which resolves to `ansible/roles/`. The `common` role must exist at `ansible/roles/common/`. The `skip-tags: report` in molecule.yml skips the report tasks but NOT the `check_internet.yml` call in `tasks/verify.yml`.

**Action required:** Verify that `ansible/roles/common/tasks/check_internet.yml` exists and works in the vagrant VM context. If the common role is missing or broken, the converge will fail at the verify step. The docker scenario already handles this (it works today), so the common role is present.

### Note: Integration Scenario Not in Vagrant

The vagrant scenario runs `shared/verify.yml` (offline assertions only), NOT the integration verify. Live NTP sync verification (waiting for `^*` source, checking NTS authentication) is handled by the `integration/` scenario which runs on localhost. Adding live checks to the vagrant scenario is possible but adds ~60s per VM for sync wait. Recommend keeping vagrant as offline-only for CI speed, and running integration tests separately against real infrastructure.
