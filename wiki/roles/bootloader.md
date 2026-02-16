# Роль: bootloader

**Phase**: 1.5 | **Направление**: Hardware & Kernel

## Цель

Настройка загрузчика (GRUB или systemd-boot), параметров ядра, secure boot и initramfs. Оптимизация загрузки, hardening параметров, поддержка encrypted root и resume from swap/zram.

## Ключевые переменные (defaults)

```yaml
bootloader_enabled: true  # Включить настройку bootloader

# Тип загрузчика
bootloader_type: "grub"  # grub / systemd-boot

# === GRUB настройки ===
bootloader_grub_timeout: 5                    # Таймаут меню (секунды)
bootloader_grub_default: "saved"              # Дефолтная запись: 0 / saved (последняя выбранная)
bootloader_grub_savedefault: true             # Сохранять выбранную запись
bootloader_grub_disable_submenu: true         # Отключить подменю (все записи в одном меню)
bootloader_grub_recordfail_timeout: 5         # Таймаут при ошибке загрузки
bootloader_grub_hidden_timeout: 0             # Скрытое меню (0 = показывать всегда)
bootloader_grub_terminal: "console"           # Терминал: console / gfxterm (графический)
bootloader_grub_gfxmode: "auto"               # Разрешение gfxterm (1920x1080, auto)
bootloader_grub_background: ""                # Путь к фону (PNG/JPG)

# === systemd-boot настройки ===
bootloader_systemd_boot_timeout: 5            # Таймаут меню
bootloader_systemd_boot_default: "@saved"     # Дефолтная запись (@saved = последняя)
bootloader_systemd_boot_editor: false         # Разрешить редактирование записей (security risk)
bootloader_systemd_boot_auto_entries: true    # Автоматическое добавление записей
bootloader_systemd_boot_console_mode: "auto"  # Режим консоли: auto / max / keep

# === Kernel параметры (для обоих загрузчиков) ===
bootloader_kernel_params:
  # Performance
  - "nowatchdog"                   # Отключить watchdog (ускорение загрузки)
  - "nmi_watchdog=0"               # Отключить NMI watchdog
  # Security
  - "apparmor=1"                   # Включить AppArmor (если используется)
  - "security=apparmor"            # Использовать AppArmor как LSM
  - "audit=1"                      # Включить audit framework
  - "slab_nomerge"                 # SLUB hardening (защита от heap overflow)
  - "init_on_alloc=1"              # Инициализировать память при аллокации
  - "init_on_free=1"               # Очищать память при освобождении
  - "page_alloc.shuffle=1"         # Рандомизация аллокатора страниц
  - "randomize_kstack_offset=on"   # KASLR для kernel stack
  - "vsyscall=none"                # Отключить vsyscall (legacy, небезопасно)
  - "debugfs=off"                  # Отключить debugfs (information leak)
  - "lockdown=confidentiality"     # Kernel lockdown mode
  # Mitigations (защита от Spectre/Meltdown)
  - "mitigations=auto,nosmt"       # Включить все mitigations, отключить SMT (Hyper-Threading)
  # Quiet boot
  - "quiet"                        # Скрыть kernel messages
  - "loglevel=3"                   # Уровень логов (3 = errors only)

# Дополнительные параметры (кастомные)
bootloader_kernel_params_extra: []

# === Initramfs (Arch: mkinitcpio, Debian: initramfs-tools, Fedora: dracut) ===
bootloader_initramfs_regenerate: true         # Пересобрать initramfs после изменений

# Arch: mkinitcpio hooks
bootloader_mkinitcpio_hooks:
  - base
  - udev
  - autodetect
  - modconf
  - kms                   # KMS (Kernel Mode Setting) для early graphics
  - keyboard
  - keymap
  - consolefont
  - block
  - filesystems
  - fsck

# Encryption support (если используется LUKS)
bootloader_encryption_enabled: false
bootloader_encryption_hooks:
  - encrypt               # LUKS decryption
  - lvm2                  # LVM support (если root на LVM)

# Resume support (для hibernation)
bootloader_resume_enabled: false              # Включить resume from swap/zram
bootloader_resume_device: ""                  # UUID swap-устройства (auto-detect если пусто)

# === Secure Boot ===
bootloader_secure_boot_enabled: false         # Настроить Secure Boot (требует MOK signing)
bootloader_secure_boot_sign_kernel: false     # Подписать kernel (требует ключи)
bootloader_secure_boot_keys_dir: "/root/secure-boot-keys"  # Директория с ключами

# === Microcode updates ===
bootloader_microcode_enabled: true            # Применить CPU microcode
bootloader_microcode_vendor: "auto"           # auto / intel / amd
```

## Что настраивает

### На Arch Linux

- Установка загрузчика:
  - GRUB: пакет `grub`, конфиг `/etc/default/grub`
  - systemd-boot: встроен в systemd, конфиг `/boot/loader/loader.conf`
- Kernel параметры через `GRUB_CMDLINE_LINUX` или systemd-boot entries
- Initramfs: `/etc/mkinitcpio.conf`, перегенерация через `mkinitcpio -P`
- Microcode: пакеты `intel-ucode` / `amd-ucode`
- Установка GRUB: `grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB`
- Обновление конфигурации: `grub-mkconfig -o /boot/grub/grub.cfg`

