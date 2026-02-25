# ssh_keys: Molecule Testing Plan (shared + docker + vagrant)

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### Role purpose

The `ssh_keys` role manages SSH authorized keys and optional keypair generation, extracted from the `user` role for single-responsibility. It performs three functions:

1. **Deploy authorized_keys** from `accounts[].ssh_keys` data source via `ansible.posix.authorized_key`.
2. **Remove authorized_keys** for absent users (zero-trust cleanup).
3. **Optionally generate SSH keypairs** (ed25519 by default) on target machines via `community.crypto.openssh_keypair`.

The role also includes inline verification (ROLE-005) that checks `.ssh` directory permissions and `authorized_keys` file existence, plus reporting via the `common` role.

### Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `ssh_keys_manage_authorized_keys` | `true` | Deploy authorized_keys from accounts data source |
| `ssh_keys_generate_user_keys` | `false` | Generate SSH keypairs on target machines |
| `ssh_keys_key_type` | `ed25519` | Key type for generation |
| `ssh_keys_exclusive` | `false` | Remove unlisted keys from authorized_keys |
| `ssh_keys_supported_os` | `[Archlinux, Debian, RedHat, Void, Gentoo]` | OS family allowlist |

### Data model

The role consumes a shared `accounts` variable:

```yaml
accounts:
  - name: alice
    state: present
    ssh_keys:
      - "ssh-ed25519 AAAA... alice@laptop"
  - name: bob
    state: absent   # authorized_keys removed
```

Falls back to `user_owner` + `user_additional_users` if `accounts` is undefined.

### Collection dependencies

- `ansible.posix >=1.0.0` -- `authorized_key` module (authorized_keys.yml)
- `community.crypto >=2.0.0` -- `openssh_keypair` module (keygen.yml, only when `ssh_keys_generate_user_keys: true`)

### Existing molecule scenario

```
molecule/
  default/
    molecule.yml    -- driver: default (localhost), local connection
    converge.yml    -- test with ansible_user_id, one ed25519 key, keygen disabled
    verify.yml      -- 5 checks: .ssh dir exists, mode 0700, authkeys exists, mode 0600, key content grep
```

**molecule.yml** uses `driver: default` with `ansible_connection: local`, vault password file, no create/destroy steps. Test sequence is `syntax -> converge -> verify` (no idempotence check).

**converge.yml** defines a single test account using `ansible_user_id` with one test SSH public key (`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey1234567890abcdefghijklmnop test@molecule`). `ssh_keys_generate_user_keys: false`, `ssh_keys_exclusive: false`.

**verify.yml** performs five assertions:
1. `.ssh` directory exists at `/home/{{ ansible_user_id }}/.ssh`
2. `.ssh` directory mode is `0700`
3. `authorized_keys` file exists
4. `authorized_keys` file mode is `0600`
5. `authorized_keys` contains `test@molecule` (via grep)

### Issues with current tests

1. **Hardcoded `/home/` path** -- verify.yml uses `/home/{{ ansible_user_id }}/.ssh` which fails for root (should be `/root/.ssh`). The role itself handles root via a conditional path expression. Tests should match.
2. **No idempotence check** -- current test_sequence omits idempotence. Both Docker and Vagrant scenarios should include it.
3. **No keygen testing** -- `ssh_keys_generate_user_keys` is always `false`. A thorough test should exercise both code paths.
4. **No absent-user testing** -- the `authorized_keys.yml` task that removes keys for absent users is never tested.
5. **No exclusive mode testing** -- `ssh_keys_exclusive` is always `false`.

## 2. Cross-Platform Analysis

SSH authorized_keys management is one of the most portable operations in Linux administration. The `~/.ssh/` directory structure and `authorized_keys` file format are defined by OpenSSH and are identical across all distributions.

### What is identical (Arch and Ubuntu)

