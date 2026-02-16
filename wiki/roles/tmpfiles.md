# Роль: tmpfiles

**Phase**: 6 | **Направление**: Services

## Цель

Настройка systemd-tmpfiles.d для управления временными файлами и каталогами. Автоматическая очистка `/tmp`, `/var/tmp`, создание runtime директорий, установка прав и владельцев. Предотвращение переполнения диска и security issues.

## Ключевые переменные (defaults)

```yaml
tmpfiles_enabled: true  # Включить настройку tmpfiles

# === Очистка /tmp ===
tmpfiles_tmp_cleanup_enabled: true            # Очистка /tmp при загрузке
tmpfiles_tmp_cleanup_age: "10d"               # Удалять файлы старше 10 дней
tmpfiles_tmp_cleanup_on_boot: true            # Очистка при загрузке системы
tmpfiles_tmp_exclude_patterns: []             # Исключения (glob patterns)
# Пример:
# - "*.lock"
# - "session-*"

# === Очистка /var/tmp ===
tmpfiles_var_tmp_cleanup_enabled: true        # Очистка /var/tmp
tmpfiles_var_tmp_cleanup_age: "30d"           # Удалять файлы старше 30 дней
tmpfiles_var_tmp_cleanup_on_boot: false       # Не очищать при загрузке (данные могут быть важны)

# === Runtime директории ===
tmpfiles_runtime_dirs: []
# Пример создания директорий:
# - path: /run/myapp
#   mode: "0755"
#   user: myapp
#   group: myapp
#   age: "-"  # Не удалять

# === Custom правила ===
tmpfiles_custom_rules: []
# Пример пользовательских правил:
# - name: myapp
#   rules:
#     - "d /run/myapp 0755 myapp myapp -"
#     - "L /run/myapp/config - - - - /etc/myapp/config"
#     - "z /var/lib/myapp 0750 myapp myapp -"

# === Каталог для конфигурации ===
tmpfiles_config_dir: /etc/tmpfiles.d

# === Применение изменений ===
tmpfiles_apply_changes: true  # Применить изменения сразу (systemd-tmpfiles --create)
```

## Что настраивает

**На всех дистрибутивах:**
- Конфигурационные файлы в `/etc/tmpfiles.d/`
- Правила очистки для `/tmp` и `/var/tmp`
- Создание runtime директорий в `/run`
- Установка прав, владельцев и ACL
- Автоматическая очистка старых файлов через systemd-tmpfiles-clean.timer
- Применение правил: `systemd-tmpfiles --create --remove`

**На Arch Linux:**
- Пакет: `systemd` (уже установлен)
- Путь: `/etc/tmpfiles.d/`
- Таймер: `systemd-tmpfiles-clean.timer` (ежедневно)

**На Debian/Ubuntu:**
- Пакет: `systemd` (уже установлен)
- Путь: `/etc/tmpfiles.d/`
- Таймер: `systemd-tmpfiles-clean.timer` (ежедневно)

**На Fedora/RHEL:**
- Пакет: `systemd` (уже установлен)
- Путь: `/etc/tmpfiles.d/`
- Таймер: `systemd-tmpfiles-clean.timer` (ежедневно)

## Зависимости

- `base_system` — systemd и базовые утилиты

## Примечания

### Синтаксис tmpfiles.d

Формат: `Type Path Mode User Group Age Argument`

**Основные типы:**

| Тип | Описание | Пример |
|-----|----------|--------|
| **d** | Создать директорию (если не существует) | `d /run/myapp 0755 myapp myapp -` |
| **D** | Создать/очистить директорию | `D /tmp 1777 root root 10d` |
| **L** | Создать symlink | `L /run/myapp/config - - - - /etc/myapp/config` |
| **f** | Создать файл (если не существует) | `f /var/log/myapp.log 0644 myapp myapp -` |
| **F** | Создать/перезаписать файл | `F /etc/myapp/default.conf 0644 root root - "key=value\n"` |
| **z** | Установить права (не создавать) | `z /var/lib/myapp 0750 myapp myapp -` |
| **Z** | Установить права рекурсивно | `Z /var/lib/myapp 0750 myapp myapp -` |
| **x** | Исключить из очистки | `x /tmp/important -` |
| **r** | Удалить файл | `r /tmp/obsolete.txt` |
| **R** | Удалить директорию рекурсивно | `R /var/cache/old-data` |

### Примеры правил

#### 1. Создание runtime директории для приложения

`/etc/tmpfiles.d/myapp.conf`:
```
# Создать /run/myapp при загрузке
d /run/myapp 0755 myapp myapp -

# Создать PID-файл
f /run/myapp/myapp.pid 0644 myapp myapp -

# Symlink на конфиг
L /run/myapp/config - - - - /etc/myapp/config
```

