# TTY — Troubleshooting и полезные команды

Кратко: отдельный справочник по проблемам с виртуальными терминалами (TTY), getty и действиям, если при переключении вы видите только мигающий курсор.

## Getty / TTY1 — быстрые шаги
- Посмотреть статус `getty@tty1`:
```bash
systemctl status getty@tty1
sudo journalctl -u getty@tty1 --no-pager -n 200
```
- Запустить `getty` на `tty1`, если он inactive:
```bash
sudo systemctl start getty@tty1
sudo systemctl enable --now getty@tty1
sudo chvt 1   # переключиться на vt1
```
- Узнать, кто занимает `/dev/tty1`:
```bash
sudo fuser -v /dev/tty1
ps aux | grep -E 'tty1|agetty|Xorg' | grep -v grep
```

## Если `getty@tty1` умирает/не стартует
- Посмотреть логи службы и причины выхода:
```bash
sudo journalctl -u getty@tty1 --no-pager -n 200
```
- Проверить активные сессии и кто использовал tty1:
```bash
loginctl list-sessions
loginctl show-session <ID> -p TTY
```
- Если другой процесс (например Xorg) удерживает VT1 — убить его или остановить DM:
```bash
sudo fuser -v /dev/tty1
sudo pkill -f Xorg || sudo kill <PID>
```

## Потеря локальной консоли (нет SSH)
- Используйте Magic SysRq (если включён):
  - `Alt+SysRq+R` — вернуть клавиатуру в управление консоли (снять у X)
  - `Alt+SysRq+K` — убить все процессы на текущем VT (ОСТОРОЖНО)
  - Безопасная перезагрузка: `Alt+SysRq+S`, `Alt+SysRq+U`, `Alt+SysRq+B`
- В крайнем случае — удержание кнопки питания для жесткого выключения.

## Быстрые команды (copy-paste)
- Запустить getty и перейти на tty1:
```bash
sudo systemctl start getty@tty1
sudo chvt 1
```
- Узнать, кто использует tty1:
```bash
sudo fuser -v /dev/tty1
```

Файл создан как выделенный краткий справочник по TTY. Если нужно — добавлю примеры вывода команд и рекомендации по системному журналированию.