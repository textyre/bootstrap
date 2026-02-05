# Краткое руководство

## Для тех, кто спешит

### Windows → Arch Linux

```powershell
# 1. Настройте SSH ключ (один раз)
cd windows
.\setup_ssh_key.ps1

# 2. Отредактируйте настройки в sync_to_server.ps1:
#    $SERVER_USER, $SERVER_HOST, $SERVER_PORT, $REMOTE_PATH

# 3. Синхронизируйте
.\sync_to_server.ps1
```

### На Arch Linux

```bash
cd ~/bootstrap

# Показать пакеты и прямые зависимости
./bin/show-installed-packages.sh

# Показать полное дерево всех зависимостей
./bin/show-all-dependencies.sh

# Сохранить в файл
./bin/show-installed-packages.sh > packages.txt
```

## Структура проекта

- **`ansible/`** - Ansible проект (роли, плейбуки, инвентарь)
- **`dotfiles/`** - Исходные дотфайлы (chezmoi source)
- **`bin/`** - Утилиты для анализа пакетов
- **`windows/`** - PowerShell утилиты для синхронизации
- **`docs/`** - Подробная документация

## Dry-run

```bash
# Показать изменения без применения
./bootstrap.sh --check

# Через task runner
task dry-run
```

## Основные команды

```bash
# Полный bootstrap
./bootstrap.sh

# Dry-run (показать изменения без применения)
./bootstrap.sh --check

# Только определённые роли
./bootstrap.sh --tags packages
./bootstrap.sh --tags "docker,ssh,firewall"

# Пропустить роли
./bootstrap.sh --skip-tags firewall

# Переопределить переменные
./bootstrap.sh -e '{"base_system_hostname": "mybox"}'
```

## Разработка

```bash
# Из корня репозитория:
task bootstrap    # Установить Python зависимости (один раз)
task check        # Проверить синтаксис
task lint         # ansible-lint best practices
task test         # Все molecule тесты (14 ролей)
task test-<role>  # Тест конкретной роли
task dry-run      # Показать изменения
task workstation  # Применить playbook
task clean        # Удалить venv
```

---

Назад к [[Home]]