#### 2. Очистка /tmp с исключениями

`/etc/tmpfiles.d/tmp-cleanup.conf`:
```
# Очистка /tmp (файлы старше 10 дней)
D /tmp 1777 root root 10d

# Исключить session файлы из очистки
x /tmp/.X11-unix -
x /tmp/.ICE-unix -

# Удалить конкретные файлы при загрузке
r /tmp/*.core
```

#### 3. Агрессивная очистка кеша

`/etc/tmpfiles.d/cache-cleanup.conf`:
```
# Очистка package manager кеша (старше 7 дней)
D /var/cache/pacman/pkg 0755 root root 7d
D /var/cache/apt/archives 0755 root root 7d

# Очистка user cache (старше 30 дней)
D /home/*/.cache 0700 - - 30d
```

#### 4. Security: ограничение прав на директории

`/etc/tmpfiles.d/security.conf`:
```
# Ограничить доступ к /var/log для non-root
z /var/log 0750 root root -

# Установить correct permissions для sensitive files
z /etc/ssh/sshd_config 0600 root root -
z /etc/shadow 0000 root root -
```

### Age (возраст файлов для очистки)

Формат: `<число><единица>`

- `s` — секунды
- `m` — минуты
- `h` — часы
- `d` — дни
- `w` — недели
- `-` — не удалять никогда

Примеры:
- `10d` — 10 дней
- `2w` — 2 недели
- `12h` — 12 часов
- `-` — не удалять

### Применение изменений

```bash
# Применить все правила из /etc/tmpfiles.d/
systemd-tmpfiles --create --remove

# Применить конкретный файл
systemd-tmpfiles --create /etc/tmpfiles.d/myapp.conf

# Dry-run (показать что будет сделано)
systemd-tmpfiles --create --remove --dry-run

# Очистить старые файлы
systemd-tmpfiles --clean
```

### Автоматическая очистка

Таймер `systemd-tmpfiles-clean.timer` запускается ежедневно и выполняет очистку старых файлов.

Проверка:
```bash
# Статус таймера
systemctl status systemd-tmpfiles-clean.timer

# Следующий запуск
systemctl list-timers systemd-tmpfiles-clean.timer

# Ручной запуск очистки
systemctl start systemd-tmpfiles-clean.service

# Логи
journalctl -u systemd-tmpfiles-clean.service -n 50
```

### /tmp vs /var/tmp

| Директория | Назначение | Срок жизни | Очистка |
|------------|-----------|-----------|---------|
| `/tmp` | Временные файлы сессии | До перезагрузки | При загрузке + таймер |
| `/var/tmp` | Временные файлы между перезагрузками | Дольше (недели) | Только таймер |
| `/run` | Runtime данные (PID, sockets) | До перезагрузки | tmpfs (в RAM) |

**Рекомендации:**
- `/tmp` — очистка 7-10 дней
- `/var/tmp` — очистка 30 дней
- `/run` — не очищать (tmpfs, очищается при перезагрузке)

### Безопасность

**Проблемы:**
- Sticky bit на `/tmp` (`1777`) — защита от удаления чужих файлов
- Race conditions — TOCTOU (Time-Of-Check-Time-Of-Use) атаки
- Symlink attacks — злоумышленник создаёт symlink в `/tmp`

**Mitigation:**
```
# Защита от symlink attacks (уже в /usr/lib/tmpfiles.d/tmp.conf)
D /tmp 1777 root root 10d
```

**Проверка прав:**
```bash
ls -ld /tmp  # Должно быть: drwxrwxrwt (1777)
```

### Приоритет конфигурации

systemd-tmpfiles читает конфигурацию из нескольких мест (по приоритету):
1. `/etc/tmpfiles.d/` — пользовательские правила (высший приоритет)
2. `/run/tmpfiles.d/` — runtime правила
3. `/usr/lib/tmpfiles.d/` — системные правила (дефолты)

Файлы с одинаковым именем в `/etc/tmpfiles.d/` переопределяют системные.

### Переполнение /tmp

Если `/tmp` переполнен, система может стать нестабильной. Решения:

1. **Увеличить размер tmpfs:**
   ```bash
   mount -o remount,size=4G /tmp
   ```

2. **Permanent:**
   ```
   # /etc/fstab
   tmpfs /tmp tmpfs defaults,size=4G,mode=1777 0 0
   ```

3. **Агрессивная очистка:**
   ```yaml
   tmpfiles_tmp_cleanup_age: "1d"  # Очистка каждый день
   ```

## Tags

- `systemd`
- `tmpfiles`
- `cleanup`
- `maintenance`
- `security`

---

Назад к [[Roadmap]]
