# Роль: loki

**Phase**: 8 | **Направление**: Логирование

## Цель

Разворачивание Grafana Loki — высокопроизводительного хранилища логов с label-based индексацией и поддержкой LogQL. Loki хранит логи от Alloy и предоставляет API для запросов из Grafana.

## Архитектура

```
Docker → journald → Alloy → Loki (эта роль) → Grafana
```

**Принцип работы Loki:**
- Индексирует только метаданные (labels), не содержимое логов
- Хранит сырые логи в chunks (по умолчанию: filesystem)
- Поддерживает LogQL — язык запросов, похожий на PromQL
- Label cardinality: низкая (job, instance, level), не высокая (user_id, trace_id)

**Интеграция:**
- Получает логи от Alloy через Loki HTTP API (`/loki/api/v1/push`)
- Отдает логи Grafana через Loki Query API (`/loki/api/v1/query_range`)

## Ключевые переменные (defaults)

```yaml
loki_enabled: true  # Включить роль

# --- Базовая конфигурация ---
loki_base_dir: "/opt/loki"           # Директория для data + config
loki_docker_network: "proxy"         # Docker network (совместно с Caddy)
loki_docker_image: "grafana/loki:latest"  # Docker образ
loki_http_listen_port: 3100          # HTTP API port (внутри контейнера)

# --- Хранилище ---
loki_retention_enabled: true         # Включить автоматическое удаление старых логов
loki_retention_period: "720h"        # Хранить логи 30 дней (720h)
loki_storage_path: "/loki/data"      # Путь внутри контейнера

# --- Производительность ---
loki_chunk_idle_period: "1h"         # Период неактивности перед flush chunk
loki_chunk_retain_period: "30s"      # Задержка перед удалением chunk из памяти
loki_max_chunk_age: "2h"             # Максимальный возраст chunk

# --- Лимиты (защита от abuse) ---
loki_ingestion_rate_mb: 10           # Макс скорость приема логов (MB/s на tenant)
loki_ingestion_burst_size_mb: 20     # Burst size (MB)
loki_max_query_length: "721h"        # Макс диапазон времени для запроса (30 дней + 1 час)
loki_max_query_series: 500           # Макс серий в одном запросе

# --- Compactor (сжатие и retention) ---
loki_compactor_enabled: true         # Включить compactor
loki_compactor_retention_delete_worker_count: 150  # Параллельные потоки удаления
```

## Что настраивает

### На всех дистрибутивах

**Структура директорий:**
```
/opt/loki/
├── docker-compose.yml    # Docker Compose конфигурация
├── loki-config.yml       # Loki configuration file
└── data/                 # Chunks и индексы
    ├── chunks/
    ├── index/
    └── wal/              # Write-Ahead Log
```

**Docker контейнеры:**
- `loki` — основной контейнер с Loki сервером
  - Порт: 3100 (HTTP API)
  - Volumes: `/opt/loki/data:/loki/data`
  - Restart policy: `unless-stopped`
  - Health check: `GET /ready`

**Caddy конфигурация:**
- `/opt/caddy/sites/loki.caddy` — reverse proxy для доступа из браузера (опционально)
- URL: `https://loki.local/` (если включен Caddy)

**Сервисы:**
- Docker Compose stack: `loki`

### Arch Linux

**Зависимости:**
- Docker (роль `docker`)
- Caddy (роль `caddy`, опционально для внешнего доступа)

### Debian/Ubuntu

**Зависимости:**
- Docker (роль `docker`)
- Caddy (роль `caddy`, опционально для внешнего доступа)

## Зависимости

**Обязательные:**
- `docker` — для запуска контейнера

**Опциональные:**
- `caddy` — для reverse proxy (если нужен доступ из браузера)
- `alloy` — источник логов (Alloy → Loki)

**Зависит от этой роли:**
- `grafana` — читает логи из Loki через datasource

## Tags

- `loki`, `logging`

---

Назад к [[Roadmap]]
