# Ansible Workstation Bootstrap

Системный `ansible-playbook` работает внутри контейнера Control Plane и настраивает Arch target по SSH. Обычный запуск выполняет один [playbooks/workstation.yml](playbooks/workstation.yml).

## Запуск через OpenStrap

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

OpenStrap создаёт `bootstrap-target` из `arch-base/base` и Docker host `ansible-control`. Cloud-init устанавливает только `docker.io` и `ca-certificates`. После `sudo -n docker info` выполняются `docker pull`, запуск постоянного контейнера и `docker exec` одного workstation playbook.

Готовый образ — `ghcr.io/textyre/bootstrap/control-plane:latest`; конкретная опубликованная ревизия доступна как `sha-<commit>`. [GitHub Actions](../.github/workflows/build-control-plane.yml) собирает его на Ubuntu 26.04 с Python, системным Ansible, ansible-lint и SSH tools из APT. ARA, collections из `requirements.yml` и исходники `/opt/bootstrap/ansible` входят в образ при сборке. `requirements.txt` используется существующими CI builds и Vagrant workflows.

Управляющая VM использует Docker напрямую; Git, Task и Compose ей не требуются. Зависимости повторно не устанавливаются; Vault расшифровывает непосредственно выполняемая команда Ansible.

## Inventory и секреты

Статический [inventory/openstrap.yml](inventory/openstrap.yml) читает SSH параметры через env lookups; адаптер Vault получает пароль из того же process environment. Переменные запуска:

| Переменная | Назначение |
|---|---|
| `BOOTSTRAP_TARGET_HOST` | SSH адрес target |
| `BOOTSTRAP_TARGET_PORT` | SSH порт |
| `BOOTSTRAP_TARGET_USER` | SSH пользователь |
| `BOOTSTRAP_TARGET_PRIVATE_KEY` | Содержимое OpenSSH private key |
| `BOOTSTRAP_VAULT_PASSWORD` | Пароль зашифрованного `inventory/group_vars/all/vault.yml` |

OpenStrap передаёт эти значения только последнему шагу `docker exec`. Для ручного запуска их предоставляет заранее настроенное окружение процесса. Произвольный `openstrap connect --run` не получает blueprint secrets автоматически.

`ansible_private_key` использует native SSH agent Ansible с `ssh_agent = auto`. Private key остаётся в памяти агента на время запуска; его не нужно копировать в проект или persistent home. `StrictHostKeyChecking=accept-new` принимает новый host key при первом соединении и отклоняет изменившийся. Named volume `bootstrap-control-plane-home` сохраняет `/root/.ssh/known_hosts` и ARA offline DB в `/root/ara`.

[vault-pass.sh](vault-pass.sh) входит в образ как `/opt/bootstrap/ansible/vault-pass.sh` и читает пароль только из env. `docker exec --env NAME` получает разрешённые имена переменных; секретные значения не входят в container configuration, image build arguments или environment files. Playbooks, все 31 роль, inventory, group vars и зашифрованный `vault.yml` уже находятся в `/opt/bootstrap/ansible` внутри образа.

## Native Docker на другом host

На Linux Docker host можно запустить тот же образ напрямую. Сначала загрузите образ, затем пересоздайте только контейнер `bootstrap-control-plane`; named volume сохраняет home:

```bash
sudo --non-interactive docker pull ghcr.io/textyre/bootstrap/control-plane:latest &&
if sudo --non-interactive docker container inspect bootstrap-control-plane >/dev/null 2>&1; then
  sudo --non-interactive docker container rm --force bootstrap-control-plane
fi &&
sudo --non-interactive docker run --detach --init --restart unless-stopped \
  --name bootstrap-control-plane \
  --mount type=volume,source=bootstrap-control-plane-home,target=/root \
  --publish 127.0.0.1:8000:8000 --pull never \
  ghcr.io/textyre/bootstrap/control-plane:latest
```

Значения пяти переменных из таблицы должны быть заранее доступны в окружении вызывающего процесса. Запуск workstation передаёт их по именам:

