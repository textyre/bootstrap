# Файлы конфигурации X Server

Этот документ описывает файлы конфигурации, которые использует X.Org Server при запуске.

## Основные конфигурационные файлы

### Файлы xorg.conf и xorg.conf.d

X.Org Server использует файл `xorg.conf` и файлы с суффиксом `.conf` из директории `xorg.conf.d` для начальной настройки.

#### Порядок поиска конфигурации (для обычного пользователя)

Согласно [официальной документации xorg.conf(5)](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml#heading3):

1. `/etc/X11/<cmdline>` — путь, указанный через `-config`
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

Дополнительные файлы конфигурации загружаются из следующих директорий:

| Директория | Назначение |
|------------|------------|
| `/usr/share/X11/xorg.conf.d/` | Системные дефолтные настройки (от вендора или пакетов) |
| `/etc/X11/xorg.conf.d/` | Пользовательские/локальные переопределения |

Файлы в этих директориях читаются в **ASCII-порядке** (алфавитном). По соглашению имена файлов начинаются с `XX-` (две цифры и дефис), например:
- `10-monitor.conf`
- `20-nvidia.conf`
- `30-touchpad.conf`

> **Важно:** При конфликтующих настройках файл, прочитанный последним, имеет приоритет. Поэтому общие настройки должны иметь меньший номер в имени файла.

### Секции конфигурационного файла

Файлы `xorg.conf` и `xorg.conf.d/*.conf` состоят из секций:

```
Section "SectionName"
    SectionEntry
    ...
EndSection
```

Основные секции:

| Секция | Описание |
|--------|----------|
| `Files` | Пути к файлам (шрифты, модули, XKB) |
| `ServerFlags` | Глобальные опции сервера |
| `Module` | Загружаемые модули |
| `Extensions` | Включение/отключение X11-расширений |
| `InputDevice` | Описание устройств ввода |
| `InputClass` | Классы устройств ввода (для автоматического применения настроек) |
| `Device` | Описание видеокарт |
| `Monitor` | Описание мониторов |
| `Modes` | Описание видеорежимов |
| `Screen` | Связывание Device и Monitor |
| `ServerLayout` | Общая конфигурация сессии (связывание Screen и InputDevice) |
| `DRI` | Настройки Direct Rendering Infrastructure |

## Файлы инициализации сессии

### ~/.xinitrc

Пользовательский скрипт, выполняемый при запуске X через `startx` или `xinit`. Если файл присутствует в домашней директории пользователя, `startx` и `xinit` выполняют его. В противном случае `startx` использует `/etc/X11/xinit/xinitrc`.

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

Для создания своего `~/.xinitrc`:
```bash
cp /etc/X11/xinit/xinitrc ~/.xinitrc
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

Выполняется при входе через Display Manager (LightDM, GDM, SDDM и др.). Используется для установки переменных окружения и запуска фоновых программ перед стартом оконного менеджера/DE.

### ~/.Xresources

Файл ресурсов X для настройки:
- Шрифтов
- Цветов терминала
- Настроек DPI
- Параметров отдельных X-приложений

Загружается командой `xrdb -merge ~/.Xresources`.

### ~/.Xmodmap

Файл для переназначения клавиш и модификаторов клавиатуры. Загружается командой `xmodmap ~/.Xmodmap`.

## Логи X Server

При запуске от обычного пользователя (rootless Xorg, по умолчанию с версии 1.16):
```
~/.local/share/xorg/Xorg.N.log
```

При запуске от root:
```
/var/log/Xorg.N.log
```

где `N` — номер дисплея (обычно 0).

## Автоматическая конфигурация

Современные версии X.Org автоматически определяют оборудование. В большинстве случаев ручная настройка `xorg.conf` не требуется. Arch Linux предоставляет дефолтные файлы конфигурации в `/usr/share/X11/xorg.conf.d/`.

Для генерации базового `xorg.conf`:
```bash
# Xorg :0 -configure
```

Это создаст файл `xorg.conf.new` в `/root/`.

## Ссылки

### Официальная документация
- [xorg.conf(5) — X.Org Manual](https://www.x.org/releases/current/doc/man/man5/xorg.conf.5.xhtml) — официальная man-страница с полным описанием всех секций и опций
- [Xorg(1) — X.Org Manual](https://www.x.org/releases/current/doc/man/man1/Xorg.1.xhtml) — документация по опциям командной строки X-сервера
- [Xserver(1) — X.Org Manual](https://www.x.org/releases/current/doc/man/man1/Xserver.1.xhtml) — общая документация X-сервера

### Arch Wiki
- [Xorg — ArchWiki](https://wiki.archlinux.org/title/Xorg) — установка, настройка и устранение проблем
- [xinit — ArchWiki](https://wiki.archlinux.org/title/Xinit) — конфигурация xinitrc и xserverrc
- [Xorg/Keyboard configuration — ArchWiki](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration) — настройка клавиатуры
- [Xresources — ArchWiki](https://wiki.archlinux.org/title/Xresources) — настройка ресурсов X
- [xprofile — ArchWiki](https://wiki.archlinux.org/title/Xprofile) — настройка профиля X-сессии
