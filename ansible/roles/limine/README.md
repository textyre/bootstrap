# limine

Управляет maintenance state для Limine.

## Execution Flow

1. **Validate inputs** — проверяет ОС, OS-specific hook backend и target policy.
2. **Resolve target** — выбирает BIOS install target: явное значение или parent disk от `limine_boot_mount`.
3. **Configure** — пишет machine-local `limine_install_target_file` и, если backend поддержан, package-manager hook.
4. **Verify target** — проверяет target file и, опционально, block device.
5. **Verify hook** — проверяет clone-safe hook content.
6. **Verify files** — проверяет Limine binary, `limine-bios.sys` и boot directory.

Роль не выполняет reboot, package upgrade и не вызывает `limine bios-install` во время Ansible run. Hook вызывает `limine bios-install` только после обновления пакета Limine.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `limine_enabled` | `true` | Включает или отключает роль. |
| `limine_manage_update_hook` | `auto` | `auto`, `true`, `false`. `auto` включает только реализованный hook backend. |
| `limine_boot_mount` | `/boot` | Mount point, от которого auto policy определяет parent disk. |
| `limine_install_target_file` | `/etc/limine/install-target` | Machine-local target file для hook. |
| `limine_bios_install_target` | `""` | Явный BIOS install target для multi-disk систем. |
| `limine_bios_install_target_auto` | `true` | Разрешает auto target от parent disk. |
| `limine_validate_target_block_device` | `true` | Проверяет, что target является block device. |
| `limine_pacman_hook_file` | `/etc/pacman.d/hooks/99-limine.hook` | Pacman hook path для Archlinux. |

## Platform Behavior

| OS family | Hook backend |
|-----------|--------------|
| Archlinux | pacman |
| Debian | none |
| RedHat | none |
| Void | none |
| Gentoo | none |

На non-Arch системах `limine_manage_update_hook: auto` не создает package-manager hook. Если hook нужен явно, сначала должен быть добавлен backend для соответствующего package manager.
