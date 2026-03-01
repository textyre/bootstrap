# SSH Molecule Coverage — Full Gap Fill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Fill all uncovered test cases in the SSH role's Molecule test suite — access control directives (AllowGroups/AllowUsers/DenyGroups/DenyUsers), Teleport CA integration, SFTP chroot, ListenAddress, moduli cleanup result, missing session/network directives, RSA public key permissions, and fix banner/AllowGroups assertion guards.

**Architecture:** Add 4 new Docker platforms (`*-access-control` and `*-features` for both Arch and Ubuntu) to `docker/molecule.yml`. Move all role variables from `converge.yml`'s `vars:` block to per-platform `host_vars` in `docker/molecule.yml` and `vagrant/molecule.yml`. All new assertions use `when: inventory_hostname is search('...')` pattern to stay conditional. The shared `verify.yml` remains the single source of truth for all scenarios.

**Tech Stack:** Ansible Molecule (Docker driver), Ansible assertions (assert/command/stat/slurp), Jinja2 `inventory_hostname is search()` conditionals, systemd containers with full PID 1

---

## Context

The SSH role lives at `ansible/roles/ssh/`. Molecule shared playbooks are at `molecule/shared/`. Docker-specific files are at `molecule/docker/`. Vagrant-specific files are at `molecule/vagrant/`.

### Key files to understand before starting:

- `molecule/shared/verify.yml` — 343-line assertion playbook (read entirely before editing)
- `molecule/shared/converge.yml` — currently has a `vars:` block (lines 9–13) that overrides host_vars; must be removed
- `molecule/docker/molecule.yml` — currently has 2 platforms; needs 4 more
- `molecule/docker/prepare.yml` — needs new platform-conditional tasks
- `molecule/vagrant/molecule.yml` — needs host_vars section added
- `templates/sshd_config.j2` — conditional blocks at lines 18-23 (ListenAddress), 110-129 (access control), 181-185 (Banner), 210-214 (Teleport), 221-229 (SFTP chroot)
- `tasks/preflight.yml` — lockout protection; checks that `ssh_user` is in `ssh_allow_groups` (IMPORTANT: if `ssh_allow_groups` is non-empty, `ssh_user` must be a member of one of those groups, or converge will fail)

### Ansible variable precedence — CRITICAL

`vars_files` loaded in `verify.yml` (e.g. `vars_files: ../../defaults/main.yml`) has precedence 14 — **higher than** `inventory host_vars` (precedence 8-10). This means you **cannot use** `when: ssh_banner_enabled` in verify.yml to guard assertions, because the defaults file would always override the host_vars value. Use `when: inventory_hostname is search('...')` patterns instead.

### Platform naming convention (encodes test scenario):

| Name pattern | Contains |
|---|---|
| `*-systemd` | banner + moduli enabled; AllowGroups=[] |
| `*-access-control` | AllowGroups/AllowUsers/DenyGroups/DenyUsers tested |
| `*-features` | Teleport CA + SFTP chroot + ListenAddress tested |
| `arch-vm`, `ubuntu-base` | Vagrant VMs; banner + moduli enabled |

---

## Task 1: Create isolated git worktree

**Files:**
- No code changes; git operation only

**Step 1: Create the worktree from master**

```bash
git worktree add /d/projects/bootstrap-ssh-coverage fix/ssh-molecule-coverage -b fix/ssh-molecule-coverage origin/master
```

Expected output: `Preparing worktree (new branch 'fix/ssh-molecule-coverage')`

**Step 2: Verify worktree is on master HEAD**

```bash
git -C /d/projects/bootstrap-ssh-coverage log --oneline -3
```

Expected: Shows recent master commits (not fail2ban changes).

**Step 3: Confirm SSH role molecule files are present**

```bash
ls /d/projects/bootstrap-ssh-coverage/ansible/roles/ssh/molecule/
```

Expected: `default  docker  shared  vagrant`

---

## Task 2: Refactor variable management — move converge.yml vars to host_vars

