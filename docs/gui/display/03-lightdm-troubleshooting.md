# LightDM — Troubleshooting и полезные команды

Кратко: здесь собраны команды и шаги, которые мы обсуждали — как остановить/перезапустить LightDM, диагностировать падения, разобраться с `display-setup-script` и восстановить доступ к TTY.

## Быстрые команды управления сервисом
- Перезапуск LightDM:
```bash
sudo systemctl restart lightdm
```
- Остановить и запретить автозапуск (при loop-restarts):
```bash
sudo systemctl stop lightdm
sudo systemctl mask lightdm
```
- Снять маску и включить снова:
```bash
sudo systemctl unmask lightdm
sudo systemctl enable --now lightdm
```
- Остановить и убить Xorg принудительно:
```bash
sudo systemctl stop lightdm
sudo pkill -f Xorg || sudo kill <Xorg_PID>
```
- Альтернатива перейти в текстовый режим:
```bash
sudo systemctl isolate multi-user.target
# вернуть GUI
sudo systemctl isolate graphical.target
```

## Логи и диагностика
- Просмотр статуса и последних логов LightDM:
```bash
sudo systemctl status lightdm
sudo journalctl -b -u lightdm --no-pager -n 200
```

## Проверка и права на скрипты
- Убедитесь, что в скрипте используются полные пути и логируются ошибки:
```bash
#!/bin/bash
exec >> /var/log/lightdm/display-setup.log 2>&1
set -x
# остальной код
```
- Права/владелец:
  - Если скрипт выполняется `display-setup-script` как `root`: `root:root` + `chmod 755`.
  - Если скрипт должен быть доступен процессам, работающим от `lightdm`: `lightdm:lightdm` + `chmod 750`.

Команды:
```bash
sudo chown root:root /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
sudo chmod 755 /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
# или
sudo chown lightdm:lightdm /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
sudo chmod 750 /etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh
```

## Быстрые рецепты (copy-paste)
- Остановить автоперезапуск и посмотреть логи:
```bash
sudo systemctl stop lightdm
sudo systemctl mask lightdm
sudo journalctl -b -u lightdm --no-pager -n 200
```
- Убить X и временно вернуть multi-user:
```bash
sudo pkill -f Xorg || true
sudo systemctl isolate multi-user.target
```

---

Файл создан на основе диалога и отладочной сессии — при необходимости добавлю примеры `cvt`/`Modeline` для ваших параметров и включу логи из системы, если вы пришлёте вывод `journalctl` или `Xorg.0.log`.
