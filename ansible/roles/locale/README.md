# locale

Генерирует системные локали и настраивает `LANG` и `LC_*` переменные через `/etc/locale.conf`.

## What this role does

- [x] Валидирует входные переменные (soft-fail: пропускает роль при некорректной конфигурации)
- [x] Генерирует локали через дистро-специфичный механизм
- [x] Проверяет наличие сгенерированных локалей (`locale -a`) перед записью конфига
- [x] Записывает `/etc/locale.conf` с `LANG` и `LC_*` переопределениями только если verify прошёл

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `locale_list` | `["en_US.UTF-8", "ru_RU.UTF-8"]` | Список локалей для генерации |
| `locale_default` | `"en_US.UTF-8"` | Основная системная локаль (`LANG` в `/etc/locale.conf`) |
| `locale_lc_overrides` | `{}` | Переопределения `LC_*` категорий |

`locale_default` **обязан** присутствовать в `locale_list`. Все значения `locale_lc_overrides` тоже должны быть в `locale_list` — иначе роль пропустит настройку и покажет `! fail` в репорте.

Реальные значения задаются в `group_vars/all/system.yml`:

```yaml
locale_list:
  - "en_US.UTF-8"
  - "ru_RU.UTF-8"
locale_default: "en_US.UTF-8"
locale_lc_overrides:
  LC_TIME: "ru_RU.UTF-8"
```

## Execution order

```
validate → generate → verify → configure
```

Verify запускается **до** configure: если локали не сгенерировались, `/etc/locale.conf`
не записывается (машина не получает сломанный конфиг).

## Responsibility boundaries

| Concern | Owner |
|---------|-------|
| Генерация и настройка системной локали | this role |
| Локаль конкретного пользователя (`~/.profile`) | пользователь / dotfiles |
| Console keymap (TTY) | `keymap` role |
| Языковые пакеты приложений | `packages` role |

## Supported platforms

Arch Linux, Debian, Ubuntu, RedHat/EL, Void Linux

## Tags

`locale`, `locale,report`

## License

MIT
