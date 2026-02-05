# Requirements

## Bootstrap

- `bootstrap.sh` полностью настраивает систему с нуля (Arch Linux)
- Все секреты (sudo пароль) хранятся в Ansible Vault
- Vault пароль запрашивается один раз при bootstrap, сохраняется в `~/.vault-pass`
- Без ручных шагов после `./bootstrap.sh`

## Роли — порядок и зависимости

- Полное обновление системы (`pacman -Syu`) перед установкой пакетов
- **base_system**: locale, timezone, hostname, pacman.conf
- **vm**: определение окружения VM, специфичные настройки
- **reflector**: ранжирование зеркал (Arch)
- **yay**: сборка AUR-хелпера из исходников
- **packages**: все pacman + AUR пакеты рабочей станции
- **user**: создание пользователя, sudoers, группы
- **ssh**: генерация ключей, hardening sshd
- **git**: per-user конфигурация (name, email, editor)
- **shell**: окружение (bash/zsh)
- **docker**: установка, сервис, группа
- **firewall**: nftables, правила
- **xorg**: X11 сервер, драйверы, утилиты
- **lightdm**: display manager, greeter
- **chezmoi**: dotfiles из репозитория

## Пакеты

- Единый реестр в `inventory/group_vars/all/packages.yml`
- Роли содержат только логику, данные — в group_vars
- AUR пакеты устанавливаются через yay с паролем из vault (SUDO_ASKPASS)
- Конфликты AUR с pacman пакетами разрешаются автоматически
- Обязательные AUR: picom-ftlabs-git, i3lock-color, rofi-greenclip, dracula-gtk-theme, i3-rounded-border-patch-git

## Тестирование

- Molecule тест для каждой роли (14 ролей)
- `go-task test --yes` прогоняет lint + все molecule тесты
- ansible-lint profile: production, 0 нарушений
- Idempotence: повторный запуск не меняет состояние системы
- Сервисы (docker, nftables, lightdm) включены и запущены в тестах

## Синхронизация Windows → VM

- `sync_to_server.ps1` копирует проект на VM
- Корректные права файлов после копирования (ansible.cfg 644, inventory go-w)
- Line endings: CRLF → LF для .sh файлов

## Инфраструктура

- Inventory: `hosts.ini` (INI формат, плагин включён в ansible.cfg)
- Vault password file: `vault-pass.sh`
- Python venv: `ansible/.venv`
- Taskfile.yml: bootstrap, check, lint, test, workstation, dry-run, vault-*

## Идемпотентность

- Каждая роль идемпотентна — повторный запуск = 0 changed
- Временные файлы (SUDO_ASKPASS) не влияют на состояние системы
- AUR пакеты: `--needed` предотвращает переустановку

---

Назад к [[Home]]
