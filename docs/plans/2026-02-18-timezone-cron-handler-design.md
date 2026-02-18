# timezone: cron restart handler — design

**Date:** 2026-02-18

## Background

Comparison with public timezone roles (geerlingguy.ntp, galexrt, yatesr, azmodude, alysoid) revealed one actionable gap:

The official `community.general.timezone` module documentation explicitly states:
> "It is recommended to restart crond after changing the timezone."

Without restarting cron, scheduled jobs may execute at incorrect times after a timezone change. Only geerlingguy.ntp addresses this. Our role does not.

## What to add

### `handlers/main.yml`

Two tasks bound via `listen: restart cron`:

```yaml
---
- name: Gather service facts for cron restart
  ansible.builtin.service_facts:
  listen: restart cron

- name: Restart cron if present
  ansible.builtin.service:
    name: "{{ _tz_cron_service[ansible_facts['os_family']] | default('crond') }}"
    state: restarted
  when: (_tz_cron_service[ansible_facts['os_family']] | default('crond')) in ansible_facts.services
  listen: restart cron
```

If cron is not installed: task shows `skipped` — explicit and honest in logs.
If cron is installed: task shows `changed` — restarted.
No red failures, no hidden errors.

### `vars/main.yml`

Cron service name varies by distro:

```yaml
---
# Internal: cron service name per os_family
# Used by the "restart cron" handler
_tz_cron_service:
  Archlinux: crond
  Debian: cron
  Ubuntu: cron
  RedHat: crond
  Void: crond
  Gentoo: crond
```

### `tasks/main.yml`

Add `notify: restart cron` to the "Set timezone" task:

```yaml
- name: Set timezone
  community.general.timezone:
    name: "{{ timezone_name }}"
  notify: restart cron
  tags: ['timezone']
```

The handler fires only when the module actually makes a change (i.e., timezone was different). Idempotent by nature.

### `README.md`

Add to "What this role does":
```
- [x] Перезапускает cron при фактической смене таймзоны (handler, skip если не установлен)
```

## What we are NOT adding (from comparison)

| Rejected | Reason |
|---|---|
| Timezone validity pre-check | `community.general.timezone` already fails with a clear error on invalid name |
| RTC/hwclock parameter | Handled by ntp role (`ntp_rtcsync: true` in chrony) |
| NTP coupling | Intentional separation of concerns |
| Rename `timezone_name` → `timezone` | Not worth breaking project convention |

## Files changed

- Create: `ansible/roles/timezone/handlers/main.yml`
- Create: `ansible/roles/timezone/vars/main.yml`
- Modify: `ansible/roles/timezone/tasks/main.yml` (add notify)
- Modify: `ansible/roles/timezone/README.md` (add handler to checklist)
