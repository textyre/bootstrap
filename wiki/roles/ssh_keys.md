# Роль: ssh_keys

**Phase**: 2 | **Направление**: Безопасность

## Цель

`ssh_keys` управляет SSH-файлами одного существующего пользователя:

- создает `~/.ssh` для `ssh_keys_user`;
- при наличии публичных ключей записывает их в `~/.ssh/authorized_keys`;
- генерирует ключевую пару пользователя на целевой машине.

Роль не создает и не удаляет пользователей, не настраивает `sshd`, не перезапускает SSH-сервис, не управляет firewall и не устанавливает пакеты. Эти контракты принадлежат соседним ролям.

## Ключевые переменные

```yaml
ssh_keys_user: "{{ target_user }}"       # Существующий пользователь
ssh_keys_authorized_keys: []             # Публичные ключи для входа на эту машину
ssh_keys_exclusive: false                # Удалять ключи, которых нет в ssh_keys_authorized_keys
ssh_keys_generate_user_key: true         # Генерировать keypair на целевой машине
ssh_keys_user_key_type: ed25519          # Тип генерируемого ключа
```

Конкретные значения задаются в inventory. `defaults/main.yml` описывает внешний контракт роли.

## Pipeline

1. `validate.yml` — проверяет поддержанную OS family.
2. `detect.yml` — читает passwd database, чтобы получить home directory пользователя.
3. `configure/main.yml` — применяет состояние `.ssh`, `authorized_keys` и keypair.
4. `report` — выводит финальный execution report через `common`.

Отдельной assertion-фазы нет: успешный converge и idempotence являются тестовым сигналом.

## Что настраивает

| Объект | Состояние |
|--------|-----------|
| `~/.ssh` | Директория `ssh_keys_user`, mode `0700`, owner=user |
| `~/.ssh/authorized_keys` | Публичные ключи из `ssh_keys_authorized_keys`; не управляется, если список пустой |
| `~/.ssh/id_<type>` | Приватный ключ, если `ssh_keys_generate_user_key: true` |
| `~/.ssh/id_<type>.pub` | Публичный ключ, если keygen включен |

`authorized_keys` — это вход на машину. Туда кладутся публичные ключи людей или систем, которым разрешен SSH-вход под `ssh_keys_user`.

Сгенерированный `id_<type>` — это исходящая идентичность самой машины. Его публичную часть можно добавить, например, в GitHub/GitLab deploy keys или account keys.

## Границы роли

- Пользователя создает роль `user`.
- SSH daemon policy настраивает роль `ssh`.
- OpenSSH client tools должны быть доступны до включения keygen.
- Monitoring/audit SSH-доступа делается через sshd/auditd/логовую подсистему, не через эту роль.

## Тестовые сценарии

Molecule запускает syntax, prepare, converge и idempotence. Shared converge применяет:

- deployment `authorized_keys`;
- exclusive replacement старого неописанного ключа;
- generated private/public keypair.

Отдельного Ansible playbook с `assert`/`stat`/`slurp` для повторной проверки результатов модулей нет.

Docker используется как контейнерная среда, Vagrant — как VM-сценарий.

## Зависимости

- `user` — должен создать `ssh_keys_user` до запуска `ssh_keys`.
- `common` — execution reporting.
- `ansible.posix` — `authorized_key`.
- `community.crypto` — `openssh_keypair`.

## Операционные события

| Событие | Источник |
|---------|----------|
| Добавление/изменение authorized key | Ansible changed от `ansible.posix.authorized_key` |
| Удаление неописанного ключа | Ansible changed при `ssh_keys_exclusive: true` |
| Генерация keypair | Ansible changed от `community.crypto.openssh_keypair` |
| SSH login/failure | sshd logs, вне контракта роли |

---

Назад к [[Roadmap]]
