# bootloader

Выбирает и вызывает backend установленного загрузчика перед подготовкой системы.

## Execution flow

1. **Validate inputs** (`tasks/validate.yml`) — проверяет поддерживаемое семейство ОС через `common/assert_supported_os.yml`, валидирует `bootloader_type` и каждую запись backend registry.
2. **Detect backend artifacts** (`tasks/detect.yml`) — проверяет объявленные `detection.paths` каждого backend-а и записывает имена найденных backend-ов.
3. **Select backend** (`tasks/detect.yml`) — определяет `bootloader_selected_type` из `bootloader_type`: `auto`, `none` или явное имя backend-а.
4. **Invoke backend** (`tasks/main.yml`) — вызывает выбранную backend role через `include_role`. Вся специфичная логика загрузчика принадлежит backend role.
5. **Report** (`tasks/main.yml`) — выводит выбранный backend и вызванную backend role через `common/report_render.yml`.

### Boundaries

`bootloader` — dispatcher role. Она не устанавливает загрузчики, не рендерит package-manager hooks, не запускает package upgrade, не перезагружает хост и не управляет workstation roles. Настройки конкретного загрузчика принадлежат backend roles, например `limine`.

## Variables

### Configurable (`defaults/main.yml`)

Переопределять через inventory, не через правку `defaults/main.yml`.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `bootloader_enabled` | `true` | safe | `false` полностью пропускает detection и backend invocation. |
| `bootloader_type` | `auto` | safe | `auto`, `none` или имя backend-а из `bootloader_backends`. |
| `bootloader_supported_os` | пять проектных OS families | internal | Runtime support list, требуемый стандартом ролей проекта. |
| `bootloader_backends` | Limine backend registry | careful | Registry известных backend roles и их detection artifacts. |

### Backend registry contract

Каждая запись backend-а объявляет имя backend-а, имя роли и artifacts для detection:

```yaml
bootloader_backends:
  - name: limine
    role: limine
    detection:
      paths:
        - /boot/limine/limine.conf
        - /usr/bin/limine
```

Backend role получает обычный play context. Backend-specific переменные принадлежат соответствующей backend role и документируются в ее README.

## Examples

### Использовать найденный backend

```yaml
# group_vars/all/bootloader.yml
bootloader_type: auto
```

`auto` выбирает первый backend, у которого найдены detection artifacts.

### Отключить bootloader maintenance

```yaml
# host_vars/<hostname>/bootloader.yml
bootloader_type: none
```

Prepare flow сохраняется, но backend role не вызывается.

### Добавить GRUB backend

```yaml
# group_vars/all/bootloader.yml
bootloader_backends:
  - name: grub
    role: grub
    detection:
      paths:
        - /boot/grub/grub.cfg
        - /usr/bin/grub-install
```

Роль `grub` должна владеть GRUB-specific settings, validation, configuration и verification.

### Добавить custom backend

```yaml
# group_vars/all/bootloader.yml
bootloader_backends:
  - name: company_loader
    role: company_loader
    detection:
      paths:
        - /etc/company-loader/config.yml
        - /usr/local/bin/company-loader
```

Custom backend должен иметь собственные `<backend>_*` переменные и README.

## Cross-platform details

Сам `bootloader` OS-family agnostic. Platform-specific behavior принадлежит backend roles. В текущем default registry есть `limine`; его package-manager hook support описан в README роли `limine`.

## Failure modes

| Failure | Meaning | Fix |
|---------|---------|-----|
| Unsupported OS family | Хост вне проектного стандарта ролей. | Запускать на одной из пяти поддерживаемых OS families или сначала менять стандарт проекта. |
| Invalid `bootloader_type` | Значение не равно `auto`, `none` или имени backend-а. | Указать `bootloader_type` из registry. |
| Invalid backend registry | В backend entry нет `name`, `role` или `detection.paths`. | Исправить registry entry в inventory или defaults. |
| Selected backend has no role | У выбранного backend-а нет вызываемой роли. | Добавить backend role или исправить `role` в registry. |

## Verification

Molecule использует fake backend role для проверки dispatcher contract. Fake backend пишет marker file, а verify проверяет, что `bootloader` выбрал и вызвал этот backend. Поведение конкретных загрузчиков тестируется в их backend roles.
