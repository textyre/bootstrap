# Роль: power_management

**Phase**: 1 | **Направление**: Система

## Цель

Управление энергопотреблением рабочей станции: TLP для ноутбуков (CPU governor, disk, USB, PCIe, WiFi, battery thresholds), CPU governor для десктопов (udev persistence), systemd sleep/hibernate, logind power actions (lid switch, power key, idle). Автоматическое определение laptop/desktop через DMI chassis_type.

## Ключевые переменные (defaults)

```yaml
power_management_enabled: true                          # Мастер-переключатель роли
power_management_manage_tlp: true                       # TLP (ноутбук): CPU, disk, USB, PCIe, WiFi
power_management_manage_governor: true                  # CPU governor (десктоп)
power_management_manage_sleep: true                     # systemd sleep.conf
power_management_manage_logind: true                    # systemd logind.conf

power_management_device_type: auto                      # auto | laptop | desktop
power_management_cpu_governor: schedutil                # Десктоп; gaming profile -> performance

power_management_tlp_cpu_governor_ac: schedutil         # TLP: сбалансированный governor на AC
power_management_tlp_cpu_governor_bat: schedutil        # TLP: сбалансированный governor на батарее
power_management_tlp_bat0_charge_start: ""              # ThinkPad/Dell: порог начала зарядки
power_management_tlp_bat0_charge_stop: ""               # ThinkPad/Dell: порог остановки зарядки

power_management_hibernate_mode: ""                     # systemd sleep override; empty = default
power_management_lid_switch_action: suspend              # logind: suspend, hibernate, poweroff, ignore
power_management_power_key_action: poweroff             # logind: действие по нажатию power key
power_management_idle_action: ignore                    # logind: действие при idle
power_management_idle_action_sec: "30min"               # logind: таймаут idle

```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/tlp.conf` -- конфигурация TLP, когда роль управляет TLP на ноутбуке
  - `/etc/systemd/sleep.conf` -- режимы hibernate/suspend, когда включен systemd sleep
  - `/etc/systemd/logind.conf` -- действия lid switch, power key, idle, когда включен systemd logind
  - `/etc/udev/rules.d/50-cpu-governor.rules` -- persistence CPU governor на десктопе через udev
- Сервисы:
  - `tlp.service` -- управление энергопотреблением ноутбука
  - `systemd-logind` -- reload при изменении logind.conf, если сервис присутствует
- Пакеты:
  - `tlp` и distro-specific TLP packages -- через `vars/<os_family>/main.yml`, только для laptop path

**Все платформы:** Archlinux, Debian, RedHat, Void, Gentoo

На non-systemd init (`runit`, `openrc`, `s6`, `dinit`) systemd sleep/logind
задачи пропускаются, потому что их файлы и сервисы принадлежат systemd.
Desktop CPU governor persistence настраивается через udev rule.

## Monitoring Integration

- Мониторинг состояния питания и сравнение состояния между запусками вынесены из контракта роли и должны проектироваться отдельно: https://github.com/textyre/bootstrap/issues/384

## Зависимости

- Нет зависимостей (`meta/main.yml: dependencies: []`)
- `common` (для report_phase/report_render) -- включается через `include_role`

## Tags

- `power` -- полный поток роли

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
