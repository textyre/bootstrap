# Роль: node_exporter

**Phase**: 8 | **Направление**: Мониторинг

## Цель

Разворачивание Prometheus Node Exporter — агента для экспорта системных метрик (CPU, RAM, disk, network, filesystem) в формате Prometheus. Является основным источником метрик инфраструктуры.

## Архитектура

```
┌─────────────────────────────────────┐
│         node_exporter               │
│     (System Metrics Exporter)       │
│                                     │
│  Читает из:                         │
│    /proc/* — CPU, memory, network   │
│    /sys/* — disk I/O, temperature   │
│    /sys/class/hwmon/* — sensors     │
│                                     │
│  HTTP endpoint: :9100/metrics       │
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

**Экспортируемые метрики:**
- **CPU**: usage, load average, context switches, interrupts
- **Memory**: total, free, used, buffers, cache, swap
- **Disk**: I/O, read/write bytes/ops, latency, queue depth
- **Network**: packets, bytes, errors, drops per interface
- **Filesystem**: size, used, free, inodes per mount point
- **Temperature**: hwmon sensors (если доступны)

## Ключевые переменные (defaults)

```yaml
node_exporter_enabled: true  # Включить роль

# --- Базовая конфигурация ---
node_exporter_base_dir: "/opt/node_exporter"  # Директория для systemd service
node_exporter_docker_network: "proxy"         # Docker network (для связи с Prometheus)
node_exporter_docker_image: "prom/node-exporter:latest"  # Docker образ
node_exporter_http_listen_port: 9100          # HTTP metrics port

# --- Collectors (какие метрики собирать) ---
node_exporter_enabled_collectors:
  - cpu         # CPU usage
  - diskstats   # Disk I/O
  - filesystem  # Filesystem usage
  - loadavg     # Load average
  - meminfo     # Memory usage
  - netdev      # Network interfaces
  - netstat     # Network statistics
  - stat        # System stats (context switches, interrupts)
  - time        # System time
  - uname       # System info
  - vmstat      # Virtual memory stats
  - hwmon       # Hardware monitoring (температура, вентиляторы)

node_exporter_disabled_collectors:
  - arp         # ARP tables (много cardinality)
  - bcache      # Bcache stats (если не используется)
  - bonding     # Bonding (если нет)
  - btrfs       # Btrfs stats (если не используется)
  - ipvs        # IPVS stats (если не используется)
  - mdadm       # Software RAID (если нет)
  - nfs         # NFS stats (если не используется)
  - zfs         # ZFS stats (если не используется)

# --- Filesystem filters ---
node_exporter_filesystem_ignored_mount_points: "^/(dev|proc|sys|var/lib/docker/.+|run/docker/netns/.+)($|/)"
node_exporter_filesystem_ignored_fs_types: "^(autofs|binfmt_misc|cgroup|configfs|debugfs|devpts|devtmpfs|fusectl|hugetlbfs|mqueue|overlay|proc|procfs|pstore|rpc_pipefs|securityfs|sysfs|tracefs)$"

# --- Производительность ---
node_exporter_log_level: "info"  # Уровень логирования (debug, info, warn, error)
```

## Что настраивает

### На всех дистрибутивах

**Структура директорий:**
```
/opt/node_exporter/
└── docker-compose.yml    # Docker Compose конфигурация
```

**Docker контейнеры:**
- `node_exporter` — основной контейнер с Node Exporter
  - Порт: 9100 (HTTP metrics endpoint)
  - Volumes:
    - `/proc:/host/proc:ro` — читает CPU, memory, network
    - `/sys:/host/sys:ro` — читает disk I/O, hwmon
    - `/:/rootfs:ro` — читает filesystem usage
  - Command: `--path.procfs=/host/proc --path.sysfs=/host/sys --path.rootfs=/rootfs`
  - Network mode: `host` (для корректных network metrics)
  - Restart policy: `unless-stopped`

**Метрики endpoint:**
- `http://localhost:9100/metrics` — Prometheus-совместимый формат

**Пример метрик:**
```
# CPU
node_cpu_seconds_total{cpu="0",mode="idle"} 12345.67

# Memory
node_memory_MemTotal_bytes 16777216000
node_memory_MemAvailable_bytes 8388608000

# Disk
node_disk_read_bytes_total{device="sda"} 1234567890
node_disk_write_bytes_total{device="sda"} 9876543210

# Network
node_network_receive_bytes_total{device="eth0"} 123456789
node_network_transmit_bytes_total{device="eth0"} 987654321
```

**Сервисы:**
- Docker Compose stack: `node_exporter`

### Arch Linux

**Зависимости:**
- Docker (роль `docker`)

**Альтернатива:** можно установить через systemd service (без Docker), но Docker-вариант удобнее для управления.

### Debian/Ubuntu

**Зависимости:**
- Docker (роль `docker`)

**Альтернатива:** пакет `prometheus-node-exporter` из apt (но Docker-вариант предпочтительнее).

## Зависимости

**Обязательные:**
- `docker` — для запуска контейнера

**Используется ролями:**
- `prometheus` — scrape метрики с node_exporter

## Tags

- `node_exporter`, `monitoring`

---

Назад к [[Roadmap]]
