# NTP Role Hardening — Design

**Date:** 2026-02-20
**Status:** Approved

## Problem Statement

The `ntp` role is functional but has several gaps compared to the project standard (as established by the recently hardened `keymap` role) and compared to reference implementations (Linuxfabrik/lfops chrony, dezeroku/arch_ansible ntp):

1. No input validation (`validate/` pattern from keymap not applied)
2. `ntp_enabled` variable declared in defaults but never enforced
3. No directory creation — `ntp_logdir` and `ntp_dumpdir` may not exist before chrony starts
4. No `ntsdumpdir` — chrony re-does full NTS handshake on every restart
5. Verify tasks are inline in `main.yml` instead of a dedicated file
6. Molecule verify only checks config content, not actual NTS connectivity
7. No `ntp_pools` — only `server` directive supported, not `pool`
8. No `ntp_allow` — no way to configure chrony as NTP server for local clients
9. No `ntp:state` tag for service-only operations

## Approach: Pattern Alignment + Functional Fixes

Bring the role to the project standard (keymap pattern) while closing functional gaps. No over-engineering — each addition solves a real problem.

## Design

### 1. File Structure Changes

```
ansible/roles/common/tasks/
  check_internet.yml    — NEW: parameterized internet connectivity check (shared utility)

ansible/roles/ntp/
  tasks/
    main.yml            — refactored: ntp_enabled guard, include_tasks
    validate.yml        — NEW: assert on input variables
    verify.yml          — NEW: extracted from main.yml inline verify
  handlers/
    main.yml            — unchanged
  defaults/
    main.yml            — add: ntp_pools, ntp_allow, ntp_ntsdumpdir
  templates/
    chrony.conf.j2      — add: pool directives, allow directives, ntsdumpdir
  molecule/
    default/verify.yml  — add: internet pre-check + NTS check
  README.md             — update variable table
```

**Rationale for `common/tasks/check_internet.yml`:** The `common` role is already used by all roles via `include_role: tasks_from:`. Any role requiring external network access (NTP, future certificate/key roles) can reuse the same parameterized check. DRY without over-engineering — pattern already established.

### 2. Input Validation (`tasks/validate.yml`)

Assert before any action:

- `ntp_servers` is defined and list length >= 1 (or `ntp_pools` non-empty — at least one source)
- `ntp_minsources` is integer, >= 1, <= total sources count
- `ntp_makestep_threshold` is numeric > 0
- `ntp_makestep_limit` is integer >= -1 (chrony: -1 = unlimited steps)

### 3. `ntp_enabled` Guard

All tasks in `main.yml` wrapped in a single `block: when: ntp_enabled | bool`.
Clean pattern: one condition, no duplication.

### 4. New Variables (`defaults/main.yml`)

```yaml
# Pool-type NTP sources (pool directive — multiple servers behind one name)
ntp_pools: []
# Example: [{host: "pool.ntp.org", iburst: true, maxsources: 4}]

# ACL for NTP server mode (allow directive)
# Empty = client-only mode (default)
ntp_allow: []
# Example: ["192.168.1.0/24", "10.0.0.0/8"]

# NTS cookie cache directory (speeds up NTS re-handshake after restart)
ntp_ntsdumpdir: "/var/lib/chrony/nts-data"
```

### 5. Directory Creation

New task before chrony starts:

```yaml
- name: Ensure chrony directories exist
  ansible.builtin.file:
    path: "{{ item.path }}"
    state: directory
    owner: chrony
    group: chrony
    mode: "{{ item.mode }}"
  loop:
    - { path: "{{ ntp_logdir }}",    mode: "0755" }
    - { path: "{{ ntp_dumpdir }}",   mode: "0750" }
    - { path: "{{ ntp_ntsdumpdir }}", mode: "0700" }
```

### 6. Template Updates (`templates/chrony.conf.j2`)

Add after existing server lines:

```jinja2
{% for pool in ntp_pools %}
pool {{ pool.host }}{% if pool.iburst | default(true) %} iburst{% endif %}{% if pool.maxsources is defined %} maxsources {{ pool.maxsources }}{% endif %}

{% endfor %}
```

Add after logging section:

```jinja2
{% if ntp_ntsdumpdir %}
ntsdumpdir {{ ntp_ntsdumpdir }}
{% endif %}

{% for cidr in ntp_allow %}
allow {{ cidr }}
{% endfor %}
```

### 7. Verify Extraction (`tasks/verify.yml`)

