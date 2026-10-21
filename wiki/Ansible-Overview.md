# Ansible Overview

Windows OpenStrap CLI управляет VirtualBox. Cloud-init загружает готовый образ проекта из GHCR и запускает его при первом старте controller; OpenStrap затем выполняет workstation через Docker exec. На Linux Docker host `ansible-control` работает контейнер с системным Ansible; Arch `bootstrap-target` — управляемая рабочая станция.

## Кто что выполняет

| Компонент | Ответственность |
|---|---|
| `openstrap.yaml` | VM, first-boot Swarm, replicas readiness, stdin secret rotation и workstation |
| `openstrap.config.mjs` | Provider, путь к SSH identity и keychain системного хранилища секретов |
| `Dockerfile` / GitHub Actions | Готовый GHCR image с системным Ansible, dependencies и `/opt/bootstrap/ansible` |
| `inventory/openstrap.yml` | Статический SSH inventory с runtime env lookups |
| `workstation.yml` | Минимальный Python bootstrap, сбор facts и полный набор 31 роли |
| ARA | История выполнения Ansible в persistent home контейнера |

## Запуск

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

Cloud-init устанавливает Docker, инициализирует single-node Swarm с route-local IP и создаёт host-network service `bootstrap-control-plane` с одной replica и persistent home. OpenStrap проверяет `1/1`, доставляет sudo и private key через stdin в native Docker secrets и выполняет один workstation Docker exec. Secret rotation заменяет service task, сохраняя home; новый образ выбирается отдельным действием. Target остаётся full clone `arch-base/base`; обе VM headless, source snapshots immutable.

GitHub Actions собирает Ubuntu 26.04 image с APT Ansible, lint, Python/SSH tools, ARA и collections. Public source входит при build; runtime credentials предоставляются Swarm secrets.

## Inventory и переменные

Static inventory workstations/bootstrap-target читает public host/port/user из environment. Controller подключается к `172.28.51.10:22` в shared network `bootstrap`; Windows использует forwarded SSH ports.

`inventory/group_vars/all/` содержит публичные параметры проекта; они входят в image.

Keychain service `bootstrap` хранит один `BOOTSTRAP_TARGET_SUDO_PASSWORD`; он используется provider для сети клона и Ansible для sudo. SSH identity остаётся локальным файлом из config. Blueprint доставляет оба credentials через SSH stdin в native `docker secret create NAME -`, монтирует root-owned `0400` `/run/secrets/sudo-password` и `/run/secrets/ssh-key`. Ansible использует `--become-password-file` и `--private-key`; public target host/port/user передаются через env. [Bootstrap Secrets](../docs/bootstrap-secrets.md) описывает настройку и rotation.

OpenSSH `StrictHostKeyChecking=accept-new` сохраняет первый host key и отклоняет изменившийся. Named volume `bootstrap-control-plane-home:/root` сохраняет known_hosts и ARA offline DB при замене service task. ARA игнорирует `/run/secrets` и `.ansible/tmp`; server запускается явно на `127.0.0.1:8000` внутри host-network task, без published Swarm port.

## Роли

Порядок читается непосредственно из `playbooks/workstation.yml`:

`reflector` → `package_manager` → `packages` → `timezone` → `locale` → `hostname` → `hostctl` → `vconsole` → `ntp` → `ntp_audit` → `pam_hardening` → `vm` → `gpu_drivers` → `sysctl` → `power_management` → `user` → `ssh_keys` → `teleport` → `ssh` → `fail2ban` → `git` → `shell` → `docker` → `firewall` → `caddy` → `vaultwarden` → `xorg` → `greeter` → `lightdm` → `zen_browser` → `chezmoi`.

Существующие `prepare_system.yml` и `mirrors-update.yml` остаются отдельными playbooks вне стандартного запуска.

## Проверки

Syntax/lint и ARA выполняются native Docker exec внутри текущей service task; команды приведены в [Ansible README](../ansible/README.md). Корневые Taskfile и Compose wrappers удалены; target-role Compose остаётся. Molecule работает в существующих `.github/workflows/molecule.yml` и `molecule-vagrant.yml`; controller не устанавливает Molecule.

Каждый run выполняет workstation один раз. Rotation заменяет service task и сохраняет home; image/controller replacement выполняется отдельно по явному выбору.

## Стандарты

[Role Requirements](standards/role-requirements.md) определяет структуру, idempotency, portability и verification ролей; [Security Standards](standards/security-standards.md) — security controls; [Profiles](standards/workstation-profiles.md) — профили.

Поддерживаемые проектом дистрибутивы: Arch, Ubuntu, Fedora, Void, Gentoo. Приведённый blueprint использует Arch target и Ubuntu Docker host; успешный такой прогон не является подтверждением остальных distro/init combinations.

[Test VM Workflow](standards/test-vm-workflow.md) · [Bootstrap Secrets](../docs/bootstrap-secrets.md).
