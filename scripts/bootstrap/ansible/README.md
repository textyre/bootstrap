# Ansible Workstation Bootstrap

13 модульных ролей для полной настройки Arch Linux рабочей станции.

## Быстрый старт

```bash
cd scripts/bootstrap/ansible
task bootstrap   # Установить Python зависимости (один раз)
task workstation # Применить все 13 ролей
```

## Команды

| Команда | Описание |
|---------|----------|
| `task bootstrap` | Установить Python зависимости |
| `task check` | Проверить синтаксис playbooks |
| `task lint` | ansible-lint best practices |
| `task test` | Все molecule тесты (13 ролей) |
| `task test-<role>` | Тест конкретной роли |
| `task dry-run` | Показать изменения без применения |
| `task workstation` | Применить полный playbook |
| `task all` | check + lint |
| `task clean` | Удалить venv |

## Роли

### System Foundation
- **base_system** — локаль, таймзона, hostname, pacman.conf
- **reflector** — оптимизация зеркал (Arch only)

### Package Infrastructure
- **yay** — AUR helper (Arch only)
- **packages** — установка всех пакетов

### User & Access
- **user** — пользователь, sudo, группы
- **ssh** — SSH ключи, hardening sshd

### Development Tools
- **git** — глобальная конфигурация git
- **shell** — bash/zsh, алиасы, PATH

### Services
- **docker** — daemon.json, сервис, группа
- **firewall** — базовый nftables

### Desktop Environment
- **xorg** — конфигурация X11 мониторов
- **lightdm** — display manager
- **chezmoi** — деплой дотфайлов

## Тестирование

```bash
# Настройка vault (один раз)
echo 'your_vault_password' > ~/.vault-pass && chmod 600 ~/.vault-pass

# Запуск тестов
task test                 # Все роли
task test-base-system     # Конкретная роль
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
