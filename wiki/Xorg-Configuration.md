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

> **Важно:** При конфликтующих настройках файл, прочитанный последним, имеет приоритет.

### Секции конфигурационного файла

Файлы `xorg.conf` и `xorg.conf.d/*.conf` состоят из секций:

```
Section "SectionName"
    SectionEntry
    ...
EndSection
```

| Секция | Описание |
|--------|----------|
| `Files` | Пути к файлам (шрифты, модули, XKB) |
| `ServerFlags` | Глобальные опции сервера |
| `Module` | Загружаемые модули |
| `Extensions` | Включение/отключение X11-расширений |
| `InputDevice` | Устройства ввода |
| `InputClass` | Классы устройств ввода |
| `Device` | Описание видеокарт |
| `Monitor` | Описание мониторов |
| `Modes` | Описание видеорежимов |
| `Screen` | Связывание Device и Monitor |
| `ServerLayout` | Общая конфигурация сессии |
| `DRI` | Настройки Direct Rendering Infrastructure |

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

### Горячие клавиши в X11

| Комбинация | Действие |
|------------|----------|
| `Ctrl + Alt + Backspace` | Убить X-сервер (если включено) |

#### Включение Ctrl+Alt+Backspace

По умолчанию отключено. Для включения:

**Вариант 1: xorg.conf.d**

Создайте `/etc/X11/xorg.conf.d/00-keyboard.conf`:
```
Section "InputClass"
    Identifier "Keyboard Defaults"
    MatchIsKeyboard "yes"
    Option "XkbOptions" "terminate:ctrl_alt_bksp"
EndSection
```

**Вариант 2: setxkbmap (временно)**
```bash
setxkbmap -option terminate:ctrl_alt_bksp
```

**Вариант 3: localectl**
```bash
sudo localectl set-x11-keymap us "" "" terminate:ctrl_alt_bksp
```

## Если X-сервер завис

1. Попробуйте `Ctrl + Alt + F2` — переключиться в TTY
2. Если не работает — `Alt + SysRq + R` (отнять клавиатуру у X)
3. Затем снова `Ctrl + Alt + F2`
4. Убейте X: `sudo pkill Xorg`

## Аварийные комбинации (SysRq)

| Комбинация | Действие |
|------------|----------|
| `Alt + SysRq + R` | Отнять клавиатуру у X-сервера (raw mode) |
| `Alt + SysRq + E` | SIGTERM всем процессам (кроме init) |
| `Alt + SysRq + I` | SIGKILL всем процессам (кроме init) |
| `Alt + SysRq + S` | Sync — записать буферы на диск |
| `Alt + SysRq + U` | Перемонтировать файловые системы read-only |
| `Alt + SysRq + B` | Немедленная перезагрузка |
| `Alt + SysRq + K` | SAK — убить все процессы на текущем TTY |

### Безопасная перезагрузка зависшей системы

Последовательность **R E I S U B** (с паузой 1-2 сек между клавишами):

```
Alt + SysRq + R  — отнять клавиатуру
Alt + SysRq + E  — завершить процессы
Alt + SysRq + I  — убить процессы
Alt + SysRq + S  — синхронизировать диски
Alt + SysRq + U  — перемонтировать read-only
Alt + SysRq + B  — перезагрузить
```

Мнемоника: **R**eboot **E**ven **I**f **S**ystem **U**tterly **B**roken

### Включение SysRq

Проверить статус:
```bash
cat /proc/sys/kernel/sysrq
```

Включить все функции:
```bash
echo 1 | sudo tee /proc/sys/kernel/sysrq
```

Для постоянного включения добавьте в `/etc/sysctl.d/99-sysrq.conf`:
```
kernel.sysrq = 1
```

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

Пользовательский скрипт, выполняемый при запуске X через `startx` или `xinit`. Если файл отсутствует, `startx` использует `/etc/X11/xinit/xinitrc`.

Для создания своего:
```bash
cp /etc/X11/xinit/xinitrc ~/.xinitrc
```

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

### ~/.xserverrc

Скрипт для запуска X-сервера с пользовательскими параметрами. И `startx`, и `xinit` выполняют `~/.xserverrc`, если он существует.

Пример:
```bash
#!/bin/sh
exec /usr/bin/Xorg -nolisten tcp "$@" vt$XDG_VTNR
```

Системный файл по умолчанию: `/etc/X11/xinit/xserverrc`

### ~/.xprofile

Выполняется при входе через Display Manager (LightDM, GDM, SDDM). Используется для установки переменных окружения и запуска фоновых программ перед стартом оконного менеджера/DE.

### ~/.Xresources

Файл ресурсов X для настройки шрифтов, цветов терминала, DPI, параметров X-приложений.

Загружается: `xrdb -merge ~/.Xresources`

### ~/.Xmodmap

Файл для переназначения клавиш и модификаторов клавиатуры. Загружается командой `xmodmap ~/.Xmodmap`.

## Автоматическая конфигурация

Современные версии X.Org автоматически определяют оборудование. В большинстве случаев ручная настройка `xorg.conf` не требуется. Arch Linux предоставляет дефолтные файлы конфигурации в `/usr/share/X11/xorg.conf.d/`.

Для генерации базового `xorg.conf`:
```bash
# Xorg :0 -configure
```

Это создаст файл `xorg.conf.new` в `/root/`.

## Ссылки

### Официальная документация
- [xorg.conf(5) — X.Org Manual](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml)
- [Xorg(1) — X.Org Manual](https://www.x.org/releases/current/doc/man/man1/Xorg.1.xhtml)
- [Xserver(1) — X.Org Manual](https://www.x.org/releases/current/doc/man/man1/Xserver.1.xhtml)
- [cvt(1)](https://www.x.org/releases/current/doc/man/man1/cvt.1.xhtml)

### Arch Wiki
- [Xorg — ArchWiki](https://wiki.archlinux.org/title/Xorg)
- [xinit — ArchWiki](https://wiki.archlinux.org/title/Xinit)
- [Xorg/Keyboard configuration](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration)
- [Xresources — ArchWiki](https://wiki.archlinux.org/title/Xresources)
- [xprofile — ArchWiki](https://wiki.archlinux.org/title/Xprofile)
- [Console — ArchWiki](https://wiki.archlinux.org/title/Linux_console)
- [Linux Magic System Request Key](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html)

---

Назад к [[Home]]
