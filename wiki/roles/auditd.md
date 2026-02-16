# Роль: auditd

**Phase**: 9 | **Направление**: Безопасность

## Цель

Аудит критических системных событий через Linux Audit Framework: изменения файлов `/etc/passwd`, `/etc/shadow`, `/etc/sudoers`, запуск привилегированных команд, системные вызовы (execve, connect), изменения прав доступа. Соответствие стандартам безопасности (PCI-DSS, STIG, CIS Benchmarks).

## Ключевые переменные (defaults)

```yaml
auditd_enabled: true                      # Включить auditd
auditd_enable_service: true               # Запустить auditd.service

# Настройки хранения логов
auditd_log_file: /var/log/audit/audit.log # Путь к файлу логов
auditd_max_log_file: 100                  # Макс. размер одного лог-файла (MB)
auditd_max_log_file_action: rotate        # Действие при достижении лимита: rotate, keep_logs, syslog
auditd_num_logs: 10                       # Количество ротированных файлов
auditd_space_left: 500                    # Свободное место для предупреждения (MB)
auditd_space_left_action: email           # Действие при низком месте: email, syslog, suspend, halt
auditd_admin_space_left: 100              # Критический порог (MB)
auditd_admin_space_left_action: suspend   # Действие: suspend (приостановить аудит), halt (остановить систему)

# Правила аудита (audit rules)
auditd_rules_enabled: true                # Применить правила аудита

# Аудит изменений системных файлов
auditd_watch_passwd: true                 # /etc/passwd, /etc/shadow, /etc/group
auditd_watch_sudoers: true                # /etc/sudoers, /etc/sudoers.d/
auditd_watch_ssh_config: true             # /etc/ssh/sshd_config
auditd_watch_pam_config: true             # /etc/pam.d/

# Аудит системных вызовов
auditd_syscall_execve: true               # Логировать запуск процессов (execve)
auditd_syscall_connect: true              # Логировать сетевые подключения
auditd_syscall_chmod: true                # Логировать изменения прав доступа (chmod, chown)
auditd_syscall_unlink: true               # Логировать удаление файлов (unlink, rmdir)

# Аудит привилегированных команд
auditd_privileged_commands: true          # Команды с SUID/SGID битами
auditd_sudo_commands: true                # Команды, выполненные через sudo

# Кастомные правила
auditd_custom_rules: []                   # Список строк правил: ["-w /custom/path -p wa -k custom_key"]

# Иммутабельность правил
auditd_rules_immutable: false             # Сделать правила неизменяемыми до reboot (-e 2)
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/audit/auditd.conf` — настройки демона auditd
  - `/etc/audit/audit.rules` — статические правила аудита (применяются при загрузке)
  - `/etc/audit/rules.d/` — модульные правила (собираются в audit.rules)
- Сервис: `auditd.service` (enabled + started)
- Логи: `/var/log/audit/audit.log`
- Команды: `ausearch`, `aureport`, `auditctl` для анализа логов

**Arch Linux:**
- Пакет: `audit`
- Сервис: `auditd.service`
- Правила: `/etc/audit/rules.d/audit.rules`

**Debian/Ubuntu:**
- Пакет: `auditd`, `audispd-plugins`
- Сервис: `auditd.service`
- Правила: `/etc/audit/rules.d/audit.rules`

## Зависимости

- `base_system` — auditd требует поддержки в ядре (CONFIG_AUDIT)
- Рекомендуется после `pam_hardening`, `ssh`, `user`

## Tags

- `auditd`, `security`, `audit`, `compliance`

---

Назад к [[Roadmap]]
