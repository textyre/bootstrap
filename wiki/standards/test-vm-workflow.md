# Test VM Workflow

OpenStrap управляет тестовыми VM, а системный Ansible в контейнере Control Plane применяет один `workstation.yml` к Arch target по SSH. Этот документ описывает запуск и границы работы с машинами.

## Машины

| Место | Действия |
|---|---|
| Windows | Редактирование проекта и OpenStrap CLI |
| `ansible-control` Docker host | Cloud-init подготавливает контейнер; Docker exec выполняет Ansible |
| Control Plane Swarm task | Системный Ansible/lint и ARA; memory-backed secret mounts |
| `bootstrap-target` | Применение ролей Ansible и явная диагностика |

`bootstrap-target` — полный клон `arch-base/base`. `arch-base` и snapshots `base`/`after-packages` immutable. Existing `arch` и `arch-test-clone` защищены и не являются тестовыми target этого проекта. Их нельзя изменять, перезагружать, восстанавливать или удалять.

## Запуск

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

Blueprint создаёт headless target и Ubuntu 24.04 controller. Shared network `bootstrap` связывает target `172.28.51.10:22` и controller `172.28.51.11`; Windows SSH ports `2251`/`2252`. Cloud-init устанавливает Docker, инициализирует single-node Swarm с route-local IP и создаёт host-network service `bootstrap-control-plane` с одной replica и persistent home. OpenStrap проверяет `1/1`, доставляет sudo и private key через stdin в native Docker secrets и выполняет один workstation Docker exec. Secret rotation заменяет service task, сохраняя home; новый образ выбирается отдельным действием.

Readiness проверяет native `docker service ls` replicas `1/1`. Два stdin шага rotate native password/key secrets; последний выполняет один полный workstation playbook. `flock` защищает rotation и весь Ansible exec. Different-target/credential-changing shared-controller deployments сериализуются целиком.

В самом `workstation.yml` есть минимальная подготовка Python через native `raw` для bare Arch, затем сбор facts и исходные 31 роль. Остальные существующие playbooks, включая `prepare_system.yml` и `mirrors-update.yml`, находятся вне обычной цепочки.

VM lifecycle использует OpenStrap provider. Existing VM не принимает changed cloud-init и не преобразует standalone container в Swarm. Secret rotation заменяет task, но не выбирает новый image. Windows edits доставляются новой публикацией и явным image/controller update. Commit/push/publication требуют user authorization; уже выданное разрешение действует в согласованной задаче.

## Контейнер и подключения

GitHub Actions/Buildx собирают Ubuntu 26.04 image с APT Python, Ansible/lint и SSH tools, ARA, collections и public `/opt/bootstrap/ansible`. Runtime credentials в image/build отсутствуют. `requirements.txt` остаётся input существующего CI/Vagrant.

Syntax/lint и ARA выполняются native Docker exec внутри текущей service task; команды приведены в [Ansible README](../../ansible/README.md). Корневые Taskfile и Compose wrappers удалены; target-role Compose остаётся. Molecule работает в существующих `.github/workflows/molecule.yml` и `molecule-vagrant.yml`; controller не устанавливает Molecule.

Static inventory читает public target host/port/user из env. Ansible читает Swarm `/run/secrets/ssh-key` через `--private-key`. OpenSSH `accept-new` сохраняет первый host key и отклоняет changed key.

Named home `bootstrap-control-plane-home` сохраняет known_hosts и ARA при service task replacement. ARA игнорирует `/run/secrets` и `.ansible/tmp`; server запускается явно на `127.0.0.1:8000` внутри host-network task, без published port.

## Секреты

Keychain service `bootstrap` хранит один `BOOTSTRAP_TARGET_SUDO_PASSWORD`; он используется provider для сети клона и Ansible для sudo. SSH identity остаётся локальным файлом из config. Blueprint доставляет оба credentials через SSH stdin в native `docker secret create NAME -`, монтирует root-owned `0400` `/run/secrets/sudo-password` и `/run/secrets/ssh-key`. Ansible использует `--become-password-file` и `--private-key`; public target host/port/user передаются через env. [Bootstrap Secrets](../../docs/bootstrap-secrets.md) описывает настройку и rotation.

Provider передаёт current target sudo-password через SSH stdin в `sudo -S` для clone network preparation.

Blueprint secret payloads идут через SSH stdin в `docker secret create NAME -`. Root-owned mounts `0400` находятся `/run/secrets/sudo-password` и `/run/secrets/ssh-key`; только public target values используют exec environment.

Ansible использует native `--become-password-file /run/secrets/sudo-password` и `--private-key /run/secrets/ssh-key`. Ansible Vault и custom password adapter удалены. Никогда не печатайте credentials и не помещайте их в CLI arguments/history.

Arbitrary `openstrap connect --run` не подставляет blueprint secrets. Manual exec использует existing Swarm mounts и три public target env values.

## Проверки и повторный запуск

Native Docker exec позволяет отдельно проверить workstation syntax и ansible-lint. Команды в [Ansible README](../../ansible/README.md). Проверки не добавляют стадии к deployment.

Molecule tests работают в существующих `.github/workflows/molecule.yml` и `molecule-vagrant.yml`. Controller их не устанавливает; запуск workflows остаётся отдельным действием.

Повторный `openstrap run` rotates secrets/task и применяет workstation на существующем target. Проверка идемпотентности на том же target и fresh clone — разные задачи. Для fresh clone можно удалить только `bootstrap-target`:

```powershell
openstrap remove bootstrap-target --local --force
openstrap run --local --host-port 2251
```

Controller можно сохранить. Protected/source VM никогда не включаются в cleanup. Ошибки исправляются в Ansible source; ручные package/service/file repairs не должны подменять результат применения ролей.

Фактический результат — exit code и recap Ansible; ARA сохраняет подробности выполнения. SQLite читается read-only. В отчёте указываются выполненные проверки и ограничения, без объявления непроведённых tests успешными.

В отчёте отдельно подтверждаются source checks, image build/publication и применение к VM. Bare-metal установка остаётся отдельным процессом и не используется как обход тестового VM запуска.
