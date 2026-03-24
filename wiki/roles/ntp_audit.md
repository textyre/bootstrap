# Роль: ntp_audit

**Phase**: 11 | **Направление**: Мониторинг и наблюдаемость

## Цель

Непрерывный аудит состояния синхронизации времени через NTP/chrony на систему. Роль развертывает автоматизированный Python скрипт, который запускается по расписанию (systemd timer или cron), собирает структурированные метрики синхронизации времени из `chronyc` и пишет JSON логи для ingestion в Grafana Alloy и alerting через Loki ruler rules.

Критична для инфраструктур, чувствительных к смещению времени: распределённые системы, микросервисы, системы с строгой аудитом.

## Ключевые переменные (defaults)

```yaml
ntp_audit_enabled: true                              # Включить аудит NTP

# Расписание
ntp_audit_interval_systemd: "*:0/5"                 # Systemd timer (каждые 5 минут)
ntp_audit_interval_cron: "*/5 * * * *"              # Cron расписание (fallback)

# Логирование
ntp_audit_log_dir: "/var/log/ntp-audit"             # Директория логов
ntp_audit_log_file: "/var/log/ntp-audit/audit.log"  # Файл логов (JSON, одна строка = один запуск)
ntp_audit_logrotate_rotate: 7                        # Удерживать 7 старых логов
ntp_audit_logrotate_size: "10M"                     # Ротировать при размере > 10M

# Обнаружение конфликтов (сервисы, конкурирующие с chrony)
ntp_audit_competitor_services:
  - systemd-timesyncd                               # Встроенный синхронизатор Systemd
  - ntpd                                             # ISC NTP daemon
  - openntpd                                         # OpenNTP (lightweight)
  - vmtoolsd                                         # VMware Tools (может переопределить время)

# PHC устройства (контроллеры точного времени — PTP)
ntp_audit_phc_devices:
  - /dev/ptp_hyperv                                # Hyper-V emulated PTP
  - /dev/ptp0                                       # Physical PHC device

# Ядерные модули (проверка наличия)
ntp_audit_kernel_modules:
  - ptp_kvm                                         # KVM PTP support

# Grafana Alloy integration (опционально)
ntp_audit_alloy_enabled: true                       # Развернуть фрагмент конфига Alloy
ntp_audit_alloy_config_dir: "/etc/alloy/conf.d"   # Директория конфигов Alloy

# Loki ruler alert rules (опционально)
ntp_audit_loki_enabled: true                        # Развернуть правила alerting Loki
ntp_audit_loki_rules_dir: "/etc/loki/rules/fake"  # Директория правил Loki

# Директория логов chrony (для Alloy фрагмента)
ntp_audit_chrony_log_dir: "/var/log/chrony"       # Путь к логам chrony

# Пороги alerting
ntp_audit_alert_offset_threshold: "0.1"            # Алерт если смещение часов > 0.1s
ntp_audit_alert_stratum_max: "4"                   # Алерт если stratum > 4
```

## Что настраивает

### Скрипт аудита
- **`/usr/local/bin/ntp-audit`** — Python zipapp, читает `chronyc -c tracking`, парсит CSV, пишет структурированный JSON
- **Поведение на ошибку**: При исключении скрипт пишет error record с `sync_status: 'error'` и всё равно выходит с кодом 0 (чтобы не ломать systemd timer)

### Расписание
- **systemd timer** (primary): `ntp-audit.timer` + `ntp-audit.service` (если `ansible_facts['service_mgr'] == 'systemd'`)
- **cron** (fallback для non-systemd): `/etc/cron.d/ntp-audit` (автоматический выбор если systemd недоступен)

### Логирование
- **Основной лог**: `/var/log/ntp-audit/audit.log` — JSON, одна строка на выполнение
- **Syslog**: Одна строка summary в журнал (niveau INFO по умолчанию, ERROR если скрипт упал)
- **Logrotate**: `/etc/logrotate.d/ntp-audit` — ротация по размеру и по дням

### Мониторинг
- **Grafana Alloy fragment**: `/etc/alloy/conf.d/ntp-audit.alloy` — парсит JSON логи в Loki, добавляет labels (hostname, stratum, sync_status)
- **Loki ruler rules**: `/etc/loki/rules/fake/ntp-audit-rules.yaml` — alert rules: смещение часов, потеря sync, конфликты сервисов

## Аудит-события (JSON schema)

Каждое выполнение скрипта пишет один JSON объект в лог с 19-20 ключами:

