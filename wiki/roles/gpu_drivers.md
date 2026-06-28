# Роль: gpu_drivers

**Phase**: 1.5 | **Направление**: Hardware & Kernel

## Цель

`gpu_drivers` настраивает стек GPU-драйверов, которым владеет эта роль: определение или явный выбор GPU vendor, установка пакетов NVIDIA/AMD/Intel для реализованных дистрибутивных pipeline, NVIDIA module options, initramfs integration, systemd suspend/resume services и VA-API environment.

Роль не настраивает X11, Wayland, GNOME, KDE, Hyprland, display manager, user session, PRIME/offloading, VM guest tools, virtual GPU integration или GPU passthrough. Эти контракты принадлежат другим ролям или отдельным сценарным проверкам.

## Источник правды

Актуальный контракт, переменные, сценарии, pipeline, тесты и ограничения описаны в role README:

- `ansible/roles/gpu_drivers/README.md`

Эта wiki-страница служит навигационной страницей и не должна становиться второй независимой спецификацией роли.

## Контракт

Роль владеет:

- GPU vendor detection через `lspci` или явным `gpu_drivers_vendor`.
- Driver package stack для реализованных Arch Linux и Debian-family pipeline.
- NVIDIA KMS/module options и nouveau blacklist, когда выбран NVIDIA proprietary/open-kernel stack.
- NVIDIA initramfs integration, когда он включен.
- NVIDIA suspend/hibernate/resume services для systemd, когда они включены.
- VA-API package stack и `/etc/environment.d/gpu.conf`, когда VA-API включен.
- Финальной verify-проверкой ожидаемого package stack.

Роль не владеет:

- VM guest display integration. Это контракт роли `vm`.
- Display server, compositor и desktop session.
- Runtime-проверками `nvidia-smi`, `vainfo`, `vulkaninfo`, compositor startup или suspend/resume.
- Удалением ранее созданных файлов при смене feature flags.
- Audit logging. `gpu_drivers_audit_enabled` зарезервирован как внешний контракт, но задачи аудита сейчас не реализованы.

## Сценарии

- Bare metal NVIDIA/AMD/Intel: роль ставит и настраивает выбранный или обнаруженный driver package stack.
- VM с GPU passthrough: роль работает как на bare metal, потому что guest видит физическую GPU.
- VM без GPU passthrough: bare-metal GPU stack обычно не нужен; guest graphics настраивает роль `vm`.
- Headless VM: использовать `gpu_drivers_vendor: none`, если физический GPU stack не нужен.
- Docker/container: только smoke/idempotence; контейнеры не являются средой проверки kernel GPU drivers.

## Verify и тесты

Role verify проверяет итоговый package-stack contract для выбранного vendor и distro. Он не повторяет работу Ansible-модулей и не запускает runtime GPU commands.

Molecule сценарии проверяют syntax, converge и idempotence. Отдельный Molecule verify playbook не используется, потому что роль запускает собственную verify-фазу во время converge.

Runtime и reboot-sensitive проверки должны выполняться отдельно в сценарных VM/bare-metal проверках, где реально доступны GPU, passthrough, user session, display server и состояние после reboot.

## Поддерживаемые платформы

- Arch Linux: реализовано.
- Debian/Ubuntu: реализовано.
- RedHat/Fedora, Void Linux, Gentoo: pipeline stubs с явным fail для не реализованных частей.

Поддерживаемые init systems: `systemd`, `runit`, `openrc`, `s6`, `dinit`. NVIDIA service management реализован для `systemd`; остальные init systems получают явный fail, когда применима NVIDIA service logic.

## Связанные роли

- `common` — `report_phase.yml`, `report_render.yml`.
- `vm` — guest integration для VirtualBox/VMware/Hyper-V/KVM.
