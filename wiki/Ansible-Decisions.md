# Ansible Decisions Log

Лог архитектурных решений и технических выборов для проекта bootstrap.

> **Примечание:** Пути в записях до 2026-01-31 используют старую структуру.
> После рефакторинга: `scripts/bootstrap/` → `ansible/`, `scripts/dotfiles/` → `dotfiles/`

## Ключевые решения

### Ansible Vault для sudo пароля

**Задача:** Безопасное хранение sudo пароля для Ansible.

**Решение:** Ansible Vault с AES-256 шифрованием.

1. `inventory/group_vars/all/vault.yml` — зашифрованный файл
2. `vault-pass.sh` — каскадный скрипт: `pass` → `~/.vault-pass` → ошибка
3. Molecule: `config_options.defaults.vault_password_file`

**Преимущества:**
- Шифрование AES-256, безопасен для git
- Работает через SSH (файл на диске)
- Разделение паролей (vault ≠ sudo)
- CI/CD совместимость
- Enterprise стандарт

### Централизация пакетов в group_vars

**Задача:** Убрать дублирование пакетов между ролями.

**Решение:** Все пакетные переменные в `inventory/group_vars/all/packages.yml`

**Почему group_vars/all/:**
- Ansible-стандартное место для "data layer"
- Precedence уровень 4: выше role defaults, ниже host_vars
- Per-host override: `inventory/host_vars/<hostname>/packages.yml`

### 13 модульных ролей

**Задача:** Полная автоматизация с DevOps best practices.

**Решение:** Маленькие, модульные, тестируемые, заменяемые роли.

```
base_system → vm → reflector → yay → packages → user → ssh → 
git → shell → docker → firewall → xorg → lightdm → chezmoi
```

**Преимущества:**
- Каждая роль — одна ответственность
- Molecule тесты для каждой
- Независимое развитие
- Легкая замена компонентов

### Мульти-дистро абстракция

**Задача:** Поддержка нескольких дистрибутивов.

**Решение:** OS-specific tasks через `include_tasks`:

```yaml
- include_tasks: "install-{{ ansible_os_family | lower }}.yml"
```

**Структура:**
- `archlinux.yml` — полная реализация
- `debian.yml` — заглушки для будущего

### Molecule для тестирования

**Драйвер:** `default` с `managed: false` для localhost testing

```yaml
driver:
  name: default
  options:
    managed: false

platforms:
  - name: localhost

provisioner:
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
```

### Reflector без --config флага

**Проблема:** Reflector не поддерживает `--config` флаг.

**Решение:** Параметры передаются напрямую в команде, конфиг используется только systemd timer через `@file` синтаксис.

### PATH для venv в Taskfile

**Решение:** PREFIX переменная с `env PATH=...`:

```yaml
vars:
  PREFIX: 'env PATH="{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH"'

tasks:
  check:
    cmds:
      - '{{.PREFIX}} ansible-playbook ...'
```

## Рефакторинг: безопасность, DRY, мульти-дистро

**Дата:** 2026-01-30

### Безопасность
- `pacman -Sy` → `pacman -Syu`
- nftables: добавлен `ct state invalid drop`, ICMP rate limiting
- SSH: `ClientAliveInterval 300`, `ClientAliveCountMax 2`

### DRY
- Единая `target_user` переменная в system.yml
- `dotfiles_base_dir` в system.yml

### Мульти-дистро
- Паттерн: `include_tasks: "install-{{ ansible_os_family | lower }}.yml"`
- OS-specific install файлы для user, ssh, firewall, shell, chezmoi

### Инфраструктура
- Inventory: `[local]` → `[workstations]`
- Playbook: `hosts: workstations`
- requirements.yml: Galaxy collections

## Технический долг

### Исправлено
- ✅ Захардкоженные константы перенесены в layout.toml
- ✅ Polybar restart logic оптимизирована
- ✅ SSH hardening улучшен
- ✅ Мульти-дистро абстракция внедрена

### Остается
- Conditional WM support (i3 vs Hyprland vs Sway)
- i18n support (rofi меню на разных языках)

---

Назад к [[Home]]
