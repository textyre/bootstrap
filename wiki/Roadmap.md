# Ansible Roles Roadmap

План развития Ansible ролей для полного покрытия VM/Bare Metal конфигурации.
Все роли — distro-agnostic (OS-specific tasks через `include_tasks`).

## Текущее состояние (21 роль)

| Фаза | Роли | Статус |
|------|------|--------|
| System Foundation | base_system, vm, reflector | ✅ |
| Hardware & Kernel | gpu_drivers, sysctl, power_management | ✅ |
| Package Infrastructure | yay, packages | ✅ |
| User & Access | user, ssh | ✅ |
| Development Tools | git, shell | ✅ |
| Services | docker, firewall, caddy, vaultwarden | ✅ |
| Desktop Environment | xorg, lightdm, greeter, zen_browser | ✅ |
| User Dotfiles | chezmoi | ✅ |

## Критические исправления

Ошибки обнаруженные при аудите текущего roadmap.

| # | Ошибка | Исправление |
|---|--------|-------------|
| 1 | Дубликат `network` в Priority 1 и Priority 4 | Убрать из Priority 1, оставить в Networking (Phase 5) |
| 2 | Пересечение `swap` и `zram` — отдельные роли с одной целью | Объединить в единую роль `memory` (zram / swap / hybrid) |
| 3 | Security на Priority 5 — слишком поздно | Разделить: Phase 2 (Foundation) и Phase 9 (Advanced) |
| 4 | `automatic_updates` → unattended-upgrades (Debian-only) | Переименовать в `auto_updates`, distro-agnostic |
| 5 | Phase 3 "hardening" включает fail2ban, но fail2ban в Priority 5 | Единый согласованный порядок фаз |
| 6 | Логирование (journald) на Priority 7 | Перенести в Phase 2 (Security Foundation) |
| 7 | Мониторинг отсутствует в рекомендуемых фазах | Добавить Phase 8: Observability & Logging Stack |
| 8 | `mkinitcpio` как отдельная роль | Убрать — уже в роли `vm` (tasks/mkinitcpio.yml), Arch-specific. Initramfs → `bootloader` |

## Quick Wins — улучшения существующих ролей

Изменения без создания новых ролей, значительно усиливающие безопасность.

| # | Роль | Что добавить | Файлы |
|---|------|-------------|-------|
| QW-1 | `ssh` | AllowGroups, MaxStartups, Ciphers/MACs/KexAlgorithms | defaults, tasks |
| QW-2 | `sysctl` | Секция Security: ASLR, kptr_restrict, rp_filter, SYN cookies | defaults, template |
| QW-3 | `docker` | userns-remap, icc, live-restore, no-new-privileges, journald driver | defaults, template |
| QW-4 | `firewall` | SSH rate limiting (4/min) в nftables | template |
| QW-5 | `base_system` | PAM faillock: deny=3, unlock_time=900, audit, silent | defaults |
| QW-6 | `user` | Sudo: timestamp_timeout=5, use_pty, logfile | tasks |

Детали каждого Quick Win: [[Quick-Wins]]

---

## Рекомендуемый порядок (13 фаз)

