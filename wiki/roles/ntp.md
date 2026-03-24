# Роль: ntp

**Phase**: 1 | **Направление**: Система

## Цель

Синхронизация системного времени через NTP протокол с использованием chrony. Обеспечивает точное время на всех узлах для корректной работы логирования, Prometheus метрик, Kubernetes, и криптографических операций. Поддерживает NTS (Network Time Security, RFC 8915) для безопасной синхронизации через незащищённые сети.

## Ключевые переменные (defaults)

```yaml
ntp_enabled: true                       # Включить NTP синхронизацию

# NTP-серверы с поддержкой NTS (Network Time Security)
ntp_servers:
  - { host: "time.cloudflare.com", nts: true, iburst: true }
  - { host: "time.nist.gov", nts: true, iburst: true }
  - { host: "ptbtime1.ptb.de", nts: true, iburst: true }

# Pool-type источники (DNS round-robin)
ntp_pools: []                           # Например: [{host: "pool.ntp.org", iburst: true, maxsources: 4}]

# Коррекция часов при запуске
ntp_makestep_threshold: 1.0             # Прыжок если расхождение > N сек
ntp_makestep_limit: 3                   # Только в первые N обновлений

# Минимум согласующихся источников для обновления часов
ntp_minsources: 2                       # Защита от одиночного испорченного сервера

# Синхронизация аппаратных часов (RTC)
ntp_rtcsync: true

# Логирование
ntp_logchange: 0.5                      # Сообщение если скачок > N секунд
ntp_log_tracking: true                  # Детальные метрики в measurements.log, statistics.log

# NTS cookie cache (ускоряет повторное NTS-рукопожатие)
ntp_ntsdumpdir: "/var/lib/chrony/nts-data"

# Автодетект виртуализации для подстройки под гостевую среду
ntp_auto_detect: true

# Ручная настройка refclocks (переопределяет автодетект)
ntp_refclocks: []

# Отключение конкурирующих NTP-демонов (ntpd, openntpd, systemd-timesyncd)
ntp_disable_competitors: true

# VMware: отключение периодической синхронизации (безопасно для vMotion)
ntp_vmware_disable_periodic_sync: true

# ACL для NTP server mode (раздача времени)
ntp_allow: []                           # Пустой = только клиент, не раздаёт время
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/chrony.conf` (Arch/RedHat/Gentoo/Void) или `/etc/chrony/chrony.conf` (Debian/Ubuntu) — конфигурация chrony
- Сервис: `chronyd.service` (Arch/RedHat/Gentoo/Void) или `chrony.service` (Debian) — enabled + started
- Логи:
  - `/var/log/chrony/measurements.log` — время, дельта, стандартное отклонение каждого источника
  - `/var/log/chrony/statistics.log` — статистика по источникам (RMS, frequency, skew)
  - `/var/log/chrony/tracking.log` — состояние синхронизации и дрейф часов
  - Syslog: события синхронизации, прыжки часов, ошибки подключения
- Отключение конкурентов:
  - `systemd-timesyncd.service` (Debian/Ubuntu/Arch) → disabled
  - `ntpd.service` (RedHat/Gentoo) → disabled, если существует
  - `openntpd.service` → disabled, если существует
- Очистка кэша NTS cookies при переустановке

**Все платформы:**
- Пакет: `chrony`
- Хозяин сервиса: `chrony` (Arch/RedHat/Gentoo/Void) или `_chrony` (Debian/Ubuntu)
- Sysctl параметры: влияние на синхронизацию RTC

## Audit Events

| События | Источник | Формат | Значение |
|---------|----------|--------|----------|
| **Инициализация NTP** | chrony daemon startup | syslog | `chronyd started`, версия chrony, PID |
| **Подключение к источнику** | chrony network phase | syslog | `Selected source <IP>`, RTT, delay |
| **Отключение источника** | chrony network phase | syslog | `No source left`, `Source <IP> unreachable` |
| **Первичная синхронизация** | chrony phase lock | syslog | `System clock was changed`, delta, direction |
| **Скачок часов > threshold** | `ntp_logchange` | syslog + tracking.log | `System clock jumped`, delta (сек), oldtime, newtime |
| **Адаптация частоты** | frequency correction | statistics.log | freq (ppm), skew (ppm) при каждом обновлении |
| **RTC sync** | RTC sync daemon | syslog | `RTC synchronized`, timestamp |
| **Ошибка NTS handshake** | TLS phase | syslog | `NTS-KE server`, error code, reason (cert, timeout, network) |
| **NTS cookie refresh** | TLS phase | nts-data/ | internal cookie rotation |
| **Ошибка демона** | chrony internal | syslog | `stratum too high`, `invalid reply`, network errors |
| **Достижение sync** | tracking.log | plain text | `System time OK`, leap indicator, root delay |
| **Потеря sync** | tracking.log | plain text | `System time unsynchronised`, stratum > 16 |
| **Daemon restart** | systemd | syslog | `chronyd stopped/started` (via systemctl) |

