# Инструкция: настройка доступа по SSH (Windows -> Arch VM)

Кратко: скрипт setup_ssh_key.ps1 создаёт ключ, копирует публичный ключ на гостя и добавляет алиас в SSH config.

1) Требования
  ```
  Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
  ```

2) Настройка конфигурации
Откройте файл конфигурации (расположение относительно скрипта):
d:\projects\arch\windows\config\config.ps1

Пример минимальных переменных:
```powershell
# filepath: d:\projects\arch\windows\config\config.ps1
$Global:SSH_KEY    = "$env:USERPROFILE\.ssh\id_ed25519"
$Global:SSH_PUB_KEY= "$env:USERPROFILE\.ssh\id_ed25519.pub"
$Global:SERVER_USER= "youruser"
$Global:SERVER_HOST= "127.0.0.1"
$Global:SERVER_PORT= 2222
$Global:SSH_CONFIG = "$env:USERPROFILE\.ssh\config"
```
**3) Настройка VirtualBox (обязательно при NAT)**
Если виртуальная машина использует NAT, нужно пробросить порт хоста на порт 22 гостьевой системы.

Через GUI: `Settings` → `Network` → `Adapter 1 (NAT)` → `Advanced` → `Port Forwarding` → добавить правило, например:
- Name: `guestssh`
- Protocol: `TCP`
- Host IP: `127.0.0.1` (или пусто)
- Host Port: `2222`
- Guest IP: (оставить пустым)
- Guest Port: `22`

Через CLI (PowerShell):
```powershell
# заменить "VM-name" на точное имя вашей VM
VBoxManage modifyvm "VM-name" --natpf1 "guestssh,tcp,,2222,,22"
VBoxManage showvminfo "VM-name" --details
```

Если вы предпочитаете bridged networking, проброс портов не нужен — используйте IP гостя.

**4) Установка и запуск SSH на госте (Arch Linux)**
Подключитесь к гостю через VirtualBox консоль или временно используйте пароль, затем выполните:
```bash
sudo pacman -Syu openssh
sudo systemctl enable --now sshd
sudo systemctl status sshd
ss -tlnp | grep ssh
```

Проверьте, что `sshd` слушает порт 22 на интерфейсе (обычно `0.0.0.0:22` или `:::22`).

Проверьте правила фаервола внутри гостя (nftables/iptables/ufw):
```bash
sudo nft list ruleset    # или sudo iptables -L -n
```

Если `PasswordAuthentication` в `/etc/ssh/sshd_config` отключён (пример: `PasswordAuthentication no`), убедитесь, что публичный ключ добавлен и права на каталоги/файлы правильные (см. раздел 7).

**5) Генерация ключа и запуск скрипта (на хосте Windows)**
Перейдите в папку со скриптом и запустите его:
```powershell
cd d:\projects\arch\windows\ssh
pwsh -NoProfile -ExecutionPolicy Bypass .\\setup_ssh_key.ps1
```

Скрипт выполняет 3 шага: генерация ключа, копирование публичного ключа на сервер (потребуется пароль при первом подключении), и обновление локального SSH `config` с алиасом.

Алиас формируется как `arch-<SERVER_HOST>-<SERVER_PORT>`; после успешной настройки вы сможете подключаться командой `ssh arch-127.0.0.1-2222` или `ssh -p 2222 youruser@127.0.0.1`.

**6) Ручная копия ключа (если авто-копирование не сработало)**
Можно вручную добавить публичный ключ на госте:
```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p 2222 youruser@127.0.0.1 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

Или на госте:
```bash
mkdir -p ~/.ssh
cat /tmp/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

**7) Проверки и отладка**
- Убедитесь, что VM запущена и проброс порта применён (`VBoxManage showvminfo` показывает `natpf1`).
- На госте: `sudo systemctl status sshd` и `ss -tlnp | grep ssh`.
- Проверьте содержимое и права:
  ```bash
  ls -la ~/.ssh
  cat ~/.ssh/authorized_keys
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
  ```
- Попробуйте подключиться с отладкой:
  ```powershell
  ssh -vvv -i C:\Users\<You>\.ssh\id_ed25519 -p 2222 youruser@127.0.0.1
  ```

**8) Полезные команды**
- Показать правила NAT/порт-форвард: `VBoxManage showvminfo "VM-name" --details`.
- Перезапустить sshd на госте: `sudo systemctl restart sshd`.
- Показать файл конфига SSH на хосте: `%USERPROFILE%\.ssh\config`.

**9) Что отправить для помощи**
Если что-то не работает, пришлите эти выводы:
- Результат `VBoxManage showvminfo "VM-name" --details` (проверка проброса портов)
- `sudo systemctl status sshd` на госте
- Вывод `ssh -vvv -p 2222 youruser@127.0.0.1` с хоста

---
Конец инструкции.

3) Запуск скрипта
Откройте PowerShell, перейдите в каталог с скриптом и запустите:
```powershell
cd d:\projects\arch\windows\ssh
pwsh -NoProfile -ExecutionPolicy Bypass .\setup_ssh_key.ps1
```
(Можно запустить просто `.\setup_ssh_key.ps1`, если используете уже открытую PowerShell с разрешёнными скриптами.)

4) Что делает скрипт
- Генерирует ключ (New-SSHKey).
- Копирует публичный ключ на сервер (Copy-SSHKey).
- Проверяет подключение (Test-SSHConnection).
- Добавляет запись в локальный SSH config (Update-SSHConfig).
Алиас формируется как `arch-<SERVER_HOST>-<SERVER_PORT>`.

5) Если подключение не работает
- Проверьте NAT / port-forwarding VirtualBox (host порт -> guest 22).
- На госте: убедитесь, что sshd запущен:
  ```
  sudo systemctl enable --now sshd
  sudo systemctl status sshd
  ```
- Проверьте права и содержимое ~/.ssh/authorized_keys на госте:
  ```
  ls -la ~/.ssh
  cat ~/.ssh/authorized_keys
  chmod 700 ~/.ssh
  chmod 600 ~/.ssh/authorized_keys
  ```
- Тест вручную с повышенной логгировкой:
  ```
  ssh -vvv -i C:\Users\<You>\.ssh\id_ed25519 -p 2222 youruser@127.0.0.1
  ```
- Если ключ не копируется автоматом, используйте вручную:
  ```powershell
  type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p 2222 youruser@127.0.0.1 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
  ```

6) Полезные команды
- Показать настроенные хосты из config:
  - Скрипт вызывает Show-SSHHosts; вручную — просмотреть файл: `%USERPROFILE%\.ssh\config`
- Повторно запустить только шаг копирования ключа — можно использовать модуль ssh-copy-id или выполнить команду вручную (см. выше).

7) Контакты для отладки
Пришлите выводы (скрипт и команды):
- Результат `VBoxManage showvminfo "VM-name" --details` (host forwarding)
- `sudo systemctl status sshd` (госте)
- Вывод `ssh -vvv -p 2222 youruser@127.0.0.1` (хост)

Конец инструкции.