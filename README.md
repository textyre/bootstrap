# Arch Linux Workstation Bootstrap

OpenStrap создаёт тестовую Arch VM и отдельный Docker host, загружает готовый образ из GHCR и запускает один `workstation.yml` по SSH. В контейнере Control Plane работает обычный системный Ansible. Контейнер можно разместить на Linux VM, в облаке или на VPS: нужен Docker и доступ к target.

## Запуск

Из PowerShell в каталоге проекта:

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

Нужны OpenStrap CLI, VirtualBox, плагины из `openstrap.config.mjs`, snapshot `base` исходной `arch-base` и SSH identity для доступа к клону. Runtime config задаёт источник identity и пароль существующего Ansible Vault. Локальные credential files не входят в Git. Подробности — [Bootstrap Secrets](docs/bootstrap-secrets.md).

## Что выполняется

| VM | Назначение |
|---|---|
| `bootstrap-target` | Полный клон `arch-base/base`; Arch Linux, пользователь `textyre` |
| `ansible-control` | Ubuntu 24.04 Docker host |

Обе VM запускаются headless. Общая приватная сеть `bootstrap` соединяет target `172.28.51.10:22` и controller `172.28.51.11`. SSH с Windows доступен через порты `2251` и `2252`. Исходная VM и её snapshots остаются неизменными.

Cloud-init устанавливает только `docker.io` и `ca-certificates` на `ansible-control`. После завершения cloud-init OpenStrap проверяет Docker командой `sudo -n docker info` и выполняет три шага по порядку:

1. Загружает `ghcr.io/textyre/bootstrap/control-plane:latest` через `docker pull`.
2. Запускает постоянный контейнер Control Plane с named volume `bootstrap-control-plane-home:/root`.
3. Через `docker exec` запускает системный `ansible-playbook` с `/opt/bootstrap/ansible/playbooks/workstation.yml` для target.

[GitHub Actions workflow](.github/workflows/build-control-plane.yml) собирает корневой `Dockerfile` на Ubuntu 26.04 и публикует образ в GHCR с тегами `latest` и `sha-<commit>`. Python, системный Ansible, ansible-lint и SSH tools устанавливаются через APT; ARA через pip и Galaxy collections из `ansible/requirements.yml` — при сборке. В `/opt/bootstrap/ansible` уже находятся playbooks, все роли, статический inventory, group vars и зашифрованный Vault. На управляющей VM не нужны Git checkout, Task, Compose или сборка образа. Обычный запуск использует готовый контейнер без повторной установки зависимостей и предварительной расшифровки Vault.

`inventory/openstrap.yml` получает адрес, порт, пользователя и содержимое private key из runtime environment последнего шага. Native Ansible `ssh_agent = auto` загружает ключ в агент на время запуска. OpenSSH с `StrictHostKeyChecking=accept-new` сохраняет новые host keys и отклоняет изменившиеся. Named volume сохраняет `/root/.ssh/known_hosts` и ARA offline DB в `/root/ara`; private key и пароль Vault передаются только процессу `docker exec` и в файлы не записываются.

На минимальном Arch без Python `workstation.yml` сначала устанавливает Python через native `raw`, затем собирает facts и выполняет исходные 31 роль. Список и порядок ролей определены в [workstation.yml](ansible/playbooks/workstation.yml). Существующие `prepare_system.yml` и `mirrors-update.yml` остаются отдельными исходными playbooks вне этой цепочки.

## Разработка и повторное применение

`Taskfile.yml` и `compose.yml` — необязательные команды для Docker host, на котором доступны эти файлы и установлены Task/Compose. `task controller:prepare` загружает опубликованный образ и пересоздаёт контейнер; `check`, `lint`, `lint:openstrap`, `workstation`, `dry-run` и `ara` работают с исходниками внутри выбранного образа. Локальный checkout в контейнер не монтируется. Для root или пользователя с прямым доступом к Docker задайте `CONTROL_PLANE_RUNTIME=docker`; по умолчанию Task вызывает Docker через non-interactive sudo. Blueprint на `ansible-control` выполняет обычные Docker-команды напрямую.

Molecule выполняется в существующих [.github/workflows/molecule.yml](.github/workflows/molecule.yml) и [.github/workflows/molecule-vagrant.yml](.github/workflows/molecule-vagrant.yml). `task test` и role test aliases сообщают об этом и завершаются с ошибкой; запуск CI остаётся отдельным действием.

Повторный `openstrap run` применяет workstation к существующему target; при ручном запуске используется `docker exec` с тем же runtime environment. Для проверки на свежем клоне можно отдельно удалить только `bootstrap-target` через OpenStrap и снова запустить проект. Повторный прогон и пересоздание target выбираются по задаче пользователя.

Изменённые роли доставляются новым опубликованным образом: локальные изменения Windows не входят в уже существующий image. Тег `sha-<commit>` позволяет выбрать конкретную ревизию; `latest` следует последней публикации. Изменение blueprint не перестраивает сеть уже существующих VM. Protected `arch-base`, `arch` и `arch-test-clone` не входят в очистку проекта.

Результат deployment определяется exit code и recap Ansible. Сборка образа и проверки исходников сами по себе не подтверждают применение ролей к VM.

## Структура

```text
openstrap.yaml                     VM, image pull/start и один workstation запуск
openstrap.config.mjs               provider, SSH и локальные секреты
Taskfile.yml                       необязательные команды разработки
Dockerfile                         публикуемый образ с Ansible и исходниками
compose.yml                        необязательный development service control-plane
ansible/playbooks/workstation.yml  полный workstation playbook
ansible/roles/                     роли рабочей станции
ansible/inventory/openstrap.yml    SSH inventory с env lookups
ansible/inventory/group_vars/all/  настройки и зашифрованный Vault
ansible/vault-pass.sh               environment-only адаптер Vault
```

Bare-metal установщики, templates и `bootstrap-env.sh` сохраняются отдельно от VM запуска. Правила работы с тестовыми машинами — [Test VM Workflow](wiki/standards/test-vm-workflow.md); команды Ansible — [ansible/README.md](ansible/README.md).

## Лицензия

MIT.