## Мониторинг (Prometheus + Alloy)

### Метрики chrony

Chrony не экспортирует метрики нативно, но предоставляет CLI:

```bash
chronyc tracking    # Состояние синхронизации: stratum, ref_id, sys_time, freq_ppm, skew
chronyc sources     # Список активных источников: tmode, state, sample, freq, reach, last_rx
chronyc sourcestats # Статистика по источникам: mean_offset, std_dev, estimated_error
```

### Alloy pipeline (Prometheus Relay)

```alloy
// Scrape chrony metrics via exec scraper
prometheus.scrape "chrony" {
  targets = [{__address__ = "localhost:9100"}]  // node_exporter с textfile collector

  // Alt: использование custom shell collector
  // targets = [{__address__ = "localhost", __scheme__ = "unix"}]
  // metrics_path = "/var/run/chrony.sock"
}

// Рекомендуемые метрики из chrony (текстовый формат для node_exporter):
// chrony_stratum 2
// chrony_ref_id 216.239.35.0
// chrony_system_time_offset_ms 0.12
// chrony_frequency_ppm -0.045
// chrony_skew_ppm 0.025
// chrony_root_delay_ms 24.3
// chrony_root_dispersion_ms 15.6
// chrony_sources_active 3
// chrony_sources_reachable 3
```

### Prometheus rules (alert rules)

```yaml
groups:
  - name: ntp_monitoring
    interval: 60s
    rules:
      # System time не синхронизирован
      - alert: NTPNotSynchronized
        expr: chrony_stratum > 15  # stratum 16+ = unsync
        for: 5m
        annotations:
          summary: "System time not synchronized (stratum={{ $value }})"
          runbook: "wiki/runbooks/ntp-not-synchronized.md"

      # Слишком большое смещение времени
      - alert: NTPTimeDriftTooLarge
        expr: abs(chrony_system_time_offset_ms) > 500  # > 500ms
        for: 2m
        annotations:
          summary: "NTP offset too large ({{ $value }}ms on {{ $labels.instance }})"
          runbook: "wiki/runbooks/ntp-time-drift.md"

      # Все NTP источники неактивны
      - alert: NTPNoActiveSources
        expr: chrony_sources_active == 0
        for: 1m
        annotations:
          summary: "No active NTP sources on {{ $labels.instance }}"
          runbook: "wiki/runbooks/ntp-no-sources.md"

      # Недостаточно согласующихся источников
      - alert: NTPTooFewSources
        expr: chrony_sources_reachable < 2
        for: 3m
        annotations:
          summary: "Only {{ $value }} reachable NTP sources (need >= 2)"
          runbook: "wiki/runbooks/ntp-few-sources.md"

      # Высокий jitter/skew (нестабильная синхронизация)
      - alert: NTPHighSkew
        expr: chrony_skew_ppm > 100
        for: 10m
        annotations:
          summary: "High NTP skew: {{ $value }} ppm"
          runbook: "wiki/runbooks/ntp-high-skew.md"

      # Ошибка NTS (Network Time Security)
      - alert: NTSAuthenticationFailure
        expr: rate(chrony_nts_auth_errors[5m]) > 0
        for: 5m
        annotations:
          summary: "NTS authentication failures detected"
          runbook: "wiki/runbooks/ntp-nts-failure.md"
```

### Grafana dashboard

Рекомендуемые панели:
- **Stratum**: текущее значение + график тренда (алерт при >15)
- **System Time Offset**: смещение в мс, диапазон ±500ms
- **Frequency Correction**: ppm (parts per million), обычно ±100ppm
- **Root Delay/Dispersion**: время в пути до корневого сервера
- **Active Sources**: gauge с целевым значением (обычно 2-4)
- **Reachability**: % достижимых источников (должно быть 100%)
- **Clock Jumps**: счётчик `ntp_logchange` событий за период
- **NTS Status**: статус каждого NTS-сервера (reachable/unreachable)

## Зависимости

- `base_system` — базовая система (systemd, syslog)
- `firewall` (опционально) — если нужна раздача времени (ntp_allow не пусто)
- `journald` (рекомендуется) — централизованное логирование

**Рекомендуется размещение:** Phase 1 (до любых других ролей, т.к. время критично для логирования, метрик, сертификатов)

## Tags

- `ntp`, `chrony`, `time`, `system`, `monitoring`

---

Назад к [[Roadmap]]
