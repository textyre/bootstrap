# Роль: systemd_resolved

**Phase**: 5 | **Направление**: Networking

## Цель

Настройка systemd-resolved как основного DNS resolver с поддержкой DNS-over-TLS (DoT) для шифрования DNS-запросов. Кеширование, DNSSEC-валидация и интеграция с NetworkManager.

## Ключевые переменные (defaults)

```yaml
systemd_resolved_enabled: true  # Включить и запустить systemd-resolved

# DNS-серверы (с поддержкой DoT)
systemd_resolved_dns_servers:
  - "1.1.1.1"       # Cloudflare
  - "1.0.0.1"       # Cloudflare secondary
  - "8.8.8.8"       # Google (fallback)

# Fallback DNS (если основные недоступны)
systemd_resolved_fallback_dns:
  - "8.8.4.4"       # Google secondary

# DNS-over-TLS
systemd_resolved_dns_over_tls: "yes"  # yes / opportunistic / no
# yes — строгий режим, запросы без TLS блокируются
# opportunistic — попытка TLS, fallback на обычный DNS
# no — DNS-over-TLS отключён

# DNSSEC validation
systemd_resolved_dnssec: "allow-downgrade"  # yes / allow-downgrade / no
# yes — строгая валидация, невалидные ответы отклоняются
# allow-downgrade — валидация если поддерживается, иначе без неё
# no — DNSSEC отключён

# Домены для поиска
systemd_resolved_domains: []  # Домены для автодополнения (например: ~localdomain)

# LLMNR (Link-Local Multicast Name Resolution)
systemd_resolved_llmnr: "no"  # yes / resolve / no
# Рекомендуется no для безопасности (уязвим к spoofing)

# MulticastDNS (mDNS / Avahi / Bonjour)
systemd_resolved_multicast_dns: "no"  # yes / resolve / no
# Полезно для .local доменов (принтеры, IoT), но создаёт риски

# Кеш DNS
systemd_resolved_cache: "yes"            # yes / no-negative / no
systemd_resolved_cache_max_entries: 2048 # Количество записей в кеше

# DNSStubListener (локальный DNS на 127.0.0.53)
systemd_resolved_dns_stub_listener: "yes"  # yes / no / udp / tcp
# yes — слушает на 127.0.0.53:53 (рекомендуется)
# no — не создаёт stub, приложения используют /run/systemd/resolve/resolv.conf напрямую

# Управление /etc/resolv.conf
systemd_resolved_manage_resolv_conf: true  # Создать symlink /etc/resolv.conf → /run/systemd/resolve/stub-resolv.conf
```

## Что настраивает

**На всех дистрибутивах:**
- Конфигурация `/etc/systemd/resolved.conf` (или drop-in `/etc/systemd/resolved.conf.d/`)
- Symlink `/etc/resolv.conf` → `/run/systemd/resolve/stub-resolv.conf`
- Запуск и включение сервиса `systemd-resolved.service`
- Интеграция с NetworkManager (если используется)

**На Arch Linux:**
- Пакет: `systemd` (уже установлен, resolved встроен)
- Путь: `/etc/systemd/resolved.conf`

**На Debian/Ubuntu:**
- Пакет: `systemd-resolved` (обычно уже установлен)
- Путь: `/etc/systemd/resolved.conf`

**На Fedora/RHEL:**
- Пакет: `systemd-resolved` (требуется установка)
- Путь: `/etc/systemd/resolved.conf`

## Зависимости

- `base_system` — systemd и базовые утилиты
- `network` (опционально) — интеграция с NetworkManager

## Примечания

### DNS-over-TLS: строгий vs opportunistic

- **Строгий режим (`yes`)**: Все DNS-запросы шифруются. Если сервер не поддерживает DoT — запрос блокируется.
- **Opportunistic (`opportunistic`)**: Попытка DoT, если не получается — fallback на обычный DNS (риск downgrade-атаки).

Рекомендуется `yes` для максимальной безопасности, если DNS-серверы гарантированно поддерживают DoT (Cloudflare, Google, Quad9).

### Проверка DoT

```bash
# Статус resolved
resolvectl status

# Проверка TLS-соединения
resolvectl query example.com --legend=no

# Статистика кеша
resolvectl statistics
```

### DNSSEC и LLMNR

- **DNSSEC**: Защита от DNS spoofing, но не все домены поддерживают. `allow-downgrade` — баланс между безопасностью и совместимостью.
- **LLMNR**: Уязвим к атакам (Responder, LLMNR poisoning). Рекомендуется `no` для безопасности.

### Интеграция с NetworkManager

NetworkManager автоматически отправляет DNS-серверы от DHCP в systemd-resolved. Приоритет:
1. Static DNS из `/etc/systemd/resolved.conf`
2. DNS от DHCP (через NetworkManager)
3. Fallback DNS

### Альтернативные resolvers

Для более продвинутой фильтрации (Pi-hole, AdGuard Home) можно использовать systemd-resolved как upstream для локального DNS:

```yaml
systemd_resolved_dns_servers:
  - "127.0.0.1"  # Pi-hole
systemd_resolved_dns_over_tls: "no"
```

## Tags

- `systemd`
- `dns`
- `networking`
- `security`
- `dns-over-tls`

---

Назад к [[Roadmap]]
