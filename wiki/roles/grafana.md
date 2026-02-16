# Роль: grafana

**Phase**: 8 | **Направление**: Логирование + Мониторинг

## Цель

Разворачивание Grafana — единого UI для визуализации логов (Loki) и метрик (Prometheus). Предоставляет дашборды, алертинг, Explore для ad-hoc запросов (LogQL, PromQL).

## Архитектура

```
┌─────────────────────────────────────────────┐
│                  Grafana                     │
│              (Unified UI)                    │
│                                              │
│  ┌──────────────┐      ┌──────────────┐     │
│  │ Loki         │      │ Prometheus   │     │
│  │ Datasource   │      │ Datasource   │     │
│  └──────┬───────┘      └──────┬───────┘     │
│         │                     │              │
│         v                     v              │
│  ┌──────────────┐      ┌──────────────┐     │
│  │ Logs         │      │ Metrics      │     │
│  │ Dashboard    │      │ Dashboard    │     │
│  └──────────────┘      └──────────────┘     │
│                                              │
│  Explore: LogQL + PromQL queries             │
│  Alerting: Rules → Notification channels     │
└─────────────────────────────────────────────┘
         │                     │
         v                     v
    ┌─────────┐          ┌─────────────┐
    │  Loki   │          │ Prometheus  │
    └─────────┘          └─────────────┘
         ^                     ^
         │                     │
    (Alloy)              (node_exporter,
                          cAdvisor)
```

**Grafana объединяет:**
- **Логи**: Loki datasource → LogQL → log panels, log browser
- **Метрики**: Prometheus datasource → PromQL → time series, gauges, tables

## Ключевые переменные (defaults)

```yaml
grafana_enabled: true  # Включить роль

# --- Базовая конфигурация ---
grafana_base_dir: "/opt/grafana"           # Директория для data + config
grafana_docker_network: "proxy"            # Docker network (совместно с Caddy)
grafana_docker_image: "grafana/grafana:latest"  # Docker образ
grafana_http_listen_port: 3000             # HTTP port (внутри контейнера)
grafana_domain: "grafana.local"            # Домен для Caddy reverse proxy

# --- Аутентификация ---
grafana_admin_user: "admin"                # Логин администратора
grafana_admin_password: "{{ vault_grafana_admin_password | default('admin') }}"  # Пароль (из vault)
grafana_allow_sign_up: false               # Запретить регистрацию новых пользователей
grafana_anonymous_enabled: false           # Анонимный доступ (read-only)

# --- Datasources (автоматическая настройка) ---
grafana_datasource_loki_enabled: true      # Подключить Loki datasource
grafana_datasource_loki_url: "http://loki:3100"  # URL Loki (internal Docker network)

grafana_datasource_prometheus_enabled: true  # Подключить Prometheus datasource
grafana_datasource_prometheus_url: "http://prometheus:9090"  # URL Prometheus

# --- Dashboards ---
grafana_dashboards_provisioning: true      # Автоматически загружать дашборды из JSON
grafana_dashboards_dir: "{{ grafana_base_dir }}/dashboards"  # Директория с JSON

# --- Alerting ---
grafana_alerting_enabled: true             # Включить Grafana Unified Alerting
grafana_smtp_enabled: false                # Email уведомления (настроить при необходимости)
grafana_smtp_host: ""
grafana_smtp_user: ""
grafana_smtp_password: ""

# --- Plugins ---
grafana_plugins: []                        # Список плагинов для установки (например: grafana-piechart-panel)

# --- Производительность ---
grafana_log_level: "info"                  # Уровень логирования (debug, info, warn, error)
grafana_data_retention_days: 30            # Хранить dashboard snapshots 30 дней
```

## Что настраивает

### На всех дистрибутивах

**Структура директорий:**
```
/opt/grafana/
├── docker-compose.yml          # Docker Compose конфигурация
├── grafana.ini                 # Grafana configuration file
├── provisioning/               # Auto-provisioning
│   ├── datasources/
│   │   ├── loki.yml            # Loki datasource
│   │   └── prometheus.yml      # Prometheus datasource
│   └── dashboards/
│       └── default.yml         # Dashboard provider
├── dashboards/                 # JSON дашборды
│   ├── logs-overview.json
│   └── system-metrics.json
└── data/                       # SQLite DB, sessions, plugins
```

**Docker контейнеры:**
- `grafana` — основной контейнер с Grafana сервером
  - Порт: 3000 (HTTP UI)
  - Volumes:
    - `/opt/grafana/data:/var/lib/grafana`
    - `/opt/grafana/provisioning:/etc/grafana/provisioning:ro`
    - `/opt/grafana/dashboards:/var/lib/grafana/dashboards:ro`
    - `/opt/grafana/grafana.ini:/etc/grafana/grafana.ini:ro`
  - Restart policy: `unless-stopped`
  - Health check: `GET /api/health`

**Caddy конфигурация:**
- `/opt/caddy/sites/grafana.caddy` — reverse proxy для HTTPS доступа
- URL: `https://grafana.local/`

**DNS (локальный доступ):**
- `/etc/hosts`: `127.0.0.1 grafana.local`

**Сервисы:**
- Docker Compose stack: `grafana`

### Arch Linux

**Зависимости:**
- Docker (роль `docker`)
- Caddy (роль `caddy`)

### Debian/Ubuntu

**Зависимости:**
- Docker (роль `docker`)
- Caddy (роль `caddy`)

## Зависимости

**Обязательные:**
- `docker` — для запуска контейнера
- `caddy` — для HTTPS reverse proxy

**Опциональные (datasources):**
- `loki` — для логов
- `prometheus` — для метрик

**Зависит от этой роли:**
- Нет (Grafana — конечная точка UI)

## Tags

- `grafana`, `logging`, `monitoring`, `observability`

---

Назад к [[Roadmap]]
