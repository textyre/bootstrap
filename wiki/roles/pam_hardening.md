# Роль: pam_hardening

**Phase**: 2 | **Направление**: Безопасность

## Цель

Усиление политик аутентификации и авторизации через PAM (Pluggable Authentication Modules): требования к сложности паролей, ограничение количества неудачных попыток входа, история паролей, лимиты на пользовательские сессии. Защита от брутфорса и слабых паролей.

## Ключевые переменные (defaults)

```yaml
pam_hardening_enabled: true               # Включить PAM hardening

# Password quality (pam_pwquality)
pam_password_min_length: 12               # Минимальная длина пароля
pam_password_require_lowercase: 1         # Минимум строчных букв
pam_password_require_uppercase: 1         # Минимум заглавных букв
pam_password_require_digit: 1             # Минимум цифр
pam_password_require_special: 1           # Минимум спецсимволов
pam_password_max_repeat: 3                # Макс. повторяющихся символов подряд
pam_password_reject_username: true        # Запретить использование username в пароле

# Password history (pam_unix)
pam_password_remember: 5                  # Помнить N последних паролей

# Account lockout (pam_faillock)
pam_faillock_enabled: true                # Включить блокировку после неудачных попыток
pam_faillock_deny: 3                      # Число попыток до блокировки
pam_faillock_unlock_time: 900             # Время блокировки в секундах (15 минут)
pam_faillock_fail_interval: 900           # Окно времени для подсчета попыток
pam_faillock_audit: true                  # Логирование в audit
pam_faillock_silent: true                 # Не показывать пользователю причину отказа

# Session limits (pam_limits)
pam_limits_enabled: true                  # Включить ulimit через /etc/security/limits.conf
pam_limits_max_logins: 3                  # Макс. одновременных сессий на пользователя
pam_limits_nofile: 65536                  # Макс. открытых файлов (soft/hard)
pam_limits_nproc: 4096                    # Макс. процессов
pam_limits_custom: []                     # Список кастомных лимитов: [{domain, type, item, value}]
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/security/pwquality.conf` — требования к паролям (pam_pwquality)
  - `/etc/security/faillock.conf` — настройки блокировки аккаунта (pam_faillock)
  - `/etc/security/limits.conf` — ulimit для пользователей и групп
  - `/etc/pam.d/system-auth` или `/etc/pam.d/common-auth` — интеграция PAM-модулей
  - `/etc/pam.d/passwd` — правила смены пароля

**Arch Linux:**
- Пакеты: `pam`, `libpwquality`
- Файлы: `/etc/pam.d/system-auth`, `/etc/pam.d/system-login`

**Debian/Ubuntu:**
- Пакеты: `libpam-modules`, `libpam-pwquality`, `libpam-tmpdir`
- Файлы: `/etc/pam.d/common-auth`, `/etc/pam.d/common-password`

## Зависимости

- `base_system` — базовая настройка PAM уже должна быть выполнена
- `user` — применяется к существующим пользователям

## Tags

- `pam_hardening`, `security`, `authentication`

---

Назад к [[Roadmap]]
