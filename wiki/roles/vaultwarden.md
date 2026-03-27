# Роль: vaultwarden

**Phase**: 3 | **Направление**: Сервисы

## Цель

Развёртывание self-hosted менеджера паролей Vaultwarden (Bitwarden-совместимый) через Docker Compose с реверс-прокси Caddy. Обеспечивает безопасное хранение паролей, TOTP-токенов, заметок и вложений с автоматическим бэкапом SQLite.

## Ключевые переменные (defaults)

```yaml
vaultwarden_enabled: true                # Включить/выключить роль

# Домен для Caddy и Vaultwarden DOMAIN env var
vaultwarden_domain: "vault.local"

# Корневая директория для compose, data/, backups/
vaultwarden_base_dir: "/opt/vaultwarden"

# Docker network (совпадает с caddy_docker_network)
vaultwarden_docker_network: "proxy"

# Admin panel — отключить после первоначальной настройки
vaultwarden_admin_enabled: true

# Регистрация — отключить после создания аккаунта
vaultwarden_signups_allowed: true

# Безопасность (dict + overwrite pattern)
vaultwarden_security:
  password_iterations: 600000           # OWASP 2023: min 310000
  login_ratelimit_max_burst: 5
  login_ratelimit_seconds: 60
  admin_ratelimit_max_burst: 3
  admin_ratelimit_seconds: 60
vaultwarden_security_overwrite: {}      # Пользовательские переопределения

# Бэкап (dict + overwrite pattern)
vaultwarden_backup:
  enabled: true
  dir: "/opt/vaultwarden/backups"
  keep_days: 30
  cron_hour: "3"
  cron_minute: "0"
vaultwarden_backup_overwrite: {}        # Пользовательские переопределения

# Профили (ROLE-009)
vaultwarden_profile_security_signups    # false при security профиле
vaultwarden_profile_security_admin      # false при security профиле
```

## Что настраивает

- Директории:
  - `{{ vaultwarden_base_dir }}/` (0755) — корневая директория
  - `{{ vaultwarden_base_dir }}/data/` (0700) — данные Vaultwarden
  - `{{ vaultwarden_backup.dir }}/` (0755) — бэкапы
- Конфигурационные файлы:
  - `{{ vaultwarden_base_dir }}/docker-compose.yml` (0644) — Docker Compose конфигурация
  - `{{ caddy_base_dir }}/sites/vault.caddy` (0644) — Caddy site config с HSTS и security headers
  - `{{ vaultwarden_base_dir }}/.admin_token` (0600) — admin token (auto-generated)
  - `{{ vaultwarden_base_dir }}/backup.sh` (0700) — скрипт бэкапа SQLite
- DNS: запись `127.0.0.1 {{ vaultwarden_domain }}` в `/etc/hosts`
- Контейнер: `vaultwarden/server:latest` через Docker Compose
- Cron: ежедневный бэкап SQLite + ротация старых бэкапов

**Кросс-платформенные различия:**

| Аспект | Arch | Debian/Ubuntu | Fedora/RHEL | Void | Gentoo |
|--------|------|---------------|-------------|------|--------|
| Cron сервис | `cronie` | `cron` | `crond` | `cronie` | `cronie` |
| Пакет sqlite | `sqlite3` | `sqlite3` | `sqlite` | `sqlite` | `sqlite` |
| Пакет cron | `cronie` | `cron` | `cronie` | `cronie` | `cronie` |

## Зависимости

- `docker` — Docker Engine (мета-зависимость в `meta/main.yml`)
- `caddy` — Caddy reverse proxy (мета-зависимость в `meta/main.yml`)
- `common` — отчёты `report_phase.yml` / `report_render.yml` (via `include_role`)

## Tags

| Tag | Что запускает | Использование |
|-----|--------------|---------------|
| `vaultwarden` | Вся роль | Полное применение |
| `secrets` | Задачи с секретами (token, compose, caddy) | Обновление конфигурации |
| `report` | Отчёты ROLE-008 | Перегенерация отчёта |
| `molecule-notest` | Docker Compose up, cron service start | Пропускается в molecule |
| `profile:security` | Задачи, зависящие от security профиля | Применение security hardening |

## Backup & Recovery

### Автоматический бэкап

Скрипт `backup.sh` запускается через cron (по умолчанию ежедневно в 03:00):

1. `sqlite3 .backup` — безопасный бэкап SQLite (не блокирует БД)
2. `tar` вложений (если директория `attachments/` существует)
3. `find -mtime +N -delete` — ротация бэкапов старше `keep_days` дней

### Восстановление

```bash
# Остановить контейнер
cd /opt/vaultwarden && docker compose down

# Восстановить SQLite
cp backups/db-YYYYMMDD-HHMMSS.sqlite3 data/db.sqlite3

# Восстановить вложения (если есть)
tar -xzf backups/attachments-YYYYMMDD-HHMMSS.tar.gz -C data/

# Запустить контейнер
docker compose up -d
```

---

Назад к [[Roadmap]]
