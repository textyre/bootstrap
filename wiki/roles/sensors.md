# Роль: sensors

**Phase**: 8 | **Направление**: Мониторинг

## Цель

Настройка lm_sensors для мониторинга температурных датчиков (CPU, GPU, motherboard, диски) и управления вентиляторами через fancontrol. Экспорт метрик для Prometheus через node_exporter (hwmon collector).

## Архитектура

```
┌─────────────────────────────────────────┐
│            lm_sensors                    │
│      (Hardware Monitoring)               │
│                                          │
│  Читает из /sys/class/hwmon/*:          │
│    ┌─ CPU temperature (coretemp)        │
│    ├─ GPU temperature (amdgpu/nvidia)   │
│    ├─ Motherboard sensors (it87, etc)   │
│    └─ Fan speeds (PWM)                  │
│                                          │
│  fancontrol:                             │
│    - Автоматическая регулировка оборотов│
│    - Температурные кривые                │
└──────────────┬──────────────────────────┘
               │
               v
        ┌──────────────┐
        │node_exporter │ (hwmon collector)
        └──────┬───────┘
               │
               v
        ┌──────────────┐
        │  Prometheus  │
        └──────┬───────┘
               │
               v
        ┌──────────────┐
        │   Grafana    │
        └──────────────┘
```

**Что мониторит lm_sensors:**
- **CPU**: температура ядер, Package temperature
- **GPU**: температура, utilization, fan speed
- **Motherboard**: VRM temp, chipset temp, ambient temp
- **Fans**: RPM, PWM duty cycle

## Ключевые переменные (defaults)

```yaml
sensors_enabled: true  # Включить роль

# --- Базовая конфигурация ---
sensors_detect_auto: true  # Автоматическое обнаружение датчиков (sensors-detect)
sensors_modules_autoload: true  # Добавить модули в /etc/modules-load.d/

# --- Fancontrol ---
sensors_fancontrol_enabled: false  # Включить fancontrol (требует ручной настройки!)
sensors_fancontrol_interval: 10    # Интервал проверки (секунды)
sensors_fancontrol_config: "/etc/fancontrol"  # Конфигурация fancontrol

# --- Пороги уведомлений (опционально) ---
sensors_alert_enabled: false       # Включить алерты на высокую температуру
sensors_alert_cpu_threshold: 85    # Температура CPU (°C)
sensors_alert_gpu_threshold: 80    # Температура GPU (°C)
sensors_alert_script: "/usr/local/bin/sensors-alert.sh"

# --- Kernel модули ---
# Автоматически загружаются через sensors-detect, но можно переопределить
sensors_kernel_modules: []
# Примеры:
# sensors_kernel_modules:
#   - coretemp        # Intel CPU temperature
#   - k10temp         # AMD CPU temperature
#   - it87            # ITE IT87xx Super I/O
#   - nct6775         # Nuvoton NCT6775/NCT6776/NCT6779

# --- Экспорт метрик ---
# node_exporter автоматически экспортирует /sys/class/hwmon/* через hwmon collector
sensors_export_to_prometheus: true
```

## Что настраивает

### На всех дистрибутивах

**Файлы конфигурации:**
- `/etc/modules-load.d/sensors.conf` — автозагрузка kernel модулей
- `/etc/fancontrol` — конфигурация fancontrol (если `sensors_fancontrol_enabled: true`)
- `/etc/sensors.d/*.conf` — custom конфигурация lm_sensors (опционально)

**Скрипты:**
- `/usr/local/bin/sensors-alert.sh` — custom alert script (если `sensors_alert_enabled: true`)

**Сервисы:**
- `lm_sensors.service` — загрузка kernel модулей при старте
- `fancontrol.service` — автоматическое управление вентиляторами (если включено)

**Команды для настройки:**
```bash
# Автоматическое обнаружение датчиков (выполняется ролью)
sudo sensors-detect --auto

# Просмотр температур
sensors

# Генерация конфигурации fancontrol (РУЧНАЯ настройка!)
sudo pwmconfig
```

### Arch Linux

**Пакеты:**
- `lm_sensors` — утилиты для работы с hwmon (sensors, sensors-detect)
- `fancontrol` — автоматическое управление вентиляторами (входит в lm_sensors)

**Kernel модули:**
- Большинство модулей встроены в ядро или доступны из `linux` пакета
- AMD: `k10temp` (Ryzen/EPYC), `amdgpu` (GPU)
- Intel: `coretemp` (Core), `i915` (GPU)

### Debian/Ubuntu

**Пакеты:**
- `lm-sensors` — утилиты для работы с hwmon
- `fancontrol` — автоматическое управление вентиляторами (отдельный пакет)

**Kernel модули:**
- Те же, что и на Arch

## Зависимости

**Рекомендуемые:**
- `node_exporter` — для экспорта метрик в Prometheus (hwmon collector)

**Опциональные:**
- `prometheus` + `grafana` — для визуализации температур
- `healthcheck` — для алертов на высокую температуру

## Tags

- `sensors`, `monitoring`, `hardware`

---

Назад к [[Roadmap]]
