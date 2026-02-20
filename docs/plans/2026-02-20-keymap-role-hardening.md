# keymap role: hardening & completeness Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden the keymap Ansible role: fix silent failures, add font/GPM support for all init systems, support custom .map files, switch to lineinfile, improve molecule tests.

**Architecture:** All changes are within `ansible/roles/keymap/`. Tasks run on the remote VM via the `/ansible` skill. Molecule is the test framework — write verify assertions first, then implement, then converge+verify. Each task ends with a commit.

**Tech Stack:** Ansible 2.15+, Molecule, systemd / OpenRC / runit

**Design doc:** `docs/plans/2026-02-20-keymap-role-hardening-design.md`

---

## Task 1: Computed keymap value fact

The KEYMAP= value is either a keymap name (`us`) or a full path to a custom `.map`
file. Compute once as `_keymap_value` so all init backends and handlers share it.

**Files:**
- Modify: `ansible/roles/keymap/defaults/main.yml`
- Create: `ansible/roles/keymap/tasks/map.yml`
- Modify: `ansible/roles/keymap/tasks/main.yml`

**Step 1: Add variable to defaults**

Add to `defaults/main.yml` after `keymap_console`:

```yaml
keymap_console_map_src: ""   # optional: local path to .map file in your repo
```

**Step 2: Create `tasks/map.yml`**

```yaml
---
# === Custom keymap file support ===

- name: Compute _keymap_value fact
  ansible.builtin.set_fact:
    _keymap_value: >-
      {{ '/usr/local/share/kbd/keymaps/' + (keymap_console_map_src | basename)
         if keymap_console_map_src | length > 0
         else keymap_console }}
  tags: ['keymap']

- name: Create custom keymap directory
  ansible.builtin.file:
    path: /usr/local/share/kbd/keymaps
    state: directory
    owner: root
    group: root
    mode: '0755'
  when: keymap_console_map_src | length > 0
  tags: ['keymap']

- name: Copy custom keymap file
  ansible.builtin.copy:
    src: "{{ keymap_console_map_src }}"
    dest: "/usr/local/share/kbd/keymaps/{{ keymap_console_map_src | basename }}"
    owner: root
    group: root
    mode: '0644'
  when: keymap_console_map_src | length > 0
  notify: apply keymap
  tags: ['keymap']
```

**Step 3: Wire into `tasks/main.yml`**

Insert `map.yml` include after the validate block, before the init block:

```yaml
# ---- Custom keymap file ----

- name: Prepare custom keymap file
  ansible.builtin.include_tasks: map.yml
  tags: ['keymap']
```

**Step 4: Run syntax check**

Use `/ansible` skill: `molecule syntax` in `ansible/roles/keymap/`

Expected: no errors.

**Step 5: Commit**

```bash
git add ansible/roles/keymap/defaults/main.yml \
        ansible/roles/keymap/tasks/map.yml \
        ansible/roles/keymap/tasks/main.yml
git commit -m "feat(keymap): add custom .map file support and _keymap_value fact"
```

---

## Task 2: Validate hardening

**Files:**
- Modify: `ansible/roles/keymap/tasks/validate/main.yml`

**Step 1: Add molecule verify assertion for invalid config**

Add a new play to `molecule/default/verify.yml` that tests validate fires correctly.
Skip this for now — validate errors abort the play, hard to test in verify.
Instead, manually verify after implementing.

**Step 2: Add assert to `validate/main.yml`**

Append after the existing `keymap_console` assert:

```yaml
- name: Assert font is set when font_map or font_unimap are used
  ansible.builtin.assert:
    that:
      - keymap_console_font | length > 0
    fail_msg: >-
      keymap_console_font_map/font_unimap require keymap_console_font to be set.
      Current keymap_console_font: '{{ keymap_console_font | default("") }}'
  when: >-
    (keymap_console_font_map | default('') | length > 0) or
    (keymap_console_font_unimap | default('') | length > 0)
  tags: ['keymap']
```

**Step 3: Run syntax check**

