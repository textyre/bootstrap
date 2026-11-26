# Ansible Workstation Bootstrap

Системный Ansible работает внутри Docker Swarm service `bootstrap-control-plane`
и выполняет один полный [playbooks/workstation.yml](playbooks/workstation.yml)
на Arch `bootstrap-target` по SSH.

## Запуск

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

OpenStrap создаёт disposable full clone `arch-base/base` и Ubuntu 24.04 Docker
host. Cloud-init устанавливает Docker, инициализирует single-node Swarm и создаёт
service из готового `ghcr.io/textyre/bootstrap/control-plane:latest`. После
проверки `1/1` replicas OpenStrap создаёт и монтирует два native Docker secrets,
затем выполняет workstation через один `docker exec`.

Образ Ubuntu 26.04 содержит Python, системный Ansible, ansible-lint и SSH tools
из APT, ARA 1.7.3, Galaxy collections и public `/opt/bootstrap/ansible` source.
Все исходные 31 роль входят в образ. `requirements.txt` остаётся input для
существующих CI/Vagrant workflows. На controller используются Docker-команды
напрямую; Git checkout, Task, Compose и сборка ему не нужны.

## Inventory и секреты

Хранилище секретов ОС (плагин `keychain` из npm) хранит `ARCH_BASE_SSH_KEY` и
`BOOTSTRAP_TARGET_SUDO_PASSWORD` текущего target; скрытый ввод выполняется один раз
через `openstrap secret set NAME`. Пароль нужен и provider для сети клона, и Ansible
для sudo; SSH-ключ blueprint называет в `identity`. [Bootstrap Secrets](../docs/bootstrap-secrets.md)
описывает весь поток, rotation и ограничения shared-controller concurrency.

Пароль и private key передаются через SSH stdin в `docker secret create NAME -`
и монтируются только в service task как root-owned файлы `0400`:

| Mount | Ansible argument |
|---|---|
| `/run/secrets/sudo-password` | `--become-password-file` |
| `/run/secrets/ssh-key` | `--private-key` |

Статический [inventory/openstrap.yml](inventory/openstrap.yml) получает только
public `BOOTSTRAP_TARGET_HOST`, `BOOTSTRAP_TARGET_PORT` и `BOOTSTRAP_TARGET_USER`
через env lookups. Private key и пароль не передаются через environment, CLI
arguments, image build или persistent home. Ansible Vault и password adapter
удалены. Swarm хранит encrypted manager state и предоставляет memory-backed
secret mounts; host/manager root имеет доступ к credentials.

OpenSSH `StrictHostKeyChecking=accept-new` принимает новый host key при первом
контакте и отклоняет изменившийся. Named volume `bootstrap-control-plane-home`
сохраняет `/root/.ssh/known_hosts` и `/root/ara` при rotation service task.
ARA игнорирует loaded files под `/run/secrets` и `.ansible/tmp`.

## Native Docker commands

Cloud-init команды подготовки и native rotation находятся в
[openstrap.yaml](../openstrap.yaml). Для другого Linux Docker host используются
тот же single-node Swarm, готовый образ, host networking и native `docker secret`.
Swarm service task получает изменяющееся имя; найдите её текущий container ID:

```bash
container=$(sudo -n docker ps --filter label=com.docker.swarm.service.name=bootstrap-control-plane \
  --filter status=running --format '{{.ID}}')
test -n "$container"
```

После mounted secrets и подготовки трёх public target env values:

```bash
sudo --non-interactive --preserve-env=BOOTSTRAP_TARGET_HOST,BOOTSTRAP_TARGET_PORT,BOOTSTRAP_TARGET_USER \
  flock /run/lock/bootstrap-control-plane.lock docker exec \
  --env BOOTSTRAP_TARGET_HOST --env BOOTSTRAP_TARGET_PORT --env BOOTSTRAP_TARGET_USER \
  "$container" ansible-playbook playbooks/workstation.yml \
  --become-password-file /run/secrets/sudo-password --private-key /run/secrets/ssh-key
```

Произвольный `openstrap connect --run` не добавляет blueprint secrets. Ansible
source находится внутри образа; изменение локального checkout требует новой
публикации и явно выбранного обновления image. Повторный OpenStrap run rotates
secrets/task и применяет workstation, но не выбирает новый образ. Existing VM с
прежним standalone container не превращается в Swarm автоматически.

## Проверки и ARA

```bash
sudo -n docker exec "$container" ansible-playbook playbooks/workstation.yml --syntax-check
sudo -n docker exec "$container" ansible-lint playbooks/workstation.yml roles/user/ roles/chezmoi/
sudo -n docker exec "$container" ansible-lint playbooks/ roles/
sudo -n docker exec -it "$container" ara-manage runserver 127.0.0.1:8000
```

ARA server слушает только localhost Docker host; Swarm порт не публикуется.
Результат deployment определяется exit code и recap Ansible. SQLite читается
read-only. Сборка и syntax checks не подтверждают применение всех ролей.

Molecule работает в существующих [.github/workflows/molecule.yml](../.github/workflows/molecule.yml)
и [molecule-vagrant.yml](../.github/workflows/molecule-vagrant.yml). Control Plane
не устанавливает Molecule. CI image workflow проверяет synthetic SSH, настоящий
password-required sudo, mode mounts и отсутствие credentials в ARA.

## Роли

Порядок задан в `playbooks/workstation.yml`: `reflector`, `package_manager`,
`packages`, `timezone`, `locale`, `hostname`, `hostctl`, `vconsole`, `ntp`,
`ntp_audit`, `pam_hardening`, `vm`, `gpu_drivers`, `sysctl`, `power_management`,
`user`, `ssh_keys`, `teleport`, `ssh`, `fail2ban`, `git`, `shell`, `docker`,
`firewall`, `caddy`, `vaultwarden`, `xorg`, `greeter`, `lightdm`, `zen_browser`,
`chezmoi`. Bare Arch Python bootstrap и fact gathering находятся в том же playbook.
`prepare_system.yml` и `mirrors-update.yml` остаются отдельными playbooks.