```
Phase 1: System Foundation (3)                     ✅
├── base_system, vm, reflector

Phase 1.5: Hardware & Kernel (4)                   частично ✅
├── gpu_drivers ✅, sysctl ✅, power_management ✅
└── bootloader

Phase 2: Security Foundation (5)                   ← НОВАЯ
├── sysctl (+ security params — QW-2)
├── fail2ban
├── pam_hardening
├── umask
└── journald

Phase 3: Package Infrastructure (3)                ✅
├── yay ✅, packages ✅
└── memory (заменяет swap + zram)

Phase 4: User & Access (2)                         ✅ + QW
├── user (+ QW-6)
└── ssh (+ QW-1)

Phase 5: Networking (4)
├── network, systemd_resolved
├── dns, vpn

Phase 6: Services (8)
├── docker (+ QW-3), firewall (+ QW-4)
├── systemd_hardening, systemd_units
├── polkit, tmpfiles, certificates
├── caddy ✅, vaultwarden ✅

Phase 7: Desktop Environment (13)
├── xorg ✅, lightdm ✅, greeter ✅, zen_browser ✅
├── audio, compositor, notifications, screen_locker
├── clipboard, screenshots, gtk_qt_theming
├── input_devices, bluetooth

Phase 8: Observability & Logging Stack (10)        ← НОВАЯ
├── Monitoring: prometheus, node_exporter, cadvisor
├── Logging: alloy (OTel Collector), loki
├── UI: grafana
├── Health: smartd, healthcheck, sensors
└── logrotate
│
│   Alloy = OpenTelemetry Collector (100% OTLP).
│   Путь к traces (→ Tempo) и app metrics (→ Mimir)
│   без изменения инфраструктуры.

Phase 9: Advanced Security (4)                     ← НОВАЯ
├── apparmor, auditd, aide, lynis

Phase 10: Autodeploy (3)                           ← НОВАЯ
├── ansible_pull, watchtower, auto_updates

Phase 11: Storage & Backup (2)
├── disk_management, backup

Phase 12: Development (3)
├── programming_languages, containers, databases

Phase 13: User Dotfiles (1)                        ✅
└── chezmoi
```

---

## Новые роли по направлениям

### 1. Безопасность (Security)

| Роль | Phase | Описание | Детали |
|------|-------|----------|--------|
| [[fail2ban]] | 2 | IPS для SSH и сервисов. Банит IP после N неудачных попыток | wiki/roles/ |
| [[pam_hardening]] | 2 | Политики паролей (pwquality), session limits, password history | wiki/roles/ |
| [[umask]] | 2 | Системный umask 027/077 через profile.d и login.defs | wiki/roles/ |
| [[apparmor]] | 9 | Mandatory Access Control. Профили для sshd, docker, caddy | wiki/roles/ |
| [[auditd]] | 9 | Аудит: изменения passwd/shadow/sudoers, execve, privilege escalation | wiki/roles/ |
| [[aide]] | 9 | File Integrity Monitoring для /etc, /bin, /usr | wiki/roles/ |
| [[lynis]] | 9 | Автоматический security audit (CIS/STIG/PCI-DSS) | wiki/roles/ |
| [[certificates]] | 6 | Управление CA, mkcert для dev, trust store | wiki/roles/ |

### 2. Логирование (Logging)

Централизованный стек: **Docker → journald → Grafana Alloy → Loki → Grafana**

| Роль | Phase | Описание | Детали |
|------|-------|----------|--------|
| [[journald]] | 2 | Persistent storage, size limits, rate limiting, compression | wiki/roles/ |
| [[loki]] | 8 | Grafana Loki — хранилище логов, label-based индексация, LogQL | wiki/roles/ |
| [[alloy]] | 8 | Grafana Alloy (OTel Collector) — единый коллектор всех логов | wiki/roles/ |
| [[grafana]] | 8 | UI для логов и метрик. Дашборды, алерты, explore | wiki/roles/ |

### 3. Автозапуск / Systemd

| Роль | Phase | Описание | Детали |
|------|-------|----------|--------|
| [[systemd_hardening]] | 6 | Sandboxing: PrivateTmp, ProtectSystem, NoNewPrivileges | wiki/roles/ |
| [[systemd_resolved]] | 5 | DNS resolver с DNS-over-TLS | wiki/roles/ |
| [[systemd_units]] | 6 | Custom timers и services | wiki/roles/ |
| [[polkit]] | 6 | PolicyKit rules для wheel группы | wiki/roles/ |

### 4. Автодеплой (Autodeploy)