| Ключ | Тип | Описание | Примеры | Когда error |
|------|-----|---------|---------|------------|
| `timestamp` | ISO8601 | Время выполнения скрипта (UTC) | `2026-03-24T12:34:56.123456+00:00` | Присутствует |
| `reference_id` | str | ID источника времени (IP или буква) | `8.8.8.8`, `CDMA`, `POOL` | `''` |
| `reference_name` | str | Имя источника времени | `google-ntp`, `ptp0`, `local.stratum` | `''` |
| `stratum` | int | Уровень вложенности от источника | `0` (local), `1` (primary), `2` (secondary), `16` (unreachable) | `0` |
| `current_correction` | float | Текущая коррекция часов (секунды) | `0.000123`, `-0.0005` | `0.0` |
| `last_offset` | float | Последнее измеренное смещение часов | `0.0001234` | `0.0` |
| `rms_offset` | float | RMS (среднеквадратическое) смещение | `0.0000567` | `0.0` |
| `frequency_ppm` | float | Частотная ошибка часов (ppm) | `-2.345`, `1.234` | `0.0` |
| `residual_freq` | float | Остаточная частотная ошибка | `0.0001` | `0.0` |
| `skew` | float | Оценка погрешности частоты (ppm) | `0.5234` | `0.0` |
| `root_delay` | float | Задержка к корневому источнику (мс) | `0.0523` | `0.0` |
| `root_dispersion` | float | Дисперсия к корневому источнику (мс) | `0.0231` | `0.0` |
| `update_interval` | float | Интервал между NTP обновлениями (с) | `64`, `128` | `0.0` |
| `leap_status` | int | Статус leap second: `0`=normal, `1`=insert, `2`=delete, `3`=unsync | `0` | `3` |
| `sync_status` | str | Статус синхронизации | `'synced'`, `'unsynced'`, `'making_steps'` | `'error'` |
| `ntp_conflict` | str | Обнаруженные конфликтующие сервисы (comma-separated) | `'none'`, `'systemd-timesyncd_active'`, `'systemd-timesyncd_active,ntpd_active'` | `'none'` |
| `ntp_phc_status` | str | Статус PHC (Precision Time Protocol) | `'present'`, `'absent'`, `'error'` | `'error'` |
| `ntp_phc_device` | str | Найденное PHC устройство (если присутствует) | `'/dev/ptp0'`, `'/dev/ptp_hyperv'` | `''` |
| `ntp_modules_status` | str | Статус ядерных модулей PTP | `'present'`, `'absent'`, `'error'` | `'error'` |
| `chrony_error` | str | (Только на error) текст исключения Python | `"[Errno 2] No such file: 'chronyc'"` | Присутствует только при ошибке |

### Error record (при исключении)
Если скрипт упадет (chrony не установлен, нет доступа к `/var/run/chrony.sock`, и т.д.), он пишет error record с:
- `sync_status: 'error'` — явный маркер ошибки
- `ntp_phc_status: 'error'`, `ntp_modules_status: 'error'` — все проверки в error состоянии
- `chrony_error: '<exception message>'` — текст исключения для debug

## Мониторинг и интеграция

### Grafana Alloy
Фрагмент конфига (`/etc/alloy/conf.d/ntp-audit.alloy`) настроен на:
1. **Parsing**: Читает JSON из `/var/log/ntp-audit/audit.log` (tail)
2. **Labels**: Добавляет `hostname`, `stratum`, `sync_status`, `source` к каждой метрике
3. **Stream**: Отправляет в Loki с лейблом `job: ntp-audit`

### Loki ruler alert rules
Правила alerting в `/etc/loki/rules/fake/ntp-audit-rules.yaml` отслеживают:
- **High offset**: `last_offset > {{ ntp_audit_alert_offset_threshold }}s` → alert `NTPHighOffset`
- **Lost sync**: `sync_status = 'error'` → alert `NTPSyncLost`
- **High stratum**: `stratum > {{ ntp_audit_alert_stratum_max }}` → alert `NTPHighStratum`
- **Service conflict**: `ntp_conflict != 'none'` → alert `NTPServiceConflict`

## Зависимости

- **Требует**: `chrony` (NTP daemon) установлен и работающий на хосте перед применением роли
  - Роль не устанавливает chrony (audit-only)
  - Если chrony не запущен, скрипт напишет error record

- **Опционально**:
  - `alloy` — для ingestion логов в Loki (если `ntp_audit_alloy_enabled: true`)
  - `loki-ruler` — для alerting (если `ntp_audit_loki_enabled: true`)

## Tags

- `ntp_audit` — все tasks роли
- `ntp_audit_script` — только развертывание скрипта
- `ntp_audit_scheduler` — только настройка расписания (systemd timer или cron)
- `ntp_audit_logging` — только logrotate конфиг
- `ntp_audit_monitoring` — только Alloy + Loki rules

## Supported platforms

Arch Linux, Debian, Ubuntu, Fedora, Void Linux — любая платформа с `chrony` и поддержкой systemd или cron.

## Testing

Три molecule scenario:

| Scenario | Driver | Платформы | Цель |
|----------|--------|-----------|------|
| `docker` | docker | Archlinux-systemd, Ubuntu-systemd | CI integration test (systemd timer + cron fallback) |
| `vagrant` | vagrant/libvirt | Arch-vm + Ubuntu-vm | Cross-platform integration test с реальным chrony |
| `disabled` | localhost | Localhost | Проверка флага `ntp_audit_enabled: false` отключает все |

---

Назад к [[Roadmap]]
