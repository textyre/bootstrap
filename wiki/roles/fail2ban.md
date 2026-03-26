# Роль: fail2ban

**Phase**: 2 | **Направление**: Безопасность

## Цель

Защита от brute-force атак через автоматическое блокирование IP-адресов после множественных неудачных попыток входа по SSH. Отслеживает логи SSH-сервиса и добавляет правила блокировки через настроенный banaction (iptables/nftables/firewalld).

## Ключевые переменные (defaults)

```yaml
fail2ban_enabled: true                           # Включить роль fail2ban
fail2ban_start_service: true                     # Запускать сервис (false для контейнеров)

# SSH jail
fail2ban_sshd_enabled: true                      # Включить sshd jail
fail2ban_sshd_port: "{{ ssh_port | default(22) }}" # Порт SSH (наследует ssh_port)
fail2ban_sshd_maxretry: 5                        # Попытки до бана (3 — строго, 10 — мягко)
fail2ban_sshd_findtime: 600                      # Окно подсчёта попыток, сек (10 мин)
fail2ban_sshd_bantime: 3600                      # Длительность бана, сек (1 час)
fail2ban_sshd_bantime_increment: true            # Прогрессивный бан (удвоение при повторах)
fail2ban_sshd_bantime_maxtime: 86400             # Верхняя граница прогрессивного бана (24 ч)
fail2ban_sshd_backend: auto                      # Бэкенд логов: auto, systemd, polling
fail2ban_sshd_banaction: ""                       # Действие бана (пусто = iptables-multiport)

# Белый список
fail2ban_ignoreip:                               # IP/CIDR, которые никогда не банятся
  - 127.0.0.1/8
  - "::1"
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/fail2ban/jail.d/sshd.conf` — конфигурация SSH jail (template)
- Сервис: `fail2ban` (enabled + started)
- Пакеты: `fail2ban` (OS-specific через vars/)

**Arch Linux:**
- Пакет: `fail2ban`

**Debian/Ubuntu:**
- Пакет: `fail2ban`

**Fedora/RHEL:**
- Пакет: `fail2ban`

## Зависимости

- `common` — для report_phase и report_render (execution report)

## Tags

- `fail2ban`, `security`, `install`, `service`, `report`

---

Назад к [[Roadmap]]