Use `/ansible` skill: `molecule syntax`

**Step 4: Commit**

```bash
git add ansible/roles/keymap/tasks/validate/main.yml
git commit -m "feat(keymap): validate font_map/font_unimap require font"
```

---

## Task 3: Font package installation

**Files:**
- Create: `ansible/roles/keymap/tasks/font.yml`
- Modify: `ansible/roles/keymap/defaults/main.yml`
- Modify: `ansible/roles/keymap/tasks/main.yml`

**Step 1: Add font variables to defaults**

`defaults/main.yml` — ensure these exist (add if missing):

```yaml
keymap_console_font_package: "terminus-font"
keymap_console_font: ""
keymap_console_font_map: ""
keymap_console_font_unimap: ""
```

**Step 2: Create `tasks/font.yml`**

```yaml
---
# === Console font package ===

- name: Install console font package
  ansible.builtin.package:
    name: "{{ keymap_console_font_package }}"
    state: present
  when: keymap_console_font | length > 0
  tags: ['keymap']
```

**Step 3: Wire into `tasks/main.yml`**

Insert after the map block, before the init block:

```yaml
# ---- Font package ----

- name: Install console font
  ansible.builtin.include_tasks: font.yml
  tags: ['keymap']
```

**Step 4: Add molecule verify check**

In `molecule/default/verify.yml`, in the systemd section, add:

```yaml
- name: Check terminus-font is installed (systemd)
  ansible.builtin.package_facts:
    manager: auto
  when: ansible_facts['service_mgr'] == 'systemd'

- name: Assert font package installed (systemd)
  ansible.builtin.assert:
    that:
      - "'terminus-font' in ansible_facts.packages"
    fail_msg: "terminus-font package not found"
  when: ansible_facts['service_mgr'] == 'systemd'
```

**Step 5: Run converge + verify**

Use `/ansible` skill: `molecule converge && molecule verify`

Expected: font package check passes.

**Step 6: Commit**

```bash
git add ansible/roles/keymap/tasks/font.yml \
        ansible/roles/keymap/defaults/main.yml \
        ansible/roles/keymap/tasks/main.yml \
        ansible/roles/keymap/molecule/default/verify.yml
git commit -m "feat(keymap): install font package before applying font"
```

---

## Task 4: Switch systemd init to lineinfile

Replace the `vconsole.conf.j2` template with individual `lineinfile` tasks.
This avoids overwriting lines managed by other roles.

**Files:**
- Modify: `ansible/roles/keymap/tasks/init/systemd.yml`
- Delete: `ansible/roles/keymap/templates/vconsole.conf.j2`

**Step 1: Rewrite `tasks/init/systemd.yml`**

```yaml
---
# === Console keymap: systemd ===
# /etc/vconsole.conf — managed line-by-line to avoid overwriting other entries

- name: Set KEYMAP in vconsole.conf (systemd)
  ansible.builtin.lineinfile:
    path: /etc/vconsole.conf
    regexp: '^KEYMAP='
    line: "KEYMAP={{ _keymap_value }}"
    create: true
    owner: root
    group: root
    mode: '0644'
  notify: apply keymap
  tags: ['keymap']

- name: Set FONT in vconsole.conf (systemd)
  ansible.builtin.lineinfile:
    path: /etc/vconsole.conf
    regexp: '^FONT='
    line: "FONT={{ keymap_console_font }}"
  when: keymap_console_font | length > 0
  notify: apply keymap
  tags: ['keymap']

- name: Set FONT_MAP in vconsole.conf (systemd)
  ansible.builtin.lineinfile:
    path: /etc/vconsole.conf
    regexp: '^FONT_MAP='
    line: "FONT_MAP={{ keymap_console_font_map }}"
  when: keymap_console_font_map | length > 0
  notify: apply keymap
  tags: ['keymap']

- name: Set FONT_UNIMAP in vconsole.conf (systemd)
  ansible.builtin.lineinfile:
    path: /etc/vconsole.conf
    regexp: '^FONT_UNIMAP='
    line: "FONT_UNIMAP={{ keymap_console_font_unimap }}"
  when: keymap_console_font_unimap | length > 0
  notify: apply keymap
  tags: ['keymap']
```

