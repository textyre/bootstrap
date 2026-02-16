# Роль: healthcheck

**Phase**: 8 | **Направление**: Мониторинг

## Цель

Настройка custom health checks для systemd сервисов и дискового пространства. Периодические проверки через systemd timers с уведомлениями при обнаружении проблем.

## Архитектура

```
┌─────────────────────────────────────────┐
│         Healthcheck Scripts             │
│     (systemd timers + shell scripts)    │
│                                          │
│  Проверки:                               │
│    ┌─ Service status (systemd-analyze)  │
│    ├─ Disk usage (df)                   │
│    ├─ Docker container health           │
│    ├─ Network connectivity              │
│    └─ Custom application checks         │
│                                          │
│  Периодичность:                          │
│    - Критические: каждые 5 минут        │
│    - Стандартные: каждые 15 минут       │
│    - Долгие: каждый час                 │
└──────────────┬──────────────────────────┘
               │
               v (при обнаружении проблемы)
        ┌──────────────┐
        │  Notification│ (journald, email, webhook)
        └──────────────┘
```

**Типы health checks:**
- **Systemd services**: проверка статуса критических сервисов (docker, ssh, caddy)
- **Disk usage**: предупреждение при заполнении диска > 80%
- **Docker containers**: проверка health status контейнеров
- **Network**: проверка доступности DNS, gateway, external hosts
- **Application-specific**: custom проверки для приложений

## Ключевые переменные (defaults)

```yaml
healthcheck_enabled: true  # Включить роль

# --- Базовая конфигурация ---
healthcheck_base_dir: "/opt/healthcheck"  # Директория для скриптов
healthcheck_scripts_dir: "{{ healthcheck_base_dir }}/scripts"
healthcheck_logs_dir: "/var/log/healthcheck"

# --- Уведомления ---
healthcheck_notify_method: "journald"  # Метод: journald, email, webhook
healthcheck_email_recipient: "root@localhost"
healthcheck_webhook_url: ""  # Webhook URL (Slack, Discord, etc)

# --- Systemd Services Check ---
healthcheck_services_enabled: true
healthcheck_services_interval: "5min"  # Проверка каждые 5 минут
healthcheck_critical_services:
  - docker
  - sshd
  - systemd-resolved
  - systemd-journald

# --- Disk Usage Check ---
healthcheck_disk_enabled: true
healthcheck_disk_interval: "15min"     # Проверка каждые 15 минут
healthcheck_disk_warning_threshold: 80  # Предупреждение при > 80%
healthcheck_disk_critical_threshold: 90 # Критично при > 90%
healthcheck_disk_excluded_filesystems:
  - tmpfs
  - devtmpfs
  - overlay

# --- Docker Containers Check ---
healthcheck_docker_enabled: true
healthcheck_docker_interval: "5min"    # Проверка каждые 5 минут
healthcheck_docker_critical_containers:
  - caddy
  - vaultwarden
  - loki
  - prometheus

# --- Network Check ---
healthcheck_network_enabled: true
healthcheck_network_interval: "15min"  # Проверка каждые 15 минут
healthcheck_network_check_dns: true    # Проверка DNS resolution
healthcheck_network_check_gateway: true  # Проверка default gateway
healthcheck_network_check_external: true  # Проверка external hosts
healthcheck_network_external_hosts:
  - "1.1.1.1"        # Cloudflare DNS
  - "8.8.8.8"        # Google DNS

# --- Custom Checks ---
healthcheck_custom_checks: []
# Пример:
# healthcheck_custom_checks:
#   - name: "caddy-health"
#     script: "/opt/healthcheck/scripts/check-caddy.sh"
#     interval: "5min"
#     critical: true

# --- Retention ---
healthcheck_logs_retention_days: 7  # Хранить логи 7 дней
```

## Что настраивает

### На всех дистрибутивах

**Структура директорий:**
```
/opt/healthcheck/
├── scripts/                    # Скрипты проверок
│   ├── check-services.sh       # Проверка systemd services
│   ├── check-disk.sh           # Проверка дискового пространства
│   ├── check-docker.sh         # Проверка Docker containers
│   ├── check-network.sh        # Проверка сети
│   └── notify.sh               # Скрипт уведомлений
└── config.env                  # Конфигурация (пороги, recipients)

/var/log/healthcheck/           # Логи проверок
├── services.log
├── disk.log
└── docker.log
```

**Systemd units:**
- `healthcheck-services.service` + `healthcheck-services.timer` — проверка сервисов
- `healthcheck-disk.service` + `healthcheck-disk.timer` — проверка дисков
- `healthcheck-docker.service` + `healthcheck-docker.timer` — проверка Docker
- `healthcheck-network.service` + `healthcheck-network.timer` — проверка сети

**Пример timer (healthcheck-disk.timer):**
```ini
[Unit]
Description=Disk usage health check timer
Requires=healthcheck-disk.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
```

**Пример service (healthcheck-disk.service):**
```ini
[Unit]
Description=Disk usage health check

[Service]
Type=oneshot
ExecStart=/opt/healthcheck/scripts/check-disk.sh
StandardOutput=journal
StandardError=journal
```

### Arch Linux

**Пакеты:**
- `coreutils` — df, stat (уже установлено)
- `systemd` — systemd-analyze (уже установлено)

### Debian/Ubuntu

**Пакеты:**
- `coreutils` — df, stat (уже установлено)
- `systemd` — systemd-analyze (уже установлено)

## Зависимости

**Рекомендуемые:**
- `docker` — для проверки Docker контейнеров
- `journald` — для логирования уведомлений

**Опциональные:**
- MTA (Postfix) — для email уведомлений

## Tags

- `healthcheck`, `monitoring`

---

Назад к [[Roadmap]]
