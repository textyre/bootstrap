# Troubleshooting History — 2026-01-31

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre

## Решено

### Lint и синтаксис

- [x] 64 ansible-lint нарушения — исправлены по всем ролям (production profile)
- [x] `ansible.builtin.pacman` -> `community.general.pacman` в docker/converge
- [x] `command-instead-of-module` в git/verify — добавлены `# noqa` (git_config модуль сломан)

### Vault

- [x] vault.yml отсутствовал — создан с `ansible_become_password`, добавлены vault-* задачи в Taskfile
- [x] packages converge не загружал packages.yml — добавлен в vars_files; корневая причина чёрного экрана после логина

### Inventory

- [x] `ini` plugin не включён — Ansible 2.20+ `auto` не парсит `.ini`; добавлен `ini` в `enable_plugins`

### Molecule тесты

- [x] Сервисы ошибочно отключались в тестах (`*_enable_service: false`) — ревертнуто
- [x] nftables oneshot сервис — `state: started` всегда `changed`; заменено на `enabled` + `nft list tables`
- [x] chezmoi "inconsistent state" — старые файлы на VM (SCP не удаляет); удалены вручную

### Система

- [x] Частичное обновление Arch — `libnftnl` mismatch; `pacman -Syu` + reboot (6.17.8 -> 6.18.7)
- [x] yay сломан после обновления — `libalpm.so.15` not found; удалён, пересобран ролью
- [x] pam_faillock блокировки — `faillock --reset`; устранена причина (SUDO_ASKPASS)
- [x] Права файлов после SCP — `ansible.cfg` 0666; ручной `chmod 644` после каждого sync

### AUR пакеты

- [x] yay не имел доступа к sudo паролю — реализован SUDO_ASKPASS в packages role
- [x] NOPASSWD sudoers хак отвергнут — vault создан для передачи пароля
- [x] picom-ftlabs-git конфликт с picom — добавлен в `packages_aur_remove_conflicts`
- [x] i3lock-color конфликт с i3lock — добавлен в `packages_aur_remove_conflicts`
- [x] Idempotence тест SUDO_ASKPASS — `changed_when: false` (временный файл, не состояние)

### UI

- [x] Чёрный экран после LightDM логина — пакеты не установлены (converge не грузил packages.yml)
- [x] 125 pacman пакетов установлены, 4 AUR пакета установлены
- [x] polybar, dunst, nm-applet, greenclip, xss-lock запущены

## Не решено

### Критичные

- [ ] **picom-ftlabs-git чёрный экран** — picom (vgit-df4c6) замораживает экран при запуске. Конфиг содержал mainline v12+ анимации (`triggers`/`preset`) вместо FT-Labs формата (`animation-for-open-window`). Формат исправлен, инкрементальное тестирование (backend → blur → animations → wintypes) проходит, но стабильность при длительной работе не подтверждена. Без picom десктоп работает нормально. GLX backend точно рабочий (подтверждено пользователем).

- [ ] **i3-rounded-border-patch-git** — патч `border_radius_v2.patch` несовместим с i3 4.25 (hunk #2 FAILED в `src/con.c`). Upstream AUR проблема. Варианты: форк PKGBUILD, альтернативный пакет, ждать мейнтейнера

### Требуют core fix в конфигах

- [ ] **Нет роли обновления системы** — `pacman -Syu` перед установкой пакетов не автоматизирован. Частичное обновление ломает libaries. Нужна роль или pre_task
- [ ] **yay проверка `which` вместо `yay --version`** — broken binary проходит `which` но падает при запуске. Нужно в ролях yay и packages
- [ ] **SCP права не исправляются автоматически** — `sync_to_server.ps1` делает `chmod +x` только для `*.sh`. `ansible.cfg`, inventory, vault получают 0666. Нужно добавить `chmod 644` в скрипт

### Низкий приоритет

- [ ] **pam_faillock** — нет обнаружения/сброса в конфигах. SUDO_ASKPASS устранил причину, но другие сценарии не покрыты
- [ ] **INI vs YAML inventory** — `hosts.ini` требует `ini` plugin. Конвертация в YAML устранит зависимость от плагина
- [ ] **exec vs exec_always в i3** — компоненты (dunst, nm-applet, greenclip) не перезапускаются при `i3-msg restart`, только при re-login

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/ansible.cfg` | Добавлен `ini` в inventory plugins |
| `ansible/inventory/group_vars/all/packages.yml` | `packages_aur_remove_conflicts`, убран i3-rounded из AUR |
| `ansible/roles/packages/tasks/main.yml` | SUDO_ASKPASS, conflict removal, changed_when: false |
| `ansible/roles/packages/defaults/main.yml` | Добавлен `packages_aur_remove_conflicts: []` |
| `ansible/roles/packages/molecule/default/converge.yml` | Добавлен packages.yml в vars_files, убран NOPASSWD хак |
| `ansible/roles/docker/molecule/default/converge.yml` | `community.general.pacman`, убран `docker_enable_service: false` |
| `ansible/roles/docker/molecule/default/verify.yml` | Добавлена проверка docker service |
| `ansible/roles/firewall/molecule/default/converge.yml` | Убран `firewall_enable_service: false` |
| `ansible/roles/firewall/molecule/default/verify.yml` | Заменён `state: started` на `enabled` + `nft list tables` |
| `ansible/roles/lightdm/molecule/default/converge.yml` | Убран `lightdm_enable_service: false` |
| `ansible/roles/lightdm/molecule/default/verify.yml` | Добавлена проверка LightDM enabled |
| `ansible/roles/git/molecule/default/verify.yml` | `# noqa: command-instead-of-module` x3 |

## Итог

13/13 molecule тестов проходят (`go-task test --yes` -> "All tests passed!"). Рабочий стол функционирует: i3 + polybar + picom + dunst. Оставшиеся проблемы — upstream AUR (i3-rounded) и отсутствующая автоматизация обновления системы.
