# Роль: certificates

**Phase**: 6 | **Направление**: Безопасность

## Цель

Управление CA (Certificate Authority), генерация и установка SSL/TLS сертификатов для локальной разработки и внутренних сервисов через mkcert. Автоматическая установка корневого CA в системный trust store для HTTPS-соединений без браузерных предупреждений. Поддержка wildcard-сертификатов для dev-доменов.

## Ключевые переменные (defaults)

```yaml
certificates_enabled: true                # Включить управление сертификатами
certificates_mkcert_enabled: true         # Установить и использовать mkcert

# Установка mkcert
certificates_mkcert_version: latest       # Версия mkcert (latest или конкретная, напр. v1.4.4)
certificates_mkcert_install_path: /usr/local/bin/mkcert  # Путь установки

# CA management
certificates_create_ca: true              # Создать локальный CA через mkcert
certificates_install_ca: true             # Установить CA в системный trust store
certificates_ca_install_firefox: true     # Установить CA в Firefox (если установлен)
certificates_ca_install_chrome: true      # Установить CA в Chrome/Chromium (если установлен)

# Генерация сертификатов
certificates_domains: []                  # Список доменов для генерации: ["localhost", "*.local.dev"]
certificates_cert_path: /etc/ssl/certs    # Директория для сертификатов
certificates_key_path: /etc/ssl/private   # Директория для приватных ключей

# Кастомные сертификаты
certificates_custom_certs: []             # Список: [{domains: ["example.local"], cert_file, key_file}]

# Trust store
certificates_trust_store_update: true     # Обновить системный trust store после установки
certificates_trust_anchors_path: /etc/ca-certificates/trust-source/anchors  # Arch
# certificates_trust_anchors_path: /usr/local/share/ca-certificates          # Debian

# Целевой пользователь (для Firefox/Chrome)
certificates_target_user: "{{ ansible_facts['env']['SUDO_USER'] | default(ansible_facts['user_id']) }}"
```

## Что настраивает

- Установка:
  - `mkcert` — `/usr/local/bin/mkcert`
  - Root CA — `~/.local/share/mkcert/rootCA.pem`, `rootCA-key.pem`
- Сертификаты:
  - `/etc/ssl/certs/<domain>.pem` — публичные сертификаты
  - `/etc/ssl/private/<domain>-key.pem` — приватные ключи (mode: 0600)
- Trust store:
  - **Arch**: `/etc/ca-certificates/trust-source/anchors/` → `trust extract-compat`
  - **Debian**: `/usr/local/share/ca-certificates/` → `update-ca-certificates`
- Браузеры:
  - Firefox: `~/.mozilla/firefox/*/cert9.db` (NSS database)
  - Chrome: использует системный trust store

**Arch Linux:**
- Пакеты: `ca-certificates`, `nss` (для Firefox)
- mkcert: установка из GitHub releases (бинарник)
- Trust store: `/etc/ca-certificates/trust-source/anchors/` → команда `trust extract-compat`

**Debian/Ubuntu:**
- Пакеты: `ca-certificates`, `libnss3-tools` (для Firefox)
- mkcert: установка из GitHub releases (бинарник)
- Trust store: `/usr/local/share/ca-certificates/` → команда `update-ca-certificates`

## Зависимости

- `base_system` — требуется установленная система с openssl
- `caddy` (опционально) — для использования сгенерированных сертификатов
- `zen_browser` или `firefox` (опционально) — для установки CA в браузер

## Tags

- `certificates`, `security`, `ssl`, `tls`, `mkcert`

---

Назад к [[Roadmap]]
