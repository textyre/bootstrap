# Роль: ssh

**Phase**: 1 | **Направление**: Безопасность

## Цель

Роль настраивает hardened OpenSSH-сервер для безопасного удаленного доступа.

Контракт роли:

- установить OpenSSH server/client packages для поддержанного дистрибутива;
- развернуть валидный `/etc/ssh/sshd_config`;
- настроить современную криптографию OpenSSH;
- запретить небезопасные способы аутентификации по умолчанию;
- обеспечить ed25519/RSA host keys;
- включить и запустить SSH service для поддержанного init system;
- развернуть SSH banner;
- отразить SFTP chroot и Teleport CA trust в `sshd_config`, если эти возможности включены.

Роль не управляет firewall, пользователями, SSH public keys, DNS, Teleport deployment,
fail2ban или мониторингом. Это контракты соседних ролей.

## Pipeline

```text
validate -> load vars -> configure -> report
```

- `tasks/main.yml` — только оркестратор.
- `tasks/validate.yml` — проверка поддержанного OS family и init system.
- `tasks/load_vars.yml` — загрузка `vars/<os_family>/main.yml`.
- `tasks/configure/main.yml` — установка, проверка access-control для целевого пользователя, host keys, `sshd_config`, banner, service state.
- `report` — финальный execution report через `common`.

## Основные переменные

```yaml
ssh_port: 22
ssh_address_family: "inet"

ssh_permit_root_login: "no"
ssh_password_authentication: "no"
ssh_authentication_methods: "publickey"
ssh_max_auth_tries: 3

ssh_allow_groups: ["wheel"]
ssh_allow_users: []
ssh_deny_groups: []
ssh_deny_users: []
ssh_user: "{{ target_user | default(ansible_user_id) }}"

ssh_x11_forwarding: "no"
ssh_allow_tcp_forwarding: "no"
ssh_allow_stream_local_forwarding: "no"
ssh_allow_agent_forwarding: "no"

ssh_log_level: "VERBOSE"
ssh_max_startups: "10:30:60"

ssh_sftp_enabled: true
ssh_sftp_chroot_enabled: false
ssh_teleport_integration: false
```

Полный внешний контракт описан в `ansible/roles/ssh/defaults/main.yml` и README роли.

## Поддержанные платформы

| OS family | Packages | Service |
|-----------|----------|---------|
| Archlinux | `openssh` | `sshd` |
| Debian / Ubuntu | `openssh-server`, `openssh-client` | `ssh` |
| RedHat / Fedora | `openssh-server`, `openssh-clients` | `sshd` |
| Void | `openssh` | `sshd` |
| Gentoo | `net-misc/openssh` | `sshd` |

Поддержанные init systems: `systemd`, `runit`, `openrc`, `s6`, `dinit`.

## Что настраивает

- `/etc/ssh/sshd_config` из `templates/sshd_config.j2`;
- `/etc/issue.net`;
- `/etc/ssh/ssh_host_ed25519_key`;
- `/etc/ssh/ssh_host_rsa_key`, если RSA используется в `ssh_host_key_algorithms`;
- Arch/systemd: отключает `sshdgenkeys.service`, чтобы host keys управлялись этой ролью;
- SSH service enabled + started.

## Проверки и тесты

В роли нет отдельного `tasks/verify.yml`: итоговый контракт проверяется Molecule.

Molecule verify проверяет:

- `sshd -t` проходит;
- `sshd -T` строит effective OpenSSH config.

Docker scenario проверяет systemd Arch/Ubuntu containers.
Vagrant scenario проверяет реальные Arch/Ubuntu VM.

## Зависимости

- `common` — execution report.
- `firewall` — открытие SSH-порта, если порт должен быть доступен извне.
- `ssh_keys` / `user` — пользователи, группы и authorized keys.
- `fail2ban` — brute-force защита, если она нужна.
- `teleport` — выполняется раньше `ssh`; при включённом экспорте CA playbook явно передаёт `ssh_teleport_integration: true` и путь к CA.

## Ограничения

- Изменение `ssh_port` не открывает firewall port.
- `ssh_password_authentication: "no"` требует заранее настроенных SSH keys.
- `ssh_allow_groups: ["wheel"]` требует, чтобы существующий `ssh_user` был в разрешенной группе.
- SFTP chroot требует корректной ownership-модели каталогов; роль только пишет SSH config.
- Monitoring/alerting на SSH logs настраивается отдельными observability ролями.

---

Назад к [[Roadmap]]
