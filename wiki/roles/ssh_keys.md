# Роль: ssh_keys

**Phase**: 2 | **Направление**: Безопасность

## Цель

Управление SSH authorized_keys и генерация SSH-ключей для пользователей. Обеспечивает контроль доступа к системе через SSH-ключи: развёртывание публичных ключей из центрального источника данных (`accounts`), удаление ключей при деактивации пользователя, и опциональная генерация ключевых пар на целевых машинах. Поддерживает exclusive-режим для удаления неучтённых ключей.

## Ключевые переменные (defaults)

```yaml
ssh_keys_manage_authorized_keys: true   # Развёртывание authorized_keys из accounts[].ssh_keys
ssh_keys_generate_user_keys: false      # Генерация SSH-ключей на целевых машинах
ssh_keys_key_type: ed25519              # Тип ключа: ed25519, rsa, ecdsa
ssh_keys_exclusive: false               # Удалить ключи, не указанные в accounts[].ssh_keys

# Источник данных (общий с user ролью)
ssh_keys_users: "{{ accounts | default([...]) }}"

# Поддерживаемые ОС
ssh_keys_supported_os:
  - Archlinux
  - Debian
  - RedHat
  - Void
  - Gentoo
```

## Что настраивает

- Файлы:
  - `~/.ssh/` — директория, mode 0700, владелец = пользователь
  - `~/.ssh/authorized_keys` — публичные ключи для авторизации (mode 0600, управляется `ansible.posix.authorized_key`)
  - `~/.ssh/id_<key_type>` / `~/.ssh/id_<key_type>.pub` — генерируемые ключевые пары (mode 0600, при `ssh_keys_generate_user_keys: true`)
- Удаление:
  - `authorized_keys` для пользователей с `state: absent`
  - Неучтённые ключи при `ssh_keys_exclusive: true`

**Все платформы:**
- Роль не устанавливает пакетов и не управляет сервисами
- sshd перезапуск управляется ролью `ssh`, не `ssh_keys`
- Одинаковое поведение на всех пяти OS family (Archlinux, Debian, RedHat, Void, Gentoo)

## Audit Events

| Событие | Источник | Формат | Значение |
|---------|----------|--------|----------|
| **Добавление SSH-ключа** | ansible.posix.authorized_key | Ansible changed | Новый публичный ключ добавлен в authorized_keys |
| **Удаление SSH-ключа (exclusive)** | ansible.posix.authorized_key | Ansible changed | Незадекларированный ключ удалён из authorized_keys |
| **Удаление authorized_keys** | ansible.builtin.file state=absent | Ansible changed | authorized_keys удалён для деактивированного пользователя |
| **Генерация ключевой пары** | community.crypto.openssh_keypair | Ansible changed | Новая ключевая пара создана для пользователя |
| **SSH-вход с ключом** | sshd | auth.log / journalctl -u sshd | `Accepted publickey for <user> from <ip>` |
| **SSH-отказ (ключ не найден)** | sshd | auth.log / journalctl -u sshd | `Connection closed by authenticating user <user>` |
| **Ошибка прав доступа** | tasks/verify.yml assert | Ansible stderr | .ssh mode != 0700 или authorized_keys не найден |

## Мониторинг (интеграция)

SSH-авторизация мониторится через sshd, не через эту роль:

- **Prometheus/node_exporter**: количество SSH-сессий через `node_textfile_collector`
- **Alloy pipeline**: парсинг auth.log для метрик SSH-авторизации
- **Auditd** (если включен): `auditctl -w /home/<user>/.ssh/authorized_keys -p wa`
- **Ansible execution report** — `common/report_phase.yml` логирует количество обработанных пользователей, статус keygen, exclusive mode
- **Git audit trail** — изменения `accounts[].ssh_keys` в inventory отслеживаются через git log

### Рекомендуемые алерты

```yaml
groups:
  - name: ssh_keys_drift
    rules:
      - alert: SSHAuthorizedKeysModified
        expr: node_textfile_ssh_authorized_keys_modified > 0
        for: 1m
        annotations:
          summary: "authorized_keys modified outside Ansible on {{ $labels.instance }}"
          runbook: "wiki/runbooks/ssh-keys-drift.md"
```

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
