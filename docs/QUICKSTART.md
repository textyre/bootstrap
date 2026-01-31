# Quick Start

Быстрая настройка Arch Linux рабочей станции через Ansible.

## Требования

- Arch Linux (свежая установка или существующая система)
- Доступ к `sudo`
- Интернет-соединение

## 3 шага

```bash
# 1. Клонировать репозиторий
git clone <repo-url> bootstrap && cd bootstrap

# 2. Запустить bootstrap
./bootstrap.sh

# 3. Готово — перезагрузка в настроенную рабочую станцию
```

`bootstrap.sh` автоматически:
- Проверит что система — Arch Linux
- Установит Ansible и go-task если отсутствуют
- Запросит vault пароль (sudo пароль, зашифрованный AES-256)
- Создаст Python venv для тулинга
- Запустит playbook с 13 ролями

## Выборочный запуск

```bash
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

Все аргументы передаются напрямую в `ansible-playbook`.

## Vault пароль

При первом запуске `bootstrap.sh` запросит vault пароль и сохранит в `~/.vault-pass` (chmod 600).

Альтернативный способ — через `pass`:
```bash
pass insert ansible/vault-password
```

Скрипт `vault-pass.sh` проверяет оба источника: `pass` → `~/.vault-pass`.

## Что устанавливается

| # | Роль | Описание |
|---|------|----------|
| 1 | `base_system` | Локаль, таймзона, hostname, pacman.conf |
| 2 | `reflector` | Оптимизация зеркал pacman |
| 3 | `yay` | Сборка AUR helper из исходников |
| 4 | `packages` | Установка всех пакетов (pacman + AUR) |
| 5 | `user` | Пользователь, sudo, группы |
| 6 | `ssh` | SSH ключи Ed25519, hardening sshd |
| 7 | `git` | Глобальная конфигурация git |
| 8 | `shell` | Bash/Zsh конфигурация, алиасы |
| 9 | `docker` | Docker daemon, сервис, группа |
| 10 | `firewall` | nftables firewall |
| 11 | `xorg` | Конфигурация X11 мониторов |
| 12 | `lightdm` | Display manager |
| 13 | `chezmoi` | Деплой дотфайлов через chezmoi |

## Доступные теги

```bash
# По роли
--tags base       # base_system
--tags mirrors    # reflector
--tags aur        # yay
--tags packages   # packages
--tags user       # user
--tags ssh        # ssh
--tags git        # git
--tags shell      # shell
--tags docker     # docker
--tags firewall   # firewall
--tags xorg       # xorg
--tags lightdm    # lightdm
--tags chezmoi    # chezmoi

# По категории
--tags security   # ssh + firewall
--tags display    # xorg + lightdm
--tags dotfiles   # chezmoi
```

## Разработка

```bash
# Из корня репозитория:
task bootstrap    # Установить Python зависимости (один раз)
task check        # Проверить синтаксис
task lint         # ansible-lint
task test         # Все molecule тесты (13 ролей)
task test-<role>  # Тест конкретной роли (например: task test-docker)
task dry-run      # Показать изменения
task workstation  # Применить playbook
task clean        # Удалить venv
```

## Передача на сервер (с Windows)

Если вы работаете с Windows и хотите перенести скрипты на Arch сервер:

```powershell
# Настройка SSH ключа (один раз)
.\windows\setup_ssh_key.ps1

# Синхронизация
.\windows\sync_to_server.ps1
```
