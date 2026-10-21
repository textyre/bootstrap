# Windows Setup

Windows запускает OpenStrap CLI и VirtualBox. Обычный системный Ansible установлен внутри контейнера Control Plane на Linux Docker host.

## Требования

1. Команда `openstrap` доступна в PowerShell.
2. VirtualBox установлен, `VBoxManage` доступен provider.
3. `openstrap.config.mjs` подключает установленные VirtualBox, SSH и keychain plugins.
4. Есть `arch-base` со snapshot `base` и локальная SSH identity, разрешённая этим snapshot.
5. В keychain service `bootstrap` сохранён `BOOTSTRAP_TARGET_SUDO_PASSWORD`. [Bootstrap Secrets](../docs/bootstrap-secrets.md) описывает скрытый ввод.
6. Порты `2251` и `2252` свободны.

Текущий project runtime config импортирует собранные плагины из соседних директорий. При переносе проекта imports и путь к identity нужно привязать к установленным plugins/ключу. Персональный ключ не входит в image и не коммитится.

Keychain автоматически получает один сохранённый sudo-пароль target. Он нужен provider и Ansible; private key остаётся существующей local identity.

## Запуск

```powershell
Set-Location D:/projects/bootstrap
openstrap plugins
openstrap run --local --host-port 2251
```

CLI создаёт `bootstrap-target` из `arch-base/base` и `ansible-control` из Ubuntu 24.04 cloud image. Target получает host SSH port `2251`, controller — `2252`. Обе VM запускаются без окна. Общая сеть `bootstrap` соединяет target `172.28.51.10:22` и Docker host `172.28.51.11`.

Cloud-init устанавливает Docker, инициализирует single-node Swarm с route-local IP и создаёт host-network service `bootstrap-control-plane` с одной replica и persistent home. OpenStrap проверяет `1/1`, доставляет sudo и private key через stdin в native Docker secrets и выполняет один workstation Docker exec. Secret rotation заменяет service task, сохраняя home; новый образ выбирается отдельным действием. Локальные edits требуют новой публикации и явно выбранного обновления image/controller.

## Просмотр состояния

```powershell
openstrap list --local
openstrap connect ansible-control --local --run "cat /etc/os-release"
openstrap connect bootstrap-target --local --run "id -un"
```

`list` показывает записанные машины. Результат Ansible определяется exit code и recap; ARA сохраняет подробности. Source checks и image build/publication не заменяют проверку применения ролей к VM.

Password/private key доставляются через stdin в Swarm mounts `/run/secrets` mode `0400`. `connect --run` не получает blueprint secrets автоматически. Public host/port/user используют exec environment.

## Повторное применение

Повторный `openstrap run` rotates secrets/task и применяет workstation, без выбора нового image. Existing VM не принимает changed cloud-init автоматически. Fresh target выбирается отдельно:

```powershell
openstrap remove bootstrap-target --local --force
openstrap run --local --host-port 2251
```

Source `arch-base` и её snapshots не изменяются. Existing `arch` и `arch-test-clone` защищены. Для проверки идемпотентности используется тот же настроенный target без reset.

## Ошибки

- `openstrap` не найден: проверьте установку CLI и PATH.
- Plugin не загрузился: проверьте imports runtime config и actual plugin installation.
- SSH identity отсутствует: укажите существующий ключ, разрешённый source; не меняйте protected source.
- Port занят: выясните владельца порта; не останавливайте произвольную VM.
- Sudo не работает: проверьте доступ к keychain и текущий target пароль; замените запись через `openstrap secret set BOOTSTRAP_TARGET_SUDO_PASSWORD` со скрытым вводом.
- Role упала: сохраните ошибку и исправьте роль в source; затем выберите повторное применение или проверку на свежем target.

[SSH Setup](SSH-Setup.md) · [Test VM Workflow](standards/test-vm-workflow.md).
