# Design: vconsole -- Vagrant KVM scenario

**Date:** 2026-02-25
**Status:** Draft

## 1. Current State

### Role purpose

The `vconsole` role configures console (TTY) keymap, optional console font, and optional GPM
(mouse in TTY). It dispatches by init system:

| Init system | Keymap file | Font file |
|-------------|-------------|-----------|
| systemd     | `/etc/vconsole.conf` (KEYMAP=, FONT=, FONT_MAP=, FONT_UNIMAP=) | same file |
| openrc      | `/etc/conf.d/keymaps` | `/etc/conf.d/consolefont` |
| runit       | `/etc/rc.conf` (KEYMAP=, FONT=) | same file |

The handler `apply vconsole` restarts `systemd-vconsole-setup.service` on systemd, or runs
`loadkeys`/`setfont` directly on openrc/runit.

GPM is installed and enabled as a systemd service when `vconsole_gpm_enabled: true`.

### Existing molecule scenarios

```
molecule/
  default/          -- localhost driver, uses vault, runs shared/ playbooks
  docker/           -- Arch systemd container, prepare installs kbd, shared/ playbooks
  shared/
    converge.yml    -- applies role with us keymap, ter-v16n font, gpm disabled
    verify.yml      -- checks by init system: vconsole.conf content, font package, GPM state
```

### Shared converge.yml variables

```yaml
vconsole_console: "us"
vconsole_console_font: "ter-v16n"
vconsole_console_font_package: "terminus-font"
vconsole_gpm_enabled: false
```

### Shared verify.yml checks (systemd path)

1. `/etc/vconsole.conf` exists, root:root 0644
2. `KEYMAP=us` present in file
3. `FONT=ter-v16n` present in file
4. `terminus-font` package installed (via `package_facts`)
5. GPM service not running (gpm disabled in converge)

Verify also has openrc and runit branches, guarded by `ansible_facts['service_mgr']`.

## 2. Cross-Platform Analysis

### Arch Linux (primary target)

- `systemd-vconsole-setup.service` reads `/etc/vconsole.conf` natively
- `localectl status` shows `VC Keymap` -- works out of the box
- Font package: `terminus-font` (pacman) provides `ter-v16n`
- `kbd` package provides `loadkeys`, `setfont`, keymap files
- GPM package: `gpm` in official repos

### Ubuntu 24.04 (Noble)

- Uses systemd, so the role takes the systemd path
- `/etc/vconsole.conf` is recognized by systemd but Ubuntu traditionally uses
  `console-setup` + `/etc/default/keyboard` instead
- `localectl status` works on Ubuntu -- it reads vconsole.conf if present, or falls back to
  console-setup. After writing vconsole.conf and restarting `systemd-vconsole-setup.service`,
  `localectl status` should reflect the keymap
- `systemd-vconsole-setup.service` exists on Ubuntu (provided by systemd itself) but may not
  be enabled by default. The handler calls `state: restarted` which will work as long as the
  unit file exists (systemd allows restarting a stopped/disabled oneshot service)
- Font package: `terminus-font` does NOT exist on Ubuntu. The equivalent is
  `fonts-terminus` (or `xfonts-terminus` for X11). However, console fonts are in
  `console-setup` / `kbd` packages. The Terminus console font name `ter-v16n` requires the
  `kbd` package and the PSF font files from `fonts-terminus`

**Key issue:** The shared converge.yml hardcodes `vconsole_console_font_package: "terminus-font"`
which is an Arch-only package name. On Ubuntu, `ansible.builtin.package` will fail trying to
install `terminus-font`.

### Resolution options for font package

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| A | Override font vars per-platform in vagrant converge | Breaks shared converge reuse |
| B | Set `vconsole_console_font: ""` for Ubuntu in prepare/group_vars | Font check skipped on Ubuntu; still tests keymap |
| C | Use platform-aware converge that sets font_package conditionally | New converge or group_vars needed |
| D | Skip font entirely in vagrant scenario (test keymap + GPM only) | Simplest; font already tested in docker/Arch |

**Recommendation: Option B** -- use host_vars in molecule.yml to override font variables to
empty strings on ubuntu-noble. This way:
- Arch VM tests full flow (keymap + font + font_package)
- Ubuntu VM tests keymap (the cross-platform valuable check) and skips font
  (which is Arch-specific in the current converge anyway)
