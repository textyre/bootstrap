# Роль: systemd_units

**Phase**: 6 | **Направление**: Services

## Цель

Управление пользовательскими systemd-юнитами: таймеры, сервисы, targets. Автоматизация задач через systemd timers (альтернатива cron), создание зависимостей между сервисами, управление состоянием.

## Ключевые переменные (defaults)

```yaml
systemd_units_enabled: true  # Включить управление юнитами

# Список пользовательских сервисов
systemd_units_services: []
# Пример:
# - name: backup
#   description: "Backup to remote storage"
#   exec_start: "/usr/local/bin/backup.sh"
#   user: root
#   working_directory: /root
#   restart: on-failure
#   restart_sec: 30
#   enabled: true
#   state: started

# Список таймеров (аналог cron)
systemd_units_timers: []
# Пример:
# - name: backup
#   description: "Backup timer — daily at 3:00 AM"
#   on_calendar: "*-*-* 03:00:00"  # Ежедневно в 03:00
#   persistent: true               # Запустить пропущенный запуск после перезагрузки
#   unit: backup.service           # Связанный сервис
#   enabled: true

# Список путей для мониторинга (path units)
systemd_units_paths: []
# Пример:
# - name: config-watcher
#   description: "Watch /etc/myapp for changes"
#   path_modified: /etc/myapp
#   unit: reload-config.service
#   enabled: true

# Каталог для drop-in файлов
systemd_units_drop_in_dir: /etc/systemd/system

# Перезагрузка daemon после изменений
systemd_units_daemon_reload: true
```

## Что настраивает

**На всех дистрибутивах:**
- Unit-файлы в `/etc/systemd/system/` (services, timers, paths, targets)
- Включение/отключение юнитов (`systemctl enable/disable`)
- Запуск/остановка сервисов (`systemctl start/stop`)
- Перезагрузка systemd daemon (`systemctl daemon-reload`)

**На Arch Linux:**
- Пакет: `systemd` (уже установлен)
- Путь: `/etc/systemd/system/`

**На Debian/Ubuntu:**
- Пакет: `systemd` (уже установлен)
- Путь: `/etc/systemd/system/`

**На Fedora/RHEL:**
- Пакет: `systemd` (уже установлен)
- Путь: `/etc/systemd/system/`

## Зависимости

- `base_system` — systemd и базовые утилиты

## Примечания

### Пример: Таймер для backup

**Сервис** (`/etc/systemd/system/backup.service`):
```ini
[Unit]
Description=Backup to remote storage
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh
User=root
WorkingDirectory=/root
```

**Таймер** (`/etc/systemd/system/backup.timer`):
```ini
[Unit]
Description=Backup timer — daily at 3:00 AM

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=backup.service

[Install]
WantedBy=timers.target
```

Включение:
```bash
systemctl daemon-reload
systemctl enable --now backup.timer
```

### OnCalendar синтаксис

- `daily` / `weekly` / `monthly` — упрощённые формы
- `*-*-* 03:00:00` — каждый день в 03:00
- `Mon *-*-* 00:00:00` — каждый понедельник в 00:00
- `*-*-01 00:00:00` — первое число каждого месяца
- `*:0/15` — каждые 15 минут

Проверка синтаксиса:
```bash
systemd-analyze calendar "Mon *-*-* 09:00:00"
```

### Path Units для мониторинга файлов

Path units запускают сервис при изменении файла/каталога:

```ini
[Unit]
Description=Watch /etc/myapp for changes

[Path]
PathModified=/etc/myapp
Unit=reload-config.service

[Install]
WantedBy=multi-user.target
```

Типы:
- `PathModified` — изменение содержимого
- `PathExists` — файл создан
- `PathExistsGlob` — glob-паттерн
- `DirectoryNotEmpty` — непустой каталог

### Persistent таймеры

`Persistent=true` — если система была выключена во время запланированного запуска, таймер запустится сразу после загрузки. Полезно для backup и maintenance.

### Проверка таймеров

```bash
# Список активных таймеров
systemctl list-timers

# Следующий запуск
systemctl status backup.timer

# Логи последнего запуска
journalctl -u backup.service -n 50
```

## Tags

- `systemd`
- `automation`
- `timers`
- `services`

---

Назад к [[Roadmap]]