```bash
sudo --non-interactive --preserve-env=BOOTSTRAP_TARGET_HOST,BOOTSTRAP_TARGET_PORT,BOOTSTRAP_TARGET_USER,BOOTSTRAP_TARGET_PRIVATE_KEY,BOOTSTRAP_VAULT_PASSWORD \
  docker exec --env BOOTSTRAP_TARGET_HOST --env BOOTSTRAP_TARGET_PORT \
  --env BOOTSTRAP_TARGET_USER --env BOOTSTRAP_TARGET_PRIVATE_KEY \
  --env BOOTSTRAP_VAULT_PASSWORD \
  bootstrap-control-plane ansible-playbook playbooks/workstation.yml
```

Для закрепления ревизии замените `latest` на `sha-<full Git commit SHA>` в pull и run. Повторное применение использует только последнюю exec-команду; ARA server запускается отдельно:

```bash
sudo --non-interactive docker exec -it bootstrap-control-plane ara-manage runserver 0.0.0.0:8000
```

## Необязательные Tasks для разработки

Task и Compose можно использовать на Docker host, где доступны `Taskfile.yml` и `compose.yml`. Они выполняют команды внутри опубликованного образа, без bind mount checkout, и не входят в обычную цепочку OpenStrap. Локальные изменения Ansible не влияют на эти команды до публикации нового образа; `CONTROL_PLANE_IMAGE` выбирает image/tag. По умолчанию Docker вызывается через non-interactive sudo; для root или пользователя с прямым доступом к Docker используйте `CONTROL_PLANE_RUNTIME=docker`.

| Task | Назначение |
|---|---|
| `controller:prepare` / `bootstrap` | Загрузить опубликованный образ и пересоздать контейнер |
| `check` | Syntax check `workstation.yml` |
| `lint:openstrap` | Lint workstation и ролей `user`, `chezmoi` |
| `lint` | Lint проекта Ansible |
| `workstation` / `run` | Применить полный workstation playbook |
| `dry-run` | Ansible check/diff |
| `ara` | Открыть ARA server с сохранёнными результатами |
| `vault-view` | Посмотреть Vault выбранного образа; вывод содержит secrets |
| `test` / `test-*` | Сообщить о CI tests и завершиться с ошибкой |

`dry-run` требует уже установленный Python на target: check mode пропускает установку, а сбор facts использует Python. Обычный `workstation` поддерживает минимальный Arch без Python.

Редактируйте зашифрованный `inventory/group_vars/all/vault.yml` в исходниках через native `ansible-vault`, затем публикуйте новый образ. Изменение файла внутри работающего контейнера не меняет исходники и теряется при его пересоздании.

Molecule работает в [.github/workflows/molecule.yml](../.github/workflows/molecule.yml) и [.github/workflows/molecule-vagrant.yml](../.github/workflows/molecule-vagrant.yml), со своим CI окружением. Контейнер Control Plane содержит инструменты обычного запуска Ansible; test Tasks не устанавливают Molecule и не запускают CI.

## Workstation

Playbook отключает первоначальный сбор facts, чтобы поддерживать минимальный Arch без Python. Небольшие `pre_tasks` проверяют наличие Python, при необходимости устанавливают его через `raw`, затем выполняют `setup`. Далее идут исходные 31 роль:

`reflector`, `package_manager`, `packages`, `timezone`, `locale`, `hostname`, `hostctl`, `vconsole`, `ntp`, `ntp_audit`, `pam_hardening`, `vm`, `gpu_drivers`, `sysctl`, `power_management`, `user`, `ssh_keys`, `teleport`, `ssh`, `fail2ban`, `git`, `shell`, `docker`, `firewall`, `caddy`, `vaultwarden`, `xorg`, `greeter`, `lightdm`, `zen_browser`, `chezmoi`.

Существующие `prepare_system.yml` и `mirrors-update.yml` находятся вне обычной цепочки запуска. Изменения dotfiles и особенностей ролей описываются в соответствующих role README.

## Результаты и повторное применение

Обычный результат запуска — exit code и recap Ansible; подробности сохраняет ARA offline client в persistent home. ARA server доступен только через localhost Docker host на порту `8000`. Повторный `openstrap run` или ручной `docker exec` на том же target выполняется по выбору пользователя. Свежий disposable clone нужен, когда требуется проверить исходное состояние; это отдельный выбор, а не обязательный шаг после каждого изменения.

Сборка образа, syntax и lint не подтверждают полный deployment. Подробности работы с тестовыми машинами — [Test VM Workflow](../wiki/standards/test-vm-workflow.md); стандарты ролей — [Role Requirements](../wiki/standards/role-requirements.md).