Remove the `vars:` block from converge.yml and add per-platform host_vars to docker/molecule.yml and vagrant/molecule.yml. This enables per-platform configuration that actually overrides defaults (the `vars:` block in the roles list has precedence 20 — too high; host_vars at precedence 8-10 are lower but sufficient because converge.yml won't load defaults/main.yml via vars_files).

**Files:**
- Modify: `ansible/roles/ssh/molecule/shared/converge.yml`
- Modify: `ansible/roles/ssh/molecule/docker/molecule.yml`
- Modify: `ansible/roles/ssh/molecule/vagrant/molecule.yml`

**Step 1: Simplify converge.yml — remove vars block**

Replace the entire content of `molecule/shared/converge.yml` with:

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: ssh
```

**Step 2: Add host_vars to docker/molecule.yml**

Replace the `provisioner:` section (lines 36–48) with this (keep the rest of the file unchanged):

```yaml
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
        ansible_user: root
        ssh_user: root
        ssh_banner_enabled: true
        ssh_moduli_cleanup: true
        ssh_allow_groups: []
      Ubuntu-systemd:
        ansible_user: root
        ssh_user: root
        ssh_banner_enabled: true
        ssh_moduli_cleanup: true
        ssh_allow_groups: []
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
```

**Step 3: Add host_vars to vagrant/molecule.yml**

Replace the `provisioner:` section with:

```yaml
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
        ssh_user: vagrant
        ssh_banner_enabled: true
        ssh_moduli_cleanup: true
        ssh_allow_groups: []
      ubuntu-base:
        ssh_user: vagrant
        ssh_banner_enabled: true
        ssh_moduli_cleanup: true
        ssh_allow_groups: []
  playbooks:
    prepare: prepare.yml
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml
```

Note: `ssh_user: vagrant` — the vagrant user has `authorized_keys` set up by Vagrant, avoiding preflight lockout. `ssh_allow_groups: []` disables the group check so we don't need to worry about which groups vagrant is in.

**Step 4: Verify syntax**

```bash
cd /d/projects/bootstrap-ssh-coverage/ansible
molecule syntax -s docker
```

Expected: No errors. (This validates that the YAML syntax is correct and Ansible can parse the playbooks.)

**Step 5: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/molecule/shared/converge.yml \
        ansible/roles/ssh/molecule/docker/molecule.yml \
        ansible/roles/ssh/molecule/vagrant/molecule.yml
git commit -m "refactor(ssh/molecule): move converge vars to molecule host_vars"
```

---

## Task 3: Add access-control platforms to docker/molecule.yml + update docker/prepare.yml

Add two new platforms (`Archlinux-access-control`, `Ubuntu-access-control`) that test AllowGroups, AllowUsers, DenyGroups, DenyUsers directives.

**Important constraint:** `preflight.yml` checks that `ssh_user` is in at least one `ssh_allow_groups` group. Since `ssh_allow_groups: ["sshusers"]` is set for these platforms and `ssh_user: root`, we must add root to the `sshusers` group in `prepare.yml` BEFORE converge runs.

**Files:**
- Modify: `ansible/roles/ssh/molecule/docker/molecule.yml`
- Modify: `ansible/roles/ssh/molecule/docker/prepare.yml`

**Step 1: Add new platforms to the `platforms:` list in docker/molecule.yml**

After the `Ubuntu-systemd` platform block (before the blank line before `provisioner:`), add:

```yaml
  - name: Archlinux-access-control
    image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/arch-base:latest}"
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

  - name: Ubuntu-access-control
    image: "${MOLECULE_UBUNTU_IMAGE:-ghcr.io/textyre/ubuntu-base:latest}"
    pre_build_image: true
    command: /lib/systemd/systemd
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
```

**Step 2: Add host_vars for access-control platforms to the `inventory.host_vars:` block**

After the `Ubuntu-systemd:` block in `host_vars`, add:

```yaml
      Archlinux-access-control:
        ansible_user: root
        ssh_user: root
        ssh_allow_groups:
          - sshusers
        ssh_allow_users:
          - root
        ssh_deny_groups:
          - badgroup
        ssh_deny_users:
          - baduser
      Ubuntu-access-control:
        ansible_user: root
        ssh_user: root
        ssh_allow_groups:
          - sshusers
        ssh_allow_users:
          - root
        ssh_deny_groups:
          - badgroup
        ssh_deny_users:
          - baduser
```

**Step 3: Add prepare tasks for access-control platforms to docker/prepare.yml**

Append these tasks at the end of `molecule/docker/prepare.yml`:

```yaml
    - name: Create sshusers group (access-control platforms)
      ansible.builtin.group:
        name: sshusers
        state: present
      when: inventory_hostname is search('access-control')

    - name: Add root to sshusers group (access-control platforms)
      ansible.builtin.user:
        name: root
        groups: sshusers
        append: true
      when: inventory_hostname is search('access-control')
```

**Step 4: Verify syntax**

```bash
cd /d/projects/bootstrap-ssh-coverage/ansible
molecule syntax -s docker
```

Expected: No errors.

**Step 5: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/molecule/docker/molecule.yml \
        ansible/roles/ssh/molecule/docker/prepare.yml
git commit -m "feat(ssh/molecule): add access-control docker platforms (AllowGroups/AllowUsers/DenyGroups/DenyUsers)"
```

---

## Task 4: Add features platforms to docker/molecule.yml + update docker/prepare.yml

Add two new platforms (`Archlinux-features`, `Ubuntu-features`) that test Teleport CA integration, SFTP chroot, and ListenAddress.

**Important:** `sshd -t` validates that `TrustedUserCAKeys` file **exists**. The fake CA file must be created in prepare.yml BEFORE converge runs.

**Files:**
- Modify: `ansible/roles/ssh/molecule/docker/molecule.yml`
- Modify: `ansible/roles/ssh/molecule/docker/prepare.yml`

**Step 1: Add new platforms to `platforms:` list in docker/molecule.yml**

After the `Ubuntu-access-control` platform block, add:

```yaml
  - name: Archlinux-features
    image: "${MOLECULE_ARCH_IMAGE:-ghcr.io/textyre/arch-base:latest}"
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

  - name: Ubuntu-features
    image: "${MOLECULE_UBUNTU_IMAGE:-ghcr.io/textyre/ubuntu-base:latest}"
    pre_build_image: true
    command: /lib/systemd/systemd
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
```

**Step 2: Add host_vars for features platforms**

After the `Ubuntu-access-control:` host_vars block, add:

```yaml
      Archlinux-features:
        ansible_user: root
        ssh_user: root
        ssh_allow_groups: []
        ssh_teleport_integration: true
        ssh_sftp_chroot_enabled: true
        ssh_listen_addresses:
          - "127.0.0.1"
      Ubuntu-features:
        ansible_user: root
        ssh_user: root
        ssh_allow_groups: []
        ssh_teleport_integration: true
        ssh_sftp_chroot_enabled: true
        ssh_listen_addresses:
          - "127.0.0.1"
```

Note: `ssh_allow_groups: []` ensures preflight AllowGroups check is skipped (no group check when list is empty).

**Step 3: Add prepare tasks for features platforms to docker/prepare.yml**

Append these tasks after the access-control tasks:

```yaml
    - name: Create fake Teleport user CA key file (features platforms)
      ansible.builtin.copy:
        content: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeKeyForMoleculeTesting fake-teleport-ca\n"
        dest: /etc/ssh/teleport_user_ca.pub
        mode: "0644"
      when: inventory_hostname is search('features')

    - name: Create sftponly group (features platforms)
      ansible.builtin.group:
        name: sftponly
        state: present
      when: inventory_hostname is search('features')
```

**Step 4: Verify syntax**

```bash
cd /d/projects/bootstrap-ssh-coverage/ansible
molecule syntax -s docker
```

Expected: No errors.

**Step 5: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/molecule/docker/molecule.yml \
        ansible/roles/ssh/molecule/docker/prepare.yml
git commit -m "feat(ssh/molecule): add features docker platforms (Teleport/SFTP-chroot/ListenAddress)"
```

---

## Task 5: Add missing always-present directive checks + fix banner/moduli guards

Update `verify.yml` to:
1. Add 11 missing always-present directive assertions (IgnoreRhosts, ChallengeResponseAuthentication, MaxSessions, ClientAliveInterval, ClientAliveCountMax, TCPKeepAlive, PrintMotd, PrintLastLog, Port, AddressFamily, AcceptEnv)
2. Add RSA public key file stat + permissions check
3. Add `AllowGroups` absent assertion (for non-access-control platforms)
4. Guard banner assertions with `when: inventory_hostname is search('systemd') or inventory_hostname in ['arch-vm', 'ubuntu-base']`
5. Add moduli cleanup verification (for systemd + vagrant platforms)

**Files:**
- Modify: `ansible/roles/ssh/molecule/shared/verify.yml`

**Step 1: Read the current verify.yml fully** (it's 343 lines — read it all before editing)

```bash
cat -n ansible/roles/ssh/molecule/shared/verify.yml
```

**Step 2: Add missing directives after the `LoginGraceTime 60` assertion (around line 204)**

After `Assert LoginGraceTime 60`, add:

```yaml
    - name: Assert MaxSessions 10
      ansible.builtin.assert:
        that: "'MaxSessions 10' in ssh_verify_config_text"
        fail_msg: "MaxSessions is not set to 10"

    - name: Assert ClientAliveInterval 300
      ansible.builtin.assert:
        that: "'ClientAliveInterval 300' in ssh_verify_config_text"
        fail_msg: "ClientAliveInterval is not set to 300"

    - name: Assert ClientAliveCountMax 2
      ansible.builtin.assert:
        that: "'ClientAliveCountMax 2' in ssh_verify_config_text"
        fail_msg: "ClientAliveCountMax is not set to 2"

    - name: Assert TCPKeepAlive no
      ansible.builtin.assert:
        that: "'TCPKeepAlive no' in ssh_verify_config_text"
        fail_msg: "TCPKeepAlive is not set to 'no'"

    - name: Assert PrintMotd no
      ansible.builtin.assert:
        that: "'PrintMotd no' in ssh_verify_config_text"
        fail_msg: "PrintMotd is not set to 'no'"

    - name: Assert PrintLastLog yes
      ansible.builtin.assert:
        that: "'PrintLastLog yes' in ssh_verify_config_text"
        fail_msg: "PrintLastLog is not set to 'yes'"

    - name: Assert Port 22
      ansible.builtin.assert:
        that: "'Port 22' in ssh_verify_config_text"
        fail_msg: "Port is not set to 22"

    - name: Assert AddressFamily inet
      ansible.builtin.assert:
        that: "'AddressFamily inet' in ssh_verify_config_text"
        fail_msg: "AddressFamily is not set to 'inet'"
```

**Step 3: Add missing auth directives after `UsePAM yes` assertion (around line 136)**

After `Assert UsePAM yes`, add:

```yaml
    - name: Assert IgnoreRhosts yes
      ansible.builtin.assert:
        that: "'IgnoreRhosts yes' in ssh_verify_config_text"
        fail_msg: "IgnoreRhosts is not set to 'yes'"

    - name: Assert ChallengeResponseAuthentication no
      ansible.builtin.assert:
        that: "'ChallengeResponseAuthentication no' in ssh_verify_config_text"
        fail_msg: "ChallengeResponseAuthentication is not set to 'no'"

    - name: Assert AcceptEnv LANG LC_*
      ansible.builtin.assert:
        that: "'AcceptEnv LANG LC_*' in ssh_verify_config_text"
        fail_msg: "AcceptEnv is not set to 'LANG LC_*'"
```

**Step 4: Add AllowGroups absent assertion — insert AFTER the `RekeyLimit configured` assertion and BEFORE the `# ---- Cryptography -- negative checks ----` comment**

```yaml
    # ---- Access control -- default state ----

    - name: Assert AllowGroups directive is absent when not configured
      ansible.builtin.assert:
        that: "'AllowGroups' not in ssh_verify_config_text"
        fail_msg: "AllowGroups should NOT be in sshd_config when ssh_allow_groups is empty"
      when: not (inventory_hostname is search('access-control'))
```

**Step 5: Add RSA public key check — insert in the `# Host keys` section after the ECDSA assertions**

After `Assert no ECDSA host key`, add:

```yaml
    - name: Stat RSA public host key
      ansible.builtin.stat:
        path: /etc/ssh/ssh_host_rsa_key.pub
      register: ssh_verify_rsa_pub_key

    - name: Assert RSA public key exists with correct permissions
      ansible.builtin.assert:
        that:
          - ssh_verify_rsa_pub_key.stat.exists
          - ssh_verify_rsa_pub_key.stat.mode == '0644'
        fail_msg: >-
          /etc/ssh/ssh_host_rsa_key.pub missing or wrong permissions
          (expected 0644, got {{ ssh_verify_rsa_pub_key.stat.mode | default('missing') }})
```

**Step 6: Guard existing banner assertions with platform condition**

Find the banner section (around lines 289–303) and add `when:` to both assertions:

Original `Assert banner file exists`:
```yaml
    - name: Assert banner file exists
      ansible.builtin.assert:
        that: ssh_verify_banner.stat.exists
        fail_msg: "/etc/issue.net not found (ssh_banner_enabled was true in converge)"
```

Replace with:
```yaml
    - name: Assert banner file exists
      ansible.builtin.assert:
        that: ssh_verify_banner.stat.exists
        fail_msg: "/etc/issue.net not found (ssh_banner_enabled was true in converge)"
      when: inventory_hostname is search('systemd') or inventory_hostname in ['arch-vm', 'ubuntu-base']
```

Also add the same `when:` to `Assert Banner directive in sshd_config` and to `Stat banner file`:
```yaml
    - name: Stat banner file
      ansible.builtin.stat:
        path: /etc/issue.net
      register: ssh_verify_banner
      when: inventory_hostname is search('systemd') or inventory_hostname in ['arch-vm', 'ubuntu-base']
```

**Step 7: Add moduli cleanup verification — insert before `# ================================================================ #  Config syntax validation` section**

```yaml
    # ================================================================
    #  DH moduli cleanup verification
    # ================================================================

    - name: Check for weak DH moduli (systemd + vagrant platforms where ssh_moduli_cleanup=true)
      ansible.builtin.command:
        cmd: awk '$5 < 3072 { print }' /etc/ssh/moduli
      register: ssh_verify_weak_moduli
      changed_when: false
      when: inventory_hostname is search('systemd') or inventory_hostname in ['arch-vm', 'ubuntu-base']

    - name: Assert no weak DH moduli remain after cleanup
      ansible.builtin.assert:
        that: ssh_verify_weak_moduli.stdout == ''
        fail_msg: "Weak DH moduli still present (< 3072 bits):\n{{ ssh_verify_weak_moduli.stdout | truncate(500) }}"
      when: inventory_hostname is search('systemd') or inventory_hostname in ['arch-vm', 'ubuntu-base']
```

**Step 8: Update the final diagnostic debug message**

Find `Assert Ansible managed comment present` section and update the debug message:

```yaml
    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          SSH verify passed on {{ inventory_hostname }}: packages installed, service running+enabled,
          sshd_config correct (0600 root, all security directives verified),
          host keys correct (ed25519+RSA present, DSA/ECDSA absent),
          cryptography validated, AllowGroups absent (or configured for this platform),
          sshd -t passed.
```

**Step 9: Run syntax check on the modified verify.yml**

```bash
cd /d/projects/bootstrap-ssh-coverage/ansible
molecule syntax -s docker
```

Expected: No errors.

**Step 10: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/molecule/shared/verify.yml
git commit -m "test(ssh/molecule): add missing directive checks, RSA key check, AllowGroups absent, moduli verification, banner guards"
```

---

## Task 6: Add access-control assertions to verify.yml

Add assertions that only run on `*-access-control` platforms to verify AllowGroups, AllowUsers, DenyGroups, DenyUsers directives are present in sshd_config.

**Files:**
- Modify: `ansible/roles/ssh/molecule/shared/verify.yml`

**Step 1: Add access-control section to verify.yml**

Insert this block at the end of the file, BEFORE the `# ================================================================ #  Diagnostic` section:

```yaml
    # ================================================================
    #  Access control directives (access-control platforms only)
    # ================================================================

    - name: Assert AllowGroups sshusers in config (access-control)
      ansible.builtin.assert:
        that: "'AllowGroups sshusers' in ssh_verify_config_text"
        fail_msg: "AllowGroups sshusers not found in sshd_config"
      when: inventory_hostname is search('access-control')

    - name: Assert AllowUsers root in config (access-control)
      ansible.builtin.assert:
        that: "'AllowUsers root' in ssh_verify_config_text"
        fail_msg: "AllowUsers root not found in sshd_config"
      when: inventory_hostname is search('access-control')

    - name: Assert DenyGroups badgroup in config (access-control)
      ansible.builtin.assert:
        that: "'DenyGroups badgroup' in ssh_verify_config_text"
        fail_msg: "DenyGroups badgroup not found in sshd_config"
      when: inventory_hostname is search('access-control')

    - name: Assert DenyUsers baduser in config (access-control)
      ansible.builtin.assert:
        that: "'DenyUsers baduser' in ssh_verify_config_text"
        fail_msg: "DenyUsers baduser not found in sshd_config"
      when: inventory_hostname is search('access-control')
```

**Step 2: Syntax check**

```bash
cd /d/projects/bootstrap-ssh-coverage/ansible
molecule syntax -s docker
```

Expected: No errors.

**Step 3: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/molecule/shared/verify.yml
git commit -m "test(ssh/molecule): add access-control directive assertions (AllowGroups/AllowUsers/DenyGroups/DenyUsers)"
```

---

## Task 7: Add features assertions to verify.yml

Add assertions that only run on `*-features` platforms to verify Teleport CA, SFTP chroot, and ListenAddress are correctly configured.

**Files:**
- Modify: `ansible/roles/ssh/molecule/shared/verify.yml`

**Step 1: Add features section to verify.yml**

Insert this block AFTER the access-control section and BEFORE the diagnostic section:

```yaml
    # ================================================================
    #  Features directives (features platforms only)
    # ================================================================

    - name: Assert ListenAddress 127.0.0.1 in config (features)
      ansible.builtin.assert:
        that: "'ListenAddress 127.0.0.1' in ssh_verify_config_text"
        fail_msg: "ListenAddress 127.0.0.1 not found in sshd_config"
      when: inventory_hostname is search('features')

    - name: Assert TrustedUserCAKeys directive in config (features)
      ansible.builtin.assert:
        that: "'TrustedUserCAKeys /etc/ssh/teleport_user_ca.pub' in ssh_verify_config_text"
        fail_msg: "TrustedUserCAKeys directive not found in sshd_config"
      when: inventory_hostname is search('features')

    - name: Assert SFTP chroot Match Group block in config (features)
      ansible.builtin.assert:
        that: "'Match Group sftponly' in ssh_verify_config_text"
        fail_msg: "Match Group sftponly block not found in sshd_config"
      when: inventory_hostname is search('features')

    - name: Assert ChrootDirectory in config (features)
      ansible.builtin.assert:
        that: "'ChrootDirectory /home/%u' in ssh_verify_config_text"
        fail_msg: "ChrootDirectory /home/%u not found in sshd_config"
      when: inventory_hostname is search('features')
```

**Step 2: Syntax check**

```bash
cd /d/projects/bootstrap-ssh-coverage/ansible
molecule syntax -s docker
```

Expected: No errors.

**Step 3: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/molecule/shared/verify.yml
git commit -m "test(ssh/molecule): add features assertions (Teleport CA, SFTP chroot, ListenAddress)"
```

---

## Task 8: Fix default scenario vault_password_file

The `default/molecule.yml` still has a `vault_password_file` reference under `config_options.defaults`. While this scenario doesn't run in CI, it will fail on developer machines. Remove the reference.

**Files:**
- Modify: `ansible/roles/ssh/molecule/default/molecule.yml`

**Step 1: Remove vault_password_file from default/molecule.yml**

Find the `config_options` block (around lines 12–16):
```yaml
  config_options:
    defaults:
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
      callbacks_enabled: profile_tasks
```

Replace with:
```yaml
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
```

**Step 2: Verify the file looks correct**

```bash
cat ansible/roles/ssh/molecule/default/molecule.yml
```

Expected: No `vault_password_file` line present.

**Step 3: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/molecule/default/molecule.yml
git commit -m "fix(ssh/molecule): remove stale vault_password_file from default scenario"
```

---

## Task 9: Update README assertion count

Count all `ansible.builtin.assert` blocks in the updated verify.yml and update the README.

**Files:**
- Modify: `ansible/roles/ssh/README.md`

**Step 1: Count assertions in verify.yml**

```bash
grep -c 'ansible.builtin.assert' ansible/roles/ssh/molecule/shared/verify.yml
```

Note the number (expected: ~55–65 assert blocks total).

**Step 2: Update the README Testing section**

Find the line (around line 196):
```
### Verify assertions (38 total)
```

Replace with the actual count from Step 1. Also update the description paragraph below to mention the new test categories:

```markdown
### Verify assertions (N total)

Package install, service enabled+running, `sshd_config` permissions (0600/root),
security directives (PermitRootLogin, PasswordAuthentication, StrictModes, and 20+ more),
session directives (ClientAlive, TCPKeepAlive, PrintMotd, MaxSessions),
network directives (Port, AddressFamily, AcceptEnv),
cryptography suite (positive + negative checks), host key presence (ed25519, RSA pub) and absence (DSA, ECDSA),
`AllowGroups` absent by default, access control directives (AllowGroups/AllowUsers/DenyGroups/DenyUsers on `*-access-control` platforms),
Teleport CA integration and SFTP chroot and ListenAddress (on `*-features` platforms),
DH moduli cleanup result, banner (on banner-enabled platforms), SFTP subsystem,
`sshd -t` syntax validation, and Ansible managed comment.
```

Also update the scenarios table (around line 177–181) to document the new platforms:

```markdown
| Scenario | Driver | Platform | Purpose |
|----------|--------|----------|---------|
| `default` | localhost | local machine | Fast syntax + functional check (no daemon restart) |
| `docker` | Docker | `Archlinux-systemd`, `Ubuntu-systemd` | Full systemd lifecycle, service running+enabled, banner, moduli |
| `docker` | Docker | `Archlinux-access-control`, `Ubuntu-access-control` | Access control directives (AllowGroups/AllowUsers/DenyGroups/DenyUsers) |
| `docker` | Docker | `Archlinux-features`, `Ubuntu-features` | Teleport CA integration, SFTP chroot, ListenAddress |
| `vagrant` | Vagrant (libvirt) | `arch-vm`, `ubuntu-base` | Cross-distro integration (Arch `sshd.service` / Debian `ssh.service`) |
```

**Step 3: Commit**

```bash
cd /d/projects/bootstrap-ssh-coverage
git add ansible/roles/ssh/README.md
git commit -m "docs(ssh): update README with new test platforms and assertion count"
```

---

## Task 10: Push and create PR, run CI, merge

**Step 1: Push the branch**

```bash
git -C /d/projects/bootstrap-ssh-coverage push -u origin fix/ssh-molecule-coverage
```

**Step 2: Create PR**

```bash
gh pr create \
  --title "test(ssh): fill molecule coverage gaps — access control, Teleport, SFTP chroot, moduli" \
  --body "$(cat <<'EOF'
## Summary

- Add 4 new Docker platforms: `*-access-control` (AllowGroups/AllowUsers/DenyGroups/DenyUsers) and `*-features` (Teleport CA + SFTP chroot + ListenAddress)
- Move `converge.yml` vars block to per-platform `host_vars` in `molecule.yml` (enables per-platform config without precedence conflicts)
- Add 15 missing always-present directive assertions (IgnoreRhosts, ChallengeResponseAuthentication, MaxSessions, ClientAliveInterval, ClientAliveCountMax, TCPKeepAlive, PrintMotd, PrintLastLog, Port, AddressFamily, AcceptEnv, RSA pub key permissions, AllowGroups absent, DH moduli cleanup result)
- Guard banner assertions for platforms where `ssh_banner_enabled: false`
- Fix `default` scenario stale vault_password_file reference

## Test plan

- [ ] Docker CI: all 6 platforms pass (`syntax → create → prepare → converge → idempotence → verify → destroy`)
- [ ] Vagrant CI: `arch-vm` and `ubuntu-base` pass
- [ ] No regression on existing systemd platform assertions

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Wait for CI**

```bash
gh pr checks --watch
```

Expected wait: ~8–12 minutes for Docker CI, ~25–35 minutes for Vagrant CI (based on previous runs).

If CI fails, investigate with:
```bash
gh run list --limit 5
gh run view <run-id> --log-failed
```

**Step 4: Merge on CI green**

```bash
gh pr merge --squash --delete-branch
```

**Step 5: Clean up worktree**

```bash
git -C /d/projects/bootstrap worktree remove /d/projects/bootstrap-ssh-coverage
```

Expected: Worktree removed. If it says "contains modified or untracked files", commit or stash first.

**Step 6: Verify master is up to date**

```bash
git -C /d/projects/bootstrap fetch origin master
git -C /d/projects/bootstrap log --oneline -3 origin/master
```

Expected: Shows the squash merge commit at the top.
