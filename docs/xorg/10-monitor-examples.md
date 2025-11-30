# Примеры: фрагменты `10-monitor.conf` и скрипты

Ниже — проверенные примеры фрагментов для `/etc/X11/xorg.conf.d/10-monitor.conf` и вспомогательные скрипты.

1) Пример для `modesetting` (универсальный, для современных DRM драйверов и VM с поддержкой KMS)

```
Section "Monitor"
    Identifier "Monitor0"
    Modeline "2560x1440_60.00"  312.25  2560 2752 3024 3488  1440 1443 1448 1493 -hsync +vsync
    Option "PreferredMode" "2560x1440_60.00"
EndSection

Section "Device"
    Identifier "Card0"
    Driver "modesetting"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Card0"
    Monitor "Monitor0"
    SubSection "Display"
        Depth 24
        Modes "2560x1440_60.00"
    EndSubSection
EndSection
```

2) Пример для VMware (если установлен `xf86-video-vmware` — более корректный DDX для VMware SVGA)

```
Section "Monitor"
    Identifier "Monitor0"
    Modeline "2560x1440_60.00"  312.25  2560 2752 3024 3488  1440 1443 1448 1493 -hsync +vsync
    Option "PreferredMode" "2560x1440_60.00"
EndSection

Section "Device"
    Identifier "Card0"
    Driver "vmware"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "Card0"
    Monitor "Monitor0"
    SubSection "Display"
        Depth 24
        Modes "2560x1440_60.00"
    EndSubSection
EndSection
```

3) Fallback: `vesa` (если ничего другого не работает — ограничено по режимам и производительности)

```
Section "Device"
    Identifier "Card0"
    Driver "vesa"
EndSection
```

4) LightDM hook — `display-setup-script` (выполняется при старте greeter, полезно если DM/greeter игнорирует conf)

Скрипт `/usr/local/bin/monitor-bootstrap.sh`:

```
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

# Добавить модельный режим (cvt вывод подставить сюда или сгенерировать заранее)
xrandr --newmode "2560x1440_60.00" 312.25 2560 2752 3024 3488 1440 1443 1448 1493 -hsync +vsync 2>/dev/null || true
xrandr --addmode "$MON" "2560x1440_60.00" 2>/dev/null || true
xrandr --output "$MON" --mode "2560x1440_60.00" --rate 60 2>/dev/null || true

exit 0
```

И в `/etc/lightdm/lightdm.conf` добавить или раскомментировать:

```
[Seat:*]
display-setup-script=/usr/local/bin/monitor-bootstrap.sh
```

5) Альтернатива — systemd unit, который запускается до display-manager.service (если нужно гарантированно выполнить до DM)

Файл `/etc/systemd/system/monitor-bootstrap.service`:

```
[Unit]
Description=Apply monitor mode before display manager
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/monitor-bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
```

Команды:

```
sudo chmod +x /usr/local/bin/monitor-bootstrap.sh
sudo systemctl daemon-reload
sudo systemctl enable --now monitor-bootstrap.service
sudo systemctl restart lightdm
```

6) Советы по генерации Modeline
- Обычный: `cvt 2560 1440 60`
- Reduced blanking (меньше pclk, полезно для VMs): `cvt -r 2560 1440 60`

7) Как вставить конфиг без редакторов (heredoc + tee)

```
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/10-monitor.conf > /dev/null <<'EOF'
# вставьте здесь содержимое примера
EOF
```

8) Тестирование вручную

```
# Запустить тестовый X на дисплее :1 и смотреть лог
sudo Xorg :1 -logfile /tmp/Xorg.1.log -verbose 3 &
tail -f /tmp/Xorg.1.log

# Проверить текущий режим (если X запущен):
DISPLAY=:0 xrandr --verbose
```

Если нужны правки/дополнения — обновлю примеры под вашу конкретную VM/железо.
