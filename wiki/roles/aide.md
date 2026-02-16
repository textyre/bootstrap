# Роль: aide

**Phase**: 9 | **Направление**: Безопасность

## Цель

File Integrity Monitoring (FIM) через AIDE (Advanced Intrusion Detection Environment). Создание криптографической базы данных контрольных сумм критических системных файлов и директорий (`/etc`, `/bin`, `/usr/bin`, `/lib`) для выявления несанкционированных изменений, подмены файлов, руткитов и malware.

## Ключевые переменные (defaults)

```yaml
aide_enabled: true                        # Включить AIDE
aide_init_db: true                        # Инициализировать базу данных при установке

# Пути к базе данных
aide_db_path: /var/lib/aide/aide.db       # Рабочая база данных
aide_db_new_path: /var/lib/aide/aide.db.new  # Новая база (после update)
aide_db_out_path: /var/log/aide/aide.log  # Лог-файл отчетов

# Директории для мониторинга
aide_watch_etc: true                      # /etc — конфигурационные файлы
aide_watch_bin: true                      # /bin, /sbin — системные бинарники
aide_watch_usr_bin: true                  # /usr/bin, /usr/sbin
aide_watch_lib: true                      # /lib, /usr/lib — библиотеки
aide_watch_boot: true                     # /boot — ядро, initramfs
aide_watch_root_home: false               # /root — домашняя директория root

# Исключения (не проверять)
aide_exclude_paths:
  - /var/log                               # Логи меняются постоянно
  - /var/cache                             # Кеши
  - /var/tmp                               # Временные файлы
  - /tmp                                   # Временные файлы
  - /proc                                  # Виртуальная FS
  - /sys                                   # Виртуальная FS

# Уровень проверки (какие атрибуты проверять)
aide_check_permissions: true              # Права доступа (mode)
aide_check_owner: true                    # Владелец (uid/gid)
aide_check_checksums: true                # Контрольные суммы (sha256, sha512)
aide_check_xattrs: true                   # Extended attributes
aide_check_acl: true                      # ACL (если используются)
aide_check_selinux: false                 # SELinux context (если используется)

# Автоматическая проверка
aide_cron_enabled: true                   # Включить автоматическую проверку через cron/timer
aide_cron_schedule: "0 5 * * *"           # Расписание (ежедневно в 5:00)
aide_cron_email: root@localhost           # Email для отправки отчетов

# Кастомные правила
aide_custom_rules: []                     # Список кастомных правил: ["!/custom/exclude/path", "/custom/watch R"]
```

## Что настраивает

- Конфигурационные файлы:
  - `/etc/aide/aide.conf` или `/etc/aide.conf` — правила мониторинга
  - `/var/lib/aide/aide.db` — база данных контрольных сумм
  - `/var/log/aide/aide.log` — отчеты о проверках
- Автоматизация:
  - Cron job: `/etc/cron.daily/aide` или systemd timer `aide-check.timer`
  - Скрипт: `/usr/local/bin/aide-check.sh` (запускает проверку и отправляет email)

**Arch Linux:**
- Пакет: `aide`
- Конфиг: `/etc/aide.conf`
- Инициализация базы: `aide --init && mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db`

**Debian/Ubuntu:**
- Пакет: `aide`, `aide-common`
- Конфиг: `/etc/aide/aide.conf`
- Инициализация: `aideinit` (wrapper-скрипт)

## Зависимости

- `base_system` — требуется установленная система
- Рекомендуется после `apparmor`, `auditd` для полного security stack

## Tags

- `aide`, `security`, `fim`, `file_integrity`

---

Назад к [[Roadmap]]
