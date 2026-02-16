# Роль: prometheus

**Phase**: 8 | **Направление**: Мониторинг

## Цель

Разворачивание Prometheus — time-series database для хранения метрик инфраструктуры и приложений. Собирает метрики через HTTP scraping от exporters (node_exporter, cAdvisor), поддерживает PromQL для запросов и алертинг.

## Архитектура

```
┌─────────────────────────────────────────────┐
│                 Prometheus                   │
│            (Metrics Storage)                 │
│                                              │
│  Scrape targets (HTTP pull):                │
│    ┌─ node_exporter:9100  (system metrics)  │
│    ├─ cAdvisor:8080       (Docker metrics)  │
│    └─ prometheus:9090     (self-monitoring) │
│                                              │
│  PromQL: query language для метрик          │
│  Alerting: rules → Alertmanager             │
└──────────────────┬───────────────────────────┘
                   │
                   v
            ┌──────────────┐
            │   Grafana    │ (visualization)
            └──────────────┘
```

**Принцип работы Prometheus:**
- **Pull model**: Prometheus активно scrape-ит HTTP endpoints (не push)
- **Time-series**: хранит метрики как `metric_name{label1="value1"} timestamp value`
- **Label cardinality**: эффективен при низкой cardinality (job, instance, env)
- **Local storage**: TSDB на диске (retention 15-90 дней)

**71% организаций используют Prometheus + OTel вместе:**
- Prometheus: infrastructure metrics (node_exporter, cAdvisor)
- OTel (Alloy → Mimir): application metrics (instrumented apps)

## Ключевые переменные (defaults)

```yaml
prometheus_enabled: true  # Включить роль

# --- Базовая конфигурация ---
prometheus_base_dir: "/opt/prometheus"       # Директория для data + config
prometheus_docker_network: "proxy"           # Docker network
prometheus_docker_image: "prom/prometheus:latest"  # Docker образ
prometheus_http_listen_port: 9090            # HTTP API port (внутри контейнера)

# --- Хранилище ---
prometheus_storage_retention_time: "15d"     # Хранить метрики 15 дней
prometheus_storage_retention_size: "10GB"    # Макс размер TSDB
prometheus_storage_path: "/prometheus"       # Путь внутри контейнера

# --- Scrape конфигурация ---
prometheus_scrape_interval: "15s"            # Частота scraping
prometheus_scrape_timeout: "10s"             # Таймаут для scrape
prometheus_evaluation_interval: "15s"        # Частота проверки alerting rules

# --- Scrape targets ---
prometheus_scrape_node_exporter: true        # Scrape node_exporter
prometheus_scrape_cadvisor: true             # Scrape cAdvisor
prometheus_scrape_self: true                 # Self-monitoring

# --- Endpoints ---
prometheus_node_exporter_endpoint: "node_exporter:9100"  # URL node_exporter
prometheus_cadvisor_endpoint: "cadvisor:8080"            # URL cAdvisor

# --- Alerting (опционально) ---
prometheus_alertmanager_enabled: false       # Включить Alertmanager
prometheus_alertmanager_endpoint: "alertmanager:9093"  # URL Alertmanager
prometheus_alerting_rules_dir: "{{ prometheus_base_dir }}/rules"  # Директория с rules

# --- Производительность ---
prometheus_query_max_concurrency: 20         # Макс одновременных запросов
prometheus_query_timeout: "2m"               # Таймаут для query
prometheus_log_level: "info"                 # Уровень логирования (debug, info, warn, error)
```

## Что настраивает

### На всех дистрибутивах

**Структура директорий:**
```
/opt/prometheus/
├── docker-compose.yml      # Docker Compose конфигурация
├── prometheus.yml          # Prometheus configuration
├── rules/                  # Alerting rules (опционально)
│   └── alerts.yml
└── data/                   # TSDB storage
    ├── chunks/
    ├── wal/                # Write-Ahead Log
    └── queries/            # Query log
```

**Docker контейнеры:**
- `prometheus` — основной контейнер с Prometheus сервером
  - Порт: 9090 (HTTP API + Web UI)
  - Volumes:
    - `/opt/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro`
    - `/opt/prometheus/rules:/etc/prometheus/rules:ro`
    - `/opt/prometheus/data:/prometheus`
  - Command: `--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus --storage.tsdb.retention.time=15d`
  - Restart policy: `unless-stopped`
  - Health check: `GET /-/healthy`

**Конфигурация (prometheus.yml):**
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  # Self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # System metrics
  - job_name: 'node_exporter'
    static_configs:
      - targets: ['node_exporter:9100']

  # Docker metrics
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']
```

**Caddy конфигурация (опционально):**
- `/opt/caddy/sites/prometheus.caddy` — reverse proxy для Web UI
- URL: `https://prometheus.local/`

**Сервисы:**
- Docker Compose stack: `prometheus`

### Arch Linux

**Зависимости:**
- Docker (роль `docker`)

### Debian/Ubuntu

**Зависимости:**
- Docker (роль `docker`)

## Зависимости

**Обязательные:**
- `docker` — для запуска контейнера

**Рекомендуемые (scrape targets):**
- `node_exporter` — системные метрики
- `cadvisor` — Docker метрики

**Опциональные:**
- `caddy` — для reverse proxy (если нужен доступ из браузера)

**Зависит от этой роли:**
- `grafana` — читает метрики из Prometheus через datasource

## Tags

- `prometheus`, `monitoring`

---

Назад к [[Roadmap]]
