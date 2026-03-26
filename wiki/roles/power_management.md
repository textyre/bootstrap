# Роль: power_management

**Phase**: 1 | **Направление**: Система

## Цель

Управление энергопотреблением рабочей станции: TLP для ноутбуков (CPU governor, disk, USB, PCIe, WiFi, battery thresholds), CPU governor для десктопов (udev/service persistence), systemd sleep/hibernate, logind power actions (lid switch, power key, idle). Автоматическое определение laptop/desktop через DMI chassis_type.

## Ключевые переменные (defaults)

```yaml
power_management_enabled: true                          # Мастер-переключатель роли
power_management_manage_tlp: true                       # TLP (ноутбук): CPU, disk, USB, PCIe, WiFi
power_management_manage_governor: true                  # CPU governor (десктоп)
power_management_manage_sleep: true                     # systemd sleep.conf
power_management_manage_logind: true                    # systemd logind.conf
power_management_manage_audit: true                     # Audit monitoring

power_management_device_type: auto                      # auto | laptop | desktop
power_management_cpu_governor: schedutil                # Десктоп: performance, powersave, schedutil, ondemand, conservative
power_management_governor_persist: udev                 # udev | service | oneshot

power_management_tlp_cpu_governor_ac: performance       # TLP: governor на AC
power_management_tlp_cpu_governor_bat: powersave        # TLP: governor на батарее
power_management_tlp_bat0_charge_start: ""              # ThinkPad/Dell: порог начала зарядки
power_management_tlp_bat0_charge_stop: ""               # ThinkPad/Dell: порог остановки зарядки

power_management_hibernate_mode: platform               # systemd sleep: platform, shutdown, reboot
power_management_lid_switch_action: suspend              # logind: suspend, hibernate, poweroff, ignore
power_management_power_key_action: poweroff             # logind: действие по нажатию power key
power_management_idle_action: ignore                    # logind: действие при idle
power_management_idle_action_sec: "30min"               # logind: таймаут idle

power_management_audit_enabled: true                    # Audit мониторинг
power_management_audit_schedule: "daily"                # Расписание аудита
power_management_drift_detection: true                  # Обнаружение дрифта конфигурации
power_management_drift_state_dir: /var/lib/ansible-power-management  # Директория состояния

power_management_assert_strict: true                    # Строгие проверки в verify.yml
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/tlp.conf` -- конфигурация TLP (ноутбук)
  - `/etc/systemd/sleep.conf` -- режимы hibernate/suspend (systemd)
  - `/etc/systemd/logind.conf` -- действия lid switch, power key, idle (systemd)
  - `/etc/udev/rules.d/50-cpu-governor.rules` -- persistence CPU governor (десктоп, udev)
  - `/etc/systemd/system/cpupower.service.d/override.conf` -- persistence CPU governor (десктоп, service)
- Сервисы:
  - `tlp.service` -- управление энергопотреблением ноутбука
  - `power-profiles-daemon.service` -- masked (конфликтует с TLP)
  - `systemd-logind` -- reload при изменении logind.conf
- Пакеты:
  - `tlp`, `cpupower` и другие -- через vars/ per distro family

**Все платформы:** Archlinux, Debian, RedHat, Void, Gentoo

## Audit Events

| Событие | Источник | Severity | Threshold |
|---------|----------|----------|-----------|
| CPU governor drift | `/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` | CRITICAL | value != configured governor |
| TLP not running on laptop | `tlp-stat -s` | CRITICAL | TLP service not active |
| power-profiles-daemon not masked | `systemctl status power-profiles-daemon` | WARNING | status != masked on laptop with TLP |
| Battery charge threshold not applied | `/sys/class/power_supply/BAT0/charge_control_start_threshold` | WARNING | value != configured threshold |
| sleep.conf HibernateMode drift | `/etc/systemd/sleep.conf` | WARNING | HibernateMode != configured value |
| logind HandleLidSwitch drift | `/etc/systemd/logind.conf` | WARNING | HandleLidSwitch != configured value |
| Battery wear level high | `tlp-stat -b` | WARNING | wear > power_management_audit_battery_wear_threshold (20%) |

## Monitoring Integration

- **Drift detection**: re-run role with `--tags power,verify` -- сравнивает live значения с ожидаемыми
- **Audit timer**: `power-audit.timer` (systemd) или cron -- проверяет governor, TLP status, battery wear
- **Prometheus metric (proposed)**: `power_cpu_governor{cpu="cpu0"}`, `power_battery_capacity`, `power_battery_wear_level`
- **Alert rule (proposed)**: `PowerGovernorDrift` -- fires when live governor differs from configured

## Зависимости

- Нет зависимостей (`meta/main.yml: dependencies: []`)
- `common` (для report_phase/report_render) -- включается через `include_role`

## Tags

- `power` -- все задачи роли
- `power`, `cpu` -- CPU governor (десктоп)
- `power`, `facts` -- сбор системных фактов
- `power`, `assert` -- проверка эффективности деплоя
- `power`, `audit` -- audit monitoring
- `power`, `report` -- execution report

## Пример использования

```yaml
# playbook.yml
- hosts: workstations
  roles:
    - role: power_management
      vars:
        power_management_cpu_governor: performance
        power_management_lid_switch_action: hibernate
```

---

Назад к [[Roadmap]]
