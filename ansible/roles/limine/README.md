# limine

Поддерживает clone-safe update state для загрузчика Limine.

## Execution flow

1. **Validate inputs** (`tasks/validate.yml`) — проверяет поддерживаемое семейство ОС, загружает OS-specific hook settings, валидирует target policy и выбирает, включено ли hook management.
2. **Resolve target** (`tasks/resolve_target.yml`) — использует `limine_bios_install_target`, если он задан, иначе передает определение boot parent в `tasks/resolve_boot_parent_target.yml`.
3. **Resolve boot parent** (`tasks/resolve_boot_parent_target.yml`) — сопоставляет `limine_boot_mount` с mounted source, ancestor disk chain и стабильным `/dev/disk/by-id` path, если он доступен. Auto mode проходит только если `/boot` однозначно ведет к одному backing disk.
4. **Validate target** (`tasks/resolve_target.yml`) — fail-fast, если target не определен, и опционально проверяет, что target является block device.
5. **Configure target state** (`tasks/configure.yml`) — записывает `limine_install_target_file`, machine-local target file для package-manager hook.
6. **Configure hook** (`tasks/hooks/pacman.yml`) — на Archlinux рендерит маленький pacman hook и отдельный helper script. Hook только вызывает helper, а helper уже читает `limine_install_target_file`, вызывает `limine bios-install` для текущего machine-local target, обновляет `limine-bios.sys` в configured boot directory и делает `sync`.
7. **Verify runtime state** (`tasks/verify.yml`) — проверяет target file, hook content, Limine binary, `limine-bios.sys` и boot directory.
8. **Report** (`tasks/main.yml`) — выводит hook kind, target source и resolved target.

### Boundaries

`limine` — backend role. Она не запускает system upgrades, не перезагружает хост, не управляет workstation roles, не добавляет другие загрузчики и не вызывает `limine bios-install` во время Ansible run. Отрендеренный package-manager hook вызывает Limine только при установке или обновлении пакета Limine.

Для BIOS boot Limine должен видеть `limine-bios.sys` и `limine.conf` в одном из стандартных каталогов на partition boot device: `/boot/limine`, `/boot`, `/limine` или root. Роль не создает дополнительные candidate paths: она поддерживает тот configured boot directory, который уже используется системой, и убирает только clone-unsafe hardcoded disk id из pacman hook.

### Pacman hook contract

Арховая реализация теперь разделена на два понятных слоя:

1. Маленький pacman hook в `limine_pacman_hook_file`.
2. Отдельный helper script в `limine_pacman_hook_script_file`.

Так hook остается минимальным, а сам boot-update flow читается как обычный shell script.

Helper script делает четыре вещи и делает их именно в таком порядке:

1. Читает machine-local install target из `limine_install_target_file`.
2. Вызывает `limine bios-install` для этого target.
3. Обновляет `{{ limine_boot_dir }}/limine-bios.sys`.
4. Делает `sync` перед отдельным reboot boundary.

Зачем это нужно:

- чтение target из файла убирает clone-unsafe hardcoded disk id;
- `bios-install` обновляет boot code на выбранном диске;
- явное обновление `limine-bios.sys` закрепляет stage file в configured boot directory;
- `sync` уменьшает риск незавершенных записей перед reboot после `prepare:system`.

## Variables

### Configurable (`defaults/main.yml`)

Переопределять через inventory, не через правку `defaults/main.yml`.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `limine_enabled` | `true` | safe | `false` пропускает роль. |
| `limine_supported_os` | пять проектных OS families | internal | Runtime support list, требуемый стандартом ролей проекта. |
| `limine_manage_update_hook` | `auto` | careful | `auto`, `true` или `false`. `auto` включает только реализованные hook backends. |
| `limine_boot_mount` | `/boot` | careful | Mount point, используемый automatic boot-parent resolver. |
| `limine_install_target_file` | `/etc/limine/install-target` | careful | Machine-local файл, который читает package-manager hook. |
| `limine_bios_install_target` | `""` | careful | Явный BIOS install target для multi-disk или custom firmware layouts. |
| `limine_bios_install_target_auto` | `true` | careful | Разрешает automatic target resolution от `limine_boot_mount`. |
| `limine_bios_install_target_auto_source` | `boot_parent` | internal | Automatic target strategy. Поддерживается только `boot_parent`. |
| `limine_bios_install_target_by_id_dir` | `/dev/disk/by-id` | internal | Каталог stable identity symlinks для auto-resolved target. |
| `limine_validate_target_block_device` | `true` | safe | Проверяет, что resolved target является block device. |
| `limine_boot_dir` | `/boot/limine` | careful | Directory с Limine boot files. |
| `limine_config_file` | `/boot/limine/limine.conf` | careful | Путь к Limine configuration file. |
| `limine_binary` | `/usr/bin/limine` | careful | Путь к Limine executable. |
| `limine_bios_sys_source` | `/usr/share/limine/limine-bios.sys` | careful | BIOS support file, который копирует hook. |
| `limine_pacman_hook_file` | `/etc/pacman.d/hooks/99-limine.hook` | careful | Archlinux pacman hook path. |
| `limine_pacman_hook_script_file` | `/usr/local/lib/bootstrap/limine-refresh-after-upgrade.sh` | careful | Helper script, который выполняет boot-update flow для Arch pacman hook. |

