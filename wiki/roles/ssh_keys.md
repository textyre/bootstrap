# Роль: ssh_keys

**Phase**: 2 | **Направление**: Безопасность

## Цель

Управление SSH authorized_keys для пользовательских аккаунтов и опциональная генерация SSH-ключей на целевых машинах. Обеспечивает единую точку управления SSH-доступом через данные из `accounts` (общий источник с ролью `user`). Поддерживает exclusive-режим для удаления неучтённых ключей.

## Ключевые переменные (defaults)

```yaml
ssh_keys_manage_authorized_keys: true    # Развернуть authorized_keys из accounts
ssh_keys_generate_user_keys: false       # Генерировать SSH-ключи на целевых машинах
ssh_keys_key_type: ed25519               # Тип ключа: ed25519, rsa, ecdsa
ssh_keys_exclusive: false                # Удалять ключи не из accounts[].ssh_keys
```

## Что настраивает

- Файлы:
  - `~/.ssh/` — директория, mode 0700, владелец = пользователь
  - `~/.ssh/authorized_keys` — файл с публичными ключами, mode 0600
  - `~/.ssh/id_<key_type>` — приватный ключ (при keygen), mode 0600
  - `~/.ssh/id_<key_type>.pub` — публичный ключ (при keygen)
- Удаление:
  - `authorized_keys` для пользователей с `state: absent`
  - Неучтённые ключи при `ssh_keys_exclusive: true`

**Все платформы:**
- Роль не устанавливает пакетов и не управляет сервисами
- Одинаковое поведение на всех пяти OS family (Archlinux, Debian, RedHat, Void, Gentoo)

## Audit Events

| События | Источник | Формат | Значение |
|---------|----------|--------|----------|
| **Добавление ключа** | ansible.posix.authorized_key | Ansible stdout (no_log) | Новый публичный ключ добавлен в authorized_keys |
| **Удаление ключа (exclusive)** | ansible.posix.authorized_key | Ansible stdout (no_log) | Ключ удалён из authorized_keys (не в accounts) |
| **Удаление authorized_keys** | ansible.builtin.file | Ansible stdout | Файл удалён для пользователя с state: absent |
| **Генерация ключа** | community.crypto.openssh_keypair | Ansible stdout | Новая ключевая пара создана |
| **Ошибка прав доступа** | tasks/verify.yml assert | Ansible stderr | .ssh mode != 0700 или authorized_keys не найден |

## Мониторинг

SSH key management не имеет runtime-метрик (нет демона). Мониторинг обеспечивается через:

- **Ansible execution report** — `common/report_phase.yml` логирует количество обработанных пользователей, статус keygen, exclusive mode
- **File integrity** — `aide` или `auditd` могут отслеживать изменения в `~/.ssh/authorized_keys`
- **Git audit trail** — изменения `accounts[].ssh_keys` в inventory отслеживаются через git log

## Зависимости

- `user` — роль создания пользователей (должна выполняться раньше, чтобы home-директории существовали)
- `common` — reporting framework (`report_phase.yml`, `report_render.yml`)

**Коллекции** (объявлены в `ansible/requirements.yml`):
- `ansible.posix` >= 1.5.0 — модуль `authorized_key`
- `community.crypto` >= 2.0.0 — модуль `openssh_keypair` (только при `ssh_keys_generate_user_keys: true`)

## Tags

- `ssh_keys`, `security`, `report`

---

Назад к [[Roadmap]]