**Step 2: Delete the template**

```bash
git rm ansible/roles/keymap/templates/vconsole.conf.j2
```

**Step 3: Run converge + verify**

Use `/ansible` skill: `molecule converge && molecule verify`

Expected: KEYMAP and FONT lines present in `/etc/vconsole.conf`.

**Step 4: Commit**

```bash
git add ansible/roles/keymap/tasks/init/systemd.yml
git commit -m "refactor(keymap): replace vconsole.conf template with lineinfile"
```

---

## Task 5: Font support for OpenRC and runit

**Files:**
- Modify: `ansible/roles/keymap/tasks/init/openrc.yml`
- Modify: `ansible/roles/keymap/tasks/init/runit.yml`
- Modify: `ansible/roles/keymap/tasks/verify/openrc.yml`
- Modify: `ansible/roles/keymap/tasks/verify/runit.yml`

**Step 5a: OpenRC — update init and verify**

Add to `tasks/init/openrc.yml` after the keymap task:

```yaml
- name: Set console font (openrc)
  ansible.builtin.lineinfile:
    path: /etc/conf.d/consolefont
    regexp: '^CONSOLEFONT='
    line: "CONSOLEFONT={{ keymap_console_font }}"
    create: true
    owner: root
    group: root
    mode: '0644'
  when: keymap_console_font | length > 0
  notify: apply keymap
  tags: ['keymap']
```

Also update the KEYMAP line in openrc.yml to use `_keymap_value`:

```yaml
- name: Set console keymap (OpenRC)
  ansible.builtin.lineinfile:
    path: /etc/conf.d/keymaps
    regexp: '^#?\s*keymap='
    line: 'keymap="{{ _keymap_value }}"'
    create: true
    owner: root
    group: root
    mode: '0644'
  notify: apply keymap
  tags: ['keymap']
```

Add to `tasks/verify/openrc.yml`:

```yaml
- name: Slurp consolefont config (openrc)
  ansible.builtin.slurp:
    src: /etc/conf.d/consolefont
  register: _keymap_slurp_consolefont
  when: keymap_console_font | length > 0
  tags: ['keymap']

- name: Assert font is set (openrc)
  ansible.builtin.assert:
    that:
      - "'CONSOLEFONT=' + keymap_console_font in (_keymap_slurp_consolefont.content | b64decode)"
    fail_msg: >-
      Font '{{ keymap_console_font }}' not found in /etc/conf.d/consolefont.
    quiet: true
  when: keymap_console_font | length > 0
  tags: ['keymap']
```

**Step 5b: runit — update init and verify**

Also update the KEYMAP line in runit.yml to use `_keymap_value`:

```yaml
- name: Set console keymap (runit)
  ansible.builtin.lineinfile:
    path: /etc/rc.conf
    regexp: '^#?\s*KEYMAP='
    line: "KEYMAP={{ _keymap_value }}"
    create: true
    owner: root
    group: root
    mode: '0644'
  notify: apply keymap
  tags: ['keymap']
```

Add font to `tasks/init/runit.yml`:

```yaml
- name: Set console font (runit)
  ansible.builtin.lineinfile:
    path: /etc/rc.conf
    regexp: '^#?\s*FONT='
    line: "FONT={{ keymap_console_font }}"
  when: keymap_console_font | length > 0
  notify: apply keymap
  tags: ['keymap']
```

Add to `tasks/verify/runit.yml`:

```yaml
- name: Assert font is set (runit)
  ansible.builtin.assert:
    that:
      - "'FONT=' + keymap_console_font in (_keymap_slurp_runit.content | b64decode)"
    fail_msg: >-
      Font '{{ keymap_console_font }}' not found in /etc/rc.conf.
    quiet: true
  when: keymap_console_font | length > 0
  tags: ['keymap']
```

