# SSH Molecule Test Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all SSH molecule tests to pass in GHA for Arch + Ubuntu (docker + vagrant) by removing broken vault references and filling two coverage gaps.

**Architecture:** The SSH role's molecule files have vault references that don't exist in GHA (vault-pass.sh, vault.yml). The role doesn't use vault vars at all. Remove the references, then add two missing assertions: service running state and RSA public key permissions. All changes are in `ansible/roles/ssh/molecule/`.

**Tech Stack:** Ansible, Molecule, GitHub Actions

---

### Task 1: Remove vault references (root cause of all CI failures)

**Files:**
- Modify: `ansible/roles/ssh/molecule/shared/converge.yml`
- Modify: `ansible/roles/ssh/molecule/shared/verify.yml`
- Modify: `ansible/roles/ssh/molecule/docker/molecule.yml`
- Modify: `ansible/roles/ssh/molecule/vagrant/molecule.yml`
- Modify: `ansible/roles/ssh/molecule/default/molecule.yml`

**Step 1: Remove vault_password_file from docker/molecule.yml**

Open `ansible/roles/ssh/molecule/docker/molecule.yml`. In the `provisioner.config_options.defaults` block, remove this line:
```yaml
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
```

The block should go from:
```yaml
  config_options:
    defaults:
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
      callbacks_enabled: profile_tasks
```
To:
```yaml
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
```

**Step 2: Remove vault_password_file from vagrant/molecule.yml**

Same change in `ansible/roles/ssh/molecule/vagrant/molecule.yml`.

**Step 3: Remove vault_password_file from default/molecule.yml**

Same change in `ansible/roles/ssh/molecule/default/molecule.yml`.

**Step 4: Remove vars_files vault.yml from converge.yml**

Open `ansible/roles/ssh/molecule/shared/converge.yml`. Remove this line from the `vars_files` block:
```yaml
    - "{{ playbook_dir }}/../../../../inventory/group_vars/all/vault.yml"
```

**Step 5: Remove vars_files vault.yml from verify.yml**

Open `ansible/roles/ssh/molecule/shared/verify.yml`. Remove this line from the `vars_files` block:
```yaml
    - "{{ playbook_dir }}/../../../../inventory/group_vars/all/vault.yml"
```

**Step 6: Commit**

```bash
cd /d/projects/bootstrap-ssh
git add ansible/roles/ssh/molecule/
git commit -m "fix(ssh): remove vault refs from molecule — ssh role uses no vault vars"
```

---

### Task 2: Add service running state assertion (GAP-1)

**Files:**
- Modify: `ansible/roles/ssh/molecule/shared/verify.yml`

Context: The current verify.yml checks service **enabled** state via `service_facts` (`.status == 'enabled'`). It doesn't verify the service is actually **running** (`.state == 'running'`). README states "service enabled+running". SSH daemon runs fine in Docker-with-systemd — no kernel module requirements.

The service name is OS-specific:
- Arch Linux: `sshd.service`
- Debian/Ubuntu: `ssh.service`

**Step 1: Locate the service enabled section**

Find the block in verify.yml:
```yaml
    # ================================================================
    #  Service enabled
    # ================================================================
```
It has two assertions: one for Archlinux and one for Debian.

**Step 2: Add running assertions after the enabled assertions**

After the "Assert ssh is enabled (Debian)" task block, add a new section:

```yaml
    # ================================================================
    #  Service running
    # ================================================================

    - name: Check sshd is active (Arch)
      ansible.builtin.command:
        cmd: systemctl is-active sshd.service
      register: _ssh_verify_active_arch
      changed_when: false
      failed_when: false
      when: ansible_os_family == 'Archlinux'

    - name: Assert sshd is active (Arch)
      ansible.builtin.assert:
        that: _ssh_verify_active_arch.stdout | trim == 'active'
        fail_msg: >-
          sshd.service is not active on Archlinux
          (systemctl is-active returned: '{{ _ssh_verify_active_arch.stdout | trim }}')
      when: ansible_os_family == 'Archlinux'

    - name: Check ssh is active (Debian)
      ansible.builtin.command:
        cmd: systemctl is-active ssh.service
      register: _ssh_verify_active_debian
      changed_when: false
      failed_when: false
      when: ansible_os_family == 'Debian'

    - name: Assert ssh is active (Debian)
      ansible.builtin.assert:
        that: _ssh_verify_active_debian.stdout | trim == 'active'
        fail_msg: >-
          ssh.service is not active on Debian/Ubuntu
          (systemctl is-active returned: '{{ _ssh_verify_active_debian.stdout | trim }}')
      when: ansible_os_family == 'Debian'
```

**Step 3: Commit**

```bash
git add ansible/roles/ssh/molecule/shared/verify.yml
git commit -m "test(ssh): assert sshd service is active (running), not just enabled"
```

---

### Task 3: Add RSA public key permission check (GAP-2)

