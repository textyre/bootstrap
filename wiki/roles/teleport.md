# Роль: teleport

**Phase**: 2 | **Направление**: Безопасность / Доступ

## Назначение

Роль устанавливает Teleport 17 и приводит машину к одному из двух состояний:

- `standalone` -- на машине работают Auth, Proxy и SSH services, то есть это самостоятельный Teleport-кластер;
- `agent` -- машина запускает SSH service и присоединяется к уже существующему кластеру через `teleport_auth_server` и `teleport_join_token`.

Teleport SSH и системный OpenSSH `sshd` являются отдельными сервисами. Роль
`teleport` управляет первым. Опциональный экспорт user CA позволяет следующей
роли `ssh` дополнительно научить OpenSSH принимать сертификаты Teleport.

## Поток выполнения

`validate -> load vars -> install -> configure -> service -> verify -> CA export -> report`

Роль:

1. проверяет поддержанный режим, способ установки, OS и systemd-контракт;
2. устанавливает Teleport из distro package, официального APT/YUM repository или checksum-проверенного binary archive;
3. создаёт `/var/lib/teleport`, не удаляя существующие данные кластера;
4. рендерит `/etc/teleport.yaml`;
5. сразу применяет service state без handlers;
6. проверяет бинарник, парсинг конфига самим Teleport и активность управляемого сервиса;
7. после запуска сервиса опционально экспортирует user CA через `tctl` и приводит вывод к формату OpenSSH `TrustedUserCAKeys`;
8. выводит итоговый report.

## Основные переменные

| Переменная | По умолчанию | Назначение |
|------------|---------------|------------|
| `teleport_mode` | `standalone` | Самостоятельный кластер или agent существующего кластера |
| `teleport_install_method` | Debian `repo`, остальные `binary` | Источник установки; RHEL может явно выбрать официальный repository, Fedora использует binary |
| `teleport_version` | `17.7.23` | Актуальный patch ветки v17 для binary archive и major channel package repository |
| `teleport_auth_server` | `""` | Адрес существующего кластера, обязателен только для agent |
| `teleport_join_token` | `""` | Секрет первичного присоединения agent |
| `teleport_node_name` | hostname | Имя ресурса, которое видит пользователь Teleport |
| `teleport_labels` | `{}` | Метки ресурса для RBAC и поиска |
| `teleport_proxy_public_addr` | `hostname:3080` | Публичный адрес standalone Proxy/Web UI |
| `teleport_session_recording` | `node` | `node`, `node-sync`, `proxy`, `proxy-sync` или `off` |
| `teleport_enhanced_recording` | `false` | Linux BPF/cgroup v2 enhanced session recording |
| `teleport_export_ca_key` | `false` | Экспортировать user CA после успешного запуска Auth service |
| `teleport_ca_keys_file` | `/etc/ssh/teleport_user_ca.pub` | Файл CA для OpenSSH `TrustedUserCAKeys` |
| `teleport_config_overwrite` | `{}` | Явное рекурсивное переопределение полей итогового Teleport-конфига |

Переменные `teleport_manage_install`, `teleport_manage_config` и
`teleport_manage_service` позволяют оставить соответствующую фазу внешнему
владельцу. Они не отключают итоговый контракт: бинарник и конфиг всё равно
должны существовать и проходить verify.

Полный контракт переменных, обоснование значений и примеры находятся в
`ansible/roles/teleport/README.md`.

## Поддержка и тесты

- OS families: Archlinux, Debian, RedHat, Void, Gentoo.
- Service management: только systemd; для остальных init systems роль падает явно, если должна управлять сервисом.
- Docker и Vagrant проверяют Arch standalone и Ubuntu agent.
- Standalone-тест проверяет реальный HTTPS Proxy API, инициализированный кластер и экспортированный SSH CA.
- Agent-тест устанавливает настоящий binary и валидирует конфиг самим Teleport, но не запускает сервис без внешнего кластера.
- Все сценарии включают idempotence.

Основные источники реализации: [Teleport 17 CLI](https://goteleport.com/docs/ver/17.x/reference/cli/teleport/), [Teleport 17 configuration](https://goteleport.com/docs/ver/17.x/reference/config/), [Linux installation](https://goteleport.com/docs/installation/linux/) и [security notice CVE-2025-49825](https://support.goteleport.com/hc/en-us/articles/42280478593043-CVE-2025-49825-for-Cloud-Customers).

---

Назад к [[Roadmap]]
