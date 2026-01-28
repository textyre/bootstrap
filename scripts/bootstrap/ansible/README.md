# Ansible Playbooks для Bootstrap

## Для разработчиков: тестирование и валидация

### Первый запуск (один раз на свежей системе)

```bash
cd scripts/bootstrap/ansible
./bootstrap.sh
```

Это автоматически установит:
- **Task** (go-task) - современный таск-раннер (аналог npm scripts)
- **Python**, pip
- **Ansible**, Molecule, ansible-lint

**Важно:** В Arch Linux команда называется `go-task`, но скрипт создает alias `task` для удобства.

### Troubleshooting: "Ansible is being run in a world writable directory"

Если при запуске `task check` или других команд вы видите ошибку:
```
[WARNING]: Ansible is being run in a world writable directory, ignoring it as an ansible.cfg source
[ERROR]: the role 'reflector' was not found
```

**Причина:** Ansible отказывается читать ansible.cfg из директории с небезопасными правами доступа.

**Решение:** Исправьте права доступа на директорию ansible:

```bash
# Убедитесь, что директория не доступна для записи всем пользователям
cd ~/bootstrap/bootstrap  # или ваш путь к проекту
chmod -R o-w ansible      # Убрать права записи для "others"

# Проверьте права (должно быть drwxr-xr-x, а не drwxrwxrwx)
ls -la | grep ansible
```

После этого команды `task check` и `task test-full` должны работать корректно.

### Troubleshooting: "Failed to find driver delegated"

Если при запуске `task test` вы видите ошибку:
```
ERROR    Failed to find driver delegated. Please ensure that the driver is correctly installed.
```

**Причина:** Пакет `molecule-plugins` не установлен или установлен некорректно.

**Решение:** Переустановите зависимости Python:

```bash
cd ~/bootstrap/bootstrap/ansible  # или ваш путь к проекту
.venv/bin/pip install --upgrade -r requirements.txt --force-reinstall molecule-plugins
```

Или полная переустановка окружения:
```bash
task clean      # Удалить venv
task bootstrap  # Переустановить все зависимости
```

### Команды разработки (как npm scripts)

```bash
# Показать все доступные команды
task

# Проверить синтаксис (быстро)
task check

# Проверить best practices
task lint

# Запустить тесты (в изолированном окружении)
task test

# Все проверки разом
task all

# Dry-run (показать что изменится, без реальных изменений)
task dry-run

# Применить playbook (реальные изменения!)
task run
```

### Что делает каждая команда

- **task check** - проверяет синтаксис YAML и Ansible, ~2 сек
- **task lint** - проверяет код на соответствие best practices (ansible-lint)
- **task test** - запускает Molecule тесты:
  - ⚠️ **ИЗМЕНЯЕТ вашу систему!** Создайте снапшот VM перед запуском
  - Применяет роль к localhost
  - Автоматически проверяет результат (systemd timer, mirrorlist, конфиги)
- **task test-full** - запускает все проверки (check + lint + test) с подтверждением
  - Требует нажать **y** для продолжения, **N** отменяет выполнение
- **task test-full-force** - то же что test-full, но БЕЗ подтверждения (для CI/CD)
- **task all** - запускает check + lint (быстрая валидация перед коммитом)
- **task run** - применяет playbook к вашей системе (РЕАЛЬНЫЕ изменения!)

### Рабочий процесс

1. После изменений в коде:
   ```bash
   task all        # Проверить синтаксис и стиль
   ```

2. Перед коммитом:
   ```bash
   task test       # Запустить полные тесты
   ```

3. Применить к системе:
   ```bash
   task dry-run    # Сначала посмотреть что изменится
   task run        # Применить реально
   ```

### Структура тестов

- [Taskfile.yml](Taskfile.yml) - все команды для разработки (как package.json scripts)
- [requirements.txt](requirements.txt) - Python зависимости (Ansible, Molecule, ansible-lint)
- [bootstrap.sh](bootstrap.sh) - скрипт первичной настройки
- `roles/reflector/molecule/` - тесты для роли reflector:
  - `molecule.yml` - конфигурация тестирования
  - `converge.yml` - применение роли
  - `verify.yml` - проверка результатов

## Быстрый старт после установки ОС

### Обновление зеркал Pacman (для Казахстана)

После установки Arch Linux просто запустите:

```bash
cd scripts/bootstrap/ansible
ansible-playbook playbooks/mirrors-update.yml
```

Это автоматически:
- Установит reflector
- Настроит оптимальные зеркала для региона КЗ (Казахстан, Россия, Европа)
- Обновит список зеркал немедленно
- Настроит автоматическое обновление зеркал ежедневно

### Конфигурация для разных регионов

Если вы находитесь в другом регионе, измените переменную при запуске:

```bash
# Для Европы
ansible-playbook playbooks/mirrors-update.yml -e "reflector_countries=DE,FR,NL,GB"

# Для США
ansible-playbook playbooks/mirrors-update.yml -e "reflector_countries=US"

# Для Азии
ansible-playbook playbooks/mirrors-update.yml -e "reflector_countries=JP,SG,KR,CN"
```

### Продвинутая настройка

Все параметры можно переопределить:

```bash
ansible-playbook playbooks/mirrors-update.yml \
  -e "reflector_countries=KZ,RU" \
  -e "reflector_latest=30" \
  -e "reflector_age=6" \
  -e "reflector_sort=rate"
```

## Доступные playbooks

- **mirrors-update.yml** - Обновление зеркал Pacman (основной playbook)

## Параметры конфигурации

См. [defaults/main.yml](roles/reflector/defaults/main.yml) для полного списка параметров:

- `reflector_countries` - Список стран (по умолчанию: KZ,RU,DE,NL,FR)
- `reflector_latest` - Количество зеркал (по умолчанию: 20)
- `reflector_age` - Максимальный возраст зеркала в часах (по умолчанию: 12)
- `reflector_sort` - Метод сортировки: rate (скорость) или age (свежесть)
- `reflector_protocol` - Протокол (по умолчанию: https)

## Архитектура (как это работает)

**Единый источник конфигурации:**

1. Все параметры определены в [defaults/main.yml](roles/reflector/defaults/main.yml)
2. Template [reflector.conf.j2](roles/reflector/templates/reflector.conf.j2) генерирует `/etc/xdg/reflector/reflector.conf`
3. **systemd timer** использует этот конфиг через response file синтаксис:
   ```
   ExecStart=/usr/bin/reflector @/etc/xdg/reflector/reflector.conf
   ```
   `@file` — стандартная фича Python argparse: читает аргументы из файла
4. При первом запуске через Ansible параметры передаются в командной строке напрямую