**Files:**
- Modify: `ansible/roles/ssh/molecule/shared/verify.yml`

Context: The verify.yml tests ed25519 private (0600) and public (0644) keys. It tests RSA private (0600) but NOT RSA public key (should be 0644). This is an inconsistency vs the ed25519 pattern.

**Step 1: Locate the RSA private key section**

Find the block:
```yaml
    - name: Stat RSA host key (private)
      ansible.builtin.stat:
        path: /etc/ssh/ssh_host_rsa_key
      register: _ssh_verify_rsa_key

    - name: Assert RSA host key exists with correct permissions
      ...
```

**Step 2: Add RSA public key check right after the RSA private key assertions**

After "Assert RSA host key exists with correct permissions", add:

```yaml
    - name: Stat RSA host key (public)
      ansible.builtin.stat:
        path: /etc/ssh/ssh_host_rsa_key.pub
      register: _ssh_verify_rsa_pub

    - name: Assert RSA public key exists with correct permissions
      ansible.builtin.assert:
        that:
          - _ssh_verify_rsa_pub.stat.exists
          - _ssh_verify_rsa_pub.stat.mode == '0644'
        fail_msg: >-
          /etc/ssh/ssh_host_rsa_key.pub missing or wrong permissions
          (expected 0644, got {{ _ssh_verify_rsa_pub.stat.mode | default('missing') }})
```

**Step 3: Commit**

```bash
git add ansible/roles/ssh/molecule/shared/verify.yml
git commit -m "test(ssh): assert RSA public host key exists with 0644 permissions"
```

---

### Task 4: Update README assertion count

**Files:**
- Modify: `ansible/roles/ssh/README.md`

Context: README says "56 total" assertions. After adding service running (2 new: arch + debian) and RSA pub key (1 new) checks, the count increases. Count the actual assertions to get the accurate number.

**Step 1: Count actual assertions in verify.yml**

Run:
```bash
grep -c 'ansible.builtin.assert' ansible/roles/ssh/molecule/shared/verify.yml
```

**Step 2: Update README**

Find in README.md:
```markdown
### Verify assertions (56 total)
```

Update the number to match the actual count from Step 1. Also update the description sentence to mention "service enabled and running" and "RSA public key (0644)".

The updated description should be:
```markdown
### Verify assertions (N total)

Package install, service enabled+running (`systemctl is-active`), `sshd_config` permissions (0600/root),
41 security directive checks (all major hardening directives including
`KbdInteractiveAuthentication`, `TCPKeepAlive`, `PrintMotd`, `PrintLastLog`,
`MaxSessions`, `AcceptEnv`), cryptography suite (positive + negative),
host key presence (ed25519+RSA private with 0600, ed25519+RSA public with 0644)
and absence (DSA/ECDSA), `RekeyLimit 512M 1h` value check, banner file + content + config directive,
`AllowGroups` absent when empty, SFTP subsystem, `sshd -t` syntax validation,
and Ansible managed comment.
```

**Step 3: Commit**

```bash
git add ansible/roles/ssh/README.md
git commit -m "docs(ssh): update verify assertion count and description in README"
```

---

### Task 5: Push and verify CI

**Step 1: Push branch**

```bash
cd /d/projects/bootstrap-ssh
git push origin fix/ssh-molecule-overhaul
```

**Step 2: Monitor GHA run**

```bash
gh run list --branch fix/ssh-molecule-overhaul --limit 3
```

Wait approximately 4 minutes (based on previous run durations: docker ~3m41s, lint ~2m17s). Then check:

```bash
gh run view <run-id>
```

Expected: All jobs pass — `test (ssh) / ssh (Arch+Ubuntu/systemd)`, lint checks.

Note: vagrant jobs (`test-vagrant (ssh, ...)`) may be skipped in PR CI if vagrant runner is not available — this is expected.

**Step 3: If CI passes, proceed to Task 6. If CI fails:**

Check failure details:
```bash
gh run view <run-id> --log-failed
```

Look for specific TASK names in the output to identify which assertion is failing.

---

### Task 6: Merge PR and clean up

**Step 1: Verify PR is mergeable**

```bash
cd /d/projects/bootstrap-ssh
gh pr view 48
```

Confirm all required checks pass.

**Step 2: Merge PR**

```bash
gh pr merge 48 --squash --delete-branch
```

**Step 3: Switch main repo to master and pull**

```bash
cd /d/projects/bootstrap
git checkout master
git pull origin master
```

**Step 4: Remove the worktree**

```bash
git worktree remove /d/projects/bootstrap-ssh
```

If it says there are changes, check with `git -C /d/projects/bootstrap-ssh status` first. After merge the worktree should be clean. Use `--force` only if the branch was deleted by the PR merge and worktree is truly done.

**Step 5: Verify cleanup**

```bash
git worktree list
```

Expected: `D:/projects/bootstrap-ssh` no longer listed.
