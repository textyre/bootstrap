# Design: locale role improvement

Date: 2026-02-18

## Business goal

Guarantee that system locale is configured predictably and uniformly across all managed machines,
regardless of how the distribution was installed. The role is a "locale contract": operator
declares desired state, role ensures it is realized on any supported distribution.

The role intentionally does NOT manage per-user locale (`~/.profile`), application language
packs, or keyboard layout (that is the `keymap` role).

## Scope of changes

Approach B — refactor to align with project patterns (keymap/timezone roles).

## Supported platforms

- Arch Linux
- Debian / Ubuntu
- RedHat / EL / Fedora
- Void Linux (glibc)

Alpine Linux support is removed (musl libc, not needed).

## Step order change

Current: `validate → generate → configure → verify`
New: `validate → generate → verify → configure`

Rationale: configure writes `/etc/locale.conf`. If generation failed, writing a locale.conf
that references a non-existent locale would leave the machine in a broken state. Verify must
confirm locales exist on disk before configure writes the file.

## Failure behavior

Two types of errors, two behaviors:

| Phase | Error type | Behavior |
|---|---|---|
| validate | Operator config error (bad variables) | debug warning + skip rest of role |
| verify | System error (locales not generated) | soft-fail: report `! fail` + skip configure |

The playbook never crashes. The report table clearly marks failures with `!`.

## File changes

| File | Action |
|---|---|
| `tasks/validate/main.yml` | NEW |
| `vars/main.yml` | NEW |
| `tasks/main.yml` | Refactor: new order, with_first_found, when blocks, 4 report phases |
| `tasks/generate/void.yml` | Add `meta: flush_handlers` at end (bug fix) |
| `tasks/generate/alpine.yml` | DELETE |
| `tasks/configure/musl.yml` | DELETE |
| `tasks/verify/musl.yml` | DELETE |
| `templates/locale-alpine.sh.j2` | DELETE |
| `meta/main.yml` | Remove Alpine from platforms |
| `molecule/default/molecule.yml` | Add idempotency to test_sequence |
| `molecule/default/verify.yml` | Add smoke `locale` command + LC_* assertions |

## tasks/validate/main.yml

Three checks on Ansible variables (no SSH, no system calls):

1. `locale_list` is not empty
2. `locale_default` is in `locale_list`
3. All values in `locale_lc_overrides` are in `locale_list`

On any failure: `set_fact _locale_skip=true` + `_locale_skip_reason` + `debug` warning.
No crash. The rest of the role is wrapped in `when: not (_locale_skip | default(false))`.

```yaml
- name: Check locale_list is not empty
  ansible.builtin.set_fact:
    _locale_skip: true
    _locale_skip_reason: "locale_list is empty"
  when: locale_list | length == 0

- name: Check locale_default is in locale_list
  ansible.builtin.set_fact:
    _locale_skip: true
    _locale_skip_reason: >-
      locale_default '{{ locale_default }}' not in locale_list {{ locale_list }}
  when:
    - not (_locale_skip | default(false))
    - locale_default not in locale_list

- name: Check LC_* override values are in locale_list
  ansible.builtin.set_fact:
    _locale_skip: true
    _locale_skip_reason: >-
      {{ item.key }}={{ item.value }} not in locale_list {{ locale_list }}
  loop: "{{ locale_lc_overrides | dict2items }}"
  when:
    - not (_locale_skip | default(false))
    - item.value not in locale_list

- name: Warn if config invalid
  ansible.builtin.debug:
    msg: "WARNING: locale role skipped — {{ _locale_skip_reason }}"
  when: _locale_skip | default(false)
```

## vars/main.yml

```yaml
_locale_supported_os_families:
  - archlinux
  - debian
  - redhat
  - void
```

## tasks/main.yml structure

