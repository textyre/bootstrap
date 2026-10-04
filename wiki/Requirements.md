# Requirements

## Bootstrap

- Windows имеет установленный OpenStrap CLI, VirtualBox и подключённые provider/SSH plugins.
- Entry command из `D:/projects/bootstrap`: `openstrap run --local --host-port 2251`.
- `bootstrap-target` — disposable full clone `arch-base/base`; `ansible-control` — Ubuntu 24.04 Docker host.
- Cloud-init устанавливает только `docker.io` и `ca-certificates`; `sudo -n docker info` подтверждает доступность Docker.
- Docker host загружает готовый `ghcr.io/textyre/bootstrap/control-plane:latest`, запускает постоянный контейнер и использует Docker exec. Git, Task, Compose и сборка на VM не нужны.
- GHCR package опубликован с public visibility, чтобы Docker host загружал образ без registry credentials.
- Ansible и lint выполняются внутри одного контейнера Control Plane; target управляется по SSH.
- Vault password и target connection values передаются только workstation process environment.
- Protected source VM и snapshots неизменны.

## Роли — порядок и зависимости

Полный scope и порядок задаёт `ansible/playbooks/workstation.yml`; актуальное описание — [[Ansible-Overview]]. Playbook сам устанавливает Python через native `raw`, если его нет, затем собирает facts и выполняет исходные 31 роль. Runtime dependencies устанавливаются declaratively до роли/сервиса, которым они нужны. Существующие `prepare_system.yml` и `mirrors-update.yml` остаются отдельными playbooks вне обычного запуска.

## Пакеты

- Единый реестр в `inventory/group_vars/all/packages.yml`
- Роли содержат только логику, данные — в group_vars
- AUR пакеты устанавливаются через yay с паролем из vault (SUDO_ASKPASS)
- Конфликты AUR с pacman пакетами разрешаются автоматически
- picom ставится из pacman (официальный upstream v12+ с анимациями и rules)
- Обязательные AUR: i3lock-color, rofi-greenclip, dracula-gtk-theme, i3-rounded-border-patch-git
- Arch mapping сохраняет явный `nodejs-lts-iron`: Node 20 совместим с build dependency Nody и runtime ctOS helper. Общая категория `nodejs` для Ubuntu не меняется.

## Проверки

- Optional development Tasks `check`, `lint:openstrap` и `lint` выполняют syntax check workstation, scoped lint workstation/user/chezmoi и lint всего проекта соответственно.
- Molecule сценарии запускаются существующими CI workflows `.github/workflows/molecule.yml` и `molecule-vagrant.yml`, со своим окружением.
- Control Plane test aliases завершаются с сообщением о CI; они не устанавливают test tools и не запускают workflows.
- Повторное применение и тест на свежем клоне выбираются по задаче пользователя.
- Реальный вывод подтверждает результат; наличие Tasks или VM не доказывает, что checks прошли.

## Доставка образа на controller

GitHub Actions собирает и публикует `ghcr.io/textyre/bootstrap/control-plane` с тегами `latest` и `sha-<commit>`. Образ уже содержит `/opt/bootstrap/ansible`: playbooks, роли, static inventory, group vars и зашифрованный Vault. Локальные изменения входят в deployment после публикации нового image; credential files и runtime config Windows в image не входят. При сборке `ansible/vault-pass.sh` включается с executable mode и читает только environment.

## Инфраструктура

- Корневой `Dockerfile` на Ubuntu 26.04 устанавливает Python, системный Ansible, ansible-lint и SSH tools через APT; ARA и Galaxy collections устанавливаются при сборке.
- Blueprint напрямую выполняет image pull, container start и Docker exec одного playbook.
- Taskfile и Compose — необязательные команды опубликованного образа на Docker host; они не устанавливаются на управляющую VM и не монтируют локальные исходники Ansible.
- Inventory: статический `ansible/inventory/openstrap.yml`, `ansible_connection: ssh`, runtime env lookups для target.
- Native `ansible_private_key` и `ssh_agent = auto` загружают OpenSSH identity в память агента на время запуска.
- Known hosts и ARA offline DB сохраняются в named volume `bootstrap-control-plane-home:/root`; ARA server port `8000` доступен только на localhost Docker host.
- Docker exec передаёт только разрешённые имена environment; secrets не хранятся в container/Compose settings и не используются при pull/start/build.
- `ansible/requirements.txt` остаётся входным файлом существующего CI/Vagrant окружения.

## Идемпотентность

Chezmoi apply выполняется с `umask 027`, согласованным с mode `0750` для управляемой `.local/share`. Не ослабляйте этот baseline до `0755` ради устранения ложного изменения.

Когда задача требует проверки идемпотентности, используйте фактическое повторное применение на той же VM. Временные файлы и dependency refresh не должны создавать ложные изменения. Частичные tags/skip-tags подтверждают только выбранный scope.

---

Назад к [[Home]]