Move inline verify tasks (chronyc tracking, chronyc sources, assert blocks) from `main.yml` to `tasks/verify.yml`. Include from `main.yml`:

```yaml
- name: Verify NTP
  ansible.builtin.include_tasks: verify.yml
  tags: ['ntp']
```

### 8. Tags

Add `ntp:state` tag to the enable/start service task. This allows:
```
ansible-playbook ... --tags ntp:state   # restart service only
ansible-playbook ... --tags ntp          # full role
```

### 9. verify.yml — Actual Sync Check

Add to `tasks/verify.yml` (and correspondingly to molecule verify): check that chrony has actually synchronized — not just that it's running. Use `chronyc -n sources` and assert at least one source has `^*` prefix (currently selected, synced source).

```yaml
- name: Check chrony has a synced source
  ansible.builtin.command: chronyc -n sources
  register: _ntp_synced
  changed_when: false

- name: Assert at least one source is synced (^* marker)
  ansible.builtin.assert:
    that:
      - _ntp_synced.stdout_lines | select('match', '^\\^\\*') | list | length > 0
    fail_msg: >-
      No synchronized NTP source (no '^*' marker in chronyc -n sources).
      Chrony is running but not synced — check internet connectivity and NTP server reachability.
    quiet: true
```

This check naturally requires internet connectivity. If there is no internet, chrony won't sync, and this assert will fail — which is the correct outcome (NTP is useless without external server access).

### 10. Internet Pre-condition via `common/tasks/check_internet.yml`

Create a shared utility in the `common` role (already used by all roles via `include_role: tasks_from:`):

**`ansible/roles/common/tasks/check_internet.yml`:**
```yaml
---
# Shared internet connectivity check
# Parameters: _check_internet_host, _check_internet_port, _check_internet_timeout (default: 5)

- name: Check internet connectivity ({{ _check_internet_host }}:{{ _check_internet_port }})
  ansible.builtin.wait_for:
    host: "{{ _check_internet_host }}"
    port: "{{ _check_internet_port }}"
    timeout: "{{ _check_internet_timeout | default(5) }}"
  register: _common_internet_check
  failed_when: false

- name: Fail if internet is unavailable
  ansible.builtin.fail:
    msg: >-
      Internet connectivity required but unavailable.
      Cannot reach {{ _check_internet_host }}:{{ _check_internet_port }}.
      Fix network access before running this role.
  when: _common_internet_check is failed
```

**Used in `tasks/verify.yml`** (in the ntp role):
```yaml
- name: Check internet connectivity (NTP requires external access)
  ansible.builtin.include_role:
    name: common
    tasks_from: check_internet.yml
  vars:
    _check_internet_host: "time.cloudflare.com"
    _check_internet_port: 123
  tags: ['ntp']
```

**Used identically in `molecule/default/verify.yml`** — same `include_role` call.

Then add NTS check (using `chronyc ntssources`, available in chrony 4.0+):
```yaml
- name: Verify NTS sources are active
  ansible.builtin.command: chronyc ntssources
  register: _verify_nts_sources
  changed_when: false

- name: Assert at least one NTS source is present
  ansible.builtin.assert:
    that:
      - _verify_nts_sources.stdout_lines | length > 1
    fail_msg: >-
      No NTS sources found (chronyc ntssources returned no entries).
      Check that NTS servers are reachable and NTS handshake succeeded.
```

Rationale: if the test environment has no internet, the common check fails fast with a clear message. `chronyc ntssources` is the correct chrony 4.0+ command for NTS source status (not `chronyc -N sources` which is not a valid flag).

## What Is NOT Changing

- Handler (`restart ntp`) — unchanged
- `vars/main.yml` OS mappings — unchanged
- `meta/main.yml` — unchanged (README update only for new vars)
- `molecule/default/converge.yml` and `molecule.yml` — unchanged
- Core chrony defaults (servers, minsources, makestep, rtcsync, logchange) — unchanged

## References

- [Linuxfabrik/lfops chrony role](https://github.com/Linuxfabrik/lfops/tree/main/roles/chrony) — `allow`, pool/server split, `chrony:state` tag pattern
- [dezeroku/arch_ansible ntp role](https://github.com/dezeroku/arch_ansible/tree/master/roles/ntp) — minimal baseline for comparison
- [chrony docs: ntsdumpdir](https://chrony-project.org/doc/4.6/chrony.conf.html#ntsdumpdir) — NTS cookie cache
