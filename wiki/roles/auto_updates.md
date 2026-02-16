# Роль: auto_updates

**Phase**: 10 | **Направление**: Autodeploy

## Цель

Автоматическое применение security updates для ОС. Distro-agnostic: использует OS-specific инструменты (pacman-contrib на Arch, unattended-upgrades на Debian, dnf-automatic на Fedora). Минимизирует окно уязвимости без ручного вмешательства.

## Ключевые переменные (defaults)

```yaml
auto_updates_enabled: true  # Включить автоматические обновления

# Общие настройки
auto_updates_reboot_required: false       # Перезагрузка при необходимости (kernel, systemd)
auto_updates_reboot_time: "03:00"         # Время перезагрузки (если требуется)
auto_updates_only_security: true          # Только security updates (рекомендуется)
auto_updates_notify: false                # Уведомления о применённых обновлениях
auto_updates_notification_email: ""       # Email для уведомлений

# Arch Linux (pacman-contrib + systemd timer)
auto_updates_arch_check_schedule: "daily"         # Частота проверки: daily / weekly
auto_updates_arch_download_schedule: "daily"      # Скачивание обновлений
auto_updates_arch_security_tool: "arch-audit"     # arch-audit — проверка CVE для установленных пакетов
auto_updates_arch_security_only: true             # Применять только пакеты из arch-audit
auto_updates_arch_hook_enabled: false             # Pacman hook для автопроверки после установки

# Debian/Ubuntu (unattended-upgrades)
auto_updates_debian_allowed_origins:
  - "${distro_id}:${distro_codename}-security"   # Только security updates
  - "${distro_id}ESMApps:${distro_codename}-apps-security"  # Ubuntu ESM (если доступно)
auto_updates_debian_auto_fix_interrupted: true   # Автофикс прерванных dpkg операций
auto_updates_debian_minimal_steps: true          # Минимальные обновления (только критичные)
auto_updates_debian_install_on_shutdown: false   # Установка обновлений при выключении
auto_updates_debian_auto_reboot: false           # Автоперезагрузка (если требуется)
auto_updates_debian_auto_reboot_time: "03:00"    # Время автоперезагрузки
auto_updates_debian_remove_unused: true          # Удалять ненужные зависимости
auto_updates_debian_auto_clean_interval: 7       # Очистка кеша (дни)

# Fedora/RHEL (dnf-automatic)
auto_updates_fedora_upgrade_type: "security"     # security / default (все обновления)
auto_updates_fedora_random_sleep: 300            # Случайная задержка (секунды)
auto_updates_fedora_download_updates: true       # Скачивать обновления автоматически
auto_updates_fedora_apply_updates: true          # Применять обновления автоматически
auto_updates_fedora_reboot: "never"              # never / when-needed
auto_updates_fedora_reboot_time: "03:00"         # Время перезагрузки (если when-needed)
auto_updates_fedora_emit_via: "stdio"            # Вывод: stdio / email / motd

# Логирование
auto_updates_log_file: "/var/log/auto-updates.log"
auto_updates_log_level: "info"  # info / debug
```

## Что настраивает

### На Arch Linux

- Установка: `pacman-contrib`, `arch-audit`
- Systemd timer: `pacman-check-updates.timer` (ежедневная проверка)
- Скрипт: `/usr/local/bin/arch-auto-update.sh`
  - Запускает `checkupdates` (список доступных обновлений)
  - Фильтрует через `arch-audit` (только пакеты с CVE)
  - Применяет обновления: `pacman -Syu --noconfirm <packages>`
- Логирование в `/var/log/auto-updates.log`
- Проверка необходимости перезагрузки (kernel, systemd, glibc)

### На Debian/Ubuntu

- Установка: `unattended-upgrades`, `apt-listchanges`
- Конфигурация: `/etc/apt/apt.conf.d/50unattended-upgrades`
- Автоматические обновления только из `-security` репозиториев
- Systemd timer: `apt-daily-upgrade.timer` (ежедневно)
- Опционально: автоперезагрузка через `update-notifier-common`
- Логирование в `/var/log/unattended-upgrades/`

