# Роль: journald

**Phase**: 2 | **Направление**: Логирование

## Цель

Настройка systemd-journald для централизованного хранения системных и сервисных логов с постоянным хранилищем, ограничениями размера, rate limiting и сжатием. Является первым звеном в цепочке логирования: **Docker → journald → Alloy → Loki → Grafana**.

## Архитектура

```
┌─────────────┐
│   Docker    │ (log-driver: journald)
│  Containers │
└──────┬──────┘
       │
       v
┌─────────────┐
│  journald   │ ← эта роль
│  (systemd)  │
└──────┬──────┘
       │
       v
┌─────────────┐
│    Alloy    │ (Grafana Alloy / OTel Collector)
│  Collector  │
└──────┬──────┘
       │
       v
┌─────────────┐
│    Loki     │ (log storage)
└──────┬──────┘
       │
       v
┌─────────────┐
│   Grafana   │ (UI)
└─────────────┘
```

journald собирает логи от:
- Системных сервисов (systemd units)
- Kernel messages (dmesg)
- Docker контейнеров (через journald log driver)
- Syslog-совместимых приложений

## Ключевые переменные (defaults)

```yaml
journald_enabled: true  # Включить роль

# --- Хранилище ---
journald_storage: "persistent"  # persistent/volatile/auto/none
journald_system_max_use: "1G"   # Максимум места на диске для логов
journald_system_keep_free: "2G" # Оставить свободным на диске
journald_runtime_max_use: "200M" # Лимит для /run/log/journal (volatile)

# --- Ротация ---
journald_max_retention_sec: "7d"    # Хранить логи 7 дней
journald_max_file_sec: "1d"         # Ротация файлов раз в день
journald_max_file_size: "100M"      # Максимум размер одного файла

# --- Rate Limiting (защита от log flooding) ---
journald_rate_limit_interval_sec: "30s"  # Интервал проверки
journald_rate_limit_burst: 10000         # Макс сообщений в интервале

# --- Производительность ---
journald_sync_interval_sec: "5m"    # Синхронизация на диск каждые 5 минут
journald_compress: "yes"            # Сжатие старых логов (XZ)
journald_seal: "no"                 # Forward Secure Sealing (требует ключи)

# --- Передача логов ---
journald_forward_to_syslog: "no"   # Не дублировать в syslog
journald_forward_to_console: "no"  # Не выводить на консоль
journald_forward_to_wall: "no"     # Не показывать wall messages
```

## Что настраивает

### На всех дистрибутивах

**Файлы конфигурации:**
- `/etc/systemd/journald.conf` — основная конфигурация journald

**Директории:**
- `/var/log/journal/` — постоянное хранилище логов (создается при `Storage=persistent`)
- `/run/log/journal/` — временное хранилище (RAM)

**Сервисы:**
- `systemd-journald.service` — restart после изменения конфигурации

### Arch Linux

**Пакеты:**
- `systemd` — уже установлен (встроенный компонент)

### Debian/Ubuntu

**Пакеты:**
- `systemd-journal-remote` — (опционально) для remote журналирования

## Зависимости

Нет прямых зависимостей. Эта роль устанавливает базовую инфраструктуру логирования.

**Используется ролями:**
- `docker` — настраивает log-driver: journald для контейнеров
- `alloy` — читает логи из journald через journald API

## Tags

- `journald`, `logging`

---

Назад к [[Roadmap]]
