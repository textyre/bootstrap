# Arch Linux Workstation Bootstrap

OpenStrap создаёт тестовую Arch VM и отдельный Docker host. Cloud-init подготавливает контейнер из готового GHCR-образа, затем OpenStrap запускает один `workstation.yml` по SSH. В контейнере Control Plane работает обычный системный Ansible. Контейнер можно разместить на Linux VM, в облаке или на VPS: нужен Docker и доступ к target.

## Запуск

Из PowerShell в каталоге проекта:

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

Нужны OpenStrap CLI с поддержкой step stdin, VirtualBox, плагины из `openstrap.config.mjs`, snapshot `base` исходной `arch-base` и существующий локальный SSH ключ. Sudo-пароль target сохраняется один раз через `openstrap secret set BOOTSTRAP_TARGET_SUDO_PASSWORD` со скрытым вводом; обычный запуск получает его через keychain service `bootstrap`. Этот же пароль используется provider и Ansible. [Bootstrap Secrets](docs/bootstrap-secrets.md) описывает доставку через stdin и native Docker Swarm secrets.

## Общее состояние через OpenStrap Server

CLI выполняет provider-операции и SSH-подключения на Windows в обоих режимах.
`--local` выбирает локальное состояние; без этого флага CLI использует выбранный
OpenStrap Server. Сервер хранит состояние и историю, а машины по-прежнему создаёт
VirtualBox на компьютере CLI.

После обновления CLI и Server до версии с поддержкой этого контракта один раз
выберите уже развёрнутый сервер и войдите из каталога проекта:

```powershell
openstrap server https://openstrap.example.com
openstrap login --token
```

Замените пример адресом своего сервера. `login --token` запрашивает выданный
сервером токен без отображения; значение не передаётся аргументом команды.
`openstrap server` показывает выбранное подключение. URL сохраняется в
пользовательской конфигурации CLI, токен — в keychain отдельно для каждого URL.
При настроенном на сервере OIDC используйте `openstrap login`.

Для запуска с общим состоянием:

```powershell
openstrap run --host-port 2251
```

CLI сначала переносит локальную историю выбранных targets и регистрирует
существующие VM с их provider ID, пользователем, портом и публичным ключом.
Приватный ключ остаётся у SSH transport. Ошибка переноса останавливает запуск;
повторная передача одной записи не дублирует её. Незавершённые операции остаются
видны как `running`; успешный результат записывается после workstation.

Sudo-пароль остаётся в keychain текущего пользователя с service `bootstrap`.
Cloud-init, native Swarm secrets и единственный `docker exec` workstation
исполняются на стороне CLI. Недоступность Server
не переключает CLI в локальное состояние автоматически.

Если CLI аварийно завершился, сначала убедитесь, что исходная операция и её
удалённые процессы остановились. Затем освободите запись по ID из сообщения
конфликта:

```powershell
openstrap recover <run-id> --reason "CLI terminated; execution stopped" --confirm-stopped
```

Эта команда помечает запись неуспешной; она не останавливает Ansible и не отменяет
изменения на VM. Новый запуск workstation остаётся отдельным действием.

## Что выполняется

| VM | Назначение |
|---|---|
| `bootstrap-target` | Полный клон `arch-base/base`; Arch Linux, пользователь `textyre` |
| `ansible-control` | Ubuntu 24.04 Docker host |

Обе VM запускаются headless. Общая приватная сеть `bootstrap` соединяет target `172.28.51.10:22` и controller `172.28.51.11`. SSH с Windows доступен через порты `2251` и `2252`. Исходная VM и её snapshots остаются неизменными.

Cloud-init устанавливает `docker.io` и `ca-certificates`, инициализирует single-node Swarm с route-local IP и запускает service `bootstrap-control-plane` из готового `ghcr.io/textyre/bootstrap/control-plane:latest`. Service использует host networking и volume `bootstrap-control-plane-home:/root`. OpenStrap ждёт cloud-init до 30 минут и проверяет `1/1` replicas. Два stdin шага создают и монтируют native Docker secrets для sudo и SSH; последний шаг выполняет один `docker exec` системного Ansible с полным `workstation.yml`.

