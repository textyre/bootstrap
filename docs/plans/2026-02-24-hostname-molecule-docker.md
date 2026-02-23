# hostname: Docker Molecule Test Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Docker-based Molecule scenario to the hostname role so it runs in CI, following the locale/shared pattern to eliminate playbook duplication.

**Architecture:** Move `converge.yml` and `verify.yml` into `molecule/shared/`, point both `default` and `docker` scenarios at those shared files. Fix an existing bug in `tasks/main.yml` where the assert references an undefined variable `_hostname_check` instead of `hostname_check`.

**Tech Stack:** Ansible, Molecule, Docker, arch-systemd container image

---

### Task 1: Fix bug in tasks/main.yml

**Files:**
- Modify: `ansible/roles/hostname/tasks/main.yml:40`

The assert on line 40 references `_hostname_check.stdout` but the variable is registered as
`hostname_check` (line 33). This causes the assert to fail on an undefined variable.

**Step 1: Open the file and confirm the bug**

Read `ansible/roles/hostname/tasks/main.yml` lines 30–43. You should see:

```yaml
- name: Verify hostname is set
  ansible.builtin.command: hostname
  register: hostname_check          # ← registered as hostname_check
  changed_when: false

- name: Assert hostname matches expected value
  ansible.builtin.assert:
    that:
      - _hostname_check.stdout == hostname_name   # ← BUG: _hostname_check is undefined
```

**Step 2: Apply the fix**

Change line 40 from:
```yaml
      - _hostname_check.stdout == hostname_name
```
to:
```yaml
      - hostname_check.stdout == hostname_name
```

**Step 3: Commit**

```bash
git add ansible/roles/hostname/tasks/main.yml
git commit -m "fix(hostname): correct variable name in hostname assert"
```

---

### Task 2: Create molecule/shared/converge.yml

**Files:**
- Create: `ansible/roles/hostname/molecule/shared/converge.yml`

This is the shared converge playbook used by both `default` and `docker` scenarios. Follows
`ansible/roles/locale/molecule/shared/converge.yml` exactly in structure — no `vars_files`,
no `pre_tasks`.

**Step 1: Create the file**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: hostname
      vars:
        hostname_name: "archbox"
        hostname_domain: "example.com"
```

**Step 2: Commit**

```bash
git add ansible/roles/hostname/molecule/shared/converge.yml
git commit -m "test(hostname): add shared converge.yml"
```

---

### Task 3: Create molecule/shared/verify.yml

**Files:**
- Create: `ansible/roles/hostname/molecule/shared/verify.yml`

Verifies three things: exact hostname match, FQDN format in /etc/hosts, no duplicate
`127.0.1.1` entries.

The role's `hosts.yml` builds this line when `hostname_domain` is set:
```
127.0.1.1\tarchbox.example.com\tarchbox
```
(tab-separated, written via `lineinfile`)

Use `ansible.builtin.slurp` to read `/etc/hosts` then assert on decoded content — same
technique as `ansible/roles/ntp/molecule/default/verify.yml` for `chrony.conf`.

**Step 1: Create the file**

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: false

  vars:
    test_hostname: "archbox"
    test_domain: "example.com"

  tasks:

    # ---- hostname exact match ----

    - name: Get current hostname
      ansible.builtin.command: hostname
      register: hostname_verify_hostname
      changed_when: false

    - name: Assert hostname matches expected value
      ansible.builtin.assert:
        that:
          - hostname_verify_hostname.stdout | trim == test_hostname
        fail_msg: >-
          Hostname mismatch: got '{{ hostname_verify_hostname.stdout | trim }}',
          expected '{{ test_hostname }}'

    # ---- /etc/hosts FQDN entry ----

    - name: Read /etc/hosts
      ansible.builtin.slurp:
        src: /etc/hosts
      register: hostname_verify_hosts_raw

    - name: Decode /etc/hosts content
      ansible.builtin.set_fact:
        hostname_verify_hosts_text: "{{ hostname_verify_hosts_raw.content | b64decode }}"

    - name: Assert FQDN entry is present in /etc/hosts
      ansible.builtin.assert:
        that:
          - "'127.0.1.1' in hostname_verify_hosts_text"
          - "test_hostname ~ '.' ~ test_domain in hostname_verify_hosts_text"
          - "test_hostname in hostname_verify_hosts_text"
        fail_msg: >-
          /etc/hosts is missing expected FQDN entry.
          Expected line containing '127.0.1.1', '{{ test_hostname }}.{{ test_domain }}',
          and '{{ test_hostname }}'.
          Actual content:
          {{ hostname_verify_hosts_text }}

    # ---- no duplicate 127.0.1.1 entries ----

    - name: Assert exactly one 127.0.1.1 line in /etc/hosts
      ansible.builtin.assert:
        that:
          - hostname_verify_hosts_text | regex_findall('^127\\.0\\.1\\.1', multiline=True) | length == 1
        fail_msg: >-
          Expected exactly one '127.0.1.1' line in /etc/hosts, found:
          {{ hostname_verify_hosts_text | regex_findall('^127\\.0\\.1\\.1', multiline=True) | length }}

    # ---- summary ----

    - name: Show result
      ansible.builtin.debug:
        msg:
          - "Hostname check passed!"
          - "Hostname: {{ hostname_verify_hostname.stdout | trim }}"
          - "/etc/hosts: 127.0.1.1 {{ test_hostname }}.{{ test_domain }} {{ test_hostname }}"
```

