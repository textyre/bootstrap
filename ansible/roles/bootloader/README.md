# bootloader

Подготавливает обслуживание загрузчика перед обновлением системы.

## Execution flow

1. **Validate inputs** (`tasks/validate.yml`) — проверяет семейство ОС, `bootloader_type`, параметры выбора Limine target и загружает OS-specific переменные для Arch Linux.
2. **Detect bootloader** (`tasks/detect.yml`) — один раз определяет текущий загрузчик по системным артефактам. Сейчас поддерживается backend Limine.
3. **Resolve Limine target** (`tasks/resolve_target.yml`) — для Limine выбирает BIOS install target: сначала явный `bootloader_limine_bios_install_target`, затем parent disk от `/boot`.
4. **Apply Limine backend** (`tasks/backends/limine.yml`) — создает `/etc/limine/install-target` и генерирует `/etc/pacman.d/hooks/99-limine.hook`.
5. **Verify state** (`tasks/verify.yml`) — проверяет target file, hook content, Limine files и отсутствие inline VirtualBox disk id в hook.
6. **Report** — выводит краткий отчет через общий report pattern.

Эта роль не выполняет reboot, не запускает package upgrade и не вызывает `limine bios-install` напрямую.

## Variables

### Configurable (`defaults/main.yml`)

Переопределять через `group_vars/` или `host_vars/`, не редактировать `defaults/main.yml` напрямую.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `bootloader_enabled` | `true` | safe | Включает или отключает роль целиком. |
| `bootloader_type` | `auto` | safe | `auto`, `limine` или `none`. |
| `bootloader_manage_update_hook` | `true` | careful | Управляет package-manager hook для backend. |
| `bootloader_boot_mount` | `/boot` | careful | Mount point, от которого auto policy определяет parent disk. |
| `bootloader_install_target_file` | `/etc/limine/install-target` | careful | Machine-local target file для Limine hook. |
| `bootloader_limine_pacman_hook_file` | `/etc/pacman.d/hooks/99-limine.hook` | careful | Hook, который запускается при обновлении пакета `limine`. |
| `bootloader_limine_bios_install_target` | `""` | careful | Явный Limine BIOS install target для multi-disk систем. |
| `bootloader_limine_bios_install_target_auto` | `true` | careful | Разрешает auto target от parent disk `/boot`. |
| `bootloader_limine_bios_install_target_auto_source` | `boot_parent` | internal | Стратегия auto target. Сейчас поддерживается только `boot_parent`. |
| `bootloader_limine_validate_target_block_device` | `true` | careful | Проверяет, что target является block device. В тестах может быть выключено. |
| `bootloader_limine_boot_dir` | `/boot/limine` | internal | Каталог Limine на boot partition. |
| `bootloader_limine_config_file` | `/boot/limine/limine.conf` | internal | Признак установленного Limine. |
| `bootloader_limine_binary` | `/usr/bin/limine` | internal | Binary Limine. |
| `bootloader_limine_bios_sys_source` | `/usr/share/limine/limine-bios.sys` | internal | Stage file, копируемый hook-ом. |

### Internal mappings (`vars/`)

| File | What it contains | When to edit |
|------|-----------------|--------------|
| `vars/Archlinux.yml` | Arch-specific package-manager hook metadata | При изменении Arch backend. |

## Examples

### VM или простая bare-metal система

```yaml
# In group_vars/all/bootloader.yml:
bootloader_type: auto
```

Если Limine найден, target будет вычислен от `/boot`: `/boot` -> partition -> parent disk -> preferred `/dev/disk/by-id`.

### Multi-disk bare metal

```yaml
# In host_vars/workstation-01/bootloader.yml:
bootloader_type: limine
bootloader_limine_bios_install_target: /dev/disk/by-id/nvme-SYSTEM_BOOT_DISK
```

Использовать, когда firmware boot disk нельзя надежно вывести из `/boot`.

### Отключить управление загрузчиком

```yaml
# In host_vars/<hostname>/bootloader.yml:
bootloader_type: none
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu/Debian | Fedora | Void | Gentoo |
|--------|------------|---------------|--------|------|--------|
| Limine pacman hook | supported | not implemented | not implemented | not implemented | not implemented |
| Auto detection | Limine only | no-op unless explicit support added | no-op | no-op | no-op |

## Logs

| Source | Command | Contents |
|--------|---------|----------|
| pacman log | `grep limine /var/log/pacman.log` | Package update hook execution and Limine errors. |
| role output | `task prepare:system` | Role phases, target resolution and verification results. |

## Tests

Run through the project Taskfile:

```bash
task test-bootloader
```

Expected coverage:

- playbook/Taskfile contract for `prepare:system`;
- no direct reboot/package-upgrade/workstation behavior in `bootloader`;
- explicit Limine target behavior;
- stale hook normalization;
- idempotence.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails to resolve target | `/boot` topology is not enough to infer boot disk | Set `bootloader_limine_bios_install_target` explicitly. |
| Hook still contains old disk id | Hook is not managed by this role or wrong hook path was configured | Check `bootloader_limine_pacman_hook_file` and rerun `task prepare:system`. |
| Target validation fails | Target does not resolve to a block device | Use a valid `/dev/disk/by-id/...` disk path. |
