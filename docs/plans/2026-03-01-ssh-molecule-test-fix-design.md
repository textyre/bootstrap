# SSH Molecule Test Fix — Design

**Date:** 2026-03-01
**Branch:** fix/ssh-molecule-overhaul
**PR:** #48

## Problem

All SSH molecule tests (docker, vagrant) fail at the `syntax` stage in GHA with:

```
[ERROR]: The vault password file .../vault-pass.sh was not found
CRITICAL Ansible return code was 1, command was: ansible-playbook --syntax-check ...
```

Root cause: molecule.yml files reference `vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh` and converge.yml/verify.yml load `vars_files: vault.yml`, but neither file exists in GHA. The SSH role does not use any vault-encrypted variables.

## Gap Analysis

Two test coverage gaps discovered beyond the CI failure:

| Gap | Description |
|-----|-------------|
| **GAP-1: Service running** | verify.yml checks `status == 'enabled'` (unit file state) but not `state == 'running'` (active state). README specifies "service enabled+running". |
| **GAP-2: RSA public key** | `ssh_host_rsa_key.pub` (expected 0644) not tested. ed25519 public key IS tested. Inconsistency. |

## Design

### Fix 1: Remove vault references (critical)

**Files to change:**
- `molecule/shared/converge.yml` — remove `vars_files: vault.yml` line
- `molecule/shared/verify.yml` — remove `vars_files: vault.yml` line
- `molecule/docker/molecule.yml` — remove `vault_password_file` config option
- `molecule/vagrant/molecule.yml` — remove `vault_password_file` config option
- `molecule/default/molecule.yml` — remove `vault_password_file` config option

No functional change — SSH role has no vault-encrypted variables.

### Fix 2: Service running state (GAP-1)

Add `systemctl is-active` check after the existing enabled check. Use the OS-specific service name:
- Arch: `sshd.service`
- Debian: `ssh.service`

Since SSH daemon runs fine in Docker containers with systemd as PID1 (unlike fail2ban which needs iptables kernel modules), no container exclusion guard is needed.

Pattern (per-OS commands):
```yaml
- name: Check sshd service is active (Arch)
  ansible.builtin.command: systemctl is-active sshd.service
  register: _ssh_verify_active_arch
  changed_when: false
  failed_when: false
  when: ansible_os_family == 'Archlinux'

- name: Assert sshd is active (Arch)
  ansible.builtin.assert:
    that: _ssh_verify_active_arch.stdout | trim == 'active'
    fail_msg: "sshd.service is not active (got: {{ _ssh_verify_active_arch.stdout | trim }})"
  when: ansible_os_family == 'Archlinux'
```

### Fix 3: RSA public key (GAP-2)

Add stat + assert for `/etc/ssh/ssh_host_rsa_key.pub` with mode `0644`, matching the existing ed25519 public key test pattern.

### Fix 4: README assertion count

Update README "56 total" to the actual count after adding RSA pub key and service running tests.

## Approach rationale

**Why not use service_facts for running check?**
service_facts in systemd containers can be unreliable for the `state` field vs `status` field. `systemctl is-active` is the canonical way to check if a unit is running — returns 'active' for running services.

**Why no Docker exclusion guard for service running?**
SSH daemon has no special kernel module requirements. The Docker scenario uses systemd as PID1 (privileged, cgroup mounted). After `state: started` in the role, sshd should be running and checkable.

**Why remove vault refs entirely instead of guarding?**
The SSH role uses zero vault variables. The vault.yml loads happened because the converge/verify templates were copied from a role that does use vault vars. Removing the references is the correct fix — not guarding with `ignore_errors`.

## Success criteria

- All molecule scenarios (docker, vagrant, default) pass in GHA
- Lint passes (no new warnings)
- Tests verify: package, service enabled+running, sshd_config (perms + 34 directives), crypto (positive + negative), host keys (ed25519+RSA private/pub, DSA/ECDSA absent), banner, AllowGroups, SFTP, sshd -t, managed header
- Idempotence step passes (no changes on second run)
