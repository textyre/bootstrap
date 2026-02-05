# Arch Linux Workstation Bootstrap

Добро пожаловать в вики проекта Arch Linux Workstation Bootstrap!

Полностью автоматизированный bootstrap Arch Linux рабочей станции через Ansible. 14 модульных ролей: от базовой настройки системы до desktop environment и dotfiles через chezmoi.

## Быстрый старт

```bash
# 1. Клонировать репозиторий
git clone <repo-url> bootstrap && cd bootstrap

# 2. Запустить bootstrap (установит Ansible, запросит vault пароль)
./bootstrap.sh

# 3. Готово — перезагрузка в настроенную рабочую станцию
```

## Документация

### Установка и настройка
- [[Quick-Start]] — Быстрая настройка системы за 3 шага
- [[Requirements]] — Системные требования и зависимости
- [[Usage]] — Использование и опции запуска

### Компоненты системы
- [[Ansible-Overview]] — Обзор Ansible ролей и архитектуры
- [[Ansible-Decisions]] — Архитектурные решения и логи
- [[Chezmoi-Guide]] — Управление dotfiles через chezmoi
- [[SSH-Setup]] — Настройка SSH с Windows на Arch VM

### Конфигурация GUI
- [[Xorg-Configuration]] — Настройка X11/Xorg сервера
- [[Display-Setup]] — LightDM и конфигурация дисплея

### Polybar (текущий status bar)
- [[Polybar-Architecture]] — Архитектура и полный анализ конфигурации Polybar

### Миграция и будущее
- [[Ewwii-Migration]] — План миграции с Polybar на Ewwii
- [[Roadmap]] — Будущие роли и планы развития

### Помощь и решение проблем
- [[Troubleshooting]] — Консолидированный лог устранения неисправностей
- [[Windows-Setup]] — Настройка синхронизации с Windows

## Что делает bootstrap

| # | Роль | Описание |
|---|------|----------|
| 1 | `base_system` | Локаль, таймзона, hostname, pacman.conf |
| 2 | `vm` | Определение VM окружения, специфичные настройки |
| 3 | `reflector` | Оптимизация зеркал pacman |
| 4 | `yay` | Сборка AUR helper из исходников |
| 5 | `packages` | Установка всех пакетов (pacman + AUR) |
| 6 | `user` | Пользователь, sudo, группы |
| 7 | `ssh` | SSH ключи, hardening sshd |
| 8 | `git` | Глобальная конфигурация git |
| 9 | `shell` | Bash/Zsh конфигурация, алиасы |
| 10 | `docker` | Docker daemon, сервис, группа |
| 11 | `firewall` | Базовый nftables firewall |
| 12 | `xorg` | Конфигурация X11 мониторов |
| 13 | `lightdm` | Display manager |
| 14 | `chezmoi` | Деплой дотфайлов через chezmoi |

## Структура проекта

```
bootstrap/
├── bootstrap.sh              # Единственная точка входа
├── Taskfile.yml              # Task runner (разработка)
├── ansible/                  # Ansible project
│   ├── ansible.cfg
│   ├── requirements.txt      # Python deps
│   ├── vault-pass.sh         # Vault password resolver
│   ├── inventory/            # Инвентарь и переменные
│   ├── playbooks/            # Плейбуки
│   └── roles/                # 14 модульных ролей
├── dotfiles/                 # Исходные дотфайлы (chezmoi source)
├── bin/                      # Утилиты
├── ci/                       # CI скрипты
├── windows/                  # Windows SSH/sync утилиты
└── docs/                     # Документация
```

## Безопасность

- Sudo пароль в Ansible Vault (AES-256)
- Vault password: `~/.vault-pass` или `pass show ansible/vault-password`
- SSH ключи Ed25519
- sshd hardening (no root, no password auth)
- nftables firewall (drop by default)

## Лицензия

MIT

---

**Версия проекта:** 2026-02
