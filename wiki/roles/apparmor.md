# Роль: apparmor

**Phase**: 9 | **Направление**: Безопасность

## Цель

Внедрение Mandatory Access Control (MAC) через AppArmor для ограничения прав доступа процессов к системным ресурсам. Создание профилей безопасности для критичных сервисов (sshd, docker, caddy, nginx) для минимизации последствий компрометации. Работает на уровне ядра Linux.

## Ключевые переменные (defaults)

```yaml
apparmor_enabled: true                    # Включить AppArmor
apparmor_enable_service: true             # Запустить apparmor.service

# Режим работы профилей
apparmor_mode: enforce                    # enforce (блокировка), complain (логирование), disable

# Стандартные профили
apparmor_enable_default_profiles: true    # Активировать дефолтные профили из пакета
apparmor_profiles_enforce: []             # Список профилей для режима enforce: ["sshd", "nginx"]
apparmor_profiles_complain: []            # Список профилей для режима complain (тестирование)

# Кастомные профили
apparmor_custom_profiles: []              # Список путей к кастомным профилям: ["/path/to/profile"]

# Профили для популярных сервисов
apparmor_profile_sshd: true               # Профиль для sshd
apparmor_profile_docker: true             # Профиль для dockerd
apparmor_profile_caddy: false             # Профиль для caddy (если установлен)
apparmor_profile_nginx: false             # Профиль для nginx (если установлен)

# Logging
apparmor_audit_denied: true               # Логировать заблокированные операции в audit.log
apparmor_audit_allowed: false             # Логировать разрешенные операции (debug)
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/apparmor.d/` — директория с профилями безопасности
  - `/etc/apparmor.d/tunables/` — переменные для профилей
  - `/etc/apparmor/parser.conf` — настройки парсера профилей
  - `/sys/kernel/security/apparmor/` — интерфейс ядра (securityfs)
- Сервис: `apparmor.service` (enabled + started)
- Логи: `/var/log/audit/audit.log` (если включен auditd) или `journalctl -u apparmor`

**Arch Linux:**
- Пакеты: `apparmor`, `audit` (опционально)
- Kernel parameter: `apparmor=1 security=apparmor` в `/etc/default/grub` → `grub-mkconfig`
- Профили: `/etc/apparmor.d/` (из пакета `apparmor`)

**Debian/Ubuntu:**
- Пакеты: `apparmor`, `apparmor-utils`, `apparmor-profiles`, `apparmor-profiles-extra`
- Kernel: AppArmor включен по умолчанию
- Профили: `/etc/apparmor.d/` (больше готовых профилей из коробки)

## Зависимости

- `base_system` — AppArmor требует поддержки в ядре (CONFIG_SECURITY_APPARMOR)
- `auditd` (опционально) — для расширенного логирования
- Сервисы (`sshd`, `docker`, `caddy`) должны быть установлены до применения профилей

## Tags

- `apparmor`, `security`, `mac`, `mandatory_access_control`

---

Назад к [[Roadmap]]
