# Роль: watchtower

**Phase**: 10 | **Направление**: Autodeploy

## Цель

Автоматическое обновление Docker-контейнеров через Watchtower. Отслеживает новые версии образов в registry, скачивает обновления и пересоздаёт контейнеры с сохранением конфигурации. Поддержка уведомлений, расписаний и rollback.

## Ключевые переменные (defaults)

```yaml
watchtower_enabled: true  # Включить Watchtower

# Режим работы
watchtower_schedule: "0 0 3 * * *"  # Cron: ежедневно в 03:00 (формат: секунды минуты часы день месяц день_недели)
watchtower_run_once: false           # Запустить один раз и выйти (для тестирования)
watchtower_monitor_only: false       # Только проверка обновлений без применения (dry-run)

# Фильтры контейнеров
watchtower_scope: ""                    # Label для фильтрации (com.centurylinklabs.watchtower.enable=true)
watchtower_include_stopped: false       # Обновлять остановленные контейнеры
watchtower_include_restarting: true     # Обновлять контейнеры в статусе restarting
watchtower_revive_stopped: false        # Запускать контейнеры после обновления, если были остановлены

# Cleanup
watchtower_cleanup: true                # Удалять старые образы после обновления
watchtower_remove_volumes: false        # Удалять volumes (опасно, default: false)

# Timeout и retry
watchtower_timeout: 10                  # Таймаут для HTTP-запросов к registry (секунды)
watchtower_stop_timeout: 10             # Таймаут для graceful stop контейнера (секунды)
watchtower_rolling_restart: false       # Обновлять контейнеры по одному (для zero-downtime)

# Уведомления
watchtower_notifications: false              # Включить уведомления
watchtower_notification_url: ""              # Webhook URL (Slack, Discord, gotify, email)
watchtower_notification_level: "info"        # Уровень: panic, fatal, error, warn, info, debug
watchtower_notification_template: ""         # Кастомный шаблон уведомления

# Registry authentication (если приватный registry)
watchtower_registry_auth: false              # Использовать аутентификацию
watchtower_registry_username: ""             # Username для registry
watchtower_registry_password: ""             # Password для registry
watchtower_registry_url: ""                  # URL registry (для приватных registry)

# HTTP API
watchtower_http_api: false                   # Включить HTTP API для ручного триггера
watchtower_http_api_port: 8080               # Порт для API
watchtower_http_api_token: ""                # Bearer token для защиты API

# Логирование
watchtower_log_level: "info"                 # Уровень логов: panic, fatal, error, warn, info, debug, trace
watchtower_log_format: "text"                # Формат: text / json

# Docker настройки
watchtower_docker_socket: /var/run/docker.sock  # Путь к Docker socket
watchtower_container_name: watchtower           # Имя контейнера Watchtower
```

## Что настраивает

**На всех дистрибутивах:**
- Docker-контейнер `watchtower` (образ: `containrrr/watchtower`)
- Мониторинг Docker-контейнеров на обновления
- Автоматическое обновление по расписанию
- Уведомления в Slack/Discord/Email (если настроено)
- HTTP API для ручного запуска (опционально)

**На Arch Linux:**
- Требует: роль `docker` (docker и docker-compose установлены)

**На Debian/Ubuntu:**
- Требует: роль `docker` (docker и docker-compose установлены)

**На Fedora/RHEL:**
- Требует: роль `docker` (docker и docker-compose установлены)

## Зависимости

- `docker` — Docker daemon и CLI

## Примечания

### Как работает Watchtower

1. **Сканирование**: Watchtower опрашивает Docker daemon и получает список запущенных контейнеров
2. **Проверка обновлений**: Для каждого образа проверяет registry на наличие нового digest
3. **Обновление**:
   - Скачивает новый образ
   - Останавливает старый контейнер (graceful stop с timeout)
   - Создаёт новый контейнер с теми же параметрами (env, volumes, networks, labels)
   - Запускает новый контейнер
4. **Cleanup**: Удаляет старый образ (если `watchtower_cleanup: true`)

### Пример docker-compose

`/opt/watchtower/docker-compose.yml`:

```yaml
services:
  watchtower:
    image: containrrr/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    environment:
      - WATCHTOWER_SCHEDULE=0 0 3 * * *
      - WATCHTOWER_CLEANUP=true
      - WATCHTOWER_TIMEOUT=10s
      - WATCHTOWER_ROLLING_RESTART=false
      - WATCHTOWER_LOG_LEVEL=info
      - WATCHTOWER_NOTIFICATION_URL=${NOTIFICATION_URL}
    labels:
      - "com.centurylinklabs.watchtower.enable=false"  # Не обновлять сам Watchtower
```

### Cron синтаксис (6 полей)

Формат: `секунды минуты часы день месяц день_недели`

- `0 0 3 * * *` — каждый день в 03:00:00
- `0 0 */6 * * *` — каждые 6 часов
- `0 30 2 * * MON` — каждый понедельник в 02:30

### Фильтрация контейнеров через labels

Чтобы Watchtower обновлял только определённые контейнеры, используйте label:

В `docker-compose.yml` контейнера:
```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"
```

В Watchtower:
```yaml
environment:
  - WATCHTOWER_LABEL_ENABLE=true
```

Теперь Watchtower обновляет только контейнеры с этим label.

### Уведомления

Пример Slack webhook:

```yaml
watchtower_notifications: true
watchtower_notification_url: "slack://token@channel"
watchtower_notification_level: "info"
```

Поддерживаемые сервисы:
- Slack: `slack://token@channel`
- Discord: `discord://token@id`
- Email: `smtp://user:pass@host:port/?from=x&to=y`
- Gotify: `gotify://host/token`
- Telegram: `telegram://token@telegram?channels=channel`

### HTTP API

Включить API для ручного запуска обновлений:

```yaml
watchtower_http_api: true
watchtower_http_api_port: 8080
watchtower_http_api_token: "mysecrettoken"
```

Запуск обновления вручную:
```bash
curl -H "Authorization: Bearer mysecrettoken" http://localhost:8080/v1/update
```

### Rolling Restart

`watchtower_rolling_restart: true` — обновляет контейнеры по одному, дожидаясь запуска предыдущего. Полезно для минимизации downtime в multi-container приложениях.

### Приватные registry

Если образы в приватном registry (GitLab, Harbor, AWS ECR):

```yaml
watchtower_registry_auth: true
watchtower_registry_username: "user"
watchtower_registry_password: "password"
watchtower_registry_url: "registry.example.com"
```

Или используйте Docker credential helpers (предпочтительно):
```bash
docker login registry.example.com
```

Watchtower автоматически использует сохранённые credentials из `~/.docker/config.json`.

### Безопасность

- **Не обновляйте критичные контейнеры автоматически** (базы данных, production) — используйте `monitor_only` или исключите через labels
- **Используйте label фильтрацию** — избегайте обновления всех контейнеров (может сломать зависимости)
- **Тестируйте на staging** перед production
- **Backup перед обновлением** — Watchtower не делает backup данных

### Проверка работы

```bash
# Логи Watchtower
docker logs -f watchtower

# Список контейнеров для обновления (dry-run)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  containrrr/watchtower \
  --run-once --monitor-only

# Статус контейнера
docker ps -f name=watchtower
```

### Альтернативы

- **Renovate Bot** (GitHub/GitLab) — автоматические PR для обновления образов
- **Diun** — только уведомления, без автообновления
- **Kubernetes** — native rolling updates через Deployments

## Tags

- `docker`
- `autodeploy`
- `containers`
- `watchtower`

---

Назад к [[Roadmap]]
