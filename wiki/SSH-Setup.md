# SSH: Windows → controller → target

SSH plugin обеспечивает доступ Windows OpenStrap к обеим VM. Контейнер Control Plane использует обычный SSH client и статический Ansible inventory для target.

## Соединения

| Откуда | Куда | Адрес |
|---|---|---|
| Windows | `bootstrap-target` / `textyre` | `127.0.0.1:2251` |
| Windows | `ansible-control` / `openstrap` | `127.0.0.1:2252` |
| Control Plane container | `bootstrap-target` / `textyre` | `172.28.51.10:22` |

Общая приватная сеть `bootstrap` соединяет обе VM. Blueprint передаёт актуальные target references в environment workstation Docker exec; адрес и порт читаются статическим inventory внутри готового image.

## Identity

Source snapshot `arch-base/base` разрешает существующий публичный SSH ключ пользователя `textyre`. `openstrap.config.mjs` задаёт соответствующую локальную identity в `ssh({ identities: { "bootstrap-target": ... } })`. Не копируйте новый ключ в source VM и не меняйте её состояние для теста.

Keychain service `bootstrap` хранит один `BOOTSTRAP_TARGET_SUDO_PASSWORD`; он используется provider для сети клона и Ansible для sudo. SSH identity остаётся локальным файлом из config. Blueprint доставляет оба credentials через SSH stdin в native `docker secret create NAME -`, монтирует root-owned `0400` `/run/secrets/sudo-password` и `/run/secrets/ssh-key`. Ansible использует `--become-password-file` и `--private-key`; public target host/port/user передаются через env. [Bootstrap Secrets](../docs/bootstrap-secrets.md) описывает настройку и rotation.

Inventory читает public host, port и user из env. Ansible SSH client читает `/run/secrets/ssh-key` через native `--private-key`; secret mount имеет owner root/mode `0400` и не находится в persistent home.

## Host key trust

`StrictHostKeyChecking=accept-new` сохраняет новый public host key при первом SSH-соединении и отклоняет изменившийся. Это доверие при первом контакте в общей приватной сети, а не независимая attestation source. OpenSSH создаёт обычный `/root/.ssh/known_hosts`; named volume `bootstrap-control-plane-home:/root` сохраняет его при пересоздании контейнера.

Не отключайте host key checking и не удаляйте known_hosts для маскировки ошибки. Сначала подтвердите identity и причину изменения, особенно при пересоздании target по тому же адресу.

## Диагностика

```powershell
Set-Location D:/projects/bootstrap
openstrap connect bootstrap-target --local --run "id -un"
openstrap connect ansible-control --local --run "cat /etc/os-release"
```

Ansible выполняется native Docker exec в текущей Swarm task; команды в [Ansible README](../ansible/README.md). Arbitrary `connect --run` не получает blueprint secrets.

Если SSH не работает, проверьте правильный target, running state, recorded port, локальную identity и known_hosts. Не назначайте protected `arch` default host и не устанавливайте пакеты/sshd вручную на source.

## Файлы и секреты

Cloud-init устанавливает Docker, инициализирует single-node Swarm с route-local IP и создаёт host-network service `bootstrap-control-plane` с одной replica и persistent home. OpenStrap проверяет `1/1`, доставляет sudo и private key через stdin в native Docker secrets и выполняет один workstation Docker exec. Secret rotation заменяет service task, сохраняя home; новый образ выбирается отдельным действием. Public image содержит inventory, роли, playbooks и group vars; runtime credentials в image не входят.

Target host/port/user передаются как public exec environment. Secret payloads идут через stdin в Docker secrets; passwords/private keys не входят в environment, image, CLI arguments или history.

[Windows Setup](Windows-Setup.md) · [Bootstrap Secrets](../docs/bootstrap-secrets.md) · [Test VM Workflow](standards/test-vm-workflow.md).
