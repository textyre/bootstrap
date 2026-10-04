# Ansible Overview

Windows OpenStrap CLI управляет VirtualBox и загружает готовый образ проекта из GHCR. На Linux Docker host `ansible-control` работает контейнер с системным Ansible; Arch `bootstrap-target` — управляемая рабочая станция.

## Кто что выполняет

| Компонент | Ответственность |
|---|---|
| `openstrap.yaml` | VM source/image, headless запуск, Docker readiness, image pull/start и один workstation запуск |
| `openstrap.config.mjs` | Provider, SSH identity и локальный read-only secret store |
| `Dockerfile` / GitHub Actions | Готовый GHCR image с системным Ansible, dependencies и `/opt/bootstrap/ansible` |
| `Taskfile.yml` / `compose.yml` | Необязательные команды выбранного опубликованного образа; checkout не монтируется |
| `inventory/openstrap.yml` | Статический SSH inventory с runtime env lookups |
| `workstation.yml` | Минимальный Python bootstrap, сбор facts и полный набор 31 роли |
| ARA | История выполнения Ansible в persistent home контейнера |

## Запуск

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

`bootstrap-target` клонируется из `arch-base/base` в режиме `full`. Ubuntu 24.04 Docker host создаётся отдельно. Оба запускаются headless; source snapshots immutable. Cloud-init устанавливает только `docker.io` и `ca-certificates`. После `sudo -n docker info` OpenStrap загружает `ghcr.io/textyre/bootstrap/control-plane:latest`, запускает постоянный контейнер и выполняет один workstation через Docker exec.

GitHub Actions собирает образ Ubuntu 26.04 с Python, системным Ansible, ansible-lint и SSH tools из APT. ARA, Galaxy collections и Ansible source включаются при сборке; образ получает теги `latest` и `sha-<commit>`. VM использует готовый контейнер без checkout, сборки, повторной установки зависимостей или предварительной расшифровки Vault. Контейнер можно разместить на другом Linux Docker host.

## Inventory и переменные

`inventory/openstrap.yml` входит в репозиторий. Группа `workstations` содержит `bootstrap-target` с connection `ssh`; адрес, порт, пользователь и private key читаются из process environment. В текущем blueprint контейнер подключается к `172.28.51.10:22` в общей приватной сети `bootstrap`. Host SSH ports предназначены для Windows.

`inventory/group_vars/all/` содержит параметры проекта и зашифрованный `vault.yml`; эти файлы входят в image. Runtime config разрешает секреты локально и передаёт target connection values и `BOOTSTRAP_VAULT_PASSWORD` только workstation Docker exec. `vault-pass.sh` — environment-only адаптер Vault. Native `ansible_private_key` и `ssh_agent = auto` загружают OpenSSH ключ в агент на время запуска; private key не сохраняется в файле. `StrictHostKeyChecking=accept-new` запоминает новый host key и отклоняет изменившийся. Named volume `bootstrap-control-plane-home:/root` сохраняет known hosts и ARA offline DB.

## Роли

Порядок читается непосредственно из `playbooks/workstation.yml`:

`reflector` → `package_manager` → `packages` → `timezone` → `locale` → `hostname` → `hostctl` → `vconsole` → `ntp` → `ntp_audit` → `pam_hardening` → `vm` → `gpu_drivers` → `sysctl` → `power_management` → `user` → `ssh_keys` → `teleport` → `ssh` → `fail2ban` → `git` → `shell` → `docker` → `firewall` → `caddy` → `vaultwarden` → `xorg` → `greeter` → `lightdm` → `zen_browser` → `chezmoi`.

Существующие `prepare_system.yml` и `mirrors-update.yml` остаются отдельными playbooks вне стандартного запуска.

## Проверки

Optional development `task check` проверяет syntax workstation; `lint:openstrap` — workstation и роли `user`, `chezmoi`; `lint` — весь Ansible проект. Molecule работает в существующих CI workflows; Control Plane test aliases сообщают об этом и завершаются с ошибкой.

Обычный запуск выполняет workstation один раз. Повторное применение на том же target и проверка на свежем клоне выбираются отдельно по задаче пользователя. Результат оценивается по фактически выполненной команде, recap и ARA.

## Стандарты

[Role Requirements](standards/role-requirements.md) определяет структуру, idempotency, portability и verification ролей; [Security Standards](standards/security-standards.md) — security controls; [Profiles](standards/workstation-profiles.md) — профили.

Поддерживаемые проектом дистрибутивы: Arch, Ubuntu, Fedora, Void, Gentoo. Приведённый blueprint использует Arch target и Ubuntu Docker host; успешный такой прогон не является подтверждением остальных distro/init combinations.

[Test VM Workflow](standards/test-vm-workflow.md) · [Bootstrap Secrets](../docs/bootstrap-secrets.md).