| Aspect | Arch Linux | Ubuntu 24.04 | Notes |
|--------|------------|--------------|-------|
| `.ssh` directory path | `~/.ssh/` | `~/.ssh/` | Universal OpenSSH convention |
| `authorized_keys` path | `~/.ssh/authorized_keys` | `~/.ssh/authorized_keys` | Default sshd_config on both |
| `authorized_keys` format | One key per line | One key per line | OpenSSH standard |
| Directory permissions | 0700 required | 0700 required | OpenSSH enforces via `StrictModes` |
| File permissions | 0600 required | 0600 required | OpenSSH enforces via `StrictModes` |
| `getent passwd` | Works | Works | POSIX standard |
| `community.crypto.openssh_keypair` | Works (needs `openssh`) | Works (needs `openssh-client`) | Package name differs |
| `ansible.posix.authorized_key` | Works | Works | Pure file manipulation |
| Home directory convention | `/home/<user>` or `/root` | `/home/<user>` or `/root` | FHS standard |

### Differences that matter

1. **Package names for keygen**: If `ssh_keys_generate_user_keys: true`, the `community.crypto.openssh_keypair` module requires `ssh-keygen` on the target. On Arch this is in the `openssh` package; on Ubuntu it is in `openssh-client`. The role itself does not install packages (it assumes SSH tooling is present). For molecule testing, Docker containers and Vagrant boxes both typically have SSH tools pre-installed.

2. **Default user in containers vs VMs**: Docker containers run as root by default. Vagrant boxes have a `vagrant` user with sudo. The converge playbook must create a test user explicitly rather than relying on `ansible_user_id`.

3. **`ansible.posix` collection availability**: Must be installed in the test environment. The Docker image (`arch-systemd`) likely has it; Vagrant boxes need it in the provisioner's collection path.

### Verdict

The role's operations are 100% cross-platform. `shared/verify.yml` can be written without any `when: ansible_facts['os_family']` guards. The same assertions apply to both Arch and Ubuntu.

## 3. Shared Migration

Move the existing `default/converge.yml` and `default/verify.yml` content into `molecule/shared/`, then point all scenarios at the shared playbooks.

### molecule/shared/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  vars:
    # Test accounts using the shared data model.
    # molecule_test_user is set by prepare.yml (defaults to "testuser").
    accounts:
      - name: "{{ molecule_test_user | default('testuser') }}"
        state: present
        ssh_keys:
          - >-
            ssh-ed25519
            AAAAC3NzaC1lZDI1NTE5AAAAITestKey1234567890abcdefghijklmnop
            test@molecule
          - >-
            ssh-ed25519
            AAAAC3NzaC1lZDI1NTE5AAAAISecondTestKey567890abcdefghijklmn
            test2@molecule
      - name: absent_user
        state: absent
    ssh_keys_generate_user_keys: false
    ssh_keys_exclusive: false

  roles:
    - role: ssh_keys
