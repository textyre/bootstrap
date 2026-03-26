# Роль: ssh

**Phase**: 1 | **Направление**: Безопасность

## Цель

Развёртывание и hardening OpenSSH-сервера в соответствии с dev-sec.io, CIS Benchmark L1 Workstation, DISA STIG и Mozilla Modern SSH. Обеспечивает безопасную удалённую аутентификацию только по публичному ключу с современной криптографией (ChaCha20-Poly1305, Curve25519, ETM MACs). Поддерживает все 5 init-систем проекта.

## Ключевые переменные (defaults)

```yaml
ssh_harden_sshd: true                    # Master switch для hardening
ssh_port: 22                             # Порт SSH-сервера
ssh_address_family: "inet"               # inet (IPv4), inet6, any

# Криптография (Mozilla Modern)
ssh_kex_algorithms:                      # KEX: curve25519, DH group16/18
ssh_ciphers:                             # AEAD only: chacha20, aes-gcm
ssh_macs:                                # ETM only: hmac-sha2-512/256-etm, umac-128-etm

# Аутентификация
ssh_permit_root_login: "no"              # CIS 5.2.10
ssh_password_authentication: "no"        # Только ключи
ssh_max_auth_tries: 3                    # CIS 5.2.7
ssh_authentication_methods: "publickey"  # Только publickey

# Контроль доступа
ssh_allow_groups: ["wheel"]              # Whitelist групп
ssh_allow_users: []                      # Whitelist пользователей

# Forwarding (всё отключено по умолчанию)
ssh_x11_forwarding: "no"
ssh_allow_tcp_forwarding: "no"
ssh_allow_agent_forwarding: "no"

# Логирование
ssh_log_level: "VERBOSE"                 # CIS 4.2.3 — fingerprint при каждом входе
ssh_syslog_facility: "AUTH"              # Стандартный журнал безопасности

# DoS-защита
ssh_max_startups: "10:30:60"             # CIS/Mozilla

# Опциональные функции
ssh_banner_enabled: false                # Pre-auth баннер
ssh_moduli_cleanup: false                # Удаление слабых DH модулей
ssh_host_key_cleanup: true               # Удаление DSA/ECDSA ключей
ssh_sftp_enabled: true                   # SFTP подсистема
ssh_sftp_chroot_enabled: false           # Chroot для SFTP
ssh_teleport_integration: false          # Teleport SSH CA
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/ssh/sshd_config` — hardened конфигурация из Jinja2 шаблона (mode 0600)
  - `/etc/issue.net` — pre-auth баннер (опционально, `ssh_banner_enabled: true`)
  - `/etc/ssh/moduli` — фильтрация слабых DH-параметров (опционально, `ssh_moduli_cleanup: true`)
- Host-ключи:
  - `/etc/ssh/ssh_host_ed25519_key` — генерация если отсутствует
  - `/etc/ssh/ssh_host_rsa_key` — генерация если RSA в `ssh_host_key_algorithms`
  - Удаление DSA/ECDSA ключей (`ssh_host_key_cleanup: true`)
- Сервис: `sshd` (Arch/RedHat/Gentoo/Void) или `ssh` (Debian) — enabled + started
- Логи: syslog через AUTH facility, `LogLevel VERBOSE`

**Все платформы:**
- Arch Linux: пакет `openssh`, сервис `sshd`
- Debian/Ubuntu: пакеты `openssh-server` + `openssh-client`, сервис `ssh`
- RedHat/Fedora: пакеты `openssh-server` + `openssh-clients`, сервис `sshd`
- Void Linux: пакет `openssh`, сервис `sshd`
- Gentoo: пакет `net-misc/openssh`, сервис `sshd`

## Audit Events