### На Debian/Ubuntu

- Установка загрузчика:
  - GRUB: пакет `grub-efi-amd64`, конфиг `/etc/default/grub`
  - systemd-boot: пакет `systemd-boot`, конфиг `/boot/efi/loader/loader.conf`
- Kernel параметры через `GRUB_CMDLINE_LINUX_DEFAULT`
- Initramfs: `/etc/initramfs-tools/`, перегенерация через `update-initramfs -u`
- Microcode: пакеты `intel-microcode` / `amd64-microcode`
- Обновление GRUB: `update-grub`

### На Fedora/RHEL

- Установка загрузчика:
  - GRUB: пакет `grub2-efi-x64`, конфиг `/etc/default/grub`
  - systemd-boot: встроен, конфиг `/boot/efi/loader/loader.conf`
- Kernel параметры через `GRUB_CMDLINE_LINUX`
- Initramfs: dracut, конфиг `/etc/dracut.conf.d/`, перегенерация через `dracut --force`
- Microcode: пакеты `microcode_ctl` (Intel/AMD)
- Обновление GRUB: `grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg`

## Зависимости

- `base_system` — базовые утилиты
- `vm` (опционально) — для initramfs hooks (virtio драйверы)

## Примечания

### GRUB vs systemd-boot

| Параметр | GRUB | systemd-boot |
|----------|------|--------------|
| **Поддержка BIOS** | ✅ Да | ❌ Только UEFI |
| **Encrypted /boot** | ✅ Да (LUKS) | ❌ Нет |
| **Multi-OS** | ✅ Да (os-prober) | ⚠️ Ограниченно |
| **Простота** | Сложный конфиг | Простой конфиг |
| **Скорость** | Медленнее | Быстрее |

**Рекомендации:**
- **GRUB** — если нужна поддержка BIOS, encrypted /boot, dual-boot Windows
- **systemd-boot** — если UEFI, single OS, простота важнее гибкости

### Kernel параметры: Security vs Performance

**Security (рекомендуется для production):**
- `init_on_alloc=1 init_on_free=1` — защита от use-after-free, но +5% overhead
- `slab_nomerge` — защита от heap exploits, но +10% памяти
- `mitigations=auto,nosmt` — защита от Spectre/Meltdown, но -20% CPU performance (без Hyper-Threading)
- `lockdown=confidentiality` — запрет доступа к kernel memory, блокирует kexec/BPF

**Performance (для десктопа/gaming):**
- `nowatchdog nmi_watchdog=0` — ускорение загрузки ~1 секунда
- `mitigations=off` — отключить Spectre/Meltdown mitigations (+20% CPU, но небезопасно)
- Без `init_on_alloc/free` — меньше overhead

**Баланс (рекомендуется):**
```yaml
bootloader_kernel_params:
  - "nowatchdog"
  - "mitigations=auto"  # Без nosmt (оставить Hyper-Threading)
  - "quiet loglevel=3"
```

### Resume from swap/zram

Для hibernation (suspend-to-disk) нужен resume hook:

1. Найти UUID swap:
   ```bash
   swapon --show
   blkid | grep swap
   ```

2. Добавить в kernel params:
   ```
   resume=UUID=xxx-xxx-xxx
   ```

3. В initramfs (mkinitcpio):
   ```yaml
   bootloader_resume_enabled: true
   bootloader_mkinitcpio_hooks:
     - resume  # После filesystems, перед fsck
   ```

Для zram-based hibernation (требует `systemd-swap` с writeback):
```
resume=/dev/zram0
```

### Secure Boot

**Внимание:** Secure Boot требует подписания kernel и модулей. Процесс сложен, требует генерации ключей MOK (Machine Owner Key).

Упрощённый процесс:
1. Генерация ключей: `sbctl create-keys`
2. Регистрация ключей в UEFI: `sbctl enroll-keys`
3. Подписание kernel: `sbctl sign -s /boot/vmlinuz-linux`
4. Включение Secure Boot в BIOS

Роль может автоматизировать через `sbctl` (Arch) или `mokutil` (Debian/Fedora).

### Microcode updates

**Критично для безопасности и стабильности** — CPU microcode патчи от Intel/AMD.

Установка:
- **Arch:** `pacman -S intel-ucode` (или `amd-ucode`)
- **Debian:** `apt install intel-microcode` (или `amd64-microcode`)
- **Fedora:** `dnf install microcode_ctl`

GRUB автоматически загружает microcode, если `/boot/intel-ucode.img` или `/boot/amd-ucode.img` существует.

### Проверка применённых параметров

```bash
# Текущие kernel параметры
cat /proc/cmdline

# Проверка mitigations
cat /sys/devices/system/cpu/vulnerabilities/*

# Проверка microcode
dmesg | grep microcode
```

## Tags

- `bootloader`
- `grub`
- `systemd-boot`
- `kernel`
- `security`
- `hardening`

---

Назад к [[Roadmap]]
