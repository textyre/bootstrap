# Роль: teleport

**Phase**: 2 | **Направление**: Безопасность / Доступ

## Цель

Установка и настройка агента Teleport — платформы для zero-trust SSH-доступа с сертификатной авторизацией. Роль устанавливает `teleport`, разворачивает конфигурацию (`/etc/teleport.yaml` v3-формат) и интегрируется с ролью `ssh` через экспорт CA-ключа.

## Ключевые переменные (defaults)

```yaml
teleport_enabled: true              # Включить/выключить роль

# === Подсистемные переключатели (ROLE-010) ===
teleport_manage_install: true       # Управлять установкой
teleport_manage_config: true        # Управлять конфигурацией
teleport_manage_service: true       # Управлять сервисом

# === Обязательные ===
teleport_auth_server: ""            # Auth/proxy адрес: "auth.example.com:443"
teleport_join_token: ""             # Join-токен кластера

# === Основные ===
teleport_version: "17.4.10"         # Версия для binary/repo метода
teleport_node_name: "{{ ansible_hostname }}"
teleport_labels: {}                 # RBAC-метки узла
teleport_session_recording: "node"  # node | proxy | off
teleport_enhanced_recording: false  # BPF-запись (требует kernel ≥ 5.8)

# === Интеграция с ssh ролью ===
teleport_export_ca_key: true
teleport_ca_keys_file: /etc/ssh/teleport_user_ca.pub

# === Override dict (ROLE-010) ===
teleport_config_overwrite: {}       # Произвольные ключи в teleport.yaml
```

## Что настраивает

- **Установка**: пакет (Arch AUR), официальный репозиторий (Debian/RedHat), или binary с CDN (Void/Gentoo)
- **Конфигурация**:
  - `/var/lib/teleport/` (0750) — директория данных
  - `/etc/teleport.yaml` (0600) — конфигурация агента (v3-формат)
- **Systemd unit** (только binary-метод): `/etc/systemd/system/teleport.service`
- **CA-экспорт**: при `teleport_export_ca_key: true` — записывает CA-ключ в `teleport_ca_keys_file` и устанавливает fact `teleport_ca_deployed: true` (роль `ssh` читает его для вычисления `ssh_teleport_integration`)

## Зависимости

- `common` — отчёты `report_phase.yml` / `report_render.yml` (via `include_role`)
- `ssh` — опциональная интеграция: `teleport` должен запускаться до `ssh` для передачи CA-факта

## Tags

| Tag | Что запускает | Использование |
|-----|--------------|---------------|
| `teleport` | Вся роль | Полное применение |
| `teleport,install` | Только установка | Обновление бинарника без смены конфига |
| `teleport,security` | Валидация join-токена + CA-экспорт | Обновление CA после ротации кластера |
| `teleport,service` | Управление сервисом | Перезапуск без применения конфига |
| `teleport,report` | Отчёты ROLE-008 | Перегенерация отчёта |

## Кросс-платформенные различия

| Аспект | Arch | Debian/Ubuntu | Fedora/RHEL | Void | Gentoo |
|--------|------|---------------|-------------|------|--------|
| Метод установки | AUR пакет | APT репо | YUM репо | binary CDN | binary CDN |
| Пакет | `teleport-bin` | `teleport` | `teleport` | — | — |
| Systemd unit | из пакета | из пакета | из пакета | роль деплоит | роль деплоит |
| Конфиг | `/etc/teleport.yaml` | `/etc/teleport.yaml` | `/etc/teleport.yaml` | `/etc/teleport.yaml` | `/etc/teleport.yaml` |

## Ограничения

| Ограничение | Подробности |
|-------------|-------------|
| AUR не тестируется в CI | `teleport-bin` — AUR-пакет; molecule-сценарии используют binary-метод |
| Сервис требует живого кластера | `teleport.service` не перейдёт в `running` без валидного `auth_server` + `join_token` |
| CA-экспорт требует `tctl` | Экспорт CA работает только при подключённом к кластеру `tctl`; в offline/CI не выполняется |
| BPF требует kernel ≥ 5.8 | `teleport_enhanced_recording: true` требует BTF-поддержки ядра |

---

Назад к [[Roadmap]]
