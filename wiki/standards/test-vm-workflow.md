# Test VM Workflow

OpenStrap управляет тестовыми VM, а системный Ansible в контейнере Control Plane применяет один `workstation.yml` к Arch target по SSH. Этот документ описывает запуск и границы работы с машинами.

## Машины

| Место | Действия |
|---|---|
| Windows | Редактирование проекта и OpenStrap CLI |
| `ansible-control` Docker host | Docker pull, container start и Docker exec |
| Control Plane container | Ansible, lint, Vault и ARA |
| `bootstrap-target` | Применение ролей Ansible и явная диагностика |

`bootstrap-target` — полный клон `arch-base/base`. `arch-base` и snapshots `base`/`after-packages` immutable. Existing `arch` и `arch-test-clone` защищены и не являются тестовыми target этого проекта. Их нельзя изменять, перезагружать, восстанавливать или удалять.

## Запуск

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

Blueprint создаёт headless target и Ubuntu 24.04 `ansible-control`. Shared network `bootstrap` связывает target `172.28.51.10:22` и controller `172.28.51.11`; SSH с Windows доступен через порты `2251` и `2252`. Cloud-init устанавливает только `docker.io` и `ca-certificates`. OpenStrap ждёт его завершения и проверяет Docker через `sudo -n docker info`.

Далее выполняются три последовательных шага:

1. `docker pull ghcr.io/textyre/bootstrap/control-plane:latest`.
2. Запуск постоянного контейнера с named volume `bootstrap-control-plane-home:/root`.
3. `docker exec` системного Ansible — один полный `/opt/bootstrap/ansible/playbooks/workstation.yml`.

В самом `workstation.yml` есть минимальная подготовка Python через native `raw` для bare Arch, затем сбор facts и исходные 31 роль. Остальные существующие playbooks, включая `prepare_system.yml` и `mirrors-update.yml`, находятся вне обычной цепочки.

VM lifecycle выполняется через OpenStrap provider. Изменённый blueprint не перестраивает сеть уже существующих VM; пересоздание принадлежащих проекту машин выполняется отдельным явным действием. Локальные Windows изменения входят в deployment только после публикации нового образа. Коммит, push и публикация требуют разрешения пользователя; уже выданное разрешение действует в рамках согласованной задачи.

## Контейнер и подключения

GitHub Actions собирает корневой `Dockerfile` на Ubuntu 26.04 и публикует `ghcr.io/textyre/bootstrap/control-plane` с тегами `latest` и `sha-<commit>`. Python, системный Ansible, ansible-lint и SSH tools устанавливаются через APT; ARA через pip и Galaxy collections из `ansible/requirements.yml` — при сборке. Образ содержит `/opt/bootstrap/ansible`: playbooks, все роли, inventory, group vars и зашифрованный Vault. `ansible/requirements.txt` остаётся входным файлом существующего CI/Vagrant окружения.

На `ansible-control` используются обычные Docker-команды, без checkout проекта, Task, Compose, сборки или повторной установки инструментов. Taskfile и Compose доступны отдельно как необязательные команды для опубликованного образа: `controller:prepare` делает pull и пересоздаёт контейнер, остальные Tasks используют исходники image. Checkout не монтируется; локальные изменения не влияют на эти проверки до выбора нового образа. Docker по умолчанию вызывается через non-interactive sudo; для optional Tasks root или пользователь с прямым Docker access может задать `CONTROL_PLANE_RUNTIME=docker`.

Статический `ansible/inventory/openstrap.yml` читает target host, port, user и содержимое private key из env. Native `ansible_private_key` с `ssh_agent = auto` загружает OpenSSH ключ в память агента на время запуска. `StrictHostKeyChecking=accept-new` сохраняет первый host key и отклоняет изменившийся. OpenSSH создаёт обычный `known_hosts`; отдельная настройка controller через Ansible не нужна.

Named volume `bootstrap-control-plane-home` сохраняет `/root/.ssh/known_hosts` и ARA offline DB в `/root/ara` при пересоздании контейнера. ARA server публикуется только на localhost Docker host, порт `8000`. Значения private key и пароля Vault в файлы не записываются.

## Секреты

OpenStrap передаёт `BOOTSTRAP_TARGET_HOST`, `BOOTSTRAP_TARGET_PORT`, `BOOTSTRAP_TARGET_USER`, `BOOTSTRAP_TARGET_PRIVATE_KEY` и `BOOTSTRAP_VAULT_PASSWORD` только workstation step. `docker exec --env NAME` получает разрешённые имена переменных; pull и container start не получают secrets. Значения не входят в container/Compose configuration, image build arguments или environment files.

`ansible/vault-pass.sh` читает пароль из env; существующий `vault.yml` расшифровывает выполняемая команда Ansible. Private key, Vault password и локальные credential files не доставляются через Git. Не печатайте их и не помещайте в командную строку или shell history.

Ручной `openstrap connect --run` сам не подставляет blueprint secrets. Для повторного применения через `docker exec` нужен тот же явно подготовленный runtime environment.

## Проверки и повторный запуск

При разработке `task check` выполняет syntax check workstation; `task lint:openstrap` проверяет workstation и роли `user`/`chezmoi`; `task lint` проверяет Ansible проект. Эти optional проверки используют контейнер и запускаются отдельно, когда нужны для изменения. Они не являются дополнительными стадиями обычного deployment.

Molecule tests работают в существующих [.github/workflows/molecule.yml](../../.github/workflows/molecule.yml) и [.github/workflows/molecule-vagrant.yml](../../.github/workflows/molecule-vagrant.yml). Контейнер Control Plane их не устанавливает. `task test` и role aliases сообщают о CI и завершаются с ошибкой, не запуская workflows.

Повторный `openstrap run` выполняет workstation на существующем target; ручной запуск использует `docker exec` с тем же runtime environment. Проверка идемпотентности на том же target или проверка на свежем клоне — отдельные задачи. Для свежего клона можно удалить только `bootstrap-target`:

```powershell
openstrap remove bootstrap-target --local --force
openstrap run --local --host-port 2251
```

Controller можно сохранить. Protected/source VM никогда не включаются в cleanup. Ошибки исправляются в Ansible source; ручные package/service/file repairs не должны подменять результат применения ролей.

Фактический результат — exit code и recap Ansible; ARA сохраняет подробности выполнения. SQLite читается read-only. В отчёте указываются выполненные проверки и ограничения, без объявления непроведённых tests успешными.

В отчёте отдельно подтверждаются source checks, image build/publication и применение к VM. Bare-metal установка остаётся отдельным процессом и не используется как обход тестового VM запуска.
