# Xorg Configuration

Полное руководство по конфигурации X.Org Server для мониторов и видеодрайверов.

## Файлы конфигурации X Server

### Основные файлы xorg.conf и xorg.conf.d

X.Org Server использует файл `xorg.conf` и файлы с суффиксом `.conf` из директории `xorg.conf.d` для начальной настройки.

#### Порядок поиска конфигурации

1. `/etc/X11/<cmdline>` — путь через `-config`
2. `/usr/etc/X11/<cmdline>`
3. `/etc/X11/$XORGCONFIG`
4. `/usr/etc/X11/$XORGCONFIG`
5. `/etc/X11/xorg.conf`
6. `/etc/xorg.conf`
7. `/usr/etc/X11/xorg.conf.<hostname>`
8. `/usr/etc/X11/xorg.conf`
9. `/usr/lib/X11/xorg.conf.<hostname>`
10. `/usr/lib/X11/xorg.conf`

#### Директории с фрагментами конфигурации

| Директория | Назначение |
|------------|------------|
| `/usr/share/X11/xorg.conf.d/` | Системные дефолтные настройки |
| `/etc/X11/xorg.conf.d/` | Пользовательские переопределения |

Файлы читаются в ASCII-порядке. Используйте префикс `XX-` (например: `10-monitor.conf`, `20-nvidia.conf`).

### Секции конфигурации

| Секция | Описание |
|--------|----------|
| `Files` | Пути к файлам (шрифты, модули, XKB) |
| `ServerFlags` | Глобальные опции сервера |
| `Module` | Загружаемые модули |
| `InputDevice` | Устройства ввода |
| `InputClass` | Классы устройств ввода |
| `Device` | Описание видеокарт |
| `Monitor` | Описание мониторов |
| `Screen` | Связывание Device и Monitor |
| `ServerLayout` | Общая конфигурация сессии |

## Секция Monitor

Определяет параметры монитора: разрешение, частоту обновления, Modeline.

| Поле | Описание | Пример |
|------|----------|--------|
| `Identifier` | Уникальное имя монитора | `"Monitor0"` |
| `Modeline` | Определение видеорежима | См. ниже |
| `Option "PreferredMode"` | Режим по умолчанию | `"2560x1440_60.00"` |
| `Option "Primary"` | Основной монитор | `"true"` |

### Modeline

Modeline определяет видеорежим: разрешение, частоту, тайминги синхронизации.

**Формат:**
```
Modeline "name" pclk hdisp hsstart hsend htotal vdisp vsstart vsend vtotal [flags]
```

**Генерация Modeline:**

```bash
# Стандартный режим (CVT)
cvt 2560 1440 60

# Reduced blanking (для VM)
cvt -r 2560 1440 60

# GTF (устаревший)
gtf 2560 1440 60
```

**Пример вывода:**
```
Modeline "2560x1440_60.00"  312.25  2560 2752 3024 3488  1440 1443 1448 1493 -hsync +vsync
```

## Секция Device

Определяет видеокарту и драйвер.

| Поле | Описание | Значения |
|------|----------|----------|
| `Identifier` | Уникальное имя устройства | `"Card0"` |
| `Driver` | Видеодрайвер Xorg | См. таблицу ниже |
| `BusID` | PCI адрес (для multi-GPU) | `"PCI:0:2:0"` |
| `Option "AccelMethod"` | Метод ускорения | `"glamor"`, `"sna"`, `"uxa"` |
| `Option "TearFree"` | Устранение разрывов | `"true"` / `"false"` |

### Драйверы

| Драйвер | Описание | Когда использовать |
|---------|----------|-------------------|
| `modesetting` | Универсальный DRM/KMS | Современные GPU, VM с KMS |
| `vmware` | VMware SVGA DDX | VMware с xf86-video-vmware |
| `vesa` | Fallback VESA | Когда другие не работают |
| `intel` | Intel integrated | Intel HD/UHD Graphics |
| `amdgpu` | AMD Radeon (GCN+) | AMD RX серии |
| `nouveau` | Open-source NVIDIA | NVIDIA без проприетарного драйвера |
| `nvidia` | Проприетарный NVIDIA | NVIDIA GeForce/Quadro |

## Секция Screen

Связывает Device и Monitor, определяет параметры экрана.

| Поле | Описание | Пример |
|------|----------|--------|
| `Identifier` | Уникальное имя экрана | `"Screen0"` |
| `Device` | Ссылка на Device | `"Card0"` |
| `Monitor` | Ссылка на Monitor | `"Monitor0"` |
| `DefaultDepth` | Глубина цвета | `24` |

### SubSection Display

