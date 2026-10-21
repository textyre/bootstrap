# Использование

## Развёртывание с Windows

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

Cloud-init устанавливает Docker, инициализирует single-node Swarm с route-local IP и создаёт host-network service `bootstrap-control-plane` с одной replica и persistent home. OpenStrap проверяет `1/1`, доставляет sudo и private key через stdin в native Docker secrets и выполняет один workstation Docker exec. Secret rotation заменяет service task, сохраняя home; новый образ выбирается отдельным действием.

## Native Docker commands

Syntax/lint и ARA выполняются native Docker exec внутри текущей service task; команды приведены в [Ansible README](../ansible/README.md). Корневые Taskfile и Compose wrappers удалены; target-role Compose остаётся. Molecule работает в существующих `.github/workflows/molecule.yml` и `molecule-vagrant.yml`; controller не устанавливает Molecule.

Полный workstation выполняет исходные 31 роль и bare Arch Python bootstrap в одном playbook. Native Ansible `--check --diff` или tags выбираются явно и подтверждают только свой scope.

## Runtime environment и повторное применение

Keychain service `bootstrap` хранит один `BOOTSTRAP_TARGET_SUDO_PASSWORD`; он используется provider для сети клона и Ansible для sudo. SSH identity остаётся локальным файлом из config. Blueprint доставляет оба credentials через SSH stdin в native `docker secret create NAME -`, монтирует root-owned `0400` `/run/secrets/sudo-password` и `/run/secrets/ssh-key`. Ansible использует `--become-password-file` и `--private-key`; public target host/port/user передаются через env. [Bootstrap Secrets](../docs/bootstrap-secrets.md) описывает настройку и rotation.

OpenStrap передаёт только public `BOOTSTRAP_TARGET_HOST`, `BOOTSTRAP_TARGET_PORT` и `BOOTSTRAP_TARGET_USER` workstation exec. Password и private key находятся в native Swarm mounts. `openstrap connect --run` не разрешает blueprint secrets автоматически.

OpenSSH `StrictHostKeyChecking=accept-new` сохраняет первый host key и отклоняет изменившийся. Named volume `bootstrap-control-plane-home:/root` сохраняет known_hosts и ARA offline DB при замене service task. ARA игнорирует `/run/secrets` и `.ansible/tmp`; server запускается явно на `127.0.0.1:8000` внутри host-network task, без published Swarm port.

Повторный `openstrap run` rotates immutable secrets/task и применяет workstation. Он не выбирает новый image; изменение cloud-init не применяется к существующей VM автоматически. Fresh target можно выбрать отдельно:

```powershell
openstrap remove bootstrap-target --local --force
openstrap run --local --host-port 2251
```

Для проверки идемпотентности используйте тот же настроенный target без удаления. Protected `arch-base`, её snapshots, `arch` и `arch-test-clone` не входят в cleanup.

## Диагностика

```powershell
openstrap list --local
openstrap connect ansible-control --local --run "cat /etc/os-release"
openstrap connect bootstrap-target --local --run "id -un"
```

Результат применения — exit code и recap Ansible. OpenSSH `StrictHostKeyChecking=accept-new` сохраняет первый host key и отклоняет изменившийся. Named volume `bootstrap-control-plane-home:/root` сохраняет known_hosts и ARA offline DB при замене service task. ARA игнорирует `/run/secrets` и `.ansible/tmp`; server запускается явно на `127.0.0.1:8000` внутри host-network task, без published Swarm port. SQLite читается read-only; публикация image не доказывает применение ролей.

[Ansible Overview](Ansible-Overview.md) · [SSH Setup](SSH-Setup.md) · [Test VM Workflow](standards/test-vm-workflow.md).