**Step 5c: Run syntax check**

Use `/ansible` skill: `molecule syntax`

**Step 5d: Commit**

```bash
git add ansible/roles/keymap/tasks/init/openrc.yml \
        ansible/roles/keymap/tasks/init/runit.yml \
        ansible/roles/keymap/tasks/verify/openrc.yml \
        ansible/roles/keymap/tasks/verify/runit.yml
git commit -m "feat(keymap): font support for openrc and runit"
```

---

## Task 6: Fix handlers

Remove `failed_when: false`. Switch from `systemd-vconsole-setup.service` restart
to `loadkeys`/`setfont` — wait, keep service restart for systemd (it applies to
all TTYs). For openrc/runit: `loadkeys` + `setfont`, without `failed_when: false`.

**Files:**
- Modify: `ansible/roles/keymap/handlers/main.yml`

**Step 1: Rewrite `handlers/main.yml`**

```yaml
---
# === Console keymap handlers ===

- name: Apply vconsole settings (systemd)
  ansible.builtin.systemd:
    name: systemd-vconsole-setup.service
    state: restarted
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] == 'systemd'

- name: Apply keymap (openrc/runit)
  ansible.builtin.command: "loadkeys {{ _keymap_value }}"
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] in ['openrc', 'runit']
  changed_when: false

- name: Apply font (openrc/runit)
  ansible.builtin.command: "setfont {{ keymap_console_font }}"
  listen: "apply keymap"
  when:
    - ansible_facts['service_mgr'] in ['openrc', 'runit']
    - keymap_console_font | length > 0
  changed_when: false
```

**Step 2: Run converge to confirm handlers fire without errors**

Use `/ansible` skill: `molecule converge`

Expected: no failed tasks.

**Step 3: Commit**

```bash
git add ansible/roles/keymap/handlers/main.yml
git commit -m "fix(keymap): remove failed_when: false from handlers, use service restart for systemd"
```

---

## Task 7: GPM support (mouse in TTY)

**Files:**
- Create: `ansible/roles/keymap/tasks/gpm.yml`
- Modify: `ansible/roles/keymap/defaults/main.yml`
- Modify: `ansible/roles/keymap/tasks/main.yml`

**Step 1: Add variable to defaults**

```yaml
keymap_gpm_enabled: true
```

**Step 2: Create `tasks/gpm.yml`**

```yaml
---
# === GPM — General Purpose Mouse daemon (mouse in TTY) ===

- name: Install GPM
  ansible.builtin.package:
    name: gpm
    state: present
  when: keymap_gpm_enabled
  tags: ['keymap']

- name: Enable and start GPM service
  ansible.builtin.service:
    name: gpm
    enabled: true
    state: started
  when: keymap_gpm_enabled
  tags: ['keymap']
```

**Step 3: Wire into `tasks/main.yml`**

Insert after the init block, before the verify block:

```yaml
# ---- GPM ----

- name: Configure GPM (mouse in TTY)
  ansible.builtin.include_tasks: gpm.yml
  tags: ['keymap']
```

**Step 4: Add molecule verify check**

In `molecule/default/verify.yml`:

```yaml
- name: Assert GPM service is running
  ansible.builtin.service_facts:

- name: Assert GPM is active
  ansible.builtin.assert:
    that:
      - "'gpm.service' in ansible_facts.services"
      - "ansible_facts.services['gpm.service'].state == 'running'"
    fail_msg: "GPM service is not running"
  when: ansible_facts['service_mgr'] == 'systemd'
```

**Step 5: Run converge + verify**

Use `/ansible` skill: `molecule converge && molecule verify`

**Step 6: Commit**

```bash
git add ansible/roles/keymap/tasks/gpm.yml \
        ansible/roles/keymap/defaults/main.yml \
        ansible/roles/keymap/tasks/main.yml \
        ansible/roles/keymap/molecule/default/verify.yml
git commit -m "feat(keymap): add GPM daemon for mouse support in TTY"
```

