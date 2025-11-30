---
title: "Testing and debugging monitor modes"
type: guide
entities: [Xorg, xrandr, testing]
created: 2025-11-30
authors: [docs-team]
tags: [testing, xorg, xrandr, debug]
---

# Тестирование и отладка

Команды для быстрого тестирования режимов и проверки логов Xorg:

```
# Запустить тестовый X на дисплее :1 и смотреть лог
sudo Xorg :1 -logfile /tmp/Xorg.1.log -verbose 3 &
tail -f /tmp/Xorg.1.log

# Проверить текущий режим (если X запущен):
DISPLAY=:0 xrandr --verbose
```

Эти команды полезны для диагностики, если случается, что дисплей не применяет
ожидаемый режим или гречер/DM игнорирует конфиг `xorg.conf.d`.