| Роль | Phase | Описание | Детали |
|------|-------|----------|--------|
| [[ansible_pull]] | 10 | Self-updating через git + systemd timer | wiki/roles/ |
| [[watchtower]] | 10 | Автообновление Docker-контейнеров | wiki/roles/ |
| [[auto_updates]] | 10 | Security updates ОС (distro-agnostic) | wiki/roles/ |

### 5. Контроль состояния (Monitoring & Observability)

Стек: **node_exporter + cAdvisor → Prometheus → Grafana**

| Роль | Phase | Описание | Детали |
|------|-------|----------|--------|
| [[prometheus]] | 8 | Metrics storage, PromQL, алертинг | wiki/roles/ |
| [[node_exporter]] | 8 | Системные метрики (CPU, RAM, disk, network) | wiki/roles/ |
| [[cadvisor]] | 8 | Docker container метрики | wiki/roles/ |
| [[smartd]] | 8 | SMART мониторинг дисков | wiki/roles/ |
| [[healthcheck]] | 8 | Health checks для systemd services и disk usage | wiki/roles/ |
| [[sensors]] | 8 | Температурные датчики, fancontrol | wiki/roles/ |

**OpenTelemetry**: Grafana Alloy (роль `alloy`) является дистрибуцией OTel Collector (100% OTLP). При появлении OTel-инструментированных приложений Alloy готов принимать traces (→ Tempo) и app metrics (→ Mimir) без изменения инфраструктуры. 71% организаций используют Prometheus + OTel вместе (complementary, не competitive).

### 6. Системные сервисы

| Роль | Phase | Описание | Детали |
|------|-------|----------|--------|
| [[bootloader]] | 1.5 | GRUB/systemd-boot, kernel params, secure boot | wiki/roles/ |
| [[memory]] | 3 | zram / swap file / hybrid (заменяет swap + zram) | wiki/roles/ |
| [[tmpfiles]] | 6 | systemd-tmpfiles.d — /tmp, /var/tmp, cleanup | wiki/roles/ |

### 7. Desktop Experience

| Роль | Phase | Описание | Детали |
|------|-------|----------|--------|
| `audio` | 7 | PipeWire + WirePlumber, default sink/source | — |
| `compositor` | 7 | picom/picom-ftlabs, vsync, blur, animations | — |
| `notifications` | 7 | dunst/mako, urgency levels | — |
| `screen_locker` | 7 | i3lock/betterlockscreen, xautolock | — |
| `clipboard` | 7 | clipmenu/copyq, clipboard history | — |
| `screenshots` | 7 | maim/flameshot, keybindings | — |
| `gtk_qt_theming` | 7 | Themes, icon themes, cursor | — |
| `input_devices` | 7 | libinput, touchpad gestures | — |
| `bluetooth` | 7 | bluez, автоподключение, bluetooth audio | — |

### 8. Storage & Backup

| Роль | Phase | Описание |
|------|-------|----------|
| `disk_management` | 11 | fstab, mount options, trim |
| `backup` | 11 | restic/borg/rsync, systemd timers |

### 9. Development

| Роль | Phase | Описание |
|------|-------|----------|
| `programming_languages` | 12 | Python (pyenv), Node (nvm/fnm), Rust, Go |
| `containers` | 12 | podman, containerd |
| `databases` | 12 | PostgreSQL/MySQL/SQLite dev |

---

## Структура новых ролей

```
roles/new_role/
├── defaults/main.yml      # Дефолтные переменные
├── tasks/
│   ├── main.yml           # Точка входа
│   ├── archlinux.yml      # Arch-specific
│   └── debian.yml         # Debian-specific (distro-agnostic)
├── handlers/main.yml      # Service handlers
├── templates/             # Jinja2 templates
├── meta/main.yml          # Galaxy metadata
└── molecule/              # Integration tests
```

### Обязательные элементы

1. OS-specific tasks через `include_tasks`
2. Tags для selective execution
3. Molecule tests для CI/CD
4. Idempotency — повторный запуск не меняет состояние
5. Feature flags — опасные параметры за переменными (default: off)

---

Назад к [[Home]]