```yaml
# 1. Validate
- include_tasks: validate/main.yml
- report_phase: "Validate config" → done / fail

# 2–4 wrapped in: when: not (_locale_skip | default(false))

# 2. Generate (with_first_found + skip + warn on unsupported OS)
- include_tasks: generate/{{ os_family }}.yml  # with_first_found, skip: true
- debug: WARNING if os_family not in _locale_supported_os_families
- report_phase: "Generate locales" → done / skip

# 3. Verify (soft-fail: set _locale_verify_ok fact, no assert)
- include_tasks: verify/glibc.yml
- report_phase: "Verify locales" → done / fail

# 4. Configure (only if verify passed)
- include_tasks: configure/glibc.yml
  when: _locale_verify_ok | default(false)
- report_phase: "Configure locale.conf" → done / skip

# 5. Render report
- report_render
```

## tasks/generate/void.yml fix

Add `meta: flush_handlers` at the end of the file so `xbps-reconfigure -f glibc-locales`
runs immediately after lineinfile changes, before verify runs.

```yaml
- name: Flush handlers (force locale regeneration)
  ansible.builtin.meta: flush_handlers
```

## tasks/verify/glibc.yml — soft-fail

Replace `assert` with fact-based result:

```yaml
- name: Get available locales
  ansible.builtin.command: locale -a
  register: _locale_check
  changed_when: false

- name: Check all requested locales are available
  ansible.builtin.set_fact:
    _locale_verify_ok: >-
      {{ _locale_normalized in _available_list }}
  vars:
    _locale_normalized: "{{ item | lower | regex_replace('[\\-\\.]', '') }}"
    _available_list: "{{ _locale_check.stdout_lines | map('lower') | map('regex_replace', '[\\-\\.]', '') | list }}"
  loop: "{{ locale_list }}"

- name: Warn on missing locales
  ansible.builtin.debug:
    msg: "WARNING: locale verify failed — not all locales found in locale -a"
  when: not (_locale_verify_ok | default(true))
```

## molecule/default/molecule.yml

Add idempotency to `scenario.test_sequence`:

```yaml
scenario:
  test_sequence:
    - converge
    - idempotency
    - verify
```

## molecule/default/verify.yml additions

Add smoke test via `locale` command and LC_* override assertions:

```yaml
- name: Run locale command
  ansible.builtin.command: locale
  register: _verify_locale_cmd
  changed_when: false

- name: Assert LANG is active
  ansible.builtin.assert:
    that: "'LANG={{ _test_locale }}' in _verify_locale_cmd.stdout"
    fail_msg: "LANG={{ _test_locale }} not active in locale output"

- name: Assert LC_* overrides are active
  ansible.builtin.assert:
    that: "'{{ item.key }}={{ item.value }}' in _verify_locale_cmd.stdout"
    fail_msg: "{{ item.key }}={{ item.value }} not active in locale output"
  loop: "{{ _test_lc_overrides | dict2items }}"
```

## Report table examples

Success:
```
+----------------------------+------------+--------------------------+
| Phase                      | Status     | Details                  |
+----------------------------+------------+--------------------------+
| Validate config            | + done     |                          |
| Generate locales           | + done     | en_US.UTF-8, ru_RU.UTF-8 |
| Verify locales             | + done     | 2 locales OK             |
| Configure locale.conf      | + done     | en_US.UTF-8              |
+----------------------------+------------+--------------------------+
```

Bad variables:
```
+----------------------------+------------+--------------------------+
| Validate config            | ! fail     | locale_default not in li |
| Generate locales           | - skip     |                          |
| Verify locales             | - skip     |                          |
| Configure locale.conf      | - skip     |                          |
+----------------------------+------------+--------------------------+
```

Generation failed:
```
+----------------------------+------------+--------------------------+
| Validate config            | + done     |                          |
| Generate locales           | + done     | en_US.UTF-8, ru_RU.UTF-8 |
| Verify locales             | ! fail     | ru_RU.UTF-8 missing      |
| Configure locale.conf      | - skip     |                          |
+----------------------------+------------+--------------------------+
```
