% Документация: Xorg — быстрая справка

Цель: собрать краткие, проверенные шаги по установке нужного разрешения (например 2560x1440@60) и автоматизации его применения на Arch Linux (включая виртуальные окружения — VirtualBox/VMware).

Ключевые идеи
- Xorg читает конфиги из `/etc/X11/xorg.conf.d/*.conf` при старте любым способом (startx/xinit/Display Manager). Если конфиг корректен — режим будет применён ещё до запуска пользовательской сессии.
- `startx` — это удобная оболочка (wrapper) для `xinit`. `xinit` — низкоуровневый вызов для запуска X и клиентов. Display manager (LightDM/gdm) — это служба, показывающая greeter и управляющая сессиями.
- `xrandr` нужен только как fallback/рантайм инструмент (динамическая подстройка, user-level изменения). Если вы полностью доверяете `/etc/X11/xorg.conf.d`, `xrandr` не обязателен.

Что делать кратко
1. Сгенерировать корректный Modeline (пример):

```
cvt 2560 1440 60
# пример вывода:
# 2560x1440 59.96 Hz (CVT 3.69M9) hsync: 89.52 kHz; pclk: 312.25 MHz
# Modeline "2560x1440_60.00"  312.25  2560 2752 3024 3488  1440 1443 1448 1493 -hsync +vsync
```

2. Вставить Modeline в фрагмент `/etc/X11/xorg.conf.d/10-monitor.conf` (пример ниже). После установки драйвера/файла перезапустить DM (`sudo systemctl restart lightdm`) или протестировать вручную.

3. Если X (особенно greeter DM) игнорирует конфиг — добавить небольшой скрипт, который выполняется при старте DM (LightDM — `display-setup-script`), и который применит модельный режим через `xrandr` (fallback).

Особенности VM (VirtualBox / VMware)
- В VirtualBox: установите Guest Additions (`virtualbox-guest-utils`) и в настройках VM выставьте `Graphics Controller = VMSVGA`, увеличить Video Memory и включите 3D, затем используйте `vboxvideo`/`modesetting`.
- В VMware: ядро использует `vmwgfx`. Установите `xf86-video-vmware` и `open-vm-tools`/`open-vm-tools-desktop`, затем можно использовать DDX `vmware` или `modesetting` с DRI `vmwgfx`.

Отладка
- Логи X: `~/.local/share/xorg/Xorg.*.log` или `/var/log/Xorg.*.log`. Для быстрого теста можно запустить: `sudo Xorg :1 -logfile /tmp/Xorg.1.log -verbose 3 &` и смотреть `tail -f /tmp/Xorg.1.log`.
- Если нет логов — проверить systemd: `sudo journalctl -u lightdm -b` и наличие бинаря Xorg: `which Xorg`.

Без редакторов — вставка файла из терминала
```
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/10-monitor.conf > /dev/null <<'EOF'
<вставьте содержимое конфигурации здесь>
EOF
```

Замечания по безопасности/практике
- Если файл регулярно перезаписывается или исчезает после перезагрузки — возможно система работает поверх tmpfs/overlay (live), или есть hooks/pacman/tmpfiles/snapper, возвращающие старую версию. Проверить `findmnt` и наличие snapshot/restore механизмов.
- Для временной блокировки от перезаписи: `sudo chattr +i /etc/X11/xorg.conf.d/10-monitor.conf` (снять флаг `-i` перед правкой).

Дальше — в `10-monitor-examples.md` есть готовые примеры для modesetting/vmware/vesa и LightDM hook.

Автор: собранные шаги по обсуждению (техподдержка). Файл служит краткой справкой и набором команд для быстрого решения.