**Step 2: Commit**

```bash
git add ansible/roles/hostname/molecule/shared/verify.yml
git commit -m "test(hostname): add shared verify.yml with FQDN and exact hostname checks"
```

---

### Task 4: Create molecule/docker/molecule.yml

**Files:**
- Create: `ansible/roles/hostname/molecule/docker/molecule.yml`

Copied from `ansible/roles/timezone/molecule/docker/molecule.yml` with two changes:
- Add `playbooks:` block pointing to `../shared/`
- Keep `skip-tags: report` (common role not available in Docker isolation)

**Step 1: Create the file**

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
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - converge
    - idempotence
    - verify
    - destroy
```

**Step 2: Commit**

```bash
git add ansible/roles/hostname/molecule/docker/molecule.yml
git commit -m "test(hostname): add docker molecule scenario for CI"
```

---

### Task 5: Update molecule/default/molecule.yml

**Files:**
- Modify: `ansible/roles/hostname/molecule/default/molecule.yml`

Replace entire content. Changes from current version:
- Remove `vault_password_file` (hostname role uses no vault vars)
- Change `ANSIBLE_ROLES_PATH` from `${MOLECULE_PROJECT_DIRECTORY}/roles` to `${MOLECULE_PROJECT_DIRECTORY}/../` (matches locale pattern, finds sibling roles)
- Add `playbooks:` block pointing to `../shared/`
- Add `idempotence` to `test_sequence`
- Remove `config_options.defaults.vault_password_file`

**Step 1: Replace the file content**

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

**Step 2: Commit**

```bash
git add ansible/roles/hostname/molecule/default/molecule.yml
git commit -m "test(hostname): update default scenario to use shared playbooks"
```

---

### Task 6: Delete old molecule/default/converge.yml and verify.yml

**Files:**
- Delete: `ansible/roles/hostname/molecule/default/converge.yml`
- Delete: `ansible/roles/hostname/molecule/default/verify.yml`

These are now replaced by `molecule/shared/`. Keeping them would cause confusion since
`molecule/default/molecule.yml` no longer references them.

**Step 1: Delete both files**

```bash
git rm ansible/roles/hostname/molecule/default/converge.yml
git rm ansible/roles/hostname/molecule/default/verify.yml
```

**Step 2: Commit**

```bash
git commit -m "test(hostname): remove old default scenario playbooks (replaced by shared)"
```

---

### Task 7: Verify the structure is correct

**Step 1: Check final file tree**

```bash
find ansible/roles/hostname/molecule -type f | sort
```

Expected output:
```
ansible/roles/hostname/molecule/default/molecule.yml
ansible/roles/hostname/molecule/docker/molecule.yml
ansible/roles/hostname/molecule/shared/converge.yml
ansible/roles/hostname/molecule/shared/verify.yml
```

**Step 2: Verify CI matrix picks up hostname**

```bash
find ansible/roles -name molecule.yml -path "*/docker/molecule.yml" \
  | sed 's|ansible/roles/||;s|/molecule.*||' | sort -u
```

`hostname` should appear in the output.

**Step 3: Run syntax check locally (via SSH to VM)**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible && source .venv/bin/activate && \
  cd roles/hostname && molecule syntax -s docker"
```

Expected: no errors.

**Step 4: Commit if any last-minute fixes were needed**

If Task 7 revealed structural issues, fix and commit them. Otherwise no commit needed here.

---

## Verification After All Tasks

Run the Docker scenario on the VM:

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible && source .venv/bin/activate && \
  ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg \
  MOLECULE_ARCH_IMAGE=ghcr.io/textyre/bootstrap/arch-systemd:latest \
  cd roles/hostname && molecule test -s docker"
```

All steps (syntax, create, converge, idempotence, verify, destroy) must pass.
