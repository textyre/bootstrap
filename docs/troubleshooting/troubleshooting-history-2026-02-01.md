# Troubleshooting History — 2026-02-01

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre

## Решено

### Категория: UI / picom compositor

- [x] **picom-ftlabs-git чёрный экран (freeze)** — picom запускался и моментально замораживал экран. Причина: в предыдущей сессии на VM остался конфиг с mainline picom v12+ синтаксисом анимаций (`animations = ({...triggers...})`), sed-команда для замены на FT-Labs формат сработала некорректно. Решение: инкрементальное тестирование конфига (backend → corners → shadows → opacity → blur → animations → fading → wintypes), каждый этап стабилен. Перезаписан `~/.config/picom.conf` через chezmoi apply с корректным FT-Labs форматом анимаций (`animation-for-open-window`, `animation-stiffness-in-tag` и т.д.).

- [x] **Верификация picom.conf.tmpl** — локальный шаблон `dotfiles/dot_config/picom.conf.tmpl` проверен: chezmoi генерирует конфиг, идентичный протестированному на VM. Все фичи работают: GLX backend, dual_kawase blur, FT-Labs animations (zoom, slide-down), rounded corners, shadows, opacity, fading.

### Категория: Десктоп стек

- [x] **Полный десктоп стек работает** — после исправления picom все компоненты запущены и стабильны: i3 4.25-21 (rounded-border-patch), picom-ftlabs-git (vgit-df4c6), polybar, dunst, nm-applet, greenclip. Workspace 3 активен с терминалами Alacritty.

### Категория: Синхронизация

- [x] **Синхронизация файлов на VM** — ansible/ и dotfiles/ скопированы через scp, права исправлены (ansible.cfg 644, inventory go-w, vault.yml 600, .sh файлы +x LF).

### Категория: i3 config

- [x] **exec vs exec_always для dunst/nm-applet/greenclip** — заменено `exec` на `exec_always` с `pkill -x` перед запуском в `dotfiles/dot_config/i3/config.tmpl`. Теперь при `i3 restart` (Mod+Shift+r) все три демона корректно перезапускаются. Паттерн: `exec_always --no-startup-id sh -c 'pkill -x <proc>; exec <proc>'`.

### Категория: Ansible / PAM

- [x] **pam_faillock warnings** — добавлен Ansible таск в `roles/base_system/tasks/archlinux.yml`: создаёт `/etc/security/faillock.conf` с дефолтами (deny=5, unlock_time=600, fail_interval=900, dir=/run/faillock). Тег: `['system', 'pam']`.

### Категория: Ansible / Inventory

- [x] **INI → YAML inventory** — создан `ansible/inventory/hosts.yml`, обновлены `ansible.cfg` (inventory path + yaml plugin) и `Taskfile.yml` (ANSIBLE_INVENTORY). Старый `hosts.ini` оставлен для справки.

## Не решено

### Требуют верификации на VM

- [ ] **Molecule тесты не запущены** — локальный Python venv отсутствует (Windows). Для запуска на VM: `task bootstrap && task test`. Конфиги изменились — нужно прогнать тесты.

- [ ] **Верификация i3 exec_always** — нужно применить `chezmoi apply` на VM и проверить что `i3 restart` корректно перезапускает dunst/nm-applet/greenclip без дублей процессов.

- [ ] **Верификация pam_faillock** — нужно запустить `task run` на VM и проверить что `sudo` больше не показывает pam_faillock warnings.

- [ ] **Удалить hosts.ini** — после проверки YAML inventory на VM можно удалить `ansible/inventory/hosts.ini`.

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `dotfiles/dot_config/picom.conf.tmpl` | Верифицирован — FT-Labs animation format корректен, все опции совместимы с picom-ftlabs-git vgit-df4c6 |
| VM: `~/.config/picom.conf` | Перезаписан через chezmoi apply с корректным конфигом |
| `dotfiles/dot_config/i3/config.tmpl` | dunst/nm-applet/greenclip → `exec_always` с `pkill -x` |
| `ansible/roles/base_system/tasks/archlinux.yml` | Добавлен таск pam_faillock (`/etc/security/faillock.conf`) |
| `ansible/inventory/hosts.yml` | Создан YAML inventory (замена hosts.ini) |
| `ansible/ansible.cfg` | Обновлён путь inventory + yaml plugin |
| `Taskfile.yml` | Обновлён `ANSIBLE_INVENTORY` path |

## Инкрементальное тестирование picom

Каждый этап запускался отдельно, picom оставался стабильным:

| Этап | Добавленные опции | Результат |
|------|-------------------|-----------|
| 1 | `backend = "glx"; vsync = true;` | OK |
| 2 | + corner-radius, shadows, shadow-exclude | OK |
| 3 | + opacity, opacity-rule | OK |
| 4 | + blur (dual_kawase, strength=5), blur-background-exclude | OK |
| 5 | + animations (FT-Labs: zoom, slide-down, stiffness, dampening) | OK |
| 6 | + fading (fade-in/out-step, fade-delta) | OK |
| 7 | + wintypes (tooltip, dock с clip-shadow-above, popup_menu) | OK |
| 8 | + blur-background, blur-background-frame, glx-no-rebind-pixmap, shadow-color, rounded-corners-exclude, Polybar excludes | OK |

## Итог

Picom-ftlabs-git исправлен и стабильно работает с полным набором эффектов. Десктоп стек полностью функционален: i3-rounded + picom (blur, анимации, скруглённые углы) + polybar + dunst. Дополнительно исправлены: i3 autostart (exec_always для демонов), pam_faillock (Ansible таск), inventory (INI → YAML). Требуется верификация на VM: `chezmoi apply`, `task run`, `task test`.
