# Quick Start

Запуск выполняется из PowerShell на Windows. OpenStrap создаёт Arch target и отдельный Docker host; системный Ansible работает внутри контейнера Control Plane.

## До запуска

- Установлены OpenStrap CLI и VirtualBox.
- `openstrap.config.mjs` подключает VirtualBox, SSH и keychain плагины; paths соответствуют установленным plugins.
- `arch-base` имеет snapshot `base`; исходная VM не используется для применения ролей.
- Runtime config указывает существующую SSH identity, уже разрешённую в source snapshot.
- Sudo-пароль target сохранён через `openstrap secret set BOOTSTRAP_TARGET_SUDO_PASSWORD`; SSH identity настроена локальным файлом. См. [Bootstrap Secrets](../docs/bootstrap-secrets.md).
- SSH ports `2251` и `2252` свободны для target и controller.

## Одна команда

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

`bootstrap-target` — full clone `arch-base/base`, Arch Linux, SSH `127.0.0.1:2251`. `ansible-control` — Ubuntu 24.04 Docker host, SSH `127.0.0.1:2252`. Обе машины запускаются headless; shared network соединяет их напрямую.

Cloud-init устанавливает Docker, инициализирует single-node Swarm с route-local IP и создаёт host-network service `bootstrap-control-plane` с одной replica и persistent home. OpenStrap проверяет `1/1`, доставляет sudo и private key через stdin в native Docker secrets и выполняет один workstation Docker exec. Secret rotation заменяет service task, сохраняя home; новый образ выбирается отдельным действием.

Keychain service `bootstrap` хранит один `BOOTSTRAP_TARGET_SUDO_PASSWORD`; он используется provider для сети клона и Ansible для sudo. SSH identity остаётся локальным файлом из config. Blueprint доставляет оба credentials через SSH stdin в native `docker secret create NAME -`, монтирует root-owned `0400` `/run/secrets/sudo-password` и `/run/secrets/ssh-key`. Ansible использует `--become-password-file` и `--private-key`; public target host/port/user передаются через env. [Bootstrap Secrets](../docs/bootstrap-secrets.md) описывает настройку и rotation.

GitHub Actions публикует образ с исходниками в `/opt/bootstrap/ansible`; изменения Windows попадут в deployment после новой публикации. Вывод команды, exit code и recap определяют результат применения. Сборка образа не подтверждает выполнение ролей.

## Просмотр

```powershell
openstrap list --local
openstrap connect ansible-control --local --run "cat /etc/os-release"
openstrap connect bootstrap-target --local --run "id -un"
```

Эти команды — read-only диагностика. `connect --run` не подставляет blueprint secrets. Native Docker команды для Ansible приведены в [Ansible README](../ansible/README.md).

## Повторное применение или свежий target

Повторный `openstrap run` rotates secret references и service task, затем применяет workstation. Он не выбирает новый image. Existing standalone controller container не преобразуется в Swarm без явного действия. Fresh target выбирается отдельно:

```powershell
openstrap remove bootstrap-target --local --force
openstrap run --local --host-port 2251
```

Выбор зависит от задачи пользователя. Только `bootstrap-target` пересоздаётся; `arch-base`, snapshots, `arch` и `arch-test-clone` защищены. Для идемпотентности повторно применяют роли к той же VM.

[Usage](Usage.md) и [Test VM Workflow](standards/test-vm-workflow.md) описывают native Swarm, secrets и ARA.