- Shared converge.yml stays unchanged
- verify.yml already guards font checks with `verify_font | default('') | length > 0`

Actually, re-examining this: the shared converge.yml sets role variables directly in `vars:`,
not via inventory. We cannot override `vars:` via host_vars (vars have higher precedence than
inventory). The correct approach is **option D** but implemented differently: create a
vagrant-specific converge that conditionally sets font variables, or better yet, use
`group_vars`/`host_vars` in molecule inventory with `default()` filters in a vagrant converge.

**Final recommendation:** Create a vagrant-specific converge.yml that uses
`ansible_facts['os_family']` to set the font package name, while reusing the role invocation
pattern from shared/converge.yml. This keeps vagrant self-contained without modifying shared/.

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
    converge: converge.yml
    verify: verify.yml

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

Notes:
- Uses `generic/arch` and `bento/ubuntu-24.04` matching the project standard from
  package_manager vagrant scenario.
- `skip-tags: report` avoids the `common` role dependency for reporting tasks.
- Vagrant-specific converge and verify (not shared/) because of cross-platform font
  package differences.
- No vault needed (role has no vault-encrypted variables).

### 3.2 molecule/vagrant/prepare.yml

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

    - name: Full system upgrade on Arch (ensures package compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Ensure kbd package is present (provides loadkeys/setfont)
      ansible.builtin.package:
        name: kbd
        state: present
```

This follows the exact pattern from `package_manager/molecule/vagrant/prepare.yml` with the
addition of the `kbd` package install from `vconsole/molecule/docker/prepare.yml`. The `kbd`
package exists on both Arch and Ubuntu and provides the console keymap infrastructure.

### 3.3 molecule/vagrant/converge.yml

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true

  vars:
    vconsole_console: "us"
    vconsole_gpm_enabled: false
    # Font config: Arch uses terminus-font, Ubuntu uses fonts-terminus
    # On Ubuntu, console font support via vconsole.conf is non-standard;
    # skip font testing there to focus on keymap (the cross-platform value)
    vconsole_console_font: >-
      {{ 'ter-v16n' if ansible_facts['os_family'] == 'Archlinux' else '' }}
    vconsole_console_font_package: >-
      {{ 'terminus-font' if ansible_facts['os_family'] == 'Archlinux' else '' }}

  roles:
    - role: vconsole
```

Key differences from shared/converge.yml:
- Font variables are conditional on `os_family` -- Arch gets full font testing, Ubuntu gets
  keymap-only testing.
- This avoids `apt` trying to install the Arch package name `terminus-font`.

### 3.4 molecule/vagrant/verify.yml

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true

  vars:
    verify_keymap: "us"
    verify_font: >-
      {{ 'ter-v16n' if ansible_facts['os_family'] == 'Archlinux' else '' }}
    verify_font_package: >-
      {{ 'terminus-font' if ansible_facts['os_family'] == 'Archlinux' else '' }}
    verify_gpm_enabled: false

  tasks:

    # ---- /etc/vconsole.conf (systemd) ----

    - name: Stat /etc/vconsole.conf
      ansible.builtin.stat:
        path: /etc/vconsole.conf
      register: vconsole_verify_stat
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert /etc/vconsole.conf exists with correct permissions
      ansible.builtin.assert:
        that:
          - vconsole_verify_stat.stat.exists
          - vconsole_verify_stat.stat.isreg
          - vconsole_verify_stat.stat.pw_name == 'root'
          - vconsole_verify_stat.stat.gr_name == 'root'
          - vconsole_verify_stat.stat.mode == '0644'
        fail_msg: "/etc/vconsole.conf missing or wrong permissions (expected root:root 0644)"
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Slurp /etc/vconsole.conf
      ansible.builtin.slurp:
        src: /etc/vconsole.conf
      register: vconsole_verify_slurp
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Set vconsole.conf content fact
      ansible.builtin.set_fact:
        vconsole_verify_content: "{{ vconsole_verify_slurp.content | b64decode }}"
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert KEYMAP is set correctly
      ansible.builtin.assert:
        that: "'KEYMAP=' + verify_keymap in vconsole_verify_content"
        fail_msg: "KEYMAP={{ verify_keymap }} not found in /etc/vconsole.conf"
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert FONT is set correctly
      ansible.builtin.assert:
        that: "'FONT=' + verify_font in vconsole_verify_content"
        fail_msg: "FONT={{ verify_font }} not found in /etc/vconsole.conf"
      when:
        - ansible_facts['service_mgr'] == 'systemd'
        - verify_font | default('') | length > 0

    # ---- localectl verification (vagrant VMs have real systemd) ----

    - name: Check localectl status
      ansible.builtin.command: localectl status
      register: vconsole_verify_localectl
      changed_when: false
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert VC Keymap shown by localectl
      ansible.builtin.assert:
        that:
          - vconsole_verify_localectl.stdout is search('VC Keymap:\s+' + verify_keymap)
        fail_msg: >-
          localectl does not show VC Keymap={{ verify_keymap }}.
          Output: {{ vconsole_verify_localectl.stdout }}
      when: ansible_facts['service_mgr'] == 'systemd'

    # ---- Font package ----

    - name: Gather package facts
      ansible.builtin.package_facts:
        manager: auto
      when: verify_font | default('') | length > 0

    - name: Assert console font package is installed
      ansible.builtin.assert:
        that: verify_font_package in ansible_facts.packages
        fail_msg: "{{ verify_font_package }} package not installed"
      when: verify_font | default('') | length > 0

    # ---- GPM (systemd) ----

    - name: Gather service facts
      ansible.builtin.service_facts:
      when: ansible_facts['service_mgr'] == 'systemd'

    - name: Assert GPM service is running (when enabled)
      ansible.builtin.assert:
        that:
          - "'gpm.service' in ansible_facts.services"
          - "ansible_facts.services['gpm.service'].state == 'running'"
        fail_msg: "GPM service is not running -- expected enabled"
      when:
        - ansible_facts['service_mgr'] == 'systemd'
        - verify_gpm_enabled | bool

    - name: Assert GPM service is absent or stopped (when disabled)
      ansible.builtin.assert:
        that: >-
          ('gpm.service' not in ansible_facts.services) or
          (ansible_facts.services['gpm.service'].state != 'running')
        fail_msg: "GPM service is running but verify_gpm_enabled=false"
      when:
        - ansible_facts['service_mgr'] == 'systemd'
        - not (verify_gpm_enabled | bool)

    # ---- Summary ----

    - name: Show verify result
      ansible.builtin.debug:
        msg: >-
          vconsole verify passed:
          keymap={{ verify_keymap }},
          font={{ verify_font | default('none') }},
          gpm={{ verify_gpm_enabled }},
          init={{ ansible_facts['service_mgr'] }},
          os={{ ansible_facts['os_family'] }}
```

Key differences from shared/verify.yml:
- `verify_font` and `verify_font_package` are conditional on `os_family` (matching converge)
- Adds `localectl status` verification -- this is meaningful in real VMs where systemd runs
  as PID 1, unlike Docker containers where localectl may not reflect vconsole.conf changes.
  The role's own `tasks/verify/systemd.yml` already does this check, but having it in molecule
  verify provides an independent post-converge assertion.
- Removes openrc/runit branches (not applicable in vagrant Arch/Ubuntu VMs)

### 3.5 Why not reuse shared/ directly?

The shared converge.yml hardcodes `vconsole_console_font_package: "terminus-font"` in `vars:`.
Ansible variable precedence means `vars:` in a play cannot be overridden by inventory
host_vars/group_vars. To test on Ubuntu without the Arch-specific font package, we need either:

1. A modified converge with conditional vars (chosen approach)
2. Modifying shared/converge.yml to be platform-aware (breaks simplicity for docker scenario)
3. Skipping font testing entirely on Ubuntu via skip-tags (no font-specific tag exists)

Option 1 keeps shared/ stable for docker and default scenarios while giving vagrant the
cross-platform flexibility it needs.

## 4. Shared verify.yml -- No Modifications Needed

The shared verify.yml already contains platform guards (`when: ansible_facts['service_mgr'] == 'systemd'`)
for all systemd-specific checks, and font checks are guarded by
`verify_font | default('') | length > 0`. No changes are required.

The vagrant scenario uses its own verify.yml (section 3.4) rather than shared/ to add the
`localectl` verification and to match the conditional font variables from the vagrant converge.

## 5. Implementation Order

1. **Create `molecule/vagrant/molecule.yml`** -- driver, platforms, provisioner config
   (section 3.1)

2. **Create `molecule/vagrant/prepare.yml`** -- Python bootstrap, keyring refresh, kbd
   install (section 3.2)

3. **Create `molecule/vagrant/converge.yml`** -- cross-platform font variable logic
   (section 3.3)

4. **Create `molecule/vagrant/verify.yml`** -- full verification with localectl check
   (section 3.4)

5. **Local smoke test** -- run syntax check:
   ```bash
   cd ansible/roles/vconsole
   molecule syntax -s vagrant
   ```

6. **Full test on KVM host** (or CI):
   ```bash
   molecule test -s vagrant
   ```

7. **Verify idempotence** -- the `lineinfile` tasks should be idempotent. The `localectl`
   and `slurp` tasks are read-only. No idempotence issues expected.

## 6. Risks and Notes

### 6.1 vconsole.conf on Ubuntu is non-standard

Ubuntu uses `console-setup` as its primary console configuration mechanism. Writing
`/etc/vconsole.conf` is valid (systemd reads it) but is not the Ubuntu-native way. In
practice:
- `systemd-vconsole-setup.service` exists and will apply vconsole.conf on boot
- `localectl set-keymap` writes to vconsole.conf on Ubuntu too
- The role's approach works, but Ubuntu users might also have `/etc/default/keyboard`
  which could conflict

For molecule testing purposes this is fine -- we are testing that the role produces the
correct file contents, not that the Ubuntu console actually renders with the new keymap.

### 6.2 Headless VMs have no real console

Vagrant VMs are accessed via SSH. There is no physical TTY to verify that the keymap or font
is actually applied visually. Our tests verify:
- File contents (vconsole.conf has correct KEYMAP= and FONT= lines)
- `localectl status` output (systemd's view of the configured keymap)
- Package installation (font package present)
- Service state (GPM stopped/absent)

We do NOT test:
- Actual keypress translation on a TTY
- Font rendering on a physical/virtual console
- `systemd-vconsole-setup.service` handler effect (requires active TTY)

This is acceptable. The handler restart may produce a benign error in the VM if no console
device is available, but the role uses `notify:` so the handler only fires if a change was
made, and handler failures on services that cannot fully apply in headless environments are
expected.

### 6.3 GPM disabled in test

GPM is disabled in the test (`vconsole_gpm_enabled: false`) because GPM requires a mouse
device (`/dev/input/mice`) which is typically absent in headless VMs. Enabling it would cause
the `gpm` service to fail to start. The verify checks for GPM-absent-or-stopped when
`verify_gpm_enabled: false`, which matches this configuration.

If GPM testing is needed in the future, a second converge scenario with GPM enabled could be
added, but only on platforms where a virtual mouse device is available.

### 6.4 generic/arch box stale keyring

The `generic/arch` Vagrant box ships with an outdated pacman keyring. The prepare.yml
includes the keyring refresh workaround (temporarily set `SigLevel = Never`, update
`archlinux-keyring`, restore signature verification). This is the same pattern used in
`package_manager/molecule/vagrant/prepare.yml` and is a known requirement for all Arch
Vagrant testing.

### 6.5 Handler restart in VM

The `apply vconsole` handler calls `systemd: name=systemd-vconsole-setup.service state=restarted`.
On Ubuntu, this unit may not be enabled or may not exist as a regular service (it is a
oneshot unit triggered by udev). The restart call should succeed (systemd allows restarting
oneshot units) but will be a no-op without a console device.

On Arch, `systemd-vconsole-setup.service` is a standard part of the base system and the
restart should succeed cleanly.

### 6.6 No shared/ modifications

This plan adds 4 new files and modifies 0 existing files:

```
ansible/roles/vconsole/molecule/vagrant/molecule.yml    (new)
ansible/roles/vconsole/molecule/vagrant/prepare.yml     (new)
ansible/roles/vconsole/molecule/vagrant/converge.yml    (new)
ansible/roles/vconsole/molecule/vagrant/verify.yml      (new)
```

Shared/ playbooks and the role itself remain untouched.

### 6.7 CI workflow

This plan covers the molecule scenario files only. A corresponding GitHub Actions workflow
(`.github/workflows/molecule-vagrant.yml`) already exists or will be extended to include
`vconsole` in the role matrix. That workflow configuration is out of scope for this document.
