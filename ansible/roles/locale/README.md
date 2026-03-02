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
| Console keymap (TTY) | `vconsole` role |
| Языковые пакеты приложений | `packages` role |

## Supported platforms

Arch Linux, Debian, Ubuntu, RedHat/EL, Void Linux

## Tags

`locale`, `locale,report`

## Testing

| Scenario | Driver | Platforms | Notes |
|----------|--------|-----------|-------|
| `default` | localhost | localhost | Syntax only |
| `docker` | docker | Arch Linux, Ubuntu (custom images) | Unit tests in container |
| `vagrant` | vagrant (libvirt) | Arch Linux, Ubuntu 24.04 | Full VM integration tests |
| `validation` | localhost | localhost | Soft-fail validation edge cases |

```bash
# Docker (fast, CI)
molecule test -s docker

# Validation edge cases (empty list, wrong default, wrong LC_*)
molecule test -s validation

# Vagrant (full integration, requires KVM)
molecule test -s vagrant

# Step-by-step vagrant
molecule create -s vagrant
molecule converge -s vagrant
molecule verify -s vagrant
molecule destroy -s vagrant
```

The shared `converge.yml` and `verify.yml` are reused across `docker` and `vagrant` scenarios. The `validation` scenario tests:
- `locale_list: []` → soft-fail, no `/etc/locale.conf` written
- `locale_default` not in `locale_list` → soft-fail
- `LC_*` override value not in `locale_list` → soft-fail

The `vagrant` scenario additionally tests:
- Ubuntu `locales` package dependency
- Cross-platform `/etc/locale.conf` behaviour
- Idempotence of `community.general.locale_gen` on pre-generated locales

## License

MIT
