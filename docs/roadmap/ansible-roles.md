# Ansible Roles Roadmap

План развития Ansible ролей для полного покрытия VM/Bare Metal конфигурации.

## Текущее состояние (17 ролей)

| Фаза | Роли | Статус |
|------|------|--------|
| System Foundation | `base_system`, `vm`, `reflector` | ✅ |
| Hardware & Kernel | `gpu_drivers`, `sysctl`, `power_management` | ✅ |
| Package Infrastructure | `yay`, `packages` | ✅ |
| User & Access | `user`, `ssh` | ✅ |
| Development Tools | `git`, `shell` | ✅ |
| Services | `docker`, `firewall` | ✅ |
| Desktop Environment | `xorg`, `lightdm` | ✅ |
| User Dotfiles | `chezmoi` | ✅ |

---

## Планируемые роли

### Приоритет 1: Критичные для Bare Metal ✅

| Роль | Описание | Сложность | Статус |
|------|----------|-----------|--------|
| `gpu_drivers` | NVIDIA/AMD/Intel драйверы, Vulkan, VA-API, hardware acceleration | High | ✅ |
| `sysctl` | Kernel параметры (vm.swappiness, net.*, fs.inotify.max_user_watches) | Low | ✅ |
| `power_management` | TLP, CPU governor, suspend/hibernate, laptop-mode-tools | Medium | ✅ |

### Приоритет 2: Desktop Experience

| Роль | Описание | Сложность |
|------|----------|-----------|
| `compositor` | picom конфигурация, vsync, blur, animations | Low |
| `notifications` | dunst/mako настройка, urgency levels, history | Low |
| `screen_locker` | i3lock/betterlockscreen, xautolock, idle timeout | Low |
| `clipboard` | clipmenu/copyq, clipboard history, sync | Low |
| `screenshots` | maim/flameshot конфигурация, keybindings | Low |
| `gtk_qt_theming` | GTK/Qt themes, icon themes, cursor themes, font config | Medium |
| `input_devices` | libinput, touchpad gestures, mouse acceleration | Low |

### Приоритет 3: System Tuning

| Роль | Описание | Сложность |
|------|----------|-----------|
| `swap` | Swap file/partition, zram конфигурация | Low |
| `systemd_units` | Custom services, timers, targets | Medium |
| `mkinitcpio` | Initramfs hooks, modules, compression (Arch-specific) | Medium |
| `bootloader` | GRUB/systemd-boot конфигурация, kernel params | High |
| `logrotate` | Log rotation policies, journal size limits | Low |

### Приоритет 4: Networking

| Роль | Описание | Сложность |
|------|----------|-----------|
| `network_manager` | NetworkManager/systemd-networkd, Wi-Fi profiles, static IP | Medium |
| `vpn` | WireGuard, OpenVPN клиенты, auto-connect | Medium |
| `dns` | systemd-resolved, DNS-over-TLS, custom resolvers | Low |
| `hosts` | /etc/hosts management, ad-blocking hosts | Low |
| `bluetooth` | bluez, bluetooth audio, auto-pairing, trusted devices | Medium |

### Приоритет 5: Security

| Роль | Описание | Сложность |
|------|----------|-----------|
| `fail2ban` | Intrusion prevention, SSH jail, custom filters | Medium |
| `apparmor` | AppArmor profiles (Debian/Ubuntu) | High |
| `audit` | auditd rules, system auditing, log analysis | High |
| `automatic_updates` | unattended-upgrades / pacman hooks | Low |
| `certificates` | CA certificates, mkcert для local dev | Low |

### Приоритет 6: Storage & Backup

| Роль | Описание | Сложность |
|------|----------|-----------|
| `disk_management` | fstab entries, mount options, trim timers | Low |
| `backup` | restic/borg/rsync настройка, systemd timers, remote backup | High |
| `smartd` | SMART monitoring, disk health alerts, email notifications | Medium |

### Приоритет 7: Hardware Monitoring

| Роль | Описание | Сложность |
|------|----------|-----------|
| `sensors` | lm_sensors, fancontrol, temperature monitoring | Medium |
| `node_exporter` | Prometheus metrics (CPU, RAM, disk, network) | Low |
| `journal` | journald конфигурация, persistent logging, size limits | Low |

### Приоритет 8: Development Tools

| Роль | Описание | Сложность |
|------|----------|-----------|
| `programming_languages` | Python (pyenv), Node (nvm/fnm), Rust, Go | Medium |
| `containers` | podman, containerd, buildah (альтернативы Docker) | Medium |
| `databases` | PostgreSQL/MySQL/SQLite dev instances | Medium |

---

## Рекомендуемый порядок реализации

```
Phase 1 (Bare Metal essentials):
├── gpu_drivers
├── sysctl
└── power_management

Phase 2 (Desktop polish):
├── compositor
├── notifications
├── screen_locker
└── input_devices

Phase 3 (System hardening):
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

---

## Структура новых ролей

Каждая новая роль должна следовать существующим паттернам:

```
roles/new_role/
├── defaults/main.yml      # Дефолтные переменные
├── tasks/
│   ├── main.yml           # Точка входа
│   ├── archlinux.yml      # Arch-specific tasks
│   └── debian.yml         # Debian-specific tasks
├── handlers/main.yml      # Service handlers
├── templates/             # Jinja2 templates
├── meta/main.yml          # Galaxy metadata
└── molecule/              # Integration tests
    └── default/
        ├── converge.yml
        ├── molecule.yml
        └── verify.yml
```

### Обязательные элементы

1. **OS-specific tasks** через `include_tasks: "{{ ansible_facts['os_family'] | lower }}.yml"`
2. **Tags** для selective execution
3. **Molecule tests** для CI/CD
4. **Idempotency** — повторный запуск не должен менять состояние

---

## Запасные (отложенные)

| Роль | Описание | Сложность | Причина |
|------|----------|-----------|---------|
| `audio` | PipeWire/PulseAudio, ALSA конфигурация, bluetooth audio | Medium | Не требуется на текущем этапе |

---

## Заметки

- Приоритет Arch Linux, Debian как secondary target
- Все роли должны быть idempotent
- Использовать handlers для перезапуска сервисов
- Sensitive данные через ansible-vault
