# Ansible Roles Roadmap

План развития Ansible ролей для полного покрытия VM/Bare Metal конфигурации.

## Текущее состояние (14 ролей)

| Фаза | Роли | Статус |
|------|------|--------|
| System Foundation | base_system, vm, reflector | ✅ |
| Package Infrastructure | yay, packages | ✅ |
| User & Access | user, ssh | ✅ |
| Development Tools | git, shell | ✅ |
| Services | docker, firewall | ✅ |
| Desktop Environment | xorg, lightdm | ✅ |
| User Dotfiles | chezmoi | ✅ |

## Планируемые роли

### Приоритет 1: Критичные для Bare Metal

| Роль | Описание | Сложность |
|------|----------|-----------|
| `gpu_drivers` | NVIDIA/AMD/Intel драйверы, Vulkan, VA-API | High |
| `audio` | PipeWire/PulseAudio, ALSA, bluetooth audio | Medium |
| `sysctl` | Kernel параметры (vm.swappiness, net.*, fs.inotify.*) | Low |
| `power_management` | TLP, CPU governor, suspend/hibernate | Medium |

### Приоритет 2: Desktop Experience

| Роль | Описание |
|------|----------|
| `compositor` | picom конфигурация, vsync, blur |
| `notifications` | dunst/mako, urgency levels |
| `screen_locker` | i3lock/betterlockscreen, xautolock |
| `clipboard` | clipmenu/copyq, clipboard history |
| `screenshots` | maim/flameshot, keybindings |
| `gtk_qt_theming` | Themes, icon themes, cursor |
| `input_devices` | libinput, touchpad gestures |

### Приоритет 3: System Tuning

- `swap` — Swap file/partition, zram
- `systemd_units` — Custom services, timers
- `mkinitcpio` — Initramfs hooks, modules
- `bootloader` — GRUB/systemd-boot конфигурация
- `logrotate` — Log rotation policies

### Приоритет 4: Networking

- `network_manager` — NetworkManager/systemd-networkd
- `vpn` — WireGuard, OpenVPN
- `dns` — systemd-resolved, DNS-over-TLS
- `hosts` — /etc/hosts management
- `bluetooth` — bluez, bluetooth audio

### Приоритет 5: Security

- `fail2ban` — Intrusion prevention
- `apparmor` — AppArmor profiles
- `audit` — auditd rules
- `automatic_updates` — unattended-upgrades
- `certificates` — CA certificates, mkcert

### Приоритет 6: Storage & Backup

- `disk_management` — fstab, mount options, trim
- `backup` — restic/borg/rsync, systemd timers
- `smartd` — SMART monitoring, alerts

### Приоритет 7: Monitoring

- `sensors` — lm_sensors, fancontrol
- `node_exporter` — Prometheus metrics
- `journal` — journald конфигурация

### Приоритет 8: Development

- `programming_languages` — Python (pyenv), Node (nvm), Rust
- `containers` — podman, containerd
- `databases` — PostgreSQL/MySQL/SQLite dev

## Рекомендуемый порядок

```
Phase 1 (Bare Metal essentials):
├── gpu_drivers
├── audio
└── sysctl

Phase 2 (Desktop polish):
├── compositor
├── notifications
├── screen_locker
└── input_devices

Phase 3 (System hardening):
├── power_management
├── swap
├── backup
└── fail2ban

Phase 4 (Networking):
├── bluetooth
├── vpn
└── dns

Phase 5 (Advanced):
├── bootloader
├── sensors
└── programming_languages
```

## Структура новых ролей

```
roles/new_role/
├── defaults/main.yml      # Дефолтные переменные
├── tasks/
│   ├── main.yml           # Точка входа
│   ├── archlinux.yml      # Arch-specific
│   └── debian.yml         # Debian-specific
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

---

Назад к [[Home]]
