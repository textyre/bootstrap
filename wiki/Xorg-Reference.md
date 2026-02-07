# Xorg Configuration Reference

Справочник по конфигурации Xorg для настройки мониторов и видеодрайверов.

**Пример конфига:** `10-monitor.conf`

**Расположение:** `/etc/X11/xorg.conf.d/10-monitor.conf`

---

## Секция Monitor

Определяет параметры монитора: разрешение, частоту обновления, Modeline.

**Официальная документация:**
- [xorg.conf(5) — Monitor Section](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml#heading6)
- [Arch Wiki — Xorg Monitor](https://wiki.archlinux.org/title/Xorg#Monitor_settings)

| Поле | Описание | Значения | Пример |
|------|----------|----------|--------|
| `Identifier` | Уникальное имя монитора для ссылок из других секций | Любая строка | `"Monitor0"` |
| `Modeline` | Определение видеорежима: имя, pixel clock, horizontal/vertical timings, флаги синхронизации | См. [Modeline](#modeline) | `"2560x1440_60.00" 312.25 2560 2752 3024 3488 1440 1443 1448 1493 -hsync +vsync` |
| `Option "PreferredMode"` | Режим по умолчанию при запуске X | Имя из Modeline | `"2560x1440_60.00"` |
| `Option "Primary"` | Установить как основной монитор | `"true"` / `"false"` | `"true"` |
| `VendorName` | Название производителя (информационное) | Любая строка | `"Generic"` |
| `ModelName` | Модель монитора (информационное) | Любая строка | `"LCD Monitor"` |

**Дополнительные опции:**
- [xorg.conf(5) — Monitor Options](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml#heading7)

---

## Секция Device

Определяет видеокарту и драйвер.

**Официальная документация:**
- [xorg.conf(5) — Device Section](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml#heading8)
- [Arch Wiki — Xorg Driver](https://wiki.archlinux.org/title/Xorg#Driver_installation)

| Поле | Описание | Значения | Пример |
|------|----------|----------|--------|
| `Identifier` | Уникальное имя устройства | Любая строка | `"Card0"` |
| `Driver` | Видеодрайвер Xorg | См. [Драйверы](#драйверы) | `"modesetting"` |
| `BusID` | PCI адрес устройства (для multi-GPU) | `"PCI:X:Y:Z"` | `"PCI:0:2:0"` |
| `Screen` | Номер экрана для multi-head карт | Целое число | `0` |
| `Option "AccelMethod"` | Метод аппаратного ускорения | `"glamor"`, `"sna"`, `"uxa"`, `"none"` | `"glamor"` |
| `Option "TearFree"` | Устранение разрывов изображения | `"true"` / `"false"` | `"true"` |

### Драйверы

| Драйвер | Описание | Когда использовать | Документация |
|---------|----------|-------------------|--------------|
| `modesetting` | Универсальный DRM/KMS драйвер | Современные GPU, виртуальные машины с KMS | [modesetting(4)](https://www.x.org/releases/current/doc/man/man4/modesetting.4.xhtml) |
| `vmware` | VMware SVGA DDX | VMware с xf86-video-vmware | [Arch Wiki — VMware](https://wiki.archlinux.org/title/VMware/Install_Arch_Linux_as_a_guest#Xorg_configuration) |
| `vesa` | Fallback VESA драйвер | Когда другие драйверы не работают | [vesa(4)](https://www.x.org/releases/current/doc/man/man4/vesa.4.xhtml) |
| `intel` | Intel integrated graphics | Intel HD/UHD Graphics (legacy) | [intel(4)](https://www.x.org/releases/current/doc/man/man4/intel.4.xhtml), [Arch Wiki](https://wiki.archlinux.org/title/Intel_graphics) |
| `amdgpu` | AMD Radeon (GCN+) | AMD RX серии | [amdgpu(4)](https://www.x.org/releases/current/doc/man/man4/amdgpu.4.xhtml), [Arch Wiki](https://wiki.archlinux.org/title/AMDGPU) |
| `nouveau` | Open-source NVIDIA | NVIDIA (без проприетарного драйвера) | [nouveau(4)](https://nouveau.freedesktop.org/), [Arch Wiki](https://wiki.archlinux.org/title/Nouveau) |
| `nvidia` | Проприетарный NVIDIA | NVIDIA GeForce/Quadro | [Arch Wiki](https://wiki.archlinux.org/title/NVIDIA) |

---

## Секция Screen

Связывает Device и Monitor, определяет параметры экрана.

**Официальная документация:**
- [xorg.conf(5) — Screen Section](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml#heading10)
- [Arch Wiki — Xorg Multiple Monitors](https://wiki.archlinux.org/title/Multihead)

| Поле | Описание | Значения | Пример |
|------|----------|----------|--------|
| `Identifier` | Уникальное имя экрана | Любая строка | `"Screen0"` |
| `Device` | Ссылка на секцию Device | Identifier из Device | `"Card0"` |
| `Monitor` | Ссылка на секцию Monitor | Identifier из Monitor | `"Monitor0"` |
| `DefaultDepth` | Глубина цвета по умолчанию | `8`, `15`, `16`, `24`, `30` | `24` |

### SubSection Display

Вложенная секция для конкретной глубины цвета.

| Поле | Описание | Значения | Пример |
|------|----------|----------|--------|
| `Depth` | Глубина цвета (бит) | `8`, `15`, `16`, `24`, `30` | `24` |
| `Modes` | Список режимов в порядке приоритета | Имена из Modeline | `"2560x1440_60.00" "1920x1080_60.00"` |
| `Virtual` | Виртуальный размер экрана | `width height` | `5120 1440` |
| `ViewPort` | Начальная позиция viewport | `x y` | `0 0` |

---

## Modeline

Modeline определяет видеорежим: разрешение, частоту, тайминги синхронизации.

**Официальная документация:**
- [xorg.conf(5) — Modeline](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml#heading7)
- [Arch Wiki — Xrandr Adding undetected resolutions](https://wiki.archlinux.org/title/Xrandr#Adding_undetected_resolutions)

### Формат

```
Modeline "name" pclk hdisp hsstart hsend htotal vdisp vsstart vsend vtotal [flags]
```

| Параметр | Описание |
|----------|----------|
| `name` | Имя режима (произвольное, но обычно `WxH_refresh`) |
| `pclk` | Pixel clock в MHz |
| `hdisp` | Horizontal display (активные пиксели по горизонтали) |
| `hsstart` | Horizontal sync start |
| `hsend` | Horizontal sync end |
| `htotal` | Horizontal total (включая blanking) |
| `vdisp` | Vertical display (активные строки) |
| `vsstart` | Vertical sync start |
| `vsend` | Vertical sync end |
| `vtotal` | Vertical total (включая blanking) |
| `flags` | `-hsync`/`+hsync`, `-vsync`/`+vsync`, `interlace`, `doublescan` |

### Генерация Modeline

**Официальная документация:**
- [cvt(1)](https://www.x.org/releases/current/doc/man/man1/cvt.1.xhtml)
- [gtf(1)](https://www.x.org/releases/current/doc/man/man1/gtf.1.xhtml)

```bash
# Стандартный режим (CVT)
cvt 2560 1440 60

# Reduced blanking (меньше pixel clock, рекомендуется для VM)
cvt -r 2560 1440 60

# GTF (устаревший стандарт)
gtf 2560 1440 60
```

**Пример вывода `cvt 2560 1440 60`:**
```
Modeline "2560x1440_60.00"  312.25  2560 2752 3024 3488  1440 1443 1448 1493 -hsync +vsync
```

**Reduced blanking (`cvt -r`)** — уменьшает pixel clock, полезно для виртуальных машин с ограничениями SVGA.

---

## Связанные материалы

### В этой wiki
- [[Xorg-Configuration]] — обзор конфигурации, управление X-сервером, TTY
- [[Display-Setup]] — настройка дисплея через LightDM

### Внешние ресурсы
- [xorg.conf(5) — полный man](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml)
- [Arch Wiki — Xorg](https://wiki.archlinux.org/title/Xorg)
- [Arch Wiki — Multihead](https://wiki.archlinux.org/title/Multihead)
- [Arch Wiki — Kernel Mode Setting](https://wiki.archlinux.org/title/Kernel_mode_setting)
- [Gentoo Wiki — Xorg/Guide](https://wiki.gentoo.org/wiki/Xorg/Guide)

---

Назад к [[Home]]
