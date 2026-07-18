# Роль: teleport

**Phase**: 2 | **Направление**: Безопасность / Доступ

## Назначение

Роль устанавливает Teleport 17 и приводит машину к одному из двух состояний:

- `standalone` -- на машине работают Auth, Proxy и SSH services, то есть это самостоятельный Teleport-кластер;
- `agent` -- машина запускает SSH service и присоединяется к уже существующему кластеру через `teleport_auth_server` и `teleport_join_token`.

Teleport SSH и системный OpenSSH `sshd` являются отдельными сервисами. Роль
`teleport` управляет первым. В standalone она экспортирует user CA, после чего
следующая роль `ssh` настраивает OpenSSH принимать сертификаты Teleport.

## Поток выполнения

`validate -> install -> configure -> service -> verify -> CA export -> report`

Роль:

1. проверяет поддержанный режим и один из пяти дистрибутивов, а для управляемого ролью agent-конфига -- адрес кластера и join token;
2. устанавливает заданную версию Teleport из официального архива одинаково на всех пяти дистрибутивах и проверяет опубликованный SHA-256 checksum;
3. создаёт `/var/lib/teleport` и рендерит `/etc/teleport.yaml`, не удаляя существующие данные кластера;
4. сразу применяет service state без handlers;
5. проверяет парсинг конфига самим Teleport;
6. в standalone после запуска сервиса экспортирует user CA через `tctl` и приводит вывод к формату OpenSSH `TrustedUserCAKeys`;
7. выводит итоговый report.

## Основные переменные

| Переменная | По умолчанию | Назначение |
|------------|---------------|------------|
| `teleport_mode` | `standalone` | Самостоятельный кластер или agent существующего кластера |
| `teleport_version` | `17.7.23` | Точная версия Teleport, одинаковая для всех поддержанных дистрибутивов |
| `teleport_auth_server` | `""` | Адрес существующего кластера, обязателен только для agent |
| `teleport_join_token` | `""` | Секрет первичного присоединения agent |
| `teleport_node_name` | hostname | Имя ресурса, которое видит пользователь Teleport |
| `teleport_labels` | `{}` | Метки ресурса для RBAC и поиска |
| `teleport_proxy_public_addr` | `hostname:3080` | Публичный адрес standalone Proxy/Web UI |
| `teleport_session_recording` | `node` | `node`, `node-sync`, `proxy`, `proxy-sync` или `off` |
| `teleport_enhanced_recording` | `false` | Linux BPF/cgroup v2 enhanced session recording |
| `teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | Файл CA для OpenSSH `TrustedUserCAKeys` |
| `teleport_config_overwrite` | `{}` | Явное рекурсивное переопределение полей итогового Teleport-конфига |

Полный контракт переменных, обоснование значений и примеры находятся в
`ansible/roles/teleport/README.md`.

## Поддержка и тесты

- Дистрибутивы: Arch Linux, Ubuntu, Fedora, Void и Gentoo.
- Service management: только systemd; для остальных init systems роль падает явно, если должна управлять сервисом.
- Docker и Vagrant проверяют Arch standalone и Ubuntu agent.
- Standalone-тест проверяет реальный HTTPS Proxy API, инициализированный кластер и экспортированный SSH CA.
- Agent-тест устанавливает настоящий binary и валидирует конфиг самим Teleport, но не заявляет регистрацию во внешнем кластере.
- Все сценарии включают idempotence.

Основные источники реализации: [Teleport 17 CLI](https://goteleport.com/docs/ver/17.x/reference/cli/teleport/), [Teleport 17 configuration](https://goteleport.com/docs/ver/17.x/reference/config/), [Linux installation](https://goteleport.com/docs/installation/linux/) и [security notice CVE-2025-49825](https://support.goteleport.com/hc/en-us/articles/42280478593043-CVE-2025-49825-for-Cloud-Customers).

---

Назад к [[Roadmap]]