```

**Design decisions:**

- Uses a dedicated `molecule_test_user` variable (set in prepare.yml) instead of `ansible_user_id`. This avoids the root-in-Docker vs vagrant-user-in-VM ambiguity.
- Two SSH keys for the present user. This tests that multiple keys are appended correctly and enables the verify playbook to check for both.
- An `absent_user` entry tests the zero-trust removal path. The prepare playbook creates this user and populates an authorized_keys file, then the role should remove it.
- `ssh_keys_generate_user_keys: false` -- keygen is tested separately or can be enabled via scenario-level variable override in the future.

### molecule/shared/verify.yml

```yaml
---
- name: Verify ssh_keys role
  hosts: all
  become: true
  gather_facts: true

  vars:
    _verify_test_user: "{{ molecule_test_user | default('testuser') }}"
    _verify_test_home: "/home/{{ _verify_test_user }}"

  tasks:

    # ---- .ssh directory ----

    - name: Stat .ssh directory
      ansible.builtin.stat:
        path: "{{ _verify_test_home }}/.ssh"
      register: _sshkeys_verify_dir

    - name: Assert .ssh directory exists with mode 0700
      ansible.builtin.assert:
        that:
          - _sshkeys_verify_dir.stat.exists
          - _sshkeys_verify_dir.stat.isdir
          - _sshkeys_verify_dir.stat.mode == '0700'
          - _sshkeys_verify_dir.stat.pw_name == _verify_test_user
        fail_msg: >-
          .ssh directory for {{ _verify_test_user }}:
          exists={{ _sshkeys_verify_dir.stat.exists | default(false) }},
          mode={{ _sshkeys_verify_dir.stat.mode | default('n/a') }},
          owner={{ _sshkeys_verify_dir.stat.pw_name | default('n/a') }}

    # ---- authorized_keys file ----

    - name: Stat authorized_keys
      ansible.builtin.stat:
        path: "{{ _verify_test_home }}/.ssh/authorized_keys"
      register: _sshkeys_verify_authkeys

    - name: Assert authorized_keys exists with mode 0600
      ansible.builtin.assert:
        that:
          - _sshkeys_verify_authkeys.stat.exists
          - _sshkeys_verify_authkeys.stat.isreg
          - _sshkeys_verify_authkeys.stat.mode == '0600'
          - _sshkeys_verify_authkeys.stat.pw_name == _verify_test_user
        fail_msg: >-
          authorized_keys for {{ _verify_test_user }}:
          exists={{ _sshkeys_verify_authkeys.stat.exists | default(false) }},
          mode={{ _sshkeys_verify_authkeys.stat.mode | default('n/a') }},
          owner={{ _sshkeys_verify_authkeys.stat.pw_name | default('n/a') }}

    # ---- Key content ----

    - name: Read authorized_keys content
      ansible.builtin.slurp:
        src: "{{ _verify_test_home }}/.ssh/authorized_keys"
      register: _sshkeys_verify_content_raw

    - name: Set authorized_keys text fact
      ansible.builtin.set_fact:
        _sshkeys_verify_content: "{{ _sshkeys_verify_content_raw.content | b64decode }}"

    - name: Assert first test key is present (test@molecule)
      ansible.builtin.assert:
        that:
          - "'test@molecule' in _sshkeys_verify_content"
        fail_msg: "Key 'test@molecule' not found in authorized_keys"

    - name: Assert second test key is present (test2@molecule)
      ansible.builtin.assert:
        that:
          - "'test2@molecule' in _sshkeys_verify_content"
        fail_msg: "Key 'test2@molecule' not found in authorized_keys"

    # ---- Absent user cleanup ----

    - name: Stat authorized_keys for absent_user
      ansible.builtin.stat:
        path: /home/absent_user/.ssh/authorized_keys
      register: _sshkeys_verify_absent

    - name: Assert authorized_keys removed for absent_user
      ansible.builtin.assert:
        that:
          - not _sshkeys_verify_absent.stat.exists
        fail_msg: >-
          authorized_keys for absent_user should have been removed
          but still exists at /home/absent_user/.ssh/authorized_keys

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          ssh_keys verify passed: .ssh directory 0700 owned by {{ _verify_test_user }},
          authorized_keys 0600 with both test keys present,
          absent_user authorized_keys removed.
```

**Design decisions:**

- Uses `slurp` + `b64decode` instead of `grep` command -- pure Ansible, no shell dependency.
- Checks both key comments (`test@molecule`, `test2@molecule`) to verify multi-key deployment.
- Validates absent-user cleanup by asserting `authorized_keys` was removed.
- Checks file ownership (not just permissions) to catch `owner:` parameter bugs.
- All paths use the `_verify_test_user` variable, no hardcoded `/home/{{ ansible_user_id }}`.
- No OS-family guards needed anywhere.

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

    # The ssh_keys role requires ansible.posix and community.crypto collections.
    # These should be available in the test environment (installed via requirements.yml).
    # No packages to install -- openssh is present in the arch-systemd image.

    - name: Create test user for ssh_keys converge
      ansible.builtin.user:
        name: testuser
        state: present
        create_home: true
        shell: /bin/bash

    - name: Create absent_user with pre-existing authorized_keys
      ansible.builtin.user:
        name: absent_user
        state: present
        create_home: true
        shell: /bin/bash

    - name: Create .ssh directory for absent_user
      ansible.builtin.file:
        path: /home/absent_user/.ssh
        state: directory
        owner: absent_user
        mode: "0700"

    - name: Plant authorized_keys for absent_user (role should remove this)
      ansible.builtin.copy:
        content: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOldKey oldkey@shouldberemoved\n"
        dest: /home/absent_user/.ssh/authorized_keys
        owner: absent_user
        mode: "0600"

    - name: Set molecule_test_user fact
      ansible.builtin.set_fact:
        molecule_test_user: testuser
        cacheable: true
```

**Design decisions:**

