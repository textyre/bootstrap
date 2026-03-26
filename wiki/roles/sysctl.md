# Роль: sysctl

**Phase**: 1 | **Направление**: Система

## Цель

Настройка параметров ядра Linux через `/etc/sysctl.d/99-z-ansible.conf` для трёх целей: hardening ядра (ASLR, ptrace, eBPF), уменьшение сетевой attack surface (ARP, ICMP, rp_filter, IPv6), оптимизация производительности рабочей станции (swappiness, inotify, somaxconn). Параметры применяются distribution-agnostic через `sysctl -e --system`.

## Ключевые переменные (defaults)

```yaml
sysctl_security_enabled: true                    # Мастер-переключатель всех security параметров
sysctl_security_kernel_hardening: true           # Kernel: ASLR, kptr_restrict, eBPF, ptrace
sysctl_security_network_hardening: true          # Network: ARP, ICMP, TCP, rp_filter, IPv6
sysctl_security_filesystem_hardening: true       # FS: hardlink/symlink/FIFO/SUID protection
sysctl_security_ipv6_disable: false              # Полностью отключить IPv6 (осторожно!)

sysctl_vm_swappiness: 10                         # Агрессивность swap
sysctl_fs_inotify_max_user_watches: 524288       # Для IDE и file watchers
sysctl_net_core_somaxconn: 4096                  # TCP backlog
sysctl_kernel_yama_ptrace_scope: 1               # Profile-aware: gaming=0, dev=1, security=2

sysctl_custom_params: []                         # Дополнительные параметры [{name, value}]
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/sysctl.d/99-z-ansible.conf` -- drop-in конфигурация, загружается при boot через `systemd-sysctl.service`
- Сервисы:
  - `apport.service` (Ubuntu) -- disabled, если `fs.suid_dumpable != 2` (apport перезаписывает значение после boot)
- Пакеты:
  - `procps-ng` (Arch/Void/Gentoo) или `procps` (Debian/RedHat) -- утилиты sysctl

**Все платформы:** Archlinux, Debian, RedHat, Void, Gentoo

## Audit Events

| Событие | Источник | Severity | Threshold |
|---------|----------|----------|-----------|
| sysctl parameter mismatch after boot | `sysctl -n` vs config file | CRITICAL | any deviation from expected value |
| ASLR disabled (`randomize_va_space != 2`) | `/proc/sys/kernel/randomize_va_space` | CRITICAL | value < 2 |
| ptrace scope relaxed (`ptrace_scope = 0`) | `/proc/sys/kernel/yama/ptrace_scope` | WARNING | value = 0 on non-gaming profile |
| SYN cookies disabled | `/proc/sys/net/ipv4/tcp_syncookies` | CRITICAL | value = 0 |
| Reverse path filter disabled | `/proc/sys/net/ipv4/conf/all/rp_filter` | WARNING | value = 0 |
| ICMP redirects accepted | `/proc/sys/net/ipv4/conf/all/accept_redirects` | WARNING | value != 0 |
| Core dump of SUID allowed | `/proc/sys/fs/suid_dumpable` | WARNING | value > 0 |
| apport re-enabled after role apply | `systemctl is-enabled apport` | WARNING | enabled on Debian with suid_dumpable hardening |
| Config file tampered | `stat /etc/sysctl.d/99-z-ansible.conf` | CRITICAL | mode != 0644, owner != root |
| Another sysctl.d file overrides values | `sysctl --system` output | WARNING | file sorting after 99-z-ansible.conf |

## Monitoring Integration

- **Drift detection**: re-run role with `--tags sysctl,verify` -- compares live values to expected
- **node_exporter textfile**: export key sysctl values via textfile collector for Prometheus
- **Prometheus metric (proposed)**: `sysctl_param_value{param="kernel.randomize_va_space"}` via custom collector
- **Alert rule (proposed)**: `SysctlDrift` -- fires when live value differs from config for > 5m after boot

### Рекомендуемые Prometheus alerts

```yaml
groups:
  - name: sysctl_monitoring
    interval: 300s
    rules:
      - alert: SysctlASLRDisabled
        expr: sysctl_param_value{param="kernel.randomize_va_space"} < 2
        for: 5m
        annotations:
          summary: "ASLR disabled on {{ $labels.instance }}"
          runbook: "wiki/runbooks/sysctl-aslr.md"

      - alert: SysctlSynCookiesDisabled
        expr: sysctl_param_value{param="net.ipv4.tcp_syncookies"} == 0
        for: 5m
        annotations:
          summary: "SYN cookies disabled on {{ $labels.instance }}"
```

## Зависимости

- Нет зависимостей (`meta/main.yml: dependencies: []`)
- `common` (для report_phase/report_render) -- включается через `include_role`

**Рекомендуется размещение:** Phase 1 (kernel параметры критичны для безопасности всех последующих ролей)

## Tags

- `sysctl` -- все задачи
- `sysctl`, `packages` -- только установка пакетов
- `sysctl`, `configure` -- только деплой конфигурации
- `sysctl`, `verify` -- только проверка live значений
- `sysctl`, `services` -- управление сервисами (apport)
- `sysctl`, `report` -- execution report

---

Назад к [[Roadmap]]
