# Plan: ntp_audit -- Vagrant KVM Molecule Scenario

**Date:** 2026-02-25
**Status:** Draft
**Role:** `ansible/roles/ntp_audit/`

---

## 1. Current State

### Existing Scenarios

| Scenario | Driver | Platforms | What it tests |
|----------|--------|-----------|---------------|
| `default/` | default (localhost) | Localhost only | Local converge+verify via shared playbooks; requires vault |
| `docker/` | docker | `Archlinux-systemd` (custom image) | Arch-only; systemd via cgroup hack; reuses `shared/` |
| `disabled/` | default (localhost) | Localhost only | Verifies `ntp_audit_enabled: false` skips all deployment |

### What the Role Does

`ntp_audit` is a **read-only audit/monitoring** role, not a configuration role. It does NOT install or configure chrony/NTP. It:

1. **Deploys a Python zipapp** (`/usr/local/bin/ntp-audit`) that calls `chronyc -c tracking` and parses CSV output
2. **Configures scheduling** -- systemd timer (primary) or cron (non-systemd fallback)
3. **Writes structured JSON** to `/var/log/ntp-audit/audit.log` (one line per run)
4. **Deploys logrotate** config for the audit log
5. **Deploys Grafana Alloy config fragment** (optional, `ntp_audit_alloy_enabled`)
6. **Deploys Loki ruler alert rules** (optional, `ntp_audit_loki_enabled`)
7. **Runs first execution** immediately after deploy
8. **Self-verifies** via `tasks/verify.yml` (included from converge and from molecule verify)

### Shared Playbooks

**`molecule/shared/converge.yml`:**
- `pre_tasks`: installs chrony package, starts `chronyd` service, waits for `/run/chrony/chronyd.sock`
- `roles`: applies `ntp_audit`

