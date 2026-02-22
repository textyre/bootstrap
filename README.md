# Arch Linux Workstation Bootstrap

Полностью автоматизированный bootstrap Arch Linux рабочей станции через Ansible.
33 модульных роли в 7 фазах: от базовой настройки системы до desktop environment и dotfiles.
Multi-distro (Archlinux, Debian, RedHat, Void, Gentoo), init-system agnostic.

## Quick Start

```bash
# 1. Клонировать репозиторий
git clone <repo-url> bootstrap && cd bootstrap

# 2. Запустить bootstrap (установит Ansible, запросит vault пароль)
./bootstrap.sh

# 3. Готово — перезагрузка в настроенную рабочую станцию
```

## Что делает

### Phase 1: System Foundation

| Роль | Описание |
|------|----------|
| `timezone` | Часовой пояс |
| `locale` | Локаль, LC_* |
| `hostname` | Имя машины |
| `hostctl` | /etc/hosts |
| `vconsole` | Шрифт и клавиатура TTY |
| `ntp` | Chrony + NTS серверы |
| `ntp_audit` | Аудит NTP синхронизации |
| `package_manager` | pacman.conf, зеркала |
| `pam_hardening` | PAM faillock — защита от brute-force |
| `vm` | Гостевые утилиты VirtualBox/VMware/Hyper-V |

### Phase 1.5: Hardware & Kernel

| Роль | Описание |
|------|----------|
| `gpu_drivers` | Драйверы GPU (NVIDIA/AMD/Intel) |
| `sysctl` | Hardening ядра, сети, производительность |
| `power_management` | TLP, управление питанием |

### Phase 2: Package Infrastructure

| Роль | Описание |
|------|----------|
| `packages` | Установка всех пакетов (pacman + AUR) |

### Phase 3: User & Access

| Роль | Описание |
|------|----------|
| `user` | Пользователь, sudo, группы, SSH ключи, пароли |
| `ssh_keys` | Генерация и деплой SSH ключей |
| `ssh` | sshd hardening, moduli, баннеры |
| `teleport` | Teleport agent (zero-trust access) |
| `fail2ban` | Jail для SSH brute-force |

### Phase 4: Development Tools

| Роль | Описание |
|------|----------|
| `git` | Developer toolchain: signing, aliases, LFS, hooks, multi-user |
| `shell` | Bash/Zsh, алиасы, PATH |

### Phase 5: Services

| Роль | Описание |
|------|----------|
| `docker` | daemon.json, сервис, группа |
| `firewall` | nftables firewall |
| `caddy` | Reverse proxy |
| `vaultwarden` | Password manager (self-hosted) |

### Phase 6: Desktop Environment

| Роль | Описание |
|------|----------|
| `xorg` | Конфигурация X11 мониторов |
| `lightdm` | Display manager |
| `greeter` | LightDM greeter |
| `zen_browser` | Zen Browser (Arch only) |

### Phase 7: User Dotfiles

| Роль | Описание |
|------|----------|
| `chezmoi` | Деплой дотфайлов через chezmoi |

### Shared

| Роль | Описание |
|------|----------|
| `common` | Shared tasks: report_phase, report_render |

## Использование

```bash
# Полный bootstrap
./bootstrap.sh

# Dry-run (показать изменения без применения)
./bootstrap.sh --check

# Только определённые роли
./bootstrap.sh --tags packages
./bootstrap.sh --tags "docker,ssh,firewall"

# Пропустить роли
./bootstrap.sh --skip-tags firewall

# Переопределить переменные
./bootstrap.sh -e '{"ntp_enabled": false}'
```

## Разработка

```bash
# Из корня репозитория:
task bootstrap    # Установить Python зависимости (один раз)
task check        # Проверить синтаксис
task lint         # ansible-lint best practices
task test         # Все molecule тесты
task test-<role>  # Тест конкретной роли
task dry-run      # Показать изменения
task workstation  # Применить playbook
task clean        # Удалить venv
```

## Структура проекта

```
bootstrap/
├── bootstrap.sh                           # Единственная точка входа
├── Taskfile.yml                           # Task runner (разработка)
├── ansible/                               # Ansible project
│   ├── ansible.cfg
│   ├── requirements.txt                   # Python deps
│   ├── vault-pass.sh                      # Vault password resolver
│   ├── inventory/
│   │   ├── hosts.ini
│   │   └── group_vars/all/
│   │       ├── packages.yml               # Реестр пакетов
│   │       ├── system.yml                 # Системные переменные
│   │       └── vault.yml                  # Encrypted (Ansible Vault)
│   ├── playbooks/
│   │   └── workstation.yml                # Полный bootstrap (7 фаз)
│   └── roles/                             # 33 модульных роли
├── wiki/                                  # Wiki + стандарты ролей
│   ├── roles/                             # Документация по каждой роли
│   └── standards/                         # Требования к ролям
├── docs/plans/                            # Планы и дизайн-доки
├── scripts/                               # Bootstrap скрипты
├── dotfiles/                              # Исходные дотфайлы (chezmoi source)
├── greeter/                               # LightDM greeter (Vite + TS)
├── ci/                                    # CI скрипты
└── windows/                               # Windows SSH/sync утилиты
```

## Стандарты ролей

Каждая роль соответствует 11 требованиям (`wiki/standards/role-requirements.md`):

- **ROLE-001** Distro-agnostic: `vars/` per distro
- **ROLE-003** Five distros: Archlinux, Debian, RedHat, Void, Gentoo
- **ROLE-005** In-role verification: `verify.yml`
- **ROLE-006** Molecule tests
- **ROLE-008** Dual logging: `common/report_phase.yml`
- **ROLE-009** Profile-aware defaults: `workstation_profiles`
- **ROLE-010** Modular config: per-subsystem toggles + `_overwrite` pattern
- **ROLE-011** Ansible-native: FQCN modules only

## Безопасность

- Sudo пароль в Ansible Vault (AES-256)
- Vault password: `~/.vault-pass` или `pass show ansible/vault-password`
- SSH ключи Ed25519
- sshd hardening (no root, no password auth)
- nftables firewall (drop by default)
- PAM faillock (brute-force protection)
- Kernel hardening (sysctl: ASLR, ptrace, BPF, ARP)
- Fail2ban SSH jail
- Git commit signing (SSH/GPG)

## Лицензия

MIT