- Creates `testuser` explicitly. Docker containers run as root, and the converge playbook needs a non-root user to test the `/home/<user>` path correctly.
- Creates `absent_user` with a pre-existing `authorized_keys` file. The converge run should remove this file, and verify checks that it is gone. This tests the zero-trust cleanup path.
- Sets `molecule_test_user` as a cacheable fact so it persists into the converge and verify plays.
- No `openssh` package installation -- the `arch-systemd` image includes it. If it does not, add `community.general.pacman: name: openssh state: present` before the user creation tasks.

### Test keys

The converge playbook uses **synthetic test keys** with obviously fake base64 payloads:

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey1234567890abcdefghijklmnop test@molecule
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISecondTestKey567890abcdefghijklmn test2@molecule
```

These are **not valid cryptographic keys**. They have the correct format prefix (`ssh-ed25519 AAAA...`) so `ansible.posix.authorized_key` accepts them, but they cannot be used for actual SSH authentication. This is intentional -- molecule tests should never contain real production keys or keys that could grant access to anything.

If `ansible.posix.authorized_key` rejects the fake base64 payload, generate real throwaway test keys during prepare:

```yaml
- name: Generate throwaway test key pair
  community.crypto.openssh_keypair:
    path: /tmp/molecule_test_key
    type: ed25519
    comment: test@molecule
  register: _prepare_testkey

- name: Set test key fact
  ansible.builtin.set_fact:
    molecule_test_pubkey: "{{ _prepare_testkey.public_key }}"
    cacheable: true
```

Then reference `molecule_test_pubkey` in converge.yml instead of the hardcoded string.

**Recommendation:** Start with the synthetic keys (they work with `authorized_key` because the module does not validate key material). Fall back to generated keys only if the module rejects them.

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

    - name: Create test user for ssh_keys converge
      ansible.builtin.user:
        name: testuser
        state: present
        create_home: true
        shell: /bin/bash

    - name: Create absent_user with pre-existing authorized_keys
      ansible.builtin.user:
        name: absent_user
        state: present
        create_home: true
        shell: /bin/bash

    - name: Create .ssh directory for absent_user
      ansible.builtin.file:
        path: /home/absent_user/.ssh
        state: directory
        owner: absent_user
        mode: "0700"

    - name: Plant authorized_keys for absent_user (role should remove this)
      ansible.builtin.copy:
        content: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOldKey oldkey@shouldberemoved\n"
        dest: /home/absent_user/.ssh/authorized_keys
        owner: absent_user
        mode: "0600"

    - name: Set molecule_test_user fact
      ansible.builtin.set_fact:
        molecule_test_user: testuser
        cacheable: true
```

**Differences from Docker prepare.yml:**

The Vagrant prepare includes the standard Vagrant bootstrapping sequence (Python install on Arch via raw, pacman keyring refresh, system upgrade, apt cache update) that is not needed in Docker (the arch-systemd image is pre-configured). The test user and absent_user creation blocks are identical between both scenarios.

This is consistent with the `package_manager` Vagrant prepare pattern.

## 6. Verify.yml Design -- Detailed Assertions

### Assertion matrix

| # | Check | Module | Expected | Failure message |
|---|-------|--------|----------|-----------------|
| 1 | `.ssh` directory exists | `stat` | `exists == true`, `isdir == true` | Directory missing |
| 2 | `.ssh` directory mode | `stat` | `mode == '0700'` | Wrong permissions |
| 3 | `.ssh` directory owner | `stat` | `pw_name == testuser` | Wrong ownership |
| 4 | `authorized_keys` exists | `stat` | `exists == true`, `isreg == true` | File missing |
| 5 | `authorized_keys` mode | `stat` | `mode == '0600'` | Wrong permissions |
| 6 | `authorized_keys` owner | `stat` | `pw_name == testuser` | Wrong ownership |
| 7 | First key present | `slurp` + string check | `'test@molecule' in content` | Key missing |
| 8 | Second key present | `slurp` + string check | `'test2@molecule' in content` | Key missing |
| 9 | Absent user cleanup | `stat` | `exists == false` | File not removed |

### Why `slurp` instead of `grep`

The existing verify.yml uses `ansible.builtin.command: grep -c ...` which works but:
- Introduces shell dependency (grep binary must exist)
- Produces `changed_when: false` noise in molecule output
- Requires `failed_when:` override to control exit codes

