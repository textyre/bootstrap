# LightDM и Display Configuration

Полное руководство по настройке LightDM display manager и конфигурации дисплея.

## LightDM: display-setup-script

### Обзор

LightDM поддерживает `display-setup-script` — скрипт, который запускается перед отображением greeter для настройки монитора.

### Пример скрипта

**Файл:** `/usr/local/bin/monitor-bootstrap.sh`

```bash
#!/bin/bash
export DISPLAY=:0

# Попытаться установить XAUTHORITY, если LightDM создал root Xauthority
if [ -z "$XAUTHORITY" ]; then
  if [ -e /var/run/lightdm/root/:0 ]; then
    export XAUTHORITY=/var/run/lightdm/root/:0
  fi
fi

MON=$(xrandr | awk '/ connected/ {print $1; exit}')
[ -n "$MON" ] || exit 0

# Добавить модельный режим
xrandr --newmode "2560x1440_60.00" 312.25 2560 2752 3024 3488 1440 1443 1448 1493 -hsync +vsync 2>/dev/null || true
xrandr --addmode "$MON" "2560x1440_60.00" 2>/dev/null || true
xrandr --output "$MON" --mode "2560x1440_60.00" --rate 60 2>/dev/null || true

exit 0
```

### Настройка в LightDM

Добавить в `/etc/lightdm/lightdm.conf`:

```ini
[Seat:*]
display-setup-script=/usr/local/bin/monitor-bootstrap.sh
```

**Важно:**
- Скрипт должен быть исполняемым: `chmod +x`
- Должен быть доступен для LightDM
- Обычно запускается от root

## Тестирование и отладка

### Тестовый запуск X

```bash
# Запустить тестовый X на дисплее :1 и смотреть лог
sudo Xorg :1 -logfile /tmp/Xorg.1.log -verbose 3 &
tail -f /tmp/Xorg.1.log

# Проверить текущий режим (если X запущен)
DISPLAY=:0 xrandr --verbose
```

### Проверка режимов

```bash
# Показать доступные режимы
xrandr

# Показать подробную информацию
xrandr --verbose

# Добавить режим вручную
cvt 2560 1440 60  # Сгенерировать Modeline
xrandr --newmode "2560x1440_60.00" <параметры из cvt>
xrandr --addmode <MONITOR> "2560x1440_60.00"
xrandr --output <MONITOR> --mode "2560x1440_60.00"
```

## LightDM Troubleshooting

### Быстрые команды управления

```bash
# Перезапуск LightDM
sudo systemctl restart lightdm

# Остановить и запретить автозапуск (при loop-restarts)
sudo systemctl stop lightdm
sudo systemctl mask lightdm

# Снять маску и включить снова
sudo systemctl unmask lightdm
sudo systemctl enable --now lightdm

# Остановить и убить Xorg принудительно
sudo systemctl stop lightdm
sudo pkill -f Xorg || sudo kill <Xorg_PID>

# Переключиться в текстовый режим
sudo systemctl isolate multi-user.target

# Вернуть GUI
sudo systemctl isolate graphical.target
```

### Логи и диагностика

```bash
# Просмотр статуса и последних логов LightDM
sudo systemctl status lightdm
sudo journalctl -b -u lightdm --no-pager -n 200

# Лог X-сервера
cat /var/log/Xorg.0.log
# или
cat ~/.local/share/xorg/Xorg.0.log

# Поиск ошибок
grep "(EE)" /var/log/Xorg.0.log
```

### Проверка прав на скрипты

```bash
# Если скрипт выполняется display-setup-script как root
sudo chown root:root /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
sudo chmod 755 /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh

# Если скрипт должен быть доступен процессам от lightdm
sudo chown lightdm:lightdm /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
sudo chmod 750 /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
```

### Отладка скрипта

Добавить логирование в скрипт:

```bash
#!/bin/bash
exec >> /var/log/lightdm/display-setup.log 2>&1
set -x

# остальной код
```

### Быстрые рецепты

**Остановить автоперезапуск и посмотреть логи:**
```bash
sudo systemctl stop lightdm
sudo systemctl mask lightdm
sudo journalctl -b -u lightdm --no-pager -n 200
```

**Убить X и временно вернуть multi-user:**
```bash
sudo pkill -f Xorg || true
sudo systemctl isolate multi-user.target
```

## TTY Troubleshooting

### Getty / TTY1 — быстрые шаги

```bash
# Посмотреть статус getty@tty1
systemctl status getty@tty1
sudo journalctl -u getty@tty1 --no-pager -n 200

# Запустить getty на tty1, если он inactive
sudo systemctl start getty@tty1
sudo systemctl enable --now getty@tty1
sudo chvt 1   # переключиться на vt1

# Узнать, кто занимает /dev/tty1
sudo fuser -v /dev/tty1
ps aux | grep -E 'tty1|agetty|Xorg' | grep -v grep
```

### Если getty@tty1 умирает/не стартует

```bash
# Посмотреть логи службы
sudo journalctl -u getty@tty1 --no-pager -n 200

# Проверить активные сессии
loginctl list-sessions
loginctl show-session <ID> -p TTY

# Если Xorg удерживает VT1 — убить его
sudo fuser -v /dev/tty1
sudo pkill -f Xorg || sudo kill <PID>
```

### Потеря локальной консоли (нет SSH)

Используйте Magic SysRq:

- `Alt+SysRq+R` — вернуть клавиатуру в управление консоли
- `Alt+SysRq+K` — убить все процессы на текущем VT (ОСТОРОЖНО)
- Безопасная перезагрузка: `Alt+SysRq+S`, `Alt+SysRq+U`, `Alt+SysRq+B`

## Автоматическая настройка через systemd

Можно создать systemd unit для настройки монитора:

### Файл: `/etc/systemd/system/monitor-bootstrap.service`

```ini
[Unit]
Description=Monitor Bootstrap (Custom Resolution)
After=display-manager.service
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor-bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
```

### Активация

```bash
sudo systemctl daemon-reload
sudo systemctl enable monitor-bootstrap.service
sudo systemctl start monitor-bootstrap.service
```

## Полезные команды

```bash
# Перезапустить LightDM
sudo systemctl restart lightdm

# Остановить LightDM
sudo systemctl stop lightdm

# Статус LightDM
sudo systemctl status lightdm

# Переключиться на TTY
Ctrl + Alt + F2

# Вернуться в X
Ctrl + Alt + F7

# Проверить текущий дисплей
echo $DISPLAY

# Список подключенных мониторов
xrandr | grep " connected"

# Применить режим
xrandr --output <MONITOR> --mode <MODE>
```

## Типичные проблемы

### LightDM не запускается

1. Проверить логи: `journalctl -u lightdm`
2. Проверить X лог: `/var/log/Xorg.0.log`
3. Проверить rights на display-setup-script
4. Попробовать запустить X вручную: `startx`

### Черный экран после login

1. Проверить `~/.xinitrc` или `~/.xsession`
2. Проверить логи X: `~/.local/share/xorg/Xorg.0.log`
3. Проверить i3 лог: `~/.local/share/i3/i3log`

### Неправильное разрешение

1. Проверить доступные режимы: `xrandr`
2. Добавить нужный режим через `cvt` + `xrandr --newmode`
3. Проверить `/etc/X11/xorg.conf.d/10-monitor.conf`
4. Проверить display-setup-script

---

Назад к [[Home]]
