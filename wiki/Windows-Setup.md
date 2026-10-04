# Windows Setup

Windows запускает OpenStrap CLI и VirtualBox. Обычный системный Ansible установлен внутри контейнера Control Plane на Linux Docker host.

## Требования

1. Команда `openstrap` доступна в PowerShell.
2. VirtualBox установлен, `VBoxManage` доступен provider.
3. `openstrap.config.mjs` подключает установленные VirtualBox и SSH plugins.
4. Есть `arch-base` со snapshot `base` и локальная SSH identity, разрешённая этим snapshot.
5. Существующий зашифрованный Vault имеет доступный локальный пароль; [runtime config](../docs/bootstrap-secrets.md) разрешает его перед запуском.
6. Порты `2251` и `2252` свободны.

Текущий project runtime config импортирует собранные плагины из соседних директорий. При переносе проекта imports и путь к identity нужно привязать к установленным plugins/ключу. Персональный ключ не входит в image и не коммитится.

## Запуск

```powershell
Set-Location D:/projects/bootstrap
openstrap plugins
openstrap run --local --host-port 2251
```

CLI создаёт `bootstrap-target` из `arch-base/base` и `ansible-control` из Ubuntu 24.04 cloud image. Target получает host SSH port `2251`, controller — `2252`. Обе VM запускаются без окна. Общая сеть `bootstrap` соединяет target `172.28.51.10:22` и Docker host `172.28.51.11`.

Cloud-init устанавливает только `docker.io` и `ca-certificates`. После Docker readiness OpenStrap загружает `ghcr.io/textyre/bootstrap/control-plane:latest`, запускает постоянный контейнер с volume `bootstrap-control-plane-home:/root` и выполняет workstation через Docker exec. Git, Task, Compose и сборка на controller не нужны. Образ уже содержит `/opt/bootstrap/ansible`; локальные изменения Windows попадут в deployment после новой публикации GitHub Actions.

## Просмотр состояния

```powershell
openstrap list --local
openstrap connect ansible-control --local --run "cat /etc/os-release"
openstrap connect bootstrap-target --local --run "id -un"
```

`list` показывает записанные машины. Результат Ansible определяется exit code и recap; ARA сохраняет подробности. Source checks и image build/publication не заменяют проверку применения ролей к VM.

Private key и Vault password передаются только process environment workstation Docker exec. `connect --run` не получает blueprint secrets автоматически. Не добавляйте парольные файлы в VM, image или container/Compose configuration.

## Повторное применение

Повторный `openstrap run` применяет workstation к существующему target. По задаче пользователя можно выполнить ручной Docker exec с тем же runtime environment или проверить роли на свежем clone:

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
- Vault не расшифровывается: проверьте локальный источник runtime secret без вывода пароля.
- Role упала: сохраните ошибку и исправьте роль в source; затем выберите повторное применение или проверку на свежем target.

[SSH Setup](SSH-Setup.md) · [Test VM Workflow](standards/test-vm-workflow.md).