Using `slurp` + `b64decode` is pure Ansible, produces cleaner output, and avoids the shell. This matches the pattern used in `ntp/molecule/shared/verify.yml`.

### What is NOT tested (and why)

| Feature | Why not tested |
|---------|---------------|
| `ssh_keys_generate_user_keys: true` | Requires `community.crypto.openssh_keypair` and `ssh-keygen` binary. Can be tested in a separate scenario or by overriding the variable. Omitted from the default converge to keep the baseline simple. |
| `ssh_keys_exclusive: true` | Exclusive mode removes all keys not in the `ssh_keys` list. Testing this requires planting extra keys first. Can be added as a separate test case within converge if needed. |
| Root user authorized_keys | The role handles root via a conditional path (`/root` vs `/home/<user>`). Testing root requires running converge with `accounts: [{name: root, ...}]`. This is lower priority since root SSH is typically disabled. |
| Multiple present users | The role loops over all present users. Testing with 2+ present users validates the loop. The current plan tests with one present user and one absent user. Adding a second present user is a future enhancement. |

### Future enhancement: keygen test block

If keygen testing is desired, add a second converge play or override the variable:

```yaml
# In converge.yml, after the main role application:
- name: Converge (keygen)
  hosts: all
  become: true
  gather_facts: true
  vars:
    accounts:
      - name: "{{ molecule_test_user | default('testuser') }}"
        state: present
        ssh_keys: []
    ssh_keys_generate_user_keys: true
    ssh_keys_key_type: ed25519
  roles:
    - role: ssh_keys
```

Then add to verify.yml:

```yaml
- name: Stat generated keypair
  ansible.builtin.stat:
    path: "{{ _verify_test_home }}/.ssh/id_ed25519"
  register: _sshkeys_verify_keygen

- name: Assert generated private key exists with mode 0600
  ansible.builtin.assert:
    that:
      - _sshkeys_verify_keygen.stat.exists
      - _sshkeys_verify_keygen.stat.mode == '0600'
```

This is out of scope for the initial implementation but documented for future use.

## 7. Implementation Order

1. **Create `molecule/shared/` directory and move playbooks**
   - Create `ansible/roles/ssh_keys/molecule/shared/converge.yml` (new content from section 3)
   - Create `ansible/roles/ssh_keys/molecule/shared/verify.yml` (new content from section 3)

2. **Update `molecule/default/molecule.yml`**
   - Point playbooks at `../shared/converge.yml` and `../shared/verify.yml`
   - Remove vault password file reference (the ssh_keys role does not use vault)
   - Add `idempotence` to test_sequence
   - Add prepare playbook reference (or inline prepare tasks)

3. **Create `molecule/default/prepare.yml`**
   - Create testuser and absent_user on localhost
   - Set `molecule_test_user` fact
   - Simpler than Docker/Vagrant -- no package cache updates needed

4. **Delete old `molecule/default/converge.yml` and `molecule/default/verify.yml`**
   - These are replaced by the shared versions

5. **Create `molecule/docker/molecule.yml`** (from section 4)

6. **Create `molecule/docker/prepare.yml`** (from section 4)

7. **Create `molecule/vagrant/molecule.yml`** (from section 5)

8. **Create `molecule/vagrant/prepare.yml`** (from section 5)

9. **Test Docker scenario locally**
   ```bash
   cd ansible/roles/ssh_keys
   molecule test -s docker
   ```
   Expected: all 7 steps pass (syntax, create, prepare, converge, idempotence, verify, destroy).

10. **Test Vagrant scenario locally** (requires KVM/libvirt)
    ```bash
    cd ansible/roles/ssh_keys
    molecule test -s vagrant
    ```
    Expected: all 7 steps pass on both arch-vm and ubuntu-noble.

11. **Test default scenario** (sanity check)
    ```bash
    cd ansible/roles/ssh_keys
    molecule test
    ```

12. **Commit** -- single commit with all new/modified files.

### Final file tree

```
ansible/roles/ssh_keys/molecule/
  shared/
    converge.yml     (NEW)
    verify.yml       (NEW)
  default/
    molecule.yml     (MODIFIED -- points to shared, adds prepare + idempotence)
    prepare.yml      (NEW)
  docker/
    molecule.yml     (NEW)
    prepare.yml      (NEW)
  vagrant/
    molecule.yml     (NEW)
    prepare.yml      (NEW)
```

