# power_management Molecule Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix molecule tests for the `power_management` role so all 3 CI environments pass (Docker, Vagrant Arch, Vagrant Ubuntu), then merge and delete the worktree.

**Architecture:** Two targeted bug fixes — add `failed_when: false` to two handlers that crash in Docker containers (udevadm/logind reload), and rewrite the vagrant prepare.yml with the vm-role's battle-tested Arch bootstrap pattern. No role logic changes.

**Tech Stack:** Ansible, Molecule, Docker (privileged systemd), Vagrant (libvirt/KVM), GitHub Actions

**Design doc:** `docs/plans/2026-03-01-power-management-molecule-fix-design.md`

---

### Task 1: Create worktree

**Files:**
- No files modified

**Step 1: Create the worktree**

```bash
git worktree add .worktrees/power-management-molecule-fix -b fix/power-management-molecule-tests
```

Expected: New directory `.worktrees/power-management-molecule-fix/` created on branch `fix/power-management-molecule-tests`.

**Step 2: Verify worktree**

```bash
git worktree list
```

Expected: Three entries — main, and the new worktree.

---

### Task 2: Fix `Reload udev rules` handler

**Files:**
- Modify: `ansible/roles/power_management/handlers/main.yml`

**Context:** `udevadm control --reload-rules` fails in Docker containers because `systemd-udevd` is not running. This causes converge to crash before verify runs. `failed_when: false` is the correct fix — the udev rule file is deployed correctly, the reload is best-effort.

**Step 1: Open the handlers file and read the current state**

File: `ansible/roles/power_management/handlers/main.yml`

Current content (lines 20-22):
```yaml
- name: Reload udev rules
  listen: "reload udev rules"
  ansible.builtin.command: udevadm control --reload-rules
  changed_when: false
```

**Step 2: Add `failed_when: false` to the `Reload udev rules` handler**

Add `failed_when: false` after `changed_when: false`:

```yaml
- name: Reload udev rules
  listen: "reload udev rules"
  ansible.builtin.command: udevadm control --reload-rules
  changed_when: false
  failed_when: false
```

**Step 3: Add `failed_when: false` to the `Reload systemd-logind` handler**

Current (lines 11-17):
```yaml
- name: Reload systemd-logind
  listen: "reload systemd-logind"
  ansible.builtin.systemd:
    name: systemd-logind
    state: reloaded
  when: power_management_init | default('') == 'systemd'
```

After fix:
```yaml
- name: Reload systemd-logind
  listen: "reload systemd-logind"
  ansible.builtin.systemd:
    name: systemd-logind
    state: reloaded
  when: power_management_init | default('') == 'systemd'
  failed_when: false
```

**Step 4: Commit**

```bash
cd .worktrees/power-management-molecule-fix
git add ansible/roles/power_management/handlers/main.yml
git commit -m "fix(power_management): add failed_when: false to udev/logind handlers

udevd and logind may not be running in Docker containers — udevadm
and systemctl reload fail with hard errors. These are best-effort
reloads; the config files are deployed correctly regardless."
```

---

### Task 3: Rewrite vagrant prepare.yml

**Files:**
- Modify: `ansible/roles/power_management/molecule/vagrant/prepare.yml`

**Context:** The vm role's `molecule/vagrant/prepare.yml` is the established pattern for Arch bootstrap in KVM VMs (confirmed working in CI). Power management's vagrant prepare has no Arch preparation at all — pacman cache is never updated, so `pacman -S cpupower` will fail with stale DB/GPG errors.

Key pattern elements (from vm role):
1. `gather_facts: false` — required because Arch box may lack Python initially
2. Raw Python install — safe no-op if already installed (arch-base has Python)
3. `ansible.builtin.setup` — gather facts after Python confirmed
4. Keyring refresh via `SigLevel=Never` trick — required for `archlinux-keyring` on stale boxes
5. `pacman -Syu` full upgrade — ensures current package DB
6. DNS fix — systemd replaces resolv.conf with IPv6 stub after upgrade; Go/native DNS resolvers break
7. Ubuntu apt cache update
8. cpufreq module loading (best-effort, kept from original)

**Step 1: Rewrite `molecule/vagrant/prepare.yml`**

Full content:

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false

  tasks:
    - name: Install Python on Arch (raw — arch-base ships Python, but explicit bootstrap is safe)
      ansible.builtin.raw: pacman -Sy --noconfirm python
      when: inventory_hostname == 'arch-vm'
      changed_when: true

    - name: Gather facts
      ansible.builtin.setup:

    - name: Refresh Arch keyring (SigLevel=Never trick)
      ansible.builtin.shell: |
        pacman -Sy --noconfirm --config <(sed 's/SigLevel.*/SigLevel = Never/' /etc/pacman.conf) archlinux-keyring
        pacman-key --populate archlinux
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade (Arch)
      community.general.pacman:
        upgrade: true
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Fix DNS after pacman -Syu (systemd stub replaced resolv.conf)
      ansible.builtin.copy:
        content: "nameserver 8.8.8.8\nnameserver 1.1.1.1\n"
        dest: /etc/resolv.conf
        mode: '0644'
        unsafe_writes: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'

    - name: Load acpi-cpufreq kernel module (VM may not expose cpufreq by default)
      ansible.builtin.command: modprobe acpi-cpufreq
      failed_when: false
      changed_when: false

    - name: Load cpufreq_schedutil kernel module
      ansible.builtin.command: modprobe cpufreq_schedutil
      failed_when: false
      changed_when: false
