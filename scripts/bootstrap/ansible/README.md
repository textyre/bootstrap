# Ansible Playbooks для Bootstrap

## Быстрый старт

```bash
cd scripts/bootstrap/ansible
task bootstrap   # Установить зависимости (один раз)
task run         # Применить playbook
```

## Команды

| Команда | Описание |
|---------|----------|
| `task bootstrap` | Установить Python зависимости |
| `task check` | Проверить синтаксис |
| `task lint` | Проверить best practices |
| `task test` | Запустить molecule тесты |
| `task dry-run` | Показать изменения без применения |
| `task run` | Применить playbook |
| `task all` | check + lint |
| `task clean` | Удалить venv |

## Тестирование

```bash
export MOLECULE_SUDO_PASS="your_password"
task test
```

**Внимание:** `task test` изменяет систему! Создайте снапшот VM перед запуском.

## Конфигурация зеркал

По умолчанию настроено для Казахстана. Для других регионов:

```bash
# Европа
task run -- -e "reflector_countries=DE,FR,NL"

# США
task run -- -e "reflector_countries=US"
```

## Параметры

См. [defaults/main.yml](roles/reflector/defaults/main.yml):

- `reflector_countries` — список стран (KZ,RU,DE,NL,FR)
- `reflector_latest` — количество зеркал (20)
- `reflector_age` — максимальный возраст в часах (12)
- `reflector_sort` — сортировка: rate или age

## Архитектура

1. Параметры в `defaults/main.yml`
2. Template генерирует `/etc/xdg/reflector/reflector.conf`
3. systemd timer использует конфиг: `reflector @/etc/xdg/reflector/reflector.conf`