### Internal mappings (`vars/`)

| File | What it contains | When to edit |
|------|------------------|--------------|
| `vars/Archlinux.yml` | `limine_update_hook_kind: pacman` | При изменении Arch hook behavior. |
| `vars/Debian.yml` | `limine_update_hook_kind: none` | При добавлении Debian package-manager hook support. |
| `vars/RedHat.yml` | `limine_update_hook_kind: none` | При добавлении RedHat package-manager hook support. |
| `vars/Void.yml` | `limine_update_hook_kind: none` | При добавлении Void package-manager hook support. |
| `vars/Gentoo.yml` | `limine_update_hook_kind: none` | При добавлении Gentoo package-manager hook support. |

## Examples

### Использовать automatic boot-parent target resolution

```yaml
# group_vars/workstations/limine.yml
limine_bios_install_target_auto: true
limine_boot_mount: /boot
```

Роль определяет диск, на котором расположен `/boot`; она не выбирает первый диск в системе.

### Использовать explicit target на multi-disk host

```yaml
# host_vars/<hostname>/limine.yml
limine_bios_install_target: /dev/disk/by-id/ata-example-system-disk
limine_bios_install_target_auto: false
```

Использовать, когда boot topology нельзя безопасно вывести из `/boot`.

### Отключить package-manager hook management

```yaml
# host_vars/<hostname>/limine.yml
limine_manage_update_hook: false
```

Роль продолжит писать и проверять target file, но не будет рендерить package-manager hooks.

## Cross-platform details

| OS family | Hook backend | Behavior |
|-----------|--------------|----------|
| Archlinux | pacman | Рендерит `limine_pacman_hook_file`. |
| Debian | none | В `auto` mode не рендерит hook. |
| RedHat | none | В `auto` mode не рендерит hook. |
| Void | none | В `auto` mode не рендерит hook. |
| Gentoo | none | В `auto` mode не рендерит hook. |

## Failure modes

| Failure | Meaning | Fix |
|---------|---------|-----|
| Unsupported OS family | Хост вне проектного стандарта ролей. | Запускать на одной из пяти поддерживаемых OS families или сначала менять стандарт проекта. |
| Target policy unavailable | Explicit target не задан, auto target resolution выключен. | Задать `limine_bios_install_target` или включить `limine_bios_install_target_auto`. |
| Boot parent cannot be resolved | `findmnt` или `lsblk` не смогли сопоставить `limine_boot_mount` с ровно одним parent disk. | Задать `limine_bios_install_target` явно для этого хоста. |
| Boot parent has multiple disks | `/boot` расположен поверх multi-disk слоя, например RAID/LVM/multipath. | Задать explicit target policy через `limine_bios_install_target`. |
| Resolved target is not a block device | Target path неправильный или недоступен. | Использовать стабильный `/dev/disk/by-id` target для boot disk. |
| Hook backend unavailable | Hook management принудительно включен на OS family без backend-а. | Добавить backend или использовать `limine_manage_update_hook: auto/false`. |
| Limine artifact missing | Нет binary, BIOS file или boot directory. | Установить/настроить Limine перед запуском backend-а. |

## Verification

Runtime verification остается частью роли, потому что реальный prepare run должен падать до package upgrades, если Limine state небезопасен. Runtime verify проверяет только safety-инварианты хоста: target file, hook path, helper script и необходимые Limine artifacts.

Molecule не повторяет этот runtime verify построчно. Вместо этого он проверяет результат сценария: stale hardcoded hook заменяется на managed hook, managed hook указывает на helper script, а helper script реально выполняет boot-update flow на тестовых fixture-файлах.
