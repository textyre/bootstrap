# Роль: smartd

**Phase**: 8 | **Направление**: Мониторинг

## Цель

Настройка smartd (SMART Monitoring Daemon) для мониторинга здоровья дисков (HDD, SSD, NVMe) через SMART (Self-Monitoring, Analysis and Reporting Technology). Обнаруживает предупреждающие признаки отказа диска и отправляет уведомления.

## Архитектура

```
┌─────────────────────────────────────────┐
│              smartd                      │
│       (SMART Monitoring Daemon)          │
│                                          │
│  Периодическая проверка (каждые 30 мин):│
│    ┌─ /dev/sda — HDD SMART attributes   │
│    ├─ /dev/nvme0n1 — NVMe health        │
│    └─ /dev/sdb — SSD wear leveling      │
│                                          │
│  Триггеры уведомлений:                  │
│    - Reallocated sectors (ID 5)         │
│    - Current pending sectors (ID 197)   │
│    - Uncorrectable errors (ID 198)      │
│    - Temperature threshold              │
│    - Pre-fail/Old-age attributes        │
└──────────────┬──────────────────────────┘
               │
               v (при обнаружении проблемы)
        ┌──────────────┐
        │  Notification│ (email, syslog, script)
        └──────────────┘
```

**Что мониторит SMART:**
- **HDD**: reallocated sectors, seek errors, spin-up time, temperature
- **SSD**: wear leveling, program/erase cycles, uncorrectable errors
- **NVMe**: critical warnings, available spare, temperature, media errors

## Ключевые переменные (defaults)

```yaml
smartd_enabled: true  # Включить роль

# --- Базовая конфигурация ---
smartd_service_enabled: true   # Включить systemd service
smartd_service_state: "started"  # Запустить сервис

# --- Мониторинг ---
smartd_interval: 1800          # Проверка каждые 30 минут (в секундах)
smartd_enable_auto_offline: true  # Автоматический offline тест
smartd_enable_auto_save: true     # Автосохранение атрибутов

# --- Тесты ---
smartd_short_test_schedule: "(S/../.././02)"   # Short self-test ежедневно в 2:00
smartd_long_test_schedule: "(L/../../6/03)"    # Long self-test по субботам в 3:00

# --- Уведомления ---
smartd_notify_enabled: true    # Включить уведомления
smartd_notify_method: "syslog" # Метод: syslog, email, script

# Email (если smartd_notify_method: email)
smartd_email_recipient: "root@localhost"
smartd_email_sender: "smartd@{{ ansible_hostname }}"
smartd_smtp_host: "localhost"

# Script (если smartd_notify_method: script)
smartd_notify_script: "/usr/local/bin/smartd-notify.sh"

# --- Температурные пороги ---
smartd_temperature_threshold: 60   # Уведомление при >= 60°C
smartd_temperature_diff: 5         # Уведомление при изменении >= 5°C

# --- Диски для мониторинга ---
# Автоматическое обнаружение всех дисков
smartd_auto_detect_devices: true

# Или явный список дисков
smartd_devices: []
# Пример:
# smartd_devices:
#   - device: /dev/sda
#     options: "-a -o on -S on -s (S/../.././02|L/../../6/03) -W 5,60,60"
#   - device: /dev/nvme0n1
#     options: "-a"

# --- Игнорируемые диски ---
smartd_excluded_devices:
  - /dev/loop*     # Loop devices
  - /dev/ram*      # RAM disks
  - /dev/sr*       # CD/DVD drives

# --- Опасные действия (по умолчанию выключены) ---
smartd_enable_standby_check: false  # Проверять диски в standby (может разбудить)
```

## Что настраивает

### На всех дистрибутивах

**Файлы конфигурации:**
- `/etc/smartd.conf` — конфигурация smartd (список дисков, опции мониторинга)

**Скрипты уведомлений:**
- `/usr/local/bin/smartd-notify.sh` — custom notification script (если `smartd_notify_method: script`)

**Сервисы:**
- `smartd.service` — systemd service для smartd daemon

### Arch Linux

**Пакеты:**
- `smartmontools` — утилиты для работы со SMART (smartctl, smartd)

**Конфигурация:**
- `/etc/smartd.conf` — основная конфигурация

### Debian/Ubuntu

**Пакеты:**
- `smartmontools` — утилиты для работы со SMART

**Конфигурация:**
- `/etc/smartd.conf` — основная конфигурация
- `/etc/default/smartmontools` — дополнительные параметры (enable smartd)

## Зависимости

Нет прямых зависимостей. Эта роль работает на уровне системы.

**Опциональные:**
- MTA (Postfix, Sendmail) — для email уведомлений
- `journald` — для syslog уведомлений

## Tags

- `smartd`, `monitoring`, `disk`

---

Назад к [[Roadmap]]