[GitHub Actions workflow](.github/workflows/build-control-plane.yml) использует Buildx для сборки корневого `Dockerfile` на Ubuntu 26.04 и публикации GHCR tags `latest`/`sha-<commit>`. Python, системный Ansible, ansible-lint и SSH tools устанавливаются через APT; ARA и Galaxy collections — при сборке. Public `/opt/bootstrap/ansible` уже содержит playbooks, все роли, inventory и group vars. Runtime secrets не входят в build; Buildx build secrets не заменяют Swarm runtime secrets. Controller не требует Git checkout, Task, Compose или сборки.

`inventory/openstrap.yml` получает public адрес, порт и пользователя из runtime environment. Ansible читает root-owned mounts `0400` через `--become-password-file /run/secrets/sudo-password` и `--private-key /run/secrets/ssh-key`. Пароль и key доставляются через SSH stdin, без secret env или custom adapter. OpenSSH `StrictHostKeyChecking=accept-new` сохраняет новый host key и отклоняет изменившийся. Named home volume сохраняет known_hosts и ARA; ARA игнорирует `/run/secrets`. ARA server запускается отдельно на `127.0.0.1:8000` внутри host-network task.

На минимальном Arch без Python `workstation.yml` сначала устанавливает Python через native `raw`, затем собирает facts и выполняет исходные 31 роль. Список и порядок ролей определены в [workstation.yml](ansible/playbooks/workstation.yml). Существующие `prepare_system.yml` и `mirrors-update.yml` остаются отдельными исходными playbooks вне этой цепочки.

## Разработка и повторное применение

Для syntax/lint, ручного Ansible exec и ARA используются native Docker-команды из [Ansible README](ansible/README.md). Корневые Taskfile и Compose wrappers удалены; Compose внутри target roles остаётся. Локальный checkout в service task не монтируется.

Molecule выполняется в существующих [.github/workflows/molecule.yml](.github/workflows/molecule.yml) и [.github/workflows/molecule-vagrant.yml](.github/workflows/molecule-vagrant.yml); запуск CI остаётся отдельным действием.

Повторный `openstrap run` проверяет service, rotates immutable secret references и service task, затем применяет workstation один раз. Новый образ не выбирается. Native `flock` блокирует rotation во время Ansible; разные targets или меняющиеся credentials на shared controller требуют сериализации всего deployment. Для свежего клона отдельно удаляют только `bootstrap-target` через OpenStrap.

Изменённые роли доставляются новым опубликованным образом: локальные изменения Windows не входят в уже существующий image. Тег `sha-<commit>` позволяет выбрать конкретную ревизию; `latest` выбирается при первоначальном pull. Изменение cloud-init или тега не обновляет существующий контейнер при повторном `openstrap run`; пересоздание controller или замена его образа выполняется отдельно по явному выбору. Изменение blueprint также не перестраивает сеть уже существующих VM. Protected `arch-base`, `arch` и `arch-test-clone` не входят в очистку проекта.

Результат deployment определяется exit code и recap Ansible. Сборка образа и проверки исходников сами по себе не подтверждают применение ролей к VM.

## Структура

```text
openstrap.yaml                     VM, cloud-init Swarm, stdin secrets и workstation
openstrap.config.mjs               provider, SSH identity и системное хранилище секретов
Dockerfile                         публикуемый образ с Ansible и исходниками
ansible/playbooks/workstation.yml  полный workstation playbook
ansible/roles/                     роли рабочей станции
ansible/inventory/openstrap.yml    SSH inventory с env lookups
ansible/inventory/group_vars/all/  публичные настройки
```

Правила работы с тестовыми машинами — [Test VM Workflow](wiki/standards/test-vm-workflow.md); команды Ansible — [ansible/README.md](ansible/README.md).

## Лицензия

MIT.
