# Роль: lynis

**Phase**: 9 | **Направление**: Безопасность

## Цель

Автоматизированный аудит безопасности системы через Lynis — open-source security auditing tool. Проверка соответствия стандартам безопасности (CIS Benchmarks, STIG, PCI-DSS): hardening SSH, firewall, kernel parameters, file permissions, outdated packages, malware signatures. Генерация отчетов с рекомендациями по улучшению security posture.

## Ключевые переменные (defaults)

```yaml
lynis_enabled: true                       # Включить Lynis
lynis_install_from_git: false             # Установить из Git (latest), иначе из пакетного менеджера

# Автоматический аудит
lynis_auto_audit: true                    # Запускать аудит автоматически после установки
lynis_cron_enabled: true                  # Регулярный аудит через cron/timer
lynis_cron_schedule: "0 3 * * 0"          # Расписание (еженедельно по воскресеньям в 3:00)

# Опции аудита
lynis_audit_system: true                  # Аудит системы (kernel, boot, services)
lynis_audit_storage: true                 # Аудит дисков, file systems, mount options
lynis_audit_filesystems: true             # Проверка прав доступа к критическим файлам
lynis_audit_boot: true                    # Bootloader, kernel parameters
lynis_audit_authentication: true          # PAM, SSH, password policies
lynis_audit_networking: true              # Firewall, open ports, network parameters
lynis_audit_software: true                # Установленные пакеты, уязвимости
lynis_audit_logging: true                 # syslog, auditd, journald
lynis_audit_crypto: true                  # Certificates, SSL/TLS, entropy

# Профиль аудита
lynis_profile: default                    # default, server, docker, custom
lynis_custom_profile_path: ""             # Путь к кастомному профилю

# Настройки отчетов
lynis_report_file: /var/log/lynis/lynis-report.dat   # Файл отчета (machine-readable)
lynis_log_file: /var/log/lynis/lynis.log             # Лог выполнения аудита
lynis_upload_reports: false               # Загружать отчеты в Lynis Enterprise (CISOfy)
lynis_email_reports: false                # Отправлять отчеты на email
lynis_email_to: root@localhost            # Email для отчетов

# Уровень строгости
lynis_hardening_index_threshold: 75       # Минимальный Hardening Index (0-100)
lynis_warnings_only: false                # Показывать только warnings (без suggestions)

# Пользовательские тесты
lynis_skip_tests: []                      # Список тестов для пропуска: ["AUTH-9328", "FILE-6310"]
lynis_custom_tests: []                    # Пути к кастомным тестам
```

## Что настраивает

- Установка:
  - **Из пакета**: `/usr/bin/lynis` (стабильная версия)
  - **Из Git**: `/opt/lynis/lynis` (latest version)
- Конфигурация:
  - `/etc/lynis/default.prf` — дефолтный профиль аудита
  - `/etc/lynis/custom.prf` — кастомные настройки (опционально)
- Отчеты:
  - `/var/log/lynis/lynis-report.dat` — machine-readable отчет
  - `/var/log/lynis/lynis.log` — лог выполнения
- Автоматизация:
  - Cron job: `/etc/cron.weekly/lynis` или systemd timer `lynis-audit.timer`
  - Скрипт: `/usr/local/bin/lynis-audit.sh` (wrapper для email reports)

**Arch Linux:**
- Пакет: `lynis` (AUR)
- Установка из Git: `/opt/lynis` (рекомендуется для latest версии)
- Конфиг: `/etc/lynis/default.prf`

**Debian/Ubuntu:**
- Пакет: `lynis` (из official repos, может быть устаревшим)
- Установка из Git: `/opt/lynis` (рекомендуется)
- Конфиг: `/etc/lynis/default.prf`

## Зависимости

- Нет жестких зависимостей
- Рекомендуется запускать после всех security ролей: `fail2ban`, `pam_hardening`, `apparmor`, `auditd`, `aide`
- Опционально: `mail` или `sendmail` для отправки email-отчетов

## Tags

- `lynis`, `security`, `audit`, `compliance`

---

Назад к [[Roadmap]]
