# Роль: memory

**Phase**: 3 | **Направление**: Package Infrastructure

## Цель

Унифицированное управление памятью: zram (compressed swap в RAM), swap file (на диске) или hybrid режим (оба). Заменяет отдельные роли `swap` и `zram`. Оптимизация использования RAM, поддержка hibernation, настройка swappiness.

## Ключевые переменные (defaults)

```yaml
memory_enabled: true  # Включить управление памятью

# === Режим работы ===
memory_mode: "zram"  # zram / swap / hybrid / none

# === ZRAM настройки ===
memory_zram_enabled: true                     # Включить zram (для mode=zram или hybrid)
memory_zram_size: "{{ (ansible_memtotal_mb * 0.5) | int }}"  # Размер zram (50% от RAM)
memory_zram_algorithm: "zstd"                 # Алгоритм сжатия: lz4 / zstd / lzo / lzo-rle
memory_zram_priority: 100                     # Приоритет swap (100 = выше чем swap file)
memory_zram_streams: "{{ ansible_processor_vcpus }}"  # Количество compression streams (по числу CPU)
memory_zram_writeback_device: ""              # Устройство для writeback (для hibernation на zram)

# === Swap File настройки ===
memory_swap_enabled: true                     # Включить swap file (для mode=swap или hybrid)
memory_swap_file_path: "/swapfile"            # Путь к swap file
memory_swap_file_size: "{{ ansible_memtotal_mb }}"  # Размер swap file (равен RAM для hibernation)
memory_swap_priority: 50                      # Приоритет swap (ниже чем zram)

# === Swappiness (агрессивность swap) ===
memory_swappiness: 10                         # 0-100 (0=минимум swap, 100=агрессивно)
# Рекомендации:
# - Desktop: 10 (минимизировать swap, держать всё в RAM)
# - Server: 60 (баланс между RAM и swap)
# - Zram-only: 100 (агрессивно использовать zram, т.к. он быстрый)

# === Cache Pressure ===
memory_vfs_cache_pressure: 50                 # Агрессивность очистки кеша (dentry/inode)
# 100 = дефолт, <100 = держать кеш дольше, >100 = агрессивная очистка

# === Transparent Huge Pages (THP) ===
memory_thp_enabled: "madvise"                 # always / madvise / never
# always = THP для всех приложений (может вызвать latency spikes)
# madvise = THP только для приложений, которые явно запрашивают (рекомендуется)
# never = THP отключён (для низкоуровневых приложений)

# === Hibernation support ===
memory_hibernation_enabled: false             # Включить поддержку hibernation
# Требует: swap size >= RAM + немного extra
# Для zram: требует writeback device
```

## Что настраивает

### На всех дистрибутивах

**ZRAM режим:**
- Создание zram устройства (`/dev/zram0`)
- Форматирование как swap (`mkswap /dev/zram0`)
- Включение swap (`swapon /dev/zram0 --priority 100`)
- Systemd service для автостарта при загрузке

**Swap File режим:**
- Создание swap file (`fallocate -l <size> /swapfile` или `dd`)
- Установка прав (`chmod 600 /swapfile`)
- Форматирование (`mkswap /swapfile`)
- Включение swap (`swapon /swapfile --priority 50`)
- Запись в `/etc/fstab` для автостарта

**Hybrid режим:**
- Оба варианта одновременно
- ZRAM с высоким priority (100) — используется первым
- Swap file с низким priority (50) — fallback для больших объёмов

**Sysctl настройки:**
- `vm.swappiness` → `/etc/sysctl.d/99-memory.conf`
- `vm.vfs_cache_pressure` → `/etc/sysctl.d/99-memory.conf`
- `vm.page-cluster` → 0 для zram (отключить readahead)

**THP:**
- Настройка через `/sys/kernel/mm/transparent_hugepage/enabled`
- Systemd service для применения при загрузке

### На Arch Linux

- Пакет: `zram-generator` (для zram, если используется systemd-zram)
- Альтернатива: ручное создание через модуль `zram`
- Путь: `/etc/systemd/zram-generator.conf` (если используется zram-generator)

### На Debian/Ubuntu

- Пакет: `zram-tools` (для zram)
- Конфигурация: `/etc/default/zramswap`
- Swap file через systemd или fstab

### На Fedora/RHEL

- Пакет: `zram-generator-defaults` (zram enabled по умолчанию в Fedora 33+)
- Конфигурация: `/usr/lib/systemd/zram-generator.conf`
- Swap file через systemd или fstab

## Зависимости

- `base_system` — sysctl, systemd
- `bootloader` (опционально) — для resume hook (hibernation)