### На Fedora/RHEL

- Установка: `dnf-automatic`
- Конфигурация: `/etc/dnf/automatic.conf`
- Режим: `upgrade_type = security` (только CVE-патчи)
- Systemd timer: `dnf-automatic.timer` (ежедневно)
- Опционально: автоперезагрузка через `dnf-automatic-install.service`
- Логирование в journalctl (`journalctl -u dnf-automatic`)

## Зависимости

- `base_system` — базовые пакеты и systemd

## Примечания

### Arch Linux: arch-audit

`arch-audit` — проверяет установленные пакеты на наличие CVE из Arch Security Tracker:

```bash
# Список уязвимых пакетов
arch-audit

# Только High/Critical severity
arch-audit --upgradable
```

Пример output:
```
Package openssl is affected by CVE-2023-12345 (High)
Package curl is affected by CVE-2023-67890 (Medium)
```

Роль автоматически применяет обновления только для пакетов из `arch-audit --upgradable`.

### Debian/Ubuntu: unattended-upgrades

Пример конфигурации `/etc/apt/apt.conf.d/50unattended-upgrades`:

```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
```

Проверка работы:
```bash
# Dry-run
unattended-upgrade --dry-run --debug

# Статус таймера
systemctl status apt-daily-upgrade.timer

# Логи
cat /var/log/unattended-upgrades/unattended-upgrades.log
```

### Fedora/RHEL: dnf-automatic

Пример конфигурации `/etc/dnf/automatic.conf`:

```ini
[commands]
upgrade_type = security
download_updates = yes
apply_updates = yes

[emitters]
emit_via = stdio

[command_email]
email_to = root@localhost
```

Проверка:
```bash
# Статус таймера
systemctl status dnf-automatic.timer

# Ручной запуск (dry-run)
dnf updateinfo list security

# Логи
journalctl -u dnf-automatic -n 50
```

### Перезагрузка после обновлений

Некоторые обновления требуют перезагрузки (kernel, systemd, glibc). Проверка:

**Arch:**
```bash
# Проверка необходимости перезагрузки
[ -f /usr/lib/modules/$(uname -r) ] || echo "Reboot required"
```

**Debian/Ubuntu:**
```bash
# Проверка через update-notifier
[ -f /var/run/reboot-required ] && cat /var/run/reboot-required.pkgs
```

**Fedora:**
```bash
# Проверка через needs-restarting
needs-restarting -r
```

Роль автоматически создаёт systemd timer для перезагрузки в заданное время (если `auto_updates_reboot_required: true`).

### Безопасность vs стабильность

**Рекомендации:**
- **Production**: `auto_updates_only_security: true` — только критичные патчи
- **Staging**: `auto_updates_only_security: false` — все обновления для тестирования
- **Desktop**: `auto_updates_only_security: false` + ручная перезагрузка

**Риски:**
- Обновление может сломать зависимости (особенно AUR-пакеты на Arch)
- Kernel updates требуют перезагрузки (downtime)
- Обновления могут изменить поведение (breaking changes)

**Mitigation:**
- Тестируйте на staging перед production
- Используйте snapshots (btrfs, LVM) для rollback
- Мониторьте логи обновлений

### Уведомления

Настройка email-уведомлений:

**Debian:**
```bash
# Установить postfix или msmtp
apt install postfix

# В /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Mail "admin@example.com";
Unattended-Upgrade::MailReport "on-change";
```

**Fedora:**
```ini
[command_email]
email_from = root@localhost
email_to = admin@example.com
```

### Проверка работы

```bash
# Arch: Статус таймера
systemctl status pacman-check-updates.timer

# Arch: Логи
tail -f /var/log/auto-updates.log

# Debian: Последние обновления
cat /var/log/unattended-upgrades/unattended-upgrades.log

# Fedora: Логи dnf-automatic
journalctl -u dnf-automatic -f
```

## Tags

- `security`
- `autodeploy`
- `updates`
- `maintenance`

---

Назад к [[Roadmap]]
