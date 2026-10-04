# Использование

## Развёртывание с Windows

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

Blueprint описывает `bootstrap-target` (full clone `arch-base/base`) и `ansible-control` (Ubuntu 24.04 Docker host). Cloud-init устанавливает только `docker.io` и `ca-certificates`. После `sudo -n docker info` OpenStrap загружает `ghcr.io/textyre/bootstrap/control-plane:latest`, запускает постоянный контейнер и выполняет один workstation playbook через Docker exec по SSH.

## Необязательные Tasks для разработки

Обычный VM запуск использует Docker напрямую и не требует Git, Task, Compose или сборки. Taskfile и Compose — optional команды на host, где доступны эти файлы; они используют исходники внутри выбранного образа, без bind mount checkout. Локальные изменения Ansible попадают в эти команды только с новым image. Docker по умолчанию вызывается через non-interactive sudo; для root или прямого Docker access можно задать `CONTROL_PLANE_RUNTIME=docker`.

| Действие | Task |
|---|---|
| Загрузить образ и пересоздать контейнер | `controller:prepare` / `bootstrap` |
| Syntax check workstation | `check` |
| Lint workstation и ролей `user`, `chezmoi` | `lint:openstrap` |
| Lint проекта Ansible | `lint` |
| Применить workstation | `workstation` / `run` |
| Check/diff | `dry-run` |
| ARA server | `ara` |
| Посмотреть Vault выбранного образа | `vault-view` |

`workstation` и `dry-run` принимают native Ansible CLI args через `--` для выбранной задачи. Частичный запуск подтверждает только выбранные роли. Полный workstation выполняет исходные 31 роль; минимальная подготовка Python и facts находится в этом же playbook.

Molecule tests работают в существующих CI workflows `.github/workflows/molecule.yml` и `molecule-vagrant.yml`. `task test` и role aliases сообщают об этом и завершаются с ошибкой, не устанавливая инструменты и не запуская CI.

Native pull/run/exec команды для любого Linux Docker host приведены в [Ansible README](../ansible/README.md#native-docker-на-другом-host). Vault изменяется в исходниках до публикации образа; `vault-view` выводит расшифрованные secrets и не используется для обычной диагностики.

## Runtime environment и повторное применение

OpenStrap предоставляет `BOOTSTRAP_TARGET_HOST`, `BOOTSTRAP_TARGET_PORT`, `BOOTSTRAP_TARGET_USER`, `BOOTSTRAP_TARGET_PRIVATE_KEY` и `BOOTSTRAP_VAULT_PASSWORD` только workstation Docker exec. Для ручного `docker exec` или optional `task workstation` нужен тот же подготовленный process environment. `openstrap connect --run` не разрешает blueprint secrets автоматически.

Static inventory читает target values из env, native SSH agent получает private key на время запуска. `docker exec --env NAME` передаёт разрешённые имена переменных. Пароли и private keys не записываются в shell history, CLI args, container/Compose settings или VM files; image pull/start/build не получают runtime secrets.

Повторное применение к существующему target или проверка на свежем клоне выбираются по задаче пользователя. Чтобы создать свежий target, удалите только disposable VM проекта и запустите его снова:

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

Результат применения — exit code и recap Ansible. ARA offline DB и known hosts сохраняются в named volume `bootstrap-control-plane-home:/root`; SQLite читается read-only. ARA server port `8000` доступен только на localhost Docker host. Вывод Ansible и ARA можно использовать для progress и диагностики. Успешная публикация image не подтверждает применение ролей к VM.

## Анализ пакетов

`bin/show-installed-packages.sh` и `bin/show-all-dependencies.sh` — отдельные Arch read-only утилиты анализа установленных пакетов. Они не создают VM и не участвуют в orchestration.

[Ansible Overview](Ansible-Overview.md) · [SSH Setup](SSH-Setup.md) · [Test VM Workflow](standards/test-vm-workflow.md).
