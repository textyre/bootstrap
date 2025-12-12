# Управление X-сервером

## Завершение X-сессии

### Переключение на TTY

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

## Если X-сервер завис (чёрный экран)

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

> Выполняйте с паузой 1-2 секунды между командами.

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

## Ссылки

- [Xorg — ArchWiki](https://wiki.archlinux.org/title/Xorg)
- [Xorg/Keyboard configuration — ArchWiki](https://wiki.archlinux.org/title/Xorg/Keyboard_configuration)
- [Xorg(1) Manual](https://www.x.org/releases/current/doc/man/man1/Xorg.1.xhtml)
