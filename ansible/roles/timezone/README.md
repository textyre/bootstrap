# timezone

Устанавливает системную таймзону и обеспечивает наличие базы данных tzdata.

## What this role does

- [x] Устанавливает пакет tzdata (имя пакета из `packages_tzdata` в `packages.yml`)
- [x] Устанавливает системную таймзону через `community.general.timezone`
- [x] Проверяет корректность применённой таймзоны
- [x] Перезапускает cron при фактической смене таймзоны (skipped если не установлен)

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `timezone_name` | `"UTC"` | Имя таймзоны в формате tz database (`timedatectl list-timezones`) |

Реальное значение задаётся в `group_vars/all/system.yml`:

```yaml
timezone_name: "Asia/Almaty"
```

`packages_tzdata` живёт в `group_vars/all/packages.yml`:

```yaml
packages_tzdata:
  Gentoo: "sys-libs/timezone-data"
  default: "tzdata"
```

## Responsibility boundaries

| Concern | Owner |
|---------|-------|
| System timezone (`/etc/localtime`) | this role |
| tzdata package currency | this role |
| RTC mode (UTC vs local) | `ntp` role (`ntp_rtcsync: true`) |
| Clock accuracy (NTP sync) | `ntp` role (chrony) |

## Supported platforms

Arch Linux, Fedora, Ubuntu, Void Linux, Gentoo

## Tags

`timezone`, `timezone,report`

## License

MIT
