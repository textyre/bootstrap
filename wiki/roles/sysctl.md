# Роль: sysctl

**Phase**: 1 | **Направление**: Система

## Цель

Роль задает workstation kernel policy через `/etc/sysctl.d/99-z-ansible.conf`.

Это не generic sysctl writer. Роль отвечает за конкретный baseline: Linux workstation должна быть жестче distro-defaults по kernel/network/filesystem controls, но не ломать обычные сценарии разработки, desktop, gaming, VM, Docker-host и IPv6/SLAAC сети.

Поэтому defaults не являются “максимально строгими”:

- `ptrace_scope=1`, чтобы `gdb ./app` работал без полного отключения ptrace restrictions.
- `arp_ignore=1`, потому что `2` строже, но ломает Docker bridge, Kubernetes VIP и multi-IP VM.
- `drop_gratuitous_arp=0`, потому что `1` ломает keepalived/VRRP и легитимные IP move announcements.
- `accept_ra=1`, потому что workstation-сети часто используют SLAAC IPv6.
- `tcp_timestamps=0` обязательно сочетается с `tcp_tw_reuse=0`.

Persistent policy рендерится в `/etc/sysctl.d/99-z-ansible.conf` из template. Роль не форсирует live apply; параметры вступают в силу через distro sysctl loader при boot/reload.

## Сценарии выполнения

| Сценарий | Что гарантирует роль | Ограничение |
|----------|----------------------|-------------|
| Bare metal | persisted sysctl policy | Управляет только sysctl policy, не firewall/DNS/service roles |
| VM guest | persisted guest sysctl policy | Не влияет на host OS и hypervisor |
| Docker container | render/converge/idempotence поведение | Не является полноценной kernel hardening средой, потому что контейнер делит ядро с host |

Docker-сценарий используется как быстрая Molecule-среда для Ansible-сходимости. Он не доказывает, что host kernel hardened.

## Обоснование policy

| Область | Зачем пользователю | Почему такие defaults |
|---------|--------------------|-----------------------|
| Kernel exposure | Меньше kernel pointers/logs/perf/BPF поверхности для обычного пользователя | Restrictive defaults, но `ptrace_scope=1` оставляет обычный dev workflow |
| Filesystem protections | Меньше `/tmp`/sticky-dir race classes | `protected_*` включены; legacy breakage должен быть явным override |
| SUID dumps | Память privileged программ не пишется в core dumps | `fs.suid_dumpable=0`; Ubuntu apport считается конфликтом этого состояния |
| Network trust | Workstation не доверяет redirects/source-route и снижает spoofing surface | Redirects/source-route off, rp_filter/ARP умеренно strict |
| IPv6 | Обычные SLAAC сети продолжают работать | IPv6 не отключается, RA принимается |
| Workstation capacity | IDE/file watchers/dev servers не упираются в низкие лимиты | inotify/file/backlog подняты как workstation baseline |

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
  - `/etc/sysctl.d/99-z-ansible.conf` -- drop-in конфигурация, загружается при boot через sysctl loader дистрибутива
- Сервисы:
  - `apport.service` (Ubuntu) -- disabled, если `fs.suid_dumpable != 2` (apport перезаписывает значение после boot)
- Пакеты:
  - `procps-ng` (Arch/Void/RedHat) или `procps` (Debian/Gentoo) -- утилиты sysctl

**Все платформы:** Archlinux, Debian, RedHat, Void, Gentoo

## Pipeline

`tasks/main.yml` является только оркестратором:

1. `validate/main.yml` -- OS/init support
2. `load/main.yml` -- distro-family vars из `vars/<os_family>/main.yml`
3. `detect/main.yml` -- service facts для Debian/apport conflict detection
4. `install/main.yml` -- установка procps/procps-ng
5. `service/main.yml` -- управление конфликтующими сервисами
6. `configure/main.yml` -- template persistent policy
7. `tasks/main.yml` -- финальный execution report через `common/report_render.yml`

## Audit Events

| Событие | Источник | Severity | Threshold |
|---------|----------|----------|-----------|
| sysctl parameter mismatch after boot/reload | `sysctl -n` vs config file | CRITICAL | any deviation from expected value |
| ASLR disabled (`randomize_va_space != 2`) | `/proc/sys/kernel/randomize_va_space` | CRITICAL | value < 2 |
| ptrace scope relaxed (`ptrace_scope = 0`) | `/proc/sys/kernel/yama/ptrace_scope` | WARNING | value = 0 on non-gaming profile |
| SYN cookies disabled | `/proc/sys/net/ipv4/tcp_syncookies` | CRITICAL | value = 0 |
| Reverse path filter disabled | `/proc/sys/net/ipv4/conf/all/rp_filter` | WARNING | value = 0 |
| ICMP redirects accepted | `/proc/sys/net/ipv4/conf/all/accept_redirects` | WARNING | value != 0 |
| Core dump of SUID allowed | `/proc/sys/fs/suid_dumpable` | WARNING | value > 0 |
| apport re-enabled after role apply | service manager state for `apport` | WARNING | enabled on Debian with suid_dumpable hardening |
| Config file tampered | `stat /etc/sysctl.d/99-z-ansible.conf` | CRITICAL | mode != 0644, owner != root |
| Another sysctl.d file overrides values | `sysctl --system` output | WARNING | file sorting after 99-z-ansible.conf |

## Monitoring Integration

- **Drift detection**: внешняя проверка после boot/reload сравнивает live values с ожидаемым состоянием
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

Роль предоставляет верхнеуровневый тег `sysctl` для полного выполнения роли. Внутренние фазы не являются отдельным операторским контрактом.

## Проверка

- `task test-sysctl` -- стандартная Taskfile-точка для Molecule-проверки роли
- `task check` -- syntax check всех playbook
- `task lint` -- ansible-lint по playbook/roles

## Источник правды

Детальный контракт, ограничения, переменные и тестовый workflow описаны в `ansible/roles/sysctl/README.md`.

---

Назад к [[Roadmap]]
