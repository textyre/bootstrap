# Роль: umask

**Phase**: 2 | **Направление**: Безопасность

## Цель

Установка системного umask для ограничения прав доступа к создаваемым файлам и директориям. Предотвращает создание world-readable/world-writable файлов по умолчанию. Повышает конфиденциальность данных пользователей и системных файлов.

## Ключевые переменные (defaults)

```yaml
umask_enabled: true                       # Включить настройку umask

# User umask (для обычных пользователей)
umask_user_default: "0027"                # rw-r----- для файлов, rwxr-x--- для директорий
                                           # (владелец: rw-, группа: r--, остальные: ---)

# Root umask (для суперпользователя)
umask_root_default: "0077"                # rw------- для файлов, rwx------ для директорий
                                           # (только владелец имеет доступ)

# System-wide umask (для всех процессов)
umask_system_default: "0027"              # Общесистемный umask

# Apply to shells
umask_apply_to_bash: true                 # Добавить в /etc/profile.d/umask.sh
umask_apply_to_zsh: true                  # Добавить в /etc/zsh/zshenv (если установлен)

# Apply to login.defs
umask_apply_to_login_defs: true           # Установить UMASK в /etc/login.defs

# Specific service umasks (опционально)
umask_custom_services: []                 # Список: [{service, umask}] для systemd unit overrides
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/profile.d/umask.sh` — применяется для всех shell-сессий (bash, sh)
  - `/etc/zsh/zshenv` — для zsh (если установлен)
  - `/etc/login.defs` — параметр `UMASK` для login/useradd
  - `/etc/systemd/system/<service>.service.d/umask.conf` — переопределение UMask для конкретных сервисов

**Arch Linux:**
- Применяется через `/etc/profile.d/` и `/etc/login.defs`
- Zsh: `/etc/zsh/zshenv` (пакет `zsh`)

**Debian/Ubuntu:**
- Применяется через `/etc/profile.d/` и `/etc/login.defs`
- Zsh: `/etc/zsh/zshenv` (пакет `zsh`)

## Зависимости

- Нет жестких зависимостей
- Рекомендуется запускать после `base_system` и `user`

## Tags

- `umask`, `security`, `permissions`

---

Назад к [[Roadmap]]