**`molecule/shared/verify.yml`:**
- Includes `../../tasks/verify.yml` (role's own verify tasks)
- Extended molecule-only checks: runs `ntp-audit` binary, asserts exit code 0, checks permissions (0755 zipapp, 0644 logrotate), validates logrotate syntax, parses JSON log, validates field types, reads Alloy config and checks log path reference

### Role Dependencies

`meta/main.yml` declares `dependencies: []`. However, the role **functionally requires** chrony to be installed and running -- the converge.yml handles this in `pre_tasks`. The role itself never installs chrony.

---

## 2. Cross-Platform Analysis: Ubuntu vs Arch

### chrony Package and Service

| Aspect | Arch Linux | Ubuntu 24.04 |
|--------|------------|--------------|
| Package name | `chrony` | `chrony` |
| Service name | `chronyd` | `chrony` (NOT `chronyd`) |
| Socket path | `/run/chrony/chronyd.sock` | `/run/chrony/chronyd.sock` (same) |
| chronyc binary | `/usr/bin/chronyc` | `/usr/bin/chronyc` |
| Default NTP competitor | none | `systemd-timesyncd` (active by default!) |
| python3 package | `python3` | `python3` (pre-installed on Ubuntu) |
| logrotate | `logrotate` (separate package) | `logrotate` (pre-installed) |
| python3 zipapp | built-in (3.11+) | built-in (3.12 on Noble) |

### Critical Issue: converge.yml Service Name

The current `shared/converge.yml` hardcodes:

```yaml
- name: Ensure chronyd is running
  ansible.builtin.service:
    name: chronyd    # <-- FAILS on Ubuntu where service is "chrony"
    state: started
    enabled: true
```

On Ubuntu 24.04, the chrony service unit is named `chrony.service`, not `chronyd.service`. The converge will **fail** on Ubuntu unless the service name is made conditional.

### Critical Issue: systemd-timesyncd Conflict on Ubuntu

Ubuntu 24.04 ships with `systemd-timesyncd` active by default. When chrony is installed via `apt`, the postinst script usually disables timesyncd, but this is not guaranteed in all VM images. If both run simultaneously:

- `ntp-audit` will detect `systemd-timesyncd` as `ntp_conflict: "systemd-timesyncd_active"`
- This is correct behavior (the audit detects the conflict), but it means the audit output will differ between platforms
- The verify.yml does NOT assert `ntp_conflict == "none"`, so this will not cause test failure

### Critical Issue: chronyd Socket Wait Path

The converge.yml waits for `/run/chrony/chronyd.sock`. On Ubuntu 24.04, chrony creates this same socket path, so this should work. However, the timing may differ -- Ubuntu's chrony may take longer to start if it needs to resolve NTP servers first.

### logrotate Availability

On Arch, `logrotate` may not be installed by default in a minimal VM image. The verify.yml already handles this gracefully:

```yaml
- name: Check if logrotate binary is present
  ansible.builtin.command:
    cmd: command -v logrotate
  register: ntp_audit_molecule_logrotate_binary
  changed_when: false
  failed_when: false

- name: Validate logrotate config syntax
  ...
  when: ntp_audit_molecule_logrotate_binary.rc == 0
```

However, `logrotate.yml` in the role tasks uses `ansible.builtin.template` to deploy the config file without first ensuring the logrotate package exists. If logrotate is missing, the config file is deployed but has no effect -- which is fine for audit purposes. The verify.yml skips syntax validation when logrotate is absent.

### Summary of Cross-Platform Differences

| Check | Arch | Ubuntu | Impact |
|-------|------|--------|--------|
| Service name for chrony | `chronyd` | `chrony` | **CONVERGE WILL FAIL** -- needs fix |
| systemd-timesyncd | not present | may be active | audit detects it; no test failure |
| logrotate installed | maybe not | yes | verify handles gracefully |
| python3 installed | needs install | pre-installed | `script.yml` handles via `package` |
| `/run/chrony/chronyd.sock` | present | present | same path on both |

---

## 3. Vagrant Scenario Files

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
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
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
- `skip-tags: report` -- consistent with template provided; ntp_audit has no `report` tag but this is harmless
- `prepare: prepare.yml` is a local file (not in shared/) because vagrant VMs need OS-level bootstrapping that docker does not
- No vault_password_file needed -- ntp_audit does not use vault variables

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

    - name: Stop and disable systemd-timesyncd (Ubuntu -- conflicts with chrony)
      ansible.builtin.systemd:
        name: systemd-timesyncd
        state: stopped
        enabled: false
      when: ansible_facts['os_family'] == 'Debian'
      failed_when: false
```

**Key additions beyond the package_manager reference prepare.yml:**
- **Stop systemd-timesyncd on Ubuntu** -- without this, chrony and timesyncd may run simultaneously. This produces a valid `ntp_conflict` detection in the audit, but it creates an inconsistent test environment. Explicitly disabling timesyncd ensures the audit runs in a clean state on both platforms, making verify results predictable.

---

## 4. Shared converge.yml Cross-Platform Fixes

The current `shared/converge.yml` has a hardcoded service name that will break on Ubuntu.

### Required Change

Replace:

```yaml
pre_tasks:
  - name: Ensure chrony is installed (ntp_audit depends on chronyc)
    ansible.builtin.package:
      name: chrony
      state: present

  - name: Ensure chronyd is running
    ansible.builtin.service:
      name: chronyd
      state: started
      enabled: true

  - name: Wait for chronyd socket to be ready
    ansible.builtin.wait_for:
      path: /run/chrony/chronyd.sock
      state: present
      timeout: 30
```

With:

```yaml
pre_tasks:
  - name: Ensure chrony is installed (ntp_audit depends on chronyc)
    ansible.builtin.package:
      name: chrony
      state: present

  - name: Set chrony service name per distribution
    ansible.builtin.set_fact:
      _ntp_audit_chrony_service: >-
        {{ 'chrony' if ansible_facts['os_family'] == 'Debian' else 'chronyd' }}

  - name: Ensure chrony is running
    ansible.builtin.service:
      name: "{{ _ntp_audit_chrony_service }}"
      state: started
      enabled: true

  - name: Wait for chronyd socket to be ready
    ansible.builtin.wait_for:
      path: /run/chrony/chronyd.sock
      state: present
      timeout: 30
```

**Impact on existing scenarios:**
- `default/` (localhost, presumably Arch): `_ntp_audit_chrony_service` resolves to `chronyd` -- no change in behavior
- `docker/` (Archlinux-systemd): resolves to `chronyd` -- no change
- `vagrant/` (arch-vm): resolves to `chronyd`; (ubuntu-noble): resolves to `chrony` -- new, correct behavior

### Verify.yml: No Changes Needed

The `shared/verify.yml` and `tasks/verify.yml` are already cross-platform safe:
- Timer checks use `when: ansible_facts['service_mgr'] == 'systemd'` (both Arch and Ubuntu use systemd in VMs)
- No service name is referenced in verify (only checks timer status, file existence, and command output)
- logrotate syntax check handles missing binary gracefully
- JSON field assertions are platform-independent (chronyc CSV output has the same format everywhere)

---

## 5. Integration with the ntp Role

### Does converge.yml need to apply the ntp role first?

**No.** The ntp_audit role is explicitly designed to be independent:

- `meta/main.yml` has `dependencies: []`
- The converge.yml `pre_tasks` already install chrony and start the service -- this is sufficient
- The ntp role would provide additional configuration (custom NTP servers, options) that is irrelevant for audit testing
- The audit script just needs `chronyc -c tracking` to return data, which works with chrony's default configuration

### What does converge.yml's pre_tasks accomplish?

It acts as a minimal substitute for the ntp role:
1. Installs the `chrony` package (provides `chronyc` binary and `chronyd` service)
2. Starts the service (chronyc needs a running daemon to query)
3. Waits for the socket (ensures `chronyc tracking` will not fail with "connection refused")

This is intentional -- the ntp_audit molecule test should validate the audit tooling itself, not the NTP configuration. Using the full ntp role would introduce unnecessary coupling and potential failure points unrelated to audit functionality.

---

## 6. Implementation Order

### Step 1: Fix shared/converge.yml for Cross-Platform Service Names

**File:** `ansible/roles/ntp_audit/molecule/shared/converge.yml`

Replace the hardcoded `chronyd` service name with a `set_fact` conditional as described in Section 4. This change is backwards-compatible with all existing scenarios.

### Step 2: Create molecule/vagrant/prepare.yml

**File:** `ansible/roles/ntp_audit/molecule/vagrant/prepare.yml`

Copy the prepare.yml content from Section 3. This is derived from `package_manager/molecule/vagrant/prepare.yml` with the addition of the `systemd-timesyncd` stop task.

### Step 3: Create molecule/vagrant/molecule.yml

**File:** `ansible/roles/ntp_audit/molecule/vagrant/molecule.yml`

Copy the molecule.yml content from Section 3.

### Step 4: Local Smoke Test (Arch VM Only)

Run the vagrant scenario targeting only the Arch VM first, since Arch is the existing known-good platform:

```bash
cd ansible/roles/ntp_audit
molecule test -s vagrant -- --limit arch-vm
```

If this fails, debug before proceeding to Ubuntu.

### Step 5: Full Cross-Platform Test

```bash
cd ansible/roles/ntp_audit
molecule test -s vagrant
```

Both arch-vm and ubuntu-noble should pass all stages: syntax, create, prepare, converge, idempotence, verify, destroy.

### Step 6: Verify Idempotence

The idempotence check may flag certain tasks as changed:
- `ntp-audit first_run` -- the `first_run.yml` uses `changed_when: false`, so this should be clean
- Handler `Build ntp-audit zipapp` -- only fires on template changes, so second converge should not trigger it
- `ansible.builtin.meta: flush_handlers` -- no-op if no pending handlers

If idempotence fails, investigate which task reports `changed` on the second run.

### Step 7: Commit

Commit with a descriptive message covering all three files (converge.yml fix + two new vagrant files).

---

## 7. Risks / Notes

### Risk: generic/arch Box Stale Keys

The `generic/arch` Vagrant box historically has stale pacman keyring. The `prepare.yml` handles this by temporarily disabling signature verification, updating the keyring, and re-enabling signatures. This is the same proven approach from `package_manager/molecule/vagrant/prepare.yml`.

### Risk: chrony Synchronization Timing in VMs

In KVM VMs, chrony may take several seconds to synchronize after starting. During this window, `chronyc -c tracking` may report `leap_status=3` (unsynchronised). The audit script handles this gracefully:
- It writes a valid JSON record with `sync_status: "unsynchronised"`
- The verify checks only assert JSON structure, not sync_status value
- The `ntp-audit` binary always exits 0 (by design -- exception handler catches all errors)

### Risk: `systemd-timesyncd` Re-enables Itself

On some Ubuntu images, `systemd-timesyncd` may be socket-activated. Stopping and disabling it in `prepare.yml` should be sufficient for the test window, but if it re-activates:
- The audit will correctly detect and report it as `ntp_conflict: "systemd-timesyncd_active"`
- The verify.yml does NOT assert `ntp_conflict == "none"`, so this will not cause a test failure
- However, it may affect idempotence if chrony and timesyncd compete for clock discipline

### Risk: Docker Scenario Regression

The converge.yml change (adding `set_fact` for service name) affects the docker scenario. Since the docker scenario runs only Archlinux-systemd, the fact will resolve to `chronyd` -- identical to the current hardcoded value. No regression expected, but worth a quick docker scenario run to confirm.

### Note: No Vault Required

Unlike some roles (`reflector`, `yay`), `ntp_audit` does not use any vault-encrypted variables. The molecule.yml does not need `vault_password_file` configuration.

### Note: Alloy/Loki Config Deployment

The role deploys Alloy and Loki config files without requiring those services to be installed. The verify checks that the files exist and contain correct paths. This works identically on both platforms -- no cross-platform concern here.

### Note: systemd Service Unit Hardcodes `chronyd.service`

The template `ntp-audit.service.j2` contains:

```ini
After=chronyd.service
Wants=chronyd.service
```

On Ubuntu, the chrony service is `chrony.service`, not `chronyd.service`. This means the `After=` and `Wants=` directives silently have no effect (systemd treats them as soft dependencies). The timer still works because `ntp-audit` calls `chronyc` directly, which connects to the daemon via socket regardless of the service unit name.

This is a pre-existing issue unrelated to the vagrant scenario, but worth noting. A future improvement would make the service unit template use a variable for the chrony service name.
