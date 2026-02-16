# Роль: fail2ban

**Phase**: 2 | **Направление**: Безопасность

## Цель

Защита от brute-force атак через автоматическое блокирование IP-адресов после множественных неудачных попыток входа. Отслеживает логи SSH, HTTP/HTTPS и других сервисов для выявления подозрительной активности и добавляет правила блокировки в firewall (nftables/iptables).

## Ключевые переменные (defaults)

```yaml
fail2ban_enabled: true                    # Включить fail2ban
fail2ban_bantime: 3600                    # Время блокировки в секундах (1 час)
fail2ban_findtime: 600                    # Окно времени для подсчета попыток (10 минут)
fail2ban_maxretry: 5                      # Максимум попыток до блокировки
fail2ban_destemail: root@localhost        # Email для уведомлений
fail2ban_sender: fail2ban@localhost       # Отправитель email
fail2ban_action: action_                  # Действие: action_ (ban only), action_mw (ban+email)

# Jail configurations
fail2ban_ssh_enabled: true                # Защита SSH
fail2ban_ssh_port: 22                     # Порт SSH
fail2ban_ssh_maxretry: 3                  # SSH: строже лимит

fail2ban_http_enabled: false              # Защита HTTP (nginx/apache)
fail2ban_http_maxretry: 5                 # HTTP: попытки до блокировки

fail2ban_custom_jails: []                 # Список дополнительных jails: [{name, enabled, port, filter, logpath}]
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/fail2ban/fail2ban.local` — глобальная конфигурация
  - `/etc/fail2ban/jail.local` — настройка jails (SSH, HTTP/HTTPS)
  - `/etc/fail2ban/filter.d/` — кастомные фильтры (опционально)
- Сервис: `fail2ban.service` (enabled + started)
- Логи: `/var/log/fail2ban.log`

**Arch Linux:**
- Пакет: `fail2ban`
- Интеграция с `nftables` через backend в `jail.local`

**Debian/Ubuntu:**
- Пакет: `fail2ban`
- Интеграция с `iptables` или `nftables` (автодетект)

## Зависимости

- `firewall` — fail2ban добавляет правила в активный firewall
- `ssh` — для jail sshd требуется настроенный sshd
- `journald` (опционально) — для чтения логов из systemd journal

## Tags

- `fail2ban`, `security`, `ips`

---

Назад к [[Roadmap]]