Files removed:
- `molecule/default/converge.yml` (replaced by shared)
- `molecule/default/verify.yml` (replaced by shared)

## 8. Risks / Notes

### Test keys are not real keys

The test SSH public keys use obviously fake base64 payloads (`TestKey1234567890abcdefghijklmnop`). These are syntactically valid enough for `ansible.posix.authorized_key` to write them to the file, but they are not cryptographically valid and cannot be used for SSH authentication.

**Risk:** If `authorized_key` validates key material (it does not -- it only validates format), the fake keys will be rejected. **Mitigation:** Generate real throwaway keys in prepare.yml using `community.crypto.openssh_keypair` (fallback documented in section 4).

### Idempotence considerations

The `ansible.posix.authorized_key` module is idempotent when the key already exists. The `.ssh` directory creation via `ansible.builtin.file` is idempotent. The absent-user file removal via `ansible.builtin.file state=absent` is idempotent (removing an already-absent file is a no-op).

**Risk:** The in-role `verify.yml` (tasks/verify.yml) runs `getent` and `stat` which register new variables on each run. These are read-only operations and will not cause idempotence failures.

**Risk:** The report tasks (`include_role: common`) are skipped via `skip-tags: report`. If report tasks are not properly tagged, they could fail in molecule due to the `common` role not being available. The existing tagging (`tags: [ssh_keys, report]`) is correct and `skip-tags: report` will exclude them.

### Docker: user creation in prepare

Docker containers start as root with no non-root users. The prepare playbook creates `testuser` and `absent_user`. These users persist for the duration of the container lifecycle. The `ansible.builtin.user` module handles home directory creation.

**Risk:** If the `arch-systemd` image lacks the `shadow` package (provides `useradd`), user creation will fail. The standard arch-systemd image includes `shadow`. If not, add `community.general.pacman: name: shadow state: present` to the top of prepare.yml.

### Vagrant: generic/arch Python

The `generic/arch` Vagrant box may not include Python. The prepare playbook uses `ansible.builtin.raw` to install Python before any module-based tasks. This is the established project pattern (identical to `package_manager/molecule/vagrant/prepare.yml`).

### No CI workflow included

This plan covers the molecule scenario files only. Integration with CI (GitHub Actions workflow for molecule-docker, molecule-vagrant) is out of scope. The scenarios are designed to be picked up by existing or future centralized CI workflows, or run manually.

### Collection installation

Both `ansible.posix` and `community.crypto` must be installed in the Ansible environment. For local development this is typically handled by `ansible-galaxy collection install -r ansible/requirements.yml`. In CI, the collections should be installed as a workflow step. The molecule scenarios do not handle collection installation themselves.

### Absent user edge case

The converge playbook lists `absent_user` with `state: absent`. The role's `authorized_keys.yml` removes the `authorized_keys` file for absent users. However, the role does **not** remove the `.ssh` directory or the user account itself -- that is the `user` role's responsibility. The verify playbook only asserts that `authorized_keys` is gone, not that the user or `.ssh` directory is removed.

## File Summary

| File | Action | Purpose |
|------|--------|---------|
| `molecule/shared/converge.yml` | CREATE | Shared converge: testuser with 2 keys + absent_user |
| `molecule/shared/verify.yml` | CREATE | Shared verify: 9 assertions (dir, file, content, cleanup) |
| `molecule/default/molecule.yml` | MODIFY | Point to shared playbooks, add idempotence + prepare |
| `molecule/default/prepare.yml` | CREATE | Create testuser + absent_user on localhost |
| `molecule/default/converge.yml` | DELETE | Replaced by shared |
| `molecule/default/verify.yml` | DELETE | Replaced by shared |
| `molecule/docker/molecule.yml` | CREATE | Docker scenario with arch-systemd |
| `molecule/docker/prepare.yml` | CREATE | Pacman cache + user creation + absent_user setup |
| `molecule/vagrant/molecule.yml` | CREATE | Vagrant scenario: Arch + Ubuntu VMs |
| `molecule/vagrant/prepare.yml` | CREATE | Python bootstrap + keyring + user creation |
