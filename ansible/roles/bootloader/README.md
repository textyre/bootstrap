# bootloader

Универсальная роль-оркестратор для подготовки загрузчика перед обновлением системы.

Роль не содержит backend-specific настройки конкретного загрузчика. Она только:

1. проверяет входные параметры;
2. определяет установленный загрузчик по declarative backend registry;
3. выбирает backend role;
4. вызывает выбранную роль;
5. выводит краткий отчет.

Сейчас в registry настроен backend `limine`, который обслуживается отдельной ролью `limine`.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `bootloader_enabled` | `true` | Включает или отключает роль целиком. |
| `bootloader_type` | `auto` | `auto`, `none` или имя backend из `bootloader_backends`. |
| `bootloader_backends` | `limine` registry | Список известных backend: `name`, `role`, `detection_paths`. |

Настройки конкретного backend задаются переменными соответствующей роли. Для Limine это `limine_*` переменные из роли `limine`.

## Boundaries

`bootloader` не выполняет reboot, package upgrade, workstation roles и не запускает команды установки загрузчика напрямую. Конкретная логика загрузчика живет в backend role.