## Примечания

### Режимы работы

#### 1. ZRAM (рекомендуется для desktop)

**Преимущества:**
- Быстрее чем swap file (RAM vs disk)
- Сжатие увеличивает эффективную RAM (1.5-3x компрессия)
- Нет износа SSD

**Недостатки:**
- Использует CPU для сжатия
- Hibernation требует дополнительной настройки (writeback)
- Ограничен размером RAM

**Пример:**
```yaml
memory_mode: "zram"
memory_zram_size: 4096  # 4 GB zram на машине с 8 GB RAM
memory_zram_algorithm: "zstd"  # Лучшая компрессия, но чуть медленнее lz4
memory_swappiness: 100  # Агрессивно использовать zram
```

#### 2. Swap File (для серверов с hibernation)

**Преимущества:**
- Поддержка hibernation (suspend-to-disk)
- Не использует CPU
- Может быть больше RAM

**Недостатки:**
- Медленнее чем zram
- Износ SSD (если на SSD)
- Занимает место на диске

**Пример:**
```yaml
memory_mode: "swap"
memory_swap_file_size: 16384  # 16 GB для hibernation (машина с 16 GB RAM)
memory_swappiness: 60
```

#### 3. Hybrid (баланс)

**Преимущества:**
- Быстрый zram для частых swap операций
- Swap file как fallback для больших объёмов
- Поддержка hibernation

**Недостатки:**
- Сложнее в настройке
- Больше overhead

**Пример:**
```yaml
memory_mode: "hybrid"
memory_zram_size: 4096       # 4 GB zram (быстрый, для активных данных)
memory_zram_priority: 100    # Высокий priority
memory_swap_file_size: 8192  # 8 GB swap file (медленный, для редких данных)
memory_swap_priority: 50     # Низкий priority
memory_swappiness: 60
```

### Алгоритмы сжатия ZRAM

| Алгоритм | Скорость сжатия | Степень сжатия | CPU overhead |
|----------|-----------------|----------------|--------------|
| **lz4** | Очень быстрый | Средняя (2-2.5x) | Низкий |
| **zstd** | Быстрый | Высокая (2.5-3x) | Средний |
| **lzo** | Быстрый | Низкая (2x) | Низкий |
| **lzo-rle** | Очень быстрый | Низкая | Очень низкий |

**Рекомендации:**
- **Desktop:** `zstd` — баланс между скоростью и компрессией
- **Gaming/Low-latency:** `lz4` — минимальный overhead
- **Server:** `zstd` — максимальная эффективность RAM

### Swappiness: оптимальные значения

- **0-10** (Desktop, много RAM): Минимальный swap, всё в RAM. Swap только при критическом недостатке памяти.
- **30-60** (Server, баланс): Баланс между RAM и swap. Swap для неактивных данных.
- **100** (Zram-only): Агрессивный swap. Безопасно для zram, т.к. он в RAM.

### Transparent Huge Pages (THP)

THP объединяет 4KB страницы в 2MB huge pages для уменьшения TLB misses.

**Режимы:**
- `always` — THP для всех процессов. Может вызвать latency spikes (compaction overhead).
- `madvise` — THP только для процессов, которые явно запрашивают через `madvise(MADV_HUGEPAGE)`. Рекомендуется.
- `never` — THP отключён. Для real-time приложений (latency-critical).

**Проверка:**
```bash
cat /sys/kernel/mm/transparent_hugepage/enabled
```

### Hibernation с ZRAM

ZRAM не поддерживает hibernation из коробки (нет постоянного хранилища). Решения:

1. **Hybrid режим**: zram для swap, swap file для hibernation
2. **ZRAM writeback**: zram с backing device (экспериментально)
3. **Swap file only**: отключить zram, использовать только swap file

Для resume нужно добавить в kernel params:
```
resume=UUID=<swap-uuid>
```

### Проверка состояния

```bash
# Статус swap
swapon --show

# Использование swap
free -h

# ZRAM статистика
cat /sys/block/zram0/mm_stat

# Swappiness
cat /proc/sys/vm/swappiness

# THP статус
cat /sys/kernel/mm/transparent_hugepage/enabled
```

### Создание swap file на btrfs

Btrfs требует специальной обработки:
```bash
truncate -s 0 /swapfile
chattr +C /swapfile  # Отключить COW
fallocate -l 8G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
```

Роль автоматически определяет btrfs и применяет `chattr +C`.

## Tags

- `memory`
- `swap`
- `zram`
- `performance`
- `system`

---

Назад к [[Roadmap]]
