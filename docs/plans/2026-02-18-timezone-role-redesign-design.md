# timezone role — redesign design

**Date:** 2026-02-18

## Problem

The current `timezone` role installs the system timezone but conflates responsibilities that belong elsewhere (RTC mode, hwclock), lacks a central package source, and supports distros outside project scope.

## Responsibility boundaries

| Concern | Owner |
|---|---|
| System timezone (`/etc/localtime`) | timezone role |
| tzdata package (currency of DST rules) | timezone role (package name from `packages.yml`) |
| RTC mode (UTC vs local) | ntp role (`ntp_rtcsync: true` → chrony writes UTC to RTC) |
| Clock accuracy (NTP sync) | ntp role (chrony) |
| Package name registry | `group_vars/all/packages.yml` |

## What timezone role does

1. **Install tzdata** — ensures the timezone database is present and named correctly per distro
2. **Set system timezone** — `/etc/localtime` symlink via `community.general.timezone`
3. **Verify** — assert the OS reports the expected timezone
4. **Report** — structured phase log via `common` role

## What timezone role does NOT do

- RTC mode / hwclock — delegated to ntp (`ntp_rtcsync: true`)
- NTP sync — delegated to ntp role
- Hardcode package names — package names live in `packages.yml`

## Variables

### `group_vars/all/system.yml` (already present)

```yaml
timezone_name: "Asia/Almaty"
```

### `group_vars/all/packages.yml` (new section)

```yaml
# timezone — роль roles/timezone
packages_tzdata:
  Gentoo: "sys-libs/timezone-data"
  default: "tzdata"
```

### `roles/timezone/defaults/main.yml`

```yaml
timezone_name: "UTC"   # fallback only; real value from system.yml
```

## Supported platforms

Arch Linux, Fedora, Ubuntu, Void Linux, Gentoo.

Removed: Alpine, Debian (separate from Ubuntu). No special Alpine handling needed as the scope narrows to the five distros above.

## Task flow (`tasks/main.yml`)

```
Install tzdata
  └─ package: packages_tzdata[os_family] | default(packages_tzdata['default'])
  └─ when: packages_tzdata is defined

Set timezone
  └─ community.general.timezone: name={{ timezone_name }}

Verify
  └─ systemd  → timedatectl show --property=Timezone --value == timezone_name
  └─ generic  → readlink -f /etc/localtime contains timezone_name

Report
  └─ report_phase: "Set timezone: {{ timezone_name }}"
  └─ report_render
```

## File structure

```
roles/timezone/
  defaults/main.yml         # timezone_name fallback
  meta/main.yml             # platforms: Arch, Fedora, Ubuntu, Void, Gentoo
  tasks/
    main.yml
    install/
      gentoo.yml            # emerge --noreplace sys-libs/timezone-data
      default.yml           # no-op (tzdata preinstalled on other distros)
    verify/
      systemd.yml           # timedatectl show
      generic.yml           # readlink /etc/localtime
  molecule/default/
    converge.yml
    molecule.yml
    verify.yml              # asserts Timezone + symlink
```

## Verification spec

**systemd** (`verify/systemd.yml`):
- `timedatectl show --property=Timezone --value` == `timezone_name`

**generic** (`verify/generic.yml`):
- `readlink -f /etc/localtime` contains `timezone_name`

**molecule verify.yml** tests:
- timezone is set to expected value
- `/etc/localtime` symlink exists and points to correct zone file

## Out of scope

- Per-user `TZ` env variable — application concern
- RTC local/UTC mode — ntp role via `ntp_rtcsync`
- Time accuracy — ntp role via chrony
