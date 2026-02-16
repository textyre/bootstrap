# Роль: cadvisor

**Phase**: 8 | **Направление**: Мониторинг

## Цель

Разворачивание cAdvisor (Container Advisor) — агента для экспорта метрик Docker контейнеров в формате Prometheus. Предоставляет детальную статистику по CPU, memory, network, disk I/O для каждого контейнера.

## Архитектура

```
┌─────────────────────────────────────┐
│           cAdvisor                  │
│    (Container Metrics Exporter)     │
│                                     │
│  Читает из:                         │
│    /var/run/docker.sock — Docker API│
│    /sys/fs/cgroup/* — cgroups       │
│    /proc/* — процессы               │
│                                     │
│  HTTP endpoint: :8080/metrics       │
└──────────────┬──────────────────────┘
               │
               v (HTTP scrape every 15s)
        ┌──────────────┐
        │  Prometheus  │
        └──────┬───────┘
               │
               v
        ┌──────────────┐
        │   Grafana    │
        └──────────────┘
```

**Экспортируемые метрики (per container):**
- **CPU**: usage (cores), throttling events
- **Memory**: usage, cache, RSS, swap, working set
- **Network**: rx/tx bytes, packets, errors, drops (per interface)
- **Disk**: read/write bytes, ops, latency
- **Filesystem**: usage per container layer

## Ключевые переменные (defaults)

```yaml
cadvisor_enabled: true  # Включить роль

# --- Базовая конфигурация ---
cadvisor_base_dir: "/opt/cadvisor"           # Директория для docker-compose
cadvisor_docker_network: "proxy"             # Docker network (для связи с Prometheus)
cadvisor_docker_image: "gcr.io/cadvisor/cadvisor:latest"  # Docker образ
cadvisor_http_listen_port: 8080              # HTTP metrics port (внутри контейнера)

# --- Сбор метрик ---
cadvisor_housekeeping_interval: "10s"        # Частота обновления метрик
cadvisor_max_housekeeping_interval: "15s"    # Макс интервал между обновлениями
cadvisor_storage_duration: "2m"              # Хранить метрики в памяти 2 минуты

# --- Фильтры (исключить неинтересные контейнеры) ---
cadvisor_disable_metrics: []                 # Список отключенных метрик (disk, network, tcp, udp, sched, process, hugetlb, perf_event, etc)
cadvisor_enable_metrics: []                  # Список включенных метрик (по умолчанию все)

# --- Docker контейнеры ---
cadvisor_docker_only: true                   # Собирать метрики только Docker контейнеров (не systemd units)
cadvisor_docker_root: "/var/lib/docker"      # Путь к Docker storage

# --- Производительность ---
cadvisor_log_level: "info"                   # Уровень логирования (info, warning, error)
```

## Что настраивает

### На всех дистрибутивах

**Структура директорий:**
```
/opt/cadvisor/
└── docker-compose.yml    # Docker Compose конфигурация
```

**Docker контейнеры:**
- `cadvisor` — основной контейнер с cAdvisor
  - Порт: 8080 (HTTP metrics endpoint + Web UI)
  - Volumes:
    - `/:/rootfs:ro` — rootfs для чтения
    - `/var/run:/var/run:ro` — Docker socket (API)
    - `/sys:/sys:ro` — cgroups, hwmon
    - `/var/lib/docker:/var/lib/docker:ro` — Docker storage
    - `/dev/disk:/dev/disk:ro` — disk stats
  - Privileged: `true` (требуется для чтения cgroups v1/v2)
  - Restart policy: `unless-stopped`
  - Health check: `GET /healthz`

**Метрики endpoint:**
- `http://localhost:8080/metrics` — Prometheus-совместимый формат
- `http://localhost:8080/` — Web UI (графики, список контейнеров)

**Пример метрик:**
```
# CPU usage (per container)
container_cpu_usage_seconds_total{name="vaultwarden",image="vaultwarden/server"} 123.45

# Memory usage (per container)
container_memory_usage_bytes{name="vaultwarden"} 134217728
container_memory_working_set_bytes{name="vaultwarden"} 104857600

# Network (per container, per interface)
container_network_receive_bytes_total{name="vaultwarden",interface="eth0"} 12345678
container_network_transmit_bytes_total{name="vaultwarden",interface="eth0"} 87654321

# Disk I/O (per container)
container_fs_reads_bytes_total{name="vaultwarden",device="sda"} 1234567890
container_fs_writes_bytes_total{name="vaultwarden",device="sda"} 9876543210
```

**Сервисы:**
- Docker Compose stack: `cadvisor`

### Arch Linux

**Зависимости:**
- Docker (роль `docker`)

**Примечание:** cAdvisor поддерживает cgroups v2 (используется в Arch Linux с kernel 5.10+).

### Debian/Ubuntu

**Зависимости:**
- Docker (роль `docker`)

**Примечание:** на старых системах с cgroups v1 может потребоваться дополнительная настройка kernel parameters.

## Зависимости

**Обязательные:**
- `docker` — для запуска контейнера + для мониторинга Docker контейнеров

**Используется ролями:**
- `prometheus` — scrape метрики с cAdvisor

## Tags

- `cadvisor`, `monitoring`

---

Назад к [[Roadmap]]
