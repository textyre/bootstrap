# Роль: alloy

**Phase**: 8 | **Направление**: Логирование

## Цель

Разворачивание Grafana Alloy — vendor-neutral дистрибуции OpenTelemetry Collector (100% OTLP совместимый, 120+ компонентов). Текущая задача: сбор логов из journald и отправка в Loki. Будущее: traces → Tempo, app metrics → Mimir без изменения инфраструктуры.

## Архитектура

```
┌─────────────────────────────────────────────────────────┐
│                      Grafana Alloy                       │
│              (OpenTelemetry Collector)                   │
│                                                           │
│  Текущее использование (Логи):                           │
│    journald → loki.source.journal → loki.write → Loki    │
│                                                           │
│  Будущий путь (без изменения инфраструктуры):           │
│    ┌─ traces → otelcol.receiver.otlp → Tempo             │
│    ├─ app metrics → otelcol.receiver.otlp → Mimir        │
│    └─ logs → loki.source.journal → Loki                  │
└─────────────────────────────────────────────────────────┘
```

**Что такое Grafana Alloy:**
- **100% OpenTelemetry**: полная OTLP совместимость (traces, metrics, logs)
- **120+ компонентов**: receivers, processors, exporters для различных источников
- **Vendor-neutral**: можно отправлять в Tempo, Mimir, Loki, Prometheus, Jaeger, Zipkin
- **Единая точка сбора**: все сигналы (logs, traces, metrics) через один агент

**71% организаций используют Prometheus + OTel вместе** (complementary, не competitive):
- Prometheus: infrastructure metrics (node_exporter, cAdvisor)
- OTel: application metrics (instrumented apps)

## Ключевые переменные (defaults)

```yaml
alloy_enabled: true  # Включить роль

# --- Базовая конфигурация ---
alloy_base_dir: "/opt/alloy"         # Директория для конфигурации
alloy_docker_network: "proxy"        # Docker network
alloy_docker_image: "grafana/alloy:latest"  # Docker образ
alloy_http_listen_port: 12345        # HTTP API port (метрики, health)
alloy_otlp_grpc_port: 4317           # OTLP gRPC receiver (для traces/metrics в будущем)
alloy_otlp_http_port: 4318           # OTLP HTTP receiver

# --- Journald Source (логи) ---
alloy_journald_enabled: true         # Читать логи из journald
alloy_journald_path: "/var/log/journal"  # Путь к journald storage
alloy_journald_matches: []           # Фильтры journald (например: _SYSTEMD_UNIT=docker.service)

# --- Loki Destination (логи) ---
alloy_loki_endpoint: "http://loki:3100/loki/api/v1/push"  # URL Loki
alloy_loki_tenant_id: ""             # Multi-tenancy (оставить пустым для single-tenant)

# --- Future: Tempo (traces) ---
alloy_tempo_enabled: false           # Включить OTLP receiver для traces (будущее)
alloy_tempo_endpoint: "http://tempo:4317"  # Tempo gRPC endpoint

# --- Future: Mimir (app metrics) ---
alloy_mimir_enabled: false           # Включить OTLP receiver для метрик (будущее)
alloy_mimir_endpoint: "http://mimir:9009/otlp/v1/metrics"  # Mimir OTLP endpoint

# --- Производительность ---
alloy_log_level: "info"              # Уровень логирования (debug, info, warn, error)
alloy_batch_size: 1024               # Размер батча перед отправкой
alloy_batch_timeout: "1s"            # Таймаут батча
```

## Что настраивает

### На всех дистрибутивах

**Структура директорий:**
```
/opt/alloy/
├── docker-compose.yml    # Docker Compose конфигурация
├── config.alloy          # Alloy River configuration (HCL-like DSL)
└── data/                 # WAL для надежной доставки
```

**Docker контейнеры:**
- `alloy` — основной контейнер с Grafana Alloy
  - Порты:
    - 12345 — HTTP API (метрики, health)
    - 4317 — OTLP gRPC (traces/metrics, future)
    - 4318 — OTLP HTTP (traces/metrics, future)
  - Volumes:
    - `/opt/alloy/config.alloy:/etc/alloy/config.alloy:ro`
    - `/var/log/journal:/var/log/journal:ro` — читает journald
    - `/opt/alloy/data:/data` — WAL
  - Privileged: `true` (требуется для чтения journald)
  - Restart policy: `unless-stopped`

**Конфигурация (config.alloy):**
```hcl
// Текущее: логи из journald → Loki
loki.source.journal "default" {
  path = "/var/log/journal"
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}

// Будущее (закомментировано): OTLP receiver для traces → Tempo
// otelcol.receiver.otlp "default" {
//   grpc { endpoint = "0.0.0.0:4317" }
//   http { endpoint = "0.0.0.0:4318" }
//   output {
//     traces = [otelcol.exporter.otlp.tempo.input]
//     metrics = [otelcol.exporter.otlp.mimir.input]
//   }
// }
```

**Сервисы:**
- Docker Compose stack: `alloy`

### Arch Linux

**Зависимости:**
- Docker (роль `docker`)

### Debian/Ubuntu

**Зависимости:**
- Docker (роль `docker`)

## Зависимости

**Обязательные:**
- `docker` — для запуска контейнера
- `journald` — источник логов

**Опциональные:**
- `loki` — destination для логов

**Зависит от этой роли:**
- `grafana` — использует Loki (который получает данные от Alloy)

## Tags

- `alloy`, `logging`, `otel`, `observability`

---

Назад к [[Roadmap]]
