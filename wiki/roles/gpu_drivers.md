# Роль: gpu_drivers

**Phase**: 2 | **Направление**: Оборудование

## Цель

Автоматизирует установку и настройку GPU-драйверов: определяет видеокарту через `lspci`, устанавливает подходящий стек драйверов (NVIDIA/AMD/Intel), настраивает Vulkan, VA-API и параметры ядра. После выполнения роли: Wayland-компостинг работает, аппаратное декодирование видео работает, GPU стабилен после перезагрузки.

## Ключевые переменные (defaults)

```yaml
gpu_drivers_vendor: auto                    # auto|nvidia|amd|intel|none
gpu_drivers_nvidia_variant: proprietary     # proprietary|open-kernel|nouveau
gpu_drivers_nvidia_kms: true               # nvidia-drm.modeset=1 (для Wayland)
gpu_drivers_nvidia_blacklist_nouveau: true  # блокировать nouveau при proprietary/open-kernel
gpu_drivers_manage_initramfs: true         # регенерировать initramfs после установки
gpu_drivers_nvidia_suspend: true           # nvidia-suspend/hibernate/resume (systemd)
gpu_drivers_nvidia_preserve_video_memory: 1 # NVreg_PreserveVideoMemoryAllocations
gpu_drivers_nvidia_modprobe_overwrite: {}  # пользовательские modprobe options (merge поверх)
gpu_drivers_multilib: false                # 32-bit либы (Wine/Steam); true при profile: gaming
gpu_drivers_vulkan_tools: true             # vulkan-tools (vulkaninfo, vkcube)
gpu_drivers_vaapi: true                    # VA-API конфигурация (LIBVA_DRIVER_NAME)
gpu_drivers_audit_enabled: false           # аудит-режим (логирование событий)
```

## Что настраивает

- `/etc/modprobe.d/nvidia.conf` — DRM KMS и NVreg_PreserveVideoMemoryAllocations
- `/etc/modprobe.d/nvidia-blacklist.conf` — блокировка nouveau
- `/etc/mkinitcpio.conf.d/nvidia.conf` — NVIDIA модули в initramfs (Arch)
- `/etc/dracut.conf.d/nvidia.conf` — NVIDIA модули в initramfs (dracut)
- `/etc/initramfs-tools/hooks/nvidia-ansible` — NVIDIA hook (Debian initramfs-tools)
- `/etc/environment.d/gpu.conf` — `LIBVA_DRIVER_NAME` для VA-API приложений
- Systemd сервисы: `nvidia-suspend.service`, `nvidia-hibernate.service`, `nvidia-resume.service`

## Audit Events

| Event | Source | Severity | Threshold |
|-------|--------|----------|-----------|
| NVIDIA driver not loaded at boot | `dmesg \| grep -i nvidia` | CRITICAL | отсутствует nvidia в lsmod |
| nouveau не заблокирован (proprietary активен) | `lsmod \| grep nouveau` | HIGH | nouveau присутствует при proprietary/open-kernel |
| VA-API недоступен | `vainfo 2>&1` | WARNING | ошибка при vainfo |
| Vulkan ICD loader не найден | `vulkaninfo --summary 2>&1` | WARNING | ошибка при vulkaninfo |
| initramfs не обновлён после установки | mtime nvidia.conf vs initramfs | WARNING | initramfs старше конфига |
| Неверный NVreg_PreserveVideoMemoryAllocations | `cat /proc/driver/nvidia/params` | WARNING | значение != ожидаемому |

## Monitoring Integration

- **Метрики GPU**: `nvidia-smi dmon` (NVIDIA), `radeontop` (AMD), `intel_gpu_top` (Intel)
- **Prometheus экспортер**: `dcgm-exporter` (NVIDIA DCGM) или `node_exporter` с textfile collector
- **Проверка VA-API**: `vainfo` — наличие профилей декодирования/кодирования
- **Журнал событий**: `journalctl -k | grep -E 'nvidia|amd|i915'` — ошибки ядра

## Зависимости

- `pciutils` (lspci) — для `gpu_drivers_vendor: auto`
- Инструмент initramfs: `mkinitcpio` (Arch), `dracut`, или `initramfs-tools` (Debian)
- NVIDIA: `community.general` Ansible collection (для модуля pacman — legacy; заменено на `ansible.builtin.package`)

## Поддерживаемые платформы

| OS family | Статус | Примечание |
|-----------|--------|------------|
| Arch Linux | ✅ Полный | pacman, mkinitcpio |
| Debian/Ubuntu | ✅ Полный | apt, initramfs-tools/dracut |
| RedHat/Fedora | 🔧 Stub | Нужен RPM Fusion; не реализовано |
| Void Linux | 🔧 Stub | Нужен nonfree repo; не реализовано |
| Gentoo | 🔧 Stub | USE flags; не реализовано |

## Теги

| Тег | Область |
|-----|---------|
| `gpu` | Все задачи роли |
| `drivers` | Определение, установка, окружение, отчёт |
| `nvidia` | NVIDIA-специфичные задачи |
| `amd` | AMD-специфичные задачи |
| `intel` | Intel-специфичные задачи |
| `vulkan` | Vulkan ICD loader и инструменты |
| `report` | Задачи структурированного отчёта |

## Связанные роли

- `common` — `report_phase.yml`, `report_render.yml`
- `base_system` — базовые пакеты, в т.ч. pciutils
