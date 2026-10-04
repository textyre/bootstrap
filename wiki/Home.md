# Arch Linux Workstation Bootstrap

Добро пожаловать в вики проекта Arch Linux Workstation Bootstrap!

OpenStrap создаёт disposable Arch target и отдельный Linux Docker host. Готовый образ из GHCR содержит обычный системный Ansible и исходники проекта; один полный workstation playbook запускается через Docker exec по SSH.

## Быстрый старт

Из PowerShell на Windows:

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

`bootstrap-target` — full clone `arch-base/base`, SSH `2251`; `ansible-control` — Ubuntu 24.04 Docker host, SSH `2252`. Обе VM headless. Cloud-init устанавливает только `docker.io` и `ca-certificates`. После Docker readiness OpenStrap загружает `ghcr.io/textyre/bootstrap/control-plane:latest`, запускает постоянный контейнер и выполняет workstation через Docker exec. Vault password и target connection values передаются только окружению последнего шага.

Подготовка, secret source и требования — [[Quick-Start]]. Результат определяется exit code и recap Ansible; повторное применение или свежий clone выбираются отдельно по задаче пользователя.

## Документация

### Установка и настройка

- [[Quick-Start]] — Запуск двух VM и workstation
- [[Requirements]] — Системные требования и зависимости
- [[Usage]] — Использование и опции запуска

### Компоненты системы

- [[Ansible-Overview]] — Обзор Ansible ролей и архитектуры
- [[Ansible-Decisions]] — Архитектурные решения и логи
- [[Chezmoi-Guide]] — Управление dotfiles через chezmoi
- [[SSH-Setup]] — SSH Windows → controller → target

### Конфигурация GUI

- [[Xorg-Configuration]] — Настройка X11/Xorg сервера
- [[Display-Setup]] — LightDM и конфигурация дисплея

### Status bar

- [[Ewwii-Architecture]] — Архитектура и требования ewwii status bar
- [[Polybar-Architecture]] — Архитектура Polybar (предыдущая реализация)

### Планы развития

- [[Roadmap]] — Будущие роли и планы развития

### Помощь и решение проблем

- [[Troubleshooting]] — Консолидированный лог устранения неисправностей
- [[Windows-Setup]] — Установка CLI и запуск с Windows

## Что делает bootstrap

Полный набор 31 роли задаёт `ansible/playbooks/workstation.yml`: системная основа, packages, access/hardening, developer tools, containers/reverse proxy, desktop и dotfiles. При отсутствии Python playbook устанавливает его через native `raw`, затем собирает facts. Состав описан в [[Ansible-Overview]], правила работы с машинами — `standards/test-vm-workflow.md`.

Controller не является workstation target. Source `arch-base` и её snapshots неизменны. Контейнер Control Plane переносится на другой Linux Docker host, включая облако или VPS.

## Структура проекта

```text
bootstrap/
├── openstrap.yaml           # VM, image pull/start и один workstation запуск
├── openstrap.config.mjs     # provider, SSH identity и host secret resolver
├── Taskfile.yml             # optional development Ansible-команды
├── Dockerfile              # публикуемый образ с Ansible и исходниками
├── compose.yml             # optional development service control-plane
├── ansible/
│   ├── inventory/           # параметры/Vault; статический openstrap.yml
│   ├── playbooks/           # workstation и отдельные исходные playbooks
│   └── roles/               # workstation roles
├── dotfiles/                # chezmoi source
├── bin/                     # отдельные read-only утилиты
└── docs/                    # документация; installer flow отдельно
```

## Безопасность

- Sudo пароль в Ansible Vault (AES-256)
- Vault password: read-only host runtime secret store → Docker exec → Ansible process env
- Install-only credentials: ignored `.local/bootstrap/`, вне VM delivery
- SSH ключи Ed25519; private key загружается native SSH agent без сохранения в контейнере
- First-contact host key сохраняется; изменившийся key отклоняется
- Known hosts и ARA offline DB сохраняются в named volume `bootstrap-control-plane-home:/root`
- sshd hardening (no root, no password auth)
- nftables firewall (drop by default)

## Лицензия

MIT

---

**Версия проекта:** 2026-10
