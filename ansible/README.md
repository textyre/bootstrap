# Ansible Workstation Bootstrap

33 модульных роли для полной настройки рабочей станции в 7 фазах.

## Быстрый старт

```bash
# Из корня репозитория:
task bootstrap   # Установить Python зависимости (один раз)
task workstation # Применить все роли
```

## Команды

| Команда | Описание |
|---------|----------|
| `task bootstrap` | Установить Python зависимости |
| `task check` | Проверить синтаксис playbooks |
| `task lint` | ansible-lint best practices |
| `task test` | Все molecule тесты |
| `task test-<role>` | Тест конкретной роли |
| `task dry-run` | Показать изменения без применения |
| `task workstation` | Применить полный playbook |
| `task all` | check + lint |
| `task clean` | Удалить venv |

## Роли

### Phase 1: System Foundation
- **timezone** — часовой пояс
- **locale** — локаль, LC_*
- **hostname** — имя машины
- **hostctl** — /etc/hosts
- **vconsole** — шрифт и клавиатура TTY
- **ntp** — chrony + NTS серверы
- **ntp_audit** — аудит NTP синхронизации
- **package_manager** — pacman.conf, зеркала
- **pam_hardening** — PAM faillock, brute-force защита
- **vm** — гостевые утилиты VirtualBox/VMware/Hyper-V

### Phase 1.5: Hardware & Kernel
- **gpu_drivers** — NVIDIA/AMD/Intel
- **sysctl** — hardening ядра, сети, производительность
- **power_management** — TLP, питание

### Phase 2: Package Infrastructure
- **packages** — установка всех пакетов (pacman + AUR)

### Phase 3: User & Access
- **user** — пользователь, sudo, группы, SSH ключи, пароли
- **ssh_keys** — генерация и деплой SSH ключей
- **ssh** — sshd hardening, moduli, баннеры
- **teleport** — zero-trust access (опционально)
- **fail2ban** — SSH brute-force jail

### Phase 4: Development Tools
- **git** — developer toolchain: signing, aliases, LFS, hooks, multi-user
- **shell** — bash/zsh, алиасы, PATH

### Phase 5: Services
- **docker** — daemon.json, сервис, группа
- **firewall** — nftables
- **caddy** — reverse proxy
- **vaultwarden** — password manager (self-hosted)

### Phase 6: Desktop Environment
- **xorg** — X11 мониторы
- **lightdm** — display manager
- **greeter** — LightDM greeter
- **zen_browser** — Zen Browser (Arch only)

### Phase 7: User Dotfiles
- **chezmoi** — деплой дотфайлов

### Shared
- **common** — report_phase, report_render (dual logging)

## Тестирование

```bash
# Настройка vault (один раз)
echo 'your_vault_password' > ~/.vault-pass && chmod 600 ~/.vault-pass

# Запуск тестов
task test                 # Все роли
task test-<role>          # Конкретная роль
```

**Внимание:** Molecule тесты изменяют систему! Создайте снапшот VM.

## Переменные

- `inventory/group_vars/all/packages.yml` — реестр пакетов
- `inventory/group_vars/all/system.yml` — системные переменные
- `inventory/group_vars/all/vault.yml` — зашифрованный sudo пароль

## Теги

```bash
# Выборочный запуск
ansible-playbook playbooks/workstation.yml --tags packages
ansible-playbook playbooks/workstation.yml --tags "docker,ssh,firewall"
ansible-playbook playbooks/workstation.yml --skip-tags firewall
```
