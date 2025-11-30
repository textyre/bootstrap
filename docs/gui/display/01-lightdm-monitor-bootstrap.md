---
title: "LightDM: display-setup-script (monitor-bootstrap)"
type: guide
entities: [LightDM, script, xrandr]
created: 2025-11-30
authors: [docs-team]
tags: [lightdm, display-setup-script, monitor, xrandr]
---

# LightDM `display-setup-script` — документация

Документация содержит пример скрипта `monitor-bootstrap.sh`, который запускается
как `display-setup-script` в LightDM greeter. Сам скрипт должен оставаться в
`scripts/` (не перемещаем скрипты в этом шаге), здесь — только документация и
пример кода для копирования/установки.

Файл `/usr/local/bin/monitor-bootstrap.sh` (пример):

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

Добавление в `/etc/lightdm/lightdm.conf`:

```
[Seat:*]
display-setup-script=/usr/local/bin/monitor-bootstrap.sh
```

Примечание: скрипт должен быть исполняемым (`chmod +x`) и находится в месте,
доступном для LightDM. В репозитории рекомендуем держать исполняемые скрипты в
`scripts/` и при установке копировать их в `/usr/local/bin`.