---

## Task 8: Verify improvements (font + exact value checks)

**Files:**
- Modify: `ansible/roles/keymap/tasks/verify/systemd.yml`

**Step 1: Add FONT check for systemd verify**

Append to `tasks/verify/systemd.yml`:

```yaml
- name: Slurp vconsole.conf (systemd)
  ansible.builtin.slurp:
    src: /etc/vconsole.conf
  register: _keymap_vconsole_content
  when: keymap_console_font | length > 0
  tags: ['keymap']

- name: Assert FONT is set in vconsole.conf (systemd)
  ansible.builtin.assert:
    that:
      - "'FONT=' + keymap_console_font in (_keymap_vconsole_content.content | b64decode)"
    fail_msg: >-
      FONT={{ keymap_console_font }} not found in /etc/vconsole.conf.
      Content: {{ _keymap_vconsole_content.content | b64decode }}
    quiet: true
  when: keymap_console_font | length > 0
  tags: ['keymap']
```

**Step 2: Run verify**

Use `/ansible` skill: `molecule verify`

Expected: all assertions pass.

**Step 3: Commit**

```bash
git add ansible/roles/keymap/tasks/verify/systemd.yml
git commit -m "feat(keymap): verify FONT is set in vconsole.conf for systemd"
```

---

## Task 9: Molecule — parametrize and add idempotence

**Files:**
- Modify: `ansible/roles/keymap/molecule/default/converge.yml`
- Modify: `ansible/roles/keymap/molecule/default/verify.yml`
- Modify: `ansible/roles/keymap/molecule/default/molecule.yml`

**Step 1: Update `converge.yml`**

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  roles:
    - role: keymap
      vars:
        keymap_console: "us"
        keymap_console_font_package: "terminus-font"
        keymap_console_font: "ter-v16n"
        keymap_gpm_enabled: true
```

**Step 2: Update `verify.yml` — remove hardcoded `_test_keymap`**

Replace every occurrence of `_test_keymap` with the actual role variable
`keymap_console`. Since verify runs as a separate play, pass vars explicitly:

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  vars:
    keymap_console: "us"
    keymap_console_font: "ter-v16n"
    keymap_gpm_enabled: true

  tasks:
    # ... existing tasks using keymap_console instead of _test_keymap ...
```

**Step 3: Add `idempotence` to `molecule.yml`**

```yaml
scenario:
  test_sequence:
    - syntax
    - converge
    - idempotence
    - verify
```

**Step 4: Run full molecule test sequence**

Use `/ansible` skill: `molecule test`

Expected: all stages pass including idempotence (no changed tasks on second run).

**Step 5: Commit**

```bash
git add ansible/roles/keymap/molecule/default/converge.yml \
        ansible/roles/keymap/molecule/default/verify.yml \
        ansible/roles/keymap/molecule/default/molecule.yml
git commit -m "test(keymap): parametrize molecule vars, add idempotence step"
```

---

## Task 10: Remove Alpine from meta

**Files:**
- Modify: `ansible/roles/keymap/meta/main.yml`

**Step 1: Remove Alpine platform**

Delete from `platforms` list:
```yaml
    - name: Alpine
      versions: [all]
```

**Step 2: Add Gentoo and Void**

```yaml
    - name: Gentoo
      versions: [all]
```

Note: Void Linux is not an official Galaxy platform name — leave a comment instead.

**Step 3: Commit**

```bash
git add ansible/roles/keymap/meta/main.yml
git commit -m "chore(keymap): remove Alpine from supported platforms, add Gentoo"
```

---

## Task 11: Final full test run

**Step 1: Run complete molecule test**

Use `/ansible` skill: `molecule test`

Expected: syntax → converge → idempotence → verify all green.

**Step 2: Run ansible-lint**

Use `/ansible` skill: `ansible-lint ansible/roles/keymap/`

Expected: no violations.

**Step 3: If any failures — fix and re-run**

Use `/ansible-debug` skill for diagnosis.
