# Requirements

## Bootstrap

- Windows имеет установленный OpenStrap CLI, VirtualBox и подключённые provider/SSH/keychain plugins.
- Sudo-пароль target сохранён в keychain service `bootstrap`; configured SSH identity остаётся локальным файлом. См. [Bootstrap Secrets](../docs/bootstrap-secrets.md).
- Entry command из `D:/projects/bootstrap`: `openstrap run --local --host-port 2251`.
- `bootstrap-target` — disposable full clone `arch-base/base`; `ansible-control` — Ubuntu 24.04 Docker host.
- Native cloud-init использует `package_update`, `packages` и `runcmd`: устанавливает Docker, инициализирует single-node Swarm и создаёт service готового image на первом старте.
- После cloud-init OpenStrap проверяет Swarm replicas `1/1`, rotates native secrets и выполняет один Docker exec workstation.
- GHCR package опубликован с public visibility, чтобы Docker host загружал образ без registry credentials.
- Ansible и lint выполняются внутри одного контейнера Control Plane; target управляется по SSH.
- Password/private key доставляются stdin и root-owned Swarm mounts `0400`; environment содержит только public target host/port/user.
- Protected source VM и snapshots неизменны.

## Роли — порядок и зависимости

Полный scope и порядок задаёт `ansible/playbooks/workstation.yml`; актуальное описание — [[Ansible-Overview]]. Playbook сам устанавливает Python через native `raw`, если его нет, затем собирает facts и выполняет исходные 31 роль. Runtime dependencies устанавливаются declaratively до роли/сервиса, которым они нужны. Существующие `prepare_system.yml` и `mirrors-update.yml` остаются отдельными playbooks вне обычного запуска.

## Пакеты

- Единый реестр в `inventory/group_vars/all/packages.yml`
- Роли содержат только логику, данные — в group_vars
- AUR пакеты устанавливаются через yay с текущим become-паролем (SUDO_ASKPASS).
- Конфликты AUR с pacman пакетами разрешаются автоматически
- picom ставится из pacman (официальный upstream v12+ с анимациями и rules)
- Обязательные AUR: i3lock-color, rofi-greenclip, dracula-gtk-theme, i3-rounded-border-patch-git
- Arch mapping сохраняет явный `nodejs-lts-iron`: Node 20 совместим с build dependency Nody и runtime ctOS helper. Общая категория `nodejs` для Ubuntu не меняется.

## Проверки

- Native Docker exec выполняет workstation syntax check и scoped/project ansible-lint; команды в [Ansible README](../ansible/README.md).
- Molecule сценарии запускаются существующими CI workflows `.github/workflows/molecule.yml` и `molecule-vagrant.yml`, со своим окружением.
- Controller не устанавливает Molecule и не запускает workflows автоматически.
- Повторное применение и тест на свежем клоне выбираются по задаче пользователя.
- Реальный вывод подтверждает результат; наличие VM не доказывает, что checks прошли.

## Доставка образа на controller

GitHub Actions использует Buildx и публикует `ghcr.io/textyre/bootstrap/control-plane` (`latest`, `sha-<commit>`). Образ содержит public Ansible source; private key, пароль и host runtime config исключены. Runtime secrets предоставляются native Swarm, вне image build.

## Инфраструктура

- Корневой `Dockerfile` на Ubuntu 26.04 устанавливает Python, системный Ansible, ansible-lint и SSH tools через APT; ARA и Galaxy collections устанавливаются при сборке.
- First-boot cloud-init инициализирует Swarm и создаёт service; финальный runtime step выполняет один workstation playbook.
- Повторный OpenStrap run rotates secrets/task, но не выбирает новый image. Existing VM не принимает changed cloud-init автоматически.
- Native Docker commands используются напрямую; корневые Task/Compose wrappers удалены. Target roles сохраняют Compose dependencies.
- Inventory: статический `ansible/inventory/openstrap.yml`, `ansible_connection: ssh`, runtime env lookups для target.
- Ansible читает `/run/secrets/ssh-key` через `--private-key` и `/run/secrets/sudo-password` через `--become-password-file`.
- Named home volume сохраняет known_hosts/ARA. Host-network ARA server запускается явно на `127.0.0.1:8000`; no Swarm port published.
- Docker exec env содержит только public target values. ARA игнорирует secret file contents под `/run/secrets` и `.ansible/tmp`.
- `ansible/requirements.txt` остаётся входным файлом существующего CI/Vagrant окружения.

## Идемпотентность

Chezmoi apply выполняется с `umask 027`, согласованным с mode `0750` для управляемой `.local/share`. Не ослабляйте этот baseline до `0755` ради устранения ложного изменения.

Когда задача требует проверки идемпотентности, используйте фактическое повторное применение на той же VM. Временные файлы и dependency refresh не должны создавать ложные изменения. Частичные tags/skip-tags подтверждают только выбранный scope.

---

Назад к [[Home]]
