# Ansible Workstation Bootstrap

13 модульных ролей для полной настройки Arch Linux рабочей станции.

## Быстрый старт

```bash
# Из корня репозитория:
task bootstrap   # Установить Python зависимости (один раз)
task workstation # Применить все 14 ролей
```

## Команды

| Команда | Описание |
|---------|----------|
| `task bootstrap` | Установить Python зависимости |
| `task check` | Проверить синтаксис playbooks |
| `task lint` | ansible-lint best practices |
| `task test` | Все molecule тесты (14 ролей) |
| `task test-<role>` | Тест конкретной роли |
| `task dry-run` | Показать изменения без применения |
| `task workstation` | Применить полный playbook |
| `task all` | check + lint |
| `task clean` | Удалить venv |

## Роли

### System Foundation
- **base_system** — локаль, таймзона, hostname, pacman.conf
- **vm** — определение VM окружения, специфичные настройки
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

## Структура проекта

```
ansible/
├── ansible.cfg
├── requirements.txt          # Python deps
├── requirements.yml          # Galaxy collections
├── vault-pass.sh             # Vault password resolver
├── inventory/
│   ├── hosts.ini
│   └── group_vars/all/
│       ├── packages.yml      # Реестр пакетов (data layer)
│       ├── system.yml        # Системные переменные (9 ролей)
│       └── vault.yml         # Encrypted sudo password (AES-256)
├── playbooks/
│   ├── workstation.yml       # 14 ролей в 7 фазах
│   └── mirrors-update.yml    # Только зеркала
└── roles/                    # 14 модульных ролей
    ├── base_system/
    ├── vm/
    ├── reflector/
    ├── yay/
    ├── packages/
    ├── user/
    ├── ssh/
    ├── git/
    ├── shell/
    ├── docker/
    ├── firewall/
    ├── xorg/
    ├── lightdm/
    └── chezmoi/
```

## Структура роли

Каждая роль следует Galaxy-совместимой структуре:

```
roles/role_name/
├── defaults/main.yml         # Переменные по умолчанию
├── tasks/
│   ├── main.yml              # Точка входа
│   ├── archlinux.yml         # Arch-specific tasks
│   └── debian.yml            # Debian-specific tasks (заглушки)
├── handlers/main.yml         # Service handlers
├── templates/                # Jinja2 templates
├── meta/main.yml             # Galaxy metadata
└── molecule/                 # Integration tests
    └── default/
        ├── converge.yml
        ├── molecule.yml
        └── verify.yml
```

## Добавление новой роли

1. Создать структуру директорий
2. Реализовать OS-specific tasks через `include_tasks`
3. Добавить теги для selective execution
4. Написать Molecule тесты
5. Обеспечить идемпотентность

## Мульти-дистро поддержка

Паттерн для кроссплатформенных ролей:

```yaml
- name: Install packages (OS-specific)
  include_tasks: "install-{{ ansible_os_family | lower }}.yml"
```

Текущая поддержка:
- **Archlinux** — полная
- **Debian** — заглушки (для будущего расширения)

---

Назад к [[Home]]