| Поле | Описание | Пример |
|------|----------|--------|
| `Depth` | Глубина цвета (бит) | `24` |
| `Modes` | Список режимов | `"2560x1440_60.00" "1920x1080_60.00"` |
| `Virtual` | Виртуальный размер | `5120 1440` |

## Управление X-сервером

### Завершение X-сессии

| Комбинация | Действие |
|------------|----------|
| `Ctrl + Alt + F1` | Переключиться на TTY1 |
| `Ctrl + Alt + F2` | Переключиться на TTY2 |
| `Ctrl + Alt + F7` | Вернуться в X-сессию |

### Убить X-сервер из TTY

```bash
# Найти процесс
ps aux | grep Xorg

# Завершить
sudo pkill Xorg
# или
sudo killall Xorg

# Или по PID
sudo kill -9 <PID>
```

### Включение Ctrl+Alt+Backspace

По умолчанию отключено. Для включения создайте `/etc/X11/xorg.conf.d/00-keyboard.conf`:

```
Section "InputClass"
    Identifier "Keyboard Defaults"
    MatchIsKeyboard "yes"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
```

## Если X-сервер завис

1. Попробуйте `Ctrl + Alt + F2` — переключиться в TTY
2. Если не работает — `Alt + SysRq + R` (отнять клавиатуру у X)
3. Затем снова `Ctrl + Alt + F2`
4. Убейте X: `sudo pkill Xorg`

## Полностью зависшая система

Используйте комбинацию SysRq для безопасной перезагрузки:

```
Alt + SysRq + R  — отнять клавиатуру у X
Alt + SysRq + E  — SIGTERM всем процессам
Alt + SysRq + I  — SIGKILL всем процессам
Alt + SysRq + S  — синхронизировать диски
Alt + SysRq + U  — перемонтировать read-only
Alt + SysRq + B  — перезагрузить
```

Мнемоника: **R**eboot **E**ven **I**f **S**ystem **U**tterly **B**roken

Выполняйте с паузой 1-2 секунды между командами.

## Управление TTY

### Переключение между TTY

| Комбинация | Действие |
|------------|----------|
| `Ctrl + Alt + F1-F6` | TTY1-TTY6 |
| `Ctrl + Alt + F7` | X-сессия (если была) |

В TTY можно использовать просто `Alt + F2` (без Ctrl).

### Прокрутка в TTY

В современных ядрах Linux (5.9+) scrollback в TTY удалён. Альтернативы:

**tmux:**
```bash
sudo pacman -S tmux
tmux
# Ctrl+B, затем [ — режим прокрутки
# PageUp/PageDown для навигации
# q — выход
```

**Перенаправление вывода:**
```bash
dmesg | less
journalctl | less
command 2>&1 | tee output.log
```

## Просмотр логов X-сервера

```bash
# Текущий лог (rootless Xorg)
cat ~/.local/share/xorg/Xorg.0.log

# Или системный (root Xorg)
cat /var/log/Xorg.0.log

# Последние ошибки
grep "(EE)" ~/.local/share/xorg/Xorg.0.log

# Предупреждения
grep "(WW)" ~/.local/share/xorg/Xorg.0.log
```

## Запуск X-сервера вручную

```bash
# Базовый запуск (используя ~/.xinitrc)
startx

# Запуск конкретного WM
startx /usr/bin/i3

# Запуск на другом дисплее
startx -- :1

# С указанием конфига
startx -- -config /path/to/xorg.conf
```

## Файлы инициализации сессии

### ~/.xinitrc

Пользовательский скрипт, выполняемый при запуске X через `startx` или `xinit`.

Типичное использование:
```bash
#!/bin/sh

# Загрузка ресурсов X
[[ -f ~/.Xresources ]] && xrdb -merge ~/.Xresources

# Запуск фоновых программ
xscreensaver &

# Запуск оконного менеджера (должен быть последним с exec)
exec i3
```

### ~/.xprofile

Выполняется при входе через Display Manager (LightDM, GDM, SDDM). Используется для установки переменных окружения.

### ~/.Xresources

Файл ресурсов X для настройки шрифтов, цветов терминала, DPI, параметров X-приложений.

Загружается: `xrdb -merge ~/.Xresources`

## Ссылки

### Официальная документация
- [xorg.conf(5) — X.Org Manual](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml)
- [Xorg(1) — X.Org Manual](https://www.x.org/releases/current/doc/man/man1/Xorg.1.xhtml)
- [cvt(1)](https://www.x.org/releases/current/doc/man/man1/cvt.1.xhtml)

### Arch Wiki
- [Xorg — ArchWiki](https://wiki.archlinux.org/title/Xorg)
- [xinit — ArchWiki](https://wiki.archlinux.org/title/Xinit)
- [Xorg/Keyboard configuration](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration)
- [Linux Magic System Request Key](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html)

---

Назад к [[Home]]
