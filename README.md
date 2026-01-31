# Arch Linux Workstation Bootstrap

Полностью автоматизированный bootstrap Arch Linux рабочей станции через Ansible.
13 модульных ролей: от базовой настройки системы до desktop environment и dotfiles через chezmoi.

## Quick Start

```bash
# 1. Клонировать репозиторий
git clone <repo-url> bootstrap && cd bootstrap

# 2. Запустить bootstrap (установит Ansible, запросит vault пароль)
./bootstrap.sh

# 3. Готово — перезагрузка в настроенную рабочую станцию
```

## Что делает

| # | Роль | Описание |
|---|------|----------|
| 1 | `base_system` | Локаль, таймзона, hostname, pacman.conf |
| 2 | `reflector` | Оптимизация зеркал pacman |
| 3 | `yay` | Сборка AUR helper из исходников |
| 4 | `packages` | Установка всех пакетов (pacman + AUR) |
| 5 | `user` | Пользователь, sudo, группы |
| 6 | `ssh` | SSH ключи, hardening sshd |
| 7 | `git` | Глобальная конфигурация git |
| 8 | `shell` | Bash/Zsh конфигурация, алиасы |
| 9 | `docker` | Docker daemon, сервис, группа |
| 10 | `firewall` | Базовый nftables firewall |
| 11 | `xorg` | Конфигурация X11 мониторов |
| 12 | `lightdm` | Display manager |
| 13 | `chezmoi` | Деплой дотфайлов через chezmoi |

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
./bootstrap.sh -e '{"base_system_hostname": "mybox"}'
```

## Разработка

```bash
# Из корня репозитория:
task bootstrap    # Установить Python зависимости (один раз)
task check        # Проверить синтаксис
task lint         # ansible-lint best practices
task test         # Все molecule тесты (13 ролей)
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
│   │   ├── hosts.ini                      # localhost
│   │   └── group_vars/all/
│   │       ├── packages.yml               # Реестр пакетов
│   │       ├── system.yml                 # Системные переменные
│   │       └── vault.yml                  # Encrypted sudo password
│   ├── playbooks/
│   │   ├── workstation.yml                # Полный bootstrap (13 ролей)
│   │   └── mirrors-update.yml             # Только зеркала
│   └── roles/                             # 13 модульных ролей
│       ├── base_system/
│       ├── reflector/
│       ├── yay/
│       ├── packages/
│       ├── user/
│       ├── ssh/
│       ├── git/
│       ├── shell/
│       ├── docker/
│       ├── firewall/
│       ├── xorg/
│       ├── lightdm/
│       └── chezmoi/
├── dotfiles/                              # Исходные дотфайлы (chezmoi source)
├── bin/                                   # Утилиты (анализ пакетов)
├── ci/                                    # CI скрипты
├── windows/                               # Windows SSH/sync утилиты
└── docs/                                  # Документация
```

## Переменные

Все переменные в `ansible/inventory/group_vars/all/`:

- **packages.yml** — реестр пакетов (100+ пакетов по категориям)
- **system.yml** — системные переменные (locale, hostname, user, git, shell, etc.)
- **vault.yml** — зашифрованный sudo пароль (Ansible Vault)

Переопределение: `host_vars/<hostname>/` или `-e` флаг.

## Безопасность

- Sudo пароль в Ansible Vault (AES-256)
- Vault password: `~/.vault-pass` или `pass show ansible/vault-password`
- SSH ключи Ed25519
- sshd hardening (no root, no password auth)
- nftables firewall (drop by default)

## Лицензия

MIT