| События | Источник | Формат | Значение |
|---------|----------|--------|----------|
| **Успешная аутентификация** | sshd via AUTH | syslog | `Accepted publickey for <user> from <IP> port <port> ssh2: ED25519 SHA256:<fingerprint>` |
| **Неудачная аутентификация** | sshd via AUTH | syslog | `Failed publickey for <user> from <IP>`, `Connection closed by authenticating user` |
| **Достижение MaxAuthTries** | sshd via AUTH | syslog | `Disconnecting authenticating user <user>: Too many authentication failures` |
| **Root login attempt** | sshd via AUTH | syslog | `Failed none for root from <IP>` (при `PermitRootLogin no`) |
| **Brute-force (MaxStartups)** | sshd via AUTH | syslog | `refused connect from <IP>`, `Connection dropped` |
| **Invalid user** | sshd via AUTH | syslog | `Invalid user <name> from <IP>` |
| **Config change** | sshd restart | syslog | `Server listening on <addr> port <port>`, `sshd[pid]: Received SIGHUP; restarting` |
| **Host key mismatch** | client-side | stderr | `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` (при смене ключей) |
| **Session open/close** | sshd via AUTH | syslog | `pam_unix(sshd:session): session opened/closed for user <user>` |
| **Forwarding denied** | sshd via AUTH | syslog | `Refused tcp forwarding`, `Refused agent forwarding` |

## Мониторинг (Prometheus + Alloy)

### Метрики SSH

SSH не экспортирует метрики нативно. Мониторинг через:

1. **node_exporter textfile collector** — количество активных сессий, неудачных попыток
2. **Loki/Alloy** — парсинг syslog AUTH записей

```bash
# Количество активных SSH-сессий
ss -tnp | grep ':22' | grep ESTAB | wc -l

# Неудачные попытки за последний час
journalctl -u sshd --since "1 hour ago" | grep -c "Failed"

# Текущие подключения с деталями
who -u
```

### Alloy pipeline (Log Relay)

```alloy
// Парсинг sshd auth логов
loki.source.journal "sshd" {
  matches = {"_SYSTEMD_UNIT" = "sshd.service"}
  labels  = {job = "sshd", component = "auth"}
}

loki.process "sshd_metrics" {
  // Извлечение метрик из логов
  stage.regex {
    expression = "(?P<action>Accepted|Failed|Invalid user|Disconnecting|refused connect)"
  }
  stage.metrics {
    counter {
      name   = "ssh_auth_events_total"
      source = "action"
      action = "inc"
    }
  }
}
```

### Prometheus rules (alert rules)

```yaml
groups:
  - name: ssh_monitoring
    interval: 60s
    rules:
      # Массовые неудачные попытки (brute-force)
      - alert: SSHBruteForceDetected
        expr: rate(ssh_auth_events_total{action="Failed"}[5m]) > 10
        for: 2m
        annotations:
          summary: "SSH brute-force detected ({{ $value }} failures/sec on {{ $labels.instance }})"
          runbook: "wiki/runbooks/ssh-brute-force.md"

      # Вход root (должен быть запрещён)
      - alert: SSHRootLoginAttempt
        expr: increase(ssh_auth_events_total{action="Failed",user="root"}[5m]) > 0
        for: 0m
        annotations:
          summary: "Root SSH login attempt detected on {{ $labels.instance }}"

      # Сервис не запущен
      - alert: SSHServiceDown
        expr: node_systemd_unit_state{name=~"sshd?.service", state="active"} != 1
        for: 1m
        annotations:
          summary: "SSH service down on {{ $labels.instance }}"

      # Нет активных SSH-сессий на production (canary)
      - alert: SSHNoSessions
        expr: ssh_active_sessions == 0
        for: 30m
        labels:
          severity: info
        annotations:
          summary: "No SSH sessions for 30m on {{ $labels.instance }}"
```

### Grafana dashboard

Рекомендуемые панели:
- **Auth Events**: счётчик Accepted/Failed/Invalid за период
- **Active Sessions**: gauge текущих SSH-сессий
- **Failed Auth Rate**: rate неудачных попыток (alert threshold)
- **Top Source IPs**: таблица IP с наибольшим числом подключений
- **User Logins**: таблица последних входов (user, IP, key fingerprint)

## Зависимости

- `common` — report_phase.yml, report_render.yml (execution report)
- `firewall` (опционально) — открытие порта SSH
- `fail2ban` (рекомендуется) — автоматическая блокировка brute-force IP

**Рекомендуется размещение:** Phase 1 (SSH критичен для удалённого управления; применять до ролей, зависящих от SSH-доступа)

## Tags

- `ssh`, `security`, `install`, `service`, `banner`, `moduli`, `report`

---

Назад к [[Roadmap]]
