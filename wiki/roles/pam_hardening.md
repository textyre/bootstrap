# Роль: pam_hardening

**Phase**: 2 | **Направление**: Безопасность

## Цель

Защита от brute-force через `pam_faillock`: блокировка аккаунтов после неудачных попыток входа с полной параметризацией через `/etc/security/faillock.conf`.

## Реализованные подсистемы

**Faillock** — единственная подсистема, реализованная в текущей версии.

### Planned (не реализовано)

- `pam_pwquality` — требования к сложности паролей
- `pam_limits` — лимиты на пользовательские сессии

## Ключевые переменные (defaults)

```yaml
pam_hardening_faillock_enabled: true          # Включить/выключить роль
pam_hardening_faillock_deny: 3                # Блокировка после N попыток
pam_hardening_faillock_fail_interval: 900     # Окно отслеживания (секунды)
pam_hardening_faillock_unlock_time: 900       # Время блокировки (0 = перманентная)
pam_hardening_faillock_root_unlock_time: 900  # Время блокировки root (-1 = перманентная)
pam_hardening_faillock_audit: true            # Логировать в audit log
pam_hardening_faillock_silent: false          # Подавлять сообщение при блокировке
pam_hardening_faillock_even_deny_root: true   # Root тоже подпадает под блокировку
pam_hardening_faillock_local_users_only: false  # Только локальные пользователи
pam_hardening_faillock_nodelay: false         # Убрать задержку (pam >= 1.5.1)
pam_hardening_faillock_x11_skip: false        # Игнорировать X11-сессии (screensaver)
```

## Что настраивает

- `/etc/security/faillock.conf` — параметры блокировки (Jinja2 шаблон, все платформы)
- PAM stack activation (зависит от платформы):
  - **Arch / Void / Gentoo**: `lineinfile` → `/etc/pam.d/system-auth`
  - **Debian / Ubuntu**: `pam-auth-update --package` с двумя profile файлами
  - **Fedora / RHEL**: `authselect enable-feature with-faillock`

## Платформы

| Платформа | `os_family` | Метод PAM |
|-----------|-------------|-----------|
| Arch Linux | `Archlinux` | lineinfile (system-auth) |
| Void Linux | `Void` | lineinfile (system-auth) |
| Gentoo | `Gentoo` | lineinfile (system-auth) |
| Debian / Ubuntu | `Debian` | pam-auth-update --package |
| Fedora / RHEL | `RedHat` | authselect with-faillock |

## Зависимости

Нет. Роль работает на стандартном PAM стеке.

## Tags

- `pam_hardening` — вся роль
- `pam`, `security`, `faillock` — конфигурация faillock
- `cis_5.4.2` — CIS Level 1 Workstation control
- `report` — execution report

## Безопасность

Реализует CIS Level 1 Workstation:

| CIS Control | Requirement | Реализация |
|-------------|-------------|------------|
| 5.4.2 | Lock accounts after failed logins | `deny = 3` |
| 5.4.3 | Unlock time ≥ 900s | `unlock_time = 900` |
| 5.4.4 | Root subject to lockout | `even_deny_root` |

---

Назад к [[Roadmap]]
