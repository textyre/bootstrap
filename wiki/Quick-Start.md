# Quick Start

Запуск выполняется из PowerShell на Windows. OpenStrap создаёт Arch target и отдельный Docker host; системный Ansible работает внутри контейнера Control Plane.

## До запуска

- Установлены OpenStrap CLI и VirtualBox.
- `openstrap.config.mjs` подключает VirtualBox и SSH плагины; paths соответствуют установленным plugins.
- `arch-base` имеет snapshot `base`; исходная VM не используется для применения ролей.
- Runtime config указывает существующую SSH identity, уже разрешённую в source snapshot.
- Доступен пароль существующего Ansible Vault через [локальный runtime secret store](../docs/bootstrap-secrets.md).
- SSH ports `2251` и `2252` свободны для target и controller.

## Одна команда

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

`bootstrap-target` — full clone `arch-base/base`, Arch Linux, SSH `127.0.0.1:2251`. `ansible-control` — Ubuntu 24.04 Docker host, SSH `127.0.0.1:2252`. Обе машины запускаются headless; shared network соединяет их напрямую.

Cloud-init устанавливает только `docker.io` и `ca-certificates`. После `sudo -n docker info` OpenStrap загружает готовый `ghcr.io/textyre/bootstrap/control-plane:latest`, запускает постоянный контейнер с volume `bootstrap-control-plane-home:/root` и выполняет один `workstation.yml` через Docker exec: Python bootstrap при необходимости, facts и исходные 31 роль. Управляющей VM не нужны Git, Task, Compose или сборка.

Статический inventory получает target connection values через environment. Native SSH agent использует private key на время запуска; Vault password передаётся только workstation process. Обычный запуск не загружает зависимости повторно и не требует дополнительного Ansible playbook.

GitHub Actions публикует образ с исходниками в `/opt/bootstrap/ansible`; изменения Windows попадут в deployment после новой публикации. Вывод команды, exit code и recap определяют результат применения. Сборка образа не подтверждает выполнение ролей.

## Просмотр

```powershell
openstrap list --local
openstrap connect ansible-control --local --run "cat /etc/os-release"
openstrap connect bootstrap-target --local --run "id -un"
```

Эти команды — read-only диагностика. Обычный `connect --run` не подставляет blueprint secrets. Ansible выполняется внутри контейнера через native Docker exec; Taskfile и Compose остаются необязательными инструментами разработки.

## Повторное применение или свежий target

Повторный `openstrap run` применяет роли к существующему target. Ручной `docker exec` требует того же runtime environment. Для проверки на свежем клоне можно отдельно выполнить:

```powershell
openstrap remove bootstrap-target --local --force
openstrap run --local --host-port 2251
```

Выбор зависит от задачи пользователя. Только `bootstrap-target` пересоздаётся; `arch-base`, snapshots, `arch` и `arch-test-clone` защищены. При проверке идемпотентности повторно применяйте роли к той же настроенной VM без reset.

[Usage](Usage.md) и [Test VM Workflow](standards/test-vm-workflow.md) описывают Docker запуск, secrets, ARA и optional Tasks.
