# Reflector Role — SOLID Refactoring Design

**Date:** 2026-02-22
**Status:** Approved
**Driver:** Comprehensive — structure + reliability + features

---

## Context

Analysis of the current `ansible/roles/reflector` role vs. public repositories (Arch Wiki, GitHub) identified:

- Monolithic `tasks/main.yml` (113 lines) with mixed responsibilities
- Gaps: no rollback on reflector failure, no mirrorlist content validation, infinite backup accumulation
- Missing: pacman hook for `pacman-mirrorlist` upgrade, `RandomizedDelaySec` on timer
- `ignore_errors: true` masking real errors on slurp

The role is already above-average vs. public repos (retries, proxy support, backup, change tracking), but structural and reliability improvements are needed.

---

## Approach

**Approach B — Full SOLID refactoring** (chosen over minimal structural or feature-flag approaches).

Split `tasks/main.yml` into `include_tasks`-based zones, add pacman hook, backup rotation, mirrorlist validation, and rollback.

---

## File Structure

### Before

```
tasks/
  main.yml              # 113 lines — everything in one place
```

### After

```
tasks/
  main.yml              # ~15 lines: assert + 4× include_tasks
  install.yml           # SRP: package installation only
  configure.yml         # SRP: template + timer drop-in + pacman hook
  service.yml           # SRP: daemon_reload + enable + start timer
  update.yml            # SRP: backup → run → validate → rollback → cleanup → diff
files/
  reflector-mirrorlist.hook   # new pacman hook file
```

### SRP Contract

| File | Responsible for | Change trigger |
|------|----------------|----------------|
| `install.yml` | Package presence | Package version changes |
| `configure.yml` | Config + schedule + hook | Parameter changes |
| `service.yml` | Unit state | Config file changes |
| `update.yml` | Mirrorlist freshness | Provisioning runs |

### main.yml structure

```yaml
---
- name: Ensure host is Arch Linux
  ansible.builtin.assert:
    that:
      - ansible_facts['os_family'] == 'Archlinux'
    fail_msg: "This role supports Arch Linux only"

- name: Install reflector
  ansible.builtin.import_tasks: install.yml
  tags: [install]

- name: Configure reflector
  ansible.builtin.import_tasks: configure.yml
  tags: [configure]

- name: Enable reflector timer
  ansible.builtin.import_tasks: service.yml
  tags: [service]

- name: Update mirrorlist
  ansible.builtin.import_tasks: update.yml
  tags: [update]
```

---

## New Variables (defaults/main.yml)

Three new variables added; all existing variables unchanged:

```yaml
# Backup rotation: how many backups to keep (0 = keep all)
reflector_backup_keep: 3

# Timer: randomize startup to prevent thundering-herd on multi-machine deploys
reflector_timer_randomized_delay: "1h"

# Pacman hook: auto-update mirrorlist when pacman-mirrorlist package is upgraded
reflector_pacman_hook: true
```

Total: 3 new + 13 existing = 16 variables.

---

## configure.yml

Two additions relative to current behavior:

### 1. RandomizedDelaySec in timer drop-in

```yaml
- name: Set reflector timer schedule drop-in
  ansible.builtin.copy:
    dest: /etc/systemd/system/reflector.timer.d/override.conf
    content: |
      [Timer]
      OnCalendar={{ reflector_timer_schedule }}
      RandomizedDelaySec={{ reflector_timer_randomized_delay }}
```

### 2. Pacman hook (conditional)

File: `files/reflector-mirrorlist.hook`

```ini
[Trigger]
Operation = Upgrade
Type = Package
Target = pacman-mirrorlist

[Action]
Description = Updating mirrorlist via reflector after pacman-mirrorlist upgrade
When = PostTransaction
Depends = reflector
Exec = /usr/bin/reflector --config /etc/xdg/reflector/reflector.conf
```

The hook uses `--config` to read the Ansible-managed config file — preserving single source of truth.

Task in configure.yml:

```yaml
- name: Deploy pacman hook for mirrorlist auto-update
  ansible.builtin.copy:
    src: reflector-mirrorlist.hook
    dest: /etc/pacman.d/hooks/reflector-mirrorlist.hook
    owner: root
    group: root
    mode: '0644'
  when: reflector_pacman_hook | bool
```

---

## update.yml — Reliability Flow

```
[1] stat old mirrorlist (replaces ignore_errors slurp)
[2] slurp old mirrorlist content (when: stat.exists)
[3] backup to timestamped file (when: backup enabled + stat.exists)
[4] block:
    [4a] run reflector (retries)
    [4b] slurp new mirrorlist
    [4c] assert: Server count >= 1
    [4d] cleanup old backups (keep N newest)
    [4e] diff + report (changed_when: content differs)
    rescue:
    [4r1] restore backup → copy back (when backup exists)
    [4r2] fail with descriptive message
[5] update pacman cache
```

### Key improvements vs. current code

| Was | Will be |
|-----|---------|
| `ignore_errors: true` on slurp | `stat` + `when: _stat.stat.exists` |
| No result validation | `assert: Server count >= 1` after reflector run |
| No rollback | `rescue:` copies backup back + `fail` |
| Infinite backup accumulation | `find ... *.bak.* \| sort \| head -n -N \| xargs rm` |
| `changed_when: false` on run | unchanged; change tracked via diff in step 4e |

### Rollback logic

```yaml
rescue:
  - name: Restore mirrorlist from latest backup
    ansible.builtin.copy:
      remote_src: yes
      src: "{{ _reflector_backups.files | sort_by('mtime') | last }}"
      dest: "{{ reflector_mirrorlist_path }}"
    when: _reflector_backups.matched > 0

  - name: Fail with descriptive message
    ansible.builtin.fail:
      msg: >
        reflector failed or produced an empty mirrorlist.
        {% if _reflector_backups.matched > 0 %}Restored from backup.{% else %}No backup available.{% endif %}
```

---

## Molecule verify — Additions

Existing checks preserved. New checks:

| Check | What it verifies |
|-------|-----------------|
| `stat` hook file | `/etc/pacman.d/hooks/reflector-mirrorlist.hook` exists |
| Hook content | contains `pacman-mirrorlist` and `--config` |
| Timer drop-in content | contains `RandomizedDelaySec` |
| Backup count | `mirrorlist.bak.*` count ≤ `reflector_backup_keep` |
| Server count | `grep -c '^Server = '` ≥ 3 (stricter than current ≥ 1) |

---

## Security Notes

- `reflector_proxy: ""` stays in defaults (empty string); usage documentation added to role README
- `--protocol https` enforced — no HTTP fallback
- `--age 12` filters stale mirrors
- Hook uses `--config` not inline args — no duplication of sensitive params
- Backup files owned root:root 0644 — unchanged

---

## Out of Scope

- Multi-distro support (Arch Linux only, by design)
- Feature flags per-feature (rejected: YAGNI for single-machine use)
- Network-online.target dependency for provisioning run (reflector.timer already has it; inline provisioning run is best-effort with retries)