```

**Step 2: Commit**

```bash
git add ansible/roles/power_management/molecule/vagrant/prepare.yml
git commit -m "fix(power_management): add Arch bootstrap to vagrant prepare.yml

Adopt the vm-role's established pattern: gather_facts:false →
raw python → setup → keyring refresh → pacman -Syu → DNS fix.
Without this, pacman -S cpupower fails on stale package DB.
Keep cpufreq module loading (best-effort for KVM VMs)."
```

---

### Task 4: Push branch and open PR

**Step 1: Push the branch**

```bash
git push -u origin fix/power-management-molecule-tests
```

**Step 2: Open PR**

```bash
gh pr create \
  --title "fix(power_management): fix molecule tests for Docker + Vagrant" \
  --body "$(cat <<'EOF'
## Summary

- Add \`failed_when: false\` to \`Reload udev rules\` and \`Reload systemd-logind\` handlers — these crash in Docker containers where udevd/logind may not be running
- Rewrite \`molecule/vagrant/prepare.yml\` with the vm-role's established Arch bootstrap pattern (keyring refresh, \`pacman -Syu\`, DNS fix) — without it, \`pacman -S cpupower\` fails on stale package DB

## Test plan

- [ ] \`test / power_management\` (Docker, Arch-systemd + Ubuntu-systemd) — green
- [ ] \`test-vagrant / power_management / arch-vm\` — green
- [ ] \`test-vagrant / power_management / ubuntu-base\` — green

Design doc: \`docs/plans/2026-03-01-power-management-molecule-fix-design.md\`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: PR URL printed to stdout.

---

### Task 5: Monitor CI and fix failures

**Step 1: Watch the CI run**

```bash
gh pr checks <PR-NUMBER> --watch
```

Wait for all 3 jobs to complete:
- `test / power_management (Arch+Ubuntu/systemd)` — Docker
- `power_management — arch-vm` — Vagrant
- `power_management — ubuntu-base` — Vagrant

**Step 2: If any job fails — investigate**

```bash
gh run view <RUN-ID> --log-failed
```

Look for the first failing task in the Ansible output. Common failure modes and fixes:

| Symptom | Root cause | Fix |
|---------|-----------|-----|
| `udevadm: No such file or directory` | udevadm not in PATH in container | Add `failed_when: false` was already added; check if handler runs |
| `systemctl: Failed to connect to bus` | D-Bus not available | Handler already has `failed_when: false` |
| `error: GPGME error: No data` | Stale keyring on Arch VM | Keyring refresh in prepare.yml should handle this |
| `pacman: target not found: cpupower` | Package name changed | Check `pacman -Ss cpupower` on Arch |
| `linux-tools-<kernel>: Unable to locate package` | Kernel-versioned package not in apt | Expected — fallback to `linux-tools-common` handles this |
| `power-audit.timer: not enabled` | systemd timer enable failed in container | Check systemd is PID 1 in container; investigate with `--log-failed` |

**Step 3: If Docker fails — add additional debug by reading the full log**

```bash
gh run view <RUN-ID> --log | grep -A 20 "FAILED\|fatal:"
```

**Step 4: Apply fixes, commit, push**

Each fix gets its own commit on the same branch. The PR auto-updates.

---

### Task 6: Merge PR and clean up worktree

**Step 1: Wait for all CI checks to pass**

```bash
gh pr checks <PR-NUMBER>
```

All must show `pass`. Do not merge if any are failing.

**Step 2: Merge the PR**

```bash
gh pr merge <PR-NUMBER> --squash --delete-branch
```

Expected: PR merged, remote branch deleted.

**Step 3: Pull master in main worktree**

```bash
cd /Users/umudrakov/Documents/bootstrap
git pull origin master
```

**Step 4: Remove the worktree**

```bash
git worktree remove .worktrees/power-management-molecule-fix
```

Expected: Directory removed cleanly (no "has changes" warning since we committed everything).

**Step 5: Verify clean state**

```bash
git worktree list
git status
```

Expected: Only the main worktree listed. Clean status.

---

## Execution notes

- **AGENTS.md policy:** No git write operations from main session — use worktree for all commits
- **Remote VM not needed:** These are molecule test fixes (file changes only), no remote VM operations required
- **If CI passes on first try:** Tasks 5 is trivially done — proceed directly to Task 6
- **Commit without confirmation:** User has authorized direct commits (see MEMORY.md)
