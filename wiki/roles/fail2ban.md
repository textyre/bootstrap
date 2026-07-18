# Роль: fail2ban

**Phase**: 2 | **Направление**: Безопасность

## Цель

Защита от brute-force атак через автоматическое блокирование IP-адресов после множественных неудачных попыток входа по SSH. Роль устанавливает Fail2Ban, настраивает `sshd` jail, включает и запускает сервис на systemd-хостах, а затем проверяет, что Fail2Ban отвечает и `sshd` jail загружен.

## Ключевые переменные (defaults)

```yaml
fail2ban_sshd_enabled: true                      # Включить sshd jail
fail2ban_sshd_port: "{{ ssh_port | default(22) }}" # Порт SSH (наследует ssh_port)
fail2ban_sshd_maxretry: 5                        # Попытки до бана (3 — строго, 10 — мягко)
fail2ban_sshd_findtime: 600                      # Окно подсчёта попыток, сек (10 мин)
fail2ban_sshd_bantime: 3600                      # Длительность бана, сек (1 час)
fail2ban_sshd_bantime_increment: true            # Прогрессивный бан (удвоение при повторах)
fail2ban_sshd_bantime_maxtime: 86400             # Верхняя граница прогрессивного бана (24 ч)
fail2ban_sshd_backend: "auto"                    # Бэкенд логов: auto, systemd, polling, pyinotify
fail2ban_sshd_banaction: ""                       # Действие бана (пусто = iptables-multiport)

fail2ban_ignoreip:                               # IP/CIDR, которые никогда не банятся
  - 127.0.0.1/8
  - "::1"
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/fail2ban/jail.d/sshd.conf` — конфигурация SSH jail (template)
- Сервис: `fail2ban` (enabled + started для systemd)
- Runtime reload: `fail2ban-client reload`, если jail изменился
- Runtime verify: `fail2ban-client ping` и `fail2ban-client status sshd`
- Пакеты: OS-specific через `vars/<os_family>/main.yml`

**Arch Linux:**
- Пакет: `fail2ban`

**Debian/Ubuntu:**
- Пакет: `fail2ban`

**Fedora/RHEL:**
- Пакет: `fail2ban`

**Void:**
- Пакет: `fail2ban`

**Gentoo:**
- Пакет: `net-analyzer/fail2ban`

## Init systems

Реальное управление сервисом сейчас реализовано только для `systemd`.
Для `runit`, `openrc`, `s6`, `dinit` роль падает явно с понятным сообщением, а не делает вид, что поддержка есть.

## Тесты

- Docker — limited install/config scenario: пакет, конфигурация и dummy auth log для config validation, без запуска сервиса и runtime verify.
- Vagrant — full runtime scenario: converge, idempotence, systemd service, `sshd` jail runtime.
- Molecule verify проверяет синтаксис Fail2Ban конфигурации через `fail2ban-server --test`.
- Runtime status проверяется самой ролью в Vagrant converge.

## Зависимости

- `common` — для report_phase и report_render (execution report)

## Tags

- `fail2ban`, `security`, `fail2ban_runtime`, `report`

---

Назад к [[Roadmap]]
