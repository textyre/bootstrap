# Troubleshooting History

Консолидированный лог устранения неисправностей, организованный по датам.

## 2026-02-07: Picom Rules, Opacity, GTK Menu Styling

**Задача:** Настройка picom rules (opacity, animations), исправление opacity leaks, rounded corners на GTK3 context menus

**Решено (6 проблем):**
1. **A/B тестирование анимаций** — 13 экспериментов, найден стабильный конфиг (appear/disappear 0.2s, glx backend)
2. **Backend xrender vs glx** — xrender визуально медленнее для анимаций, вернули glx
3. **Opacity leak на dock/desktop/GTK** — default rule без match применял opacity ко всем; добавлен explicit `opacity = 1`
4. **Thunar context menu opacity** — перенесён rule после popup_menu (порядок rules имеет значение)
5. **GTK3 context menu rounded corners** — синхронизация GTK CSS + picom corner-radius (рецепт из adw-gtk3 #100)
6. **Rules порядок и приоритет** — задокументировано что поздние rules перезаписывают ранние

**Известные ограничения:**
- Open-анимация не работает в VM (BUG [#1393](https://github.com/yshui/picom/issues/1393) + software rendering)
- GTK3 menu hover может выступать за border-radius (ограничение GTK3)

**Ключевые выводы:**
- Picom `rules:` — последовательный приоритет (поздние перезаписывают)
- GTK CSS + picom corner-radius должны быть синхронизированы
- `!important` не поддерживается в GTK CSS
- Thunar 4.20 использует GTK3, не GTK4

**Файлы:** picom.conf.tmpl, gtk-3.0/gtk.css.tmpl, gtk-4.0/gtk.css.tmpl

**Документация:** [[Picom-Configuration]], [[GTK-CSS-Reference]]

---

## 2026-02-05: Ewwii — начальная настройка

**Задача:** Настройка ewwii status bar (замена Polybar)

**Решено:**
- Single transparent dock window с тремя островами
- External SCSS (community standard, файл `ewwii.scss`)
- Workspaces через i3 IPC + JSON
- Chezmoi templating для тем и layout
- `GSK_RENDERER=cairo` для экономии RAM

**Ключевые открытия:**
- CSS файл должен называться `ewwii.scss`, не `eww.scss`
- `space_evenly: false` обязателен на каждом box-виджете
- Leaf widgets (button, label) определяют ширину по контенту

**Документация:** [[Ewwii-Architecture]]

---

## 2026-02-05: Polybar Workspaces Analysis

**Задача:** Полный анализ конфигурации Polybar для документации

**Проведен анализ:**
- 1 главный конфиг + 7 скриптов
- 4 бара (workspaces, workspace-add, clock, system)
- 9 модулей (6 internal, 3 custom)
- 2 цветовые схемы (dracula, monochrome)

**Идентифицирован технический долг:**
- EDGE_PADDING=12 захардкожен в 3 местах
- Полный polybar restart вместо hot reload
- Динамическая ширина не полностью верифицирована

**Результат:** Созданы 4 документа:
- POLYBAR_FULL_ANALYSIS_SUMMARY.md
- polybar-detailed-analysis.md
- polybar-quick-reference.md
- polybar-architecture-diagram.md

**Документация:** [[Polybar-Architecture]]

---

## 2026-02-02: Major Configuration Refactoring

**Задача:** Рефакторинг структуры проекта и Ansible ролей

**Изменения:**
1. Миграция с кастомного Python на 13 Ansible ролей
2. Отделение данных (packages.yml) от логики (роли)
3. Добавлена роль `vm` для определения окружения
4. Мульти-дистро поддержка через OS-specific tasks
5. Улучшен SSH hardening
6. Обновлена безопасность firewall

**Новые роли:**
- base_system, vm, user, ssh, git, shell, docker, firewall, xorg, lightdm

**Удалено:**
- Кастомный Python-код для deploy (15 файлов, ~500 LOC)
- Старые bash-скрипты bootstrap
- scripts/lib/ директория

**Результат:** Полностью модульная архитектура

---

## 2026-02-01: VM Role и Environment Detection

**Задача:** Определение VM окружения для специфичных настроек

**Проблема:** Bare metal и VM требуют разных настроек (drivers, services)

**Решение:** Новая роль `vm` с определением окружения:
- Детект через dmidecode (VirtualBox, VMware, QEMU, KVM)
- Установка guest additions для VM
- Пропуск драйверов GPU на VM

**Реализация:**
```yaml
- name: Detect VM environment
  command: dmidecode -s system-product-name
  register: vm_detect

- name: Set VM facts
  set_fact:
    is_vm: "{{ 'VirtualBox' in vm_detect.stdout or 'VMware' in vm_detect.stdout }}"
```

**Статус:** Внедрено в ansible/roles/vm/

---

## 2026-02-01: Driver Configuration Issues

**Задача:** Настройка GPU драйверов для VM

**Проблема:** VMware SVGA конфликты с modesetting

**Решение:**
- Использовать modesetting driver для VM (DRM/KMS)
- Для bare metal: определять GPU и устанавливать соответствующий драйвер
- xf86-video-vmware только если явно требуется

**Конфигурация Xorg:**
```
Section "Device"
    Identifier "Card0"
    Driver "modesetting"  # Универсальный для VM
EndSection
```

**Документация:** [[Xorg-Configuration]]

---

## 2026-01-31: Initial Bootstrap Setup

**Задача:** Настройка начального bootstrap окружения и локального источника Vault credentials.

Ранние самостоятельные bootstrap scripts заменены текущим запуском OpenStrap и контейнерным Control Plane. Исторические команды не используются для deployment; актуальные инструкции находятся в [[Usage]] и [Bootstrap Secrets](../docs/bootstrap-secrets.md).

---

## Типичные проблемы и решения

Ниже — диагностика текущего OpenStrap/container запуска. Записи выше описывают историю проекта.

### CLI или SSH недоступны

Из `D:/projects/bootstrap`:

```powershell
openstrap plugins
openstrap list --local
openstrap connect ansible-control --local --run "cat /etc/os-release"
openstrap connect bootstrap-target --local --run "id -un"
```

Проверьте установленный CLI, runtime plugin imports, явно выбранный target, SSH port и локальную identity. Target/controller используют Windows ports `2251`/`2252`; контейнер подключается к target через общую приватную сеть. Не назначайте protected `arch` default host и не меняйте source snapshot.

Если после роли user пропал SSH, проверьте порядок установки login shell до назначения аккаунту. Исправьте роль локально; повторное применение или fresh target выбираются по задаче. Не ремонтируйте source VM вручную и не отключайте host key checking.

### Docker или контейнер недоступен

Cloud-init устанавливает Docker, инициализирует single-node Swarm с route-local IP и создаёт host-network service `bootstrap-control-plane` с одной replica и persistent home. OpenStrap проверяет `1/1`, доставляет sudo и private key через stdin в native Docker secrets и выполняет один workstation Docker exec. Secret rotation заменяет service task, сохраняя home; новый образ выбирается отдельным действием.

Cloud-init работает от root, readiness/rotation/exec используют non-interactive sudo. Проверьте `docker service ps bootstrap-control-plane` и `docker service ls` replicas `1/1`. Existing VM не принимает changed cloud-init и не преобразует standalone container в Swarm; image/controller update выбирается явно.

### Native secret или sudo недоступен

Проверьте OS keychain service `bootstrap` и текущий target sudo-пароль. Замените `BOOTSTRAP_TARGET_SUDO_PASSWORD` через `openstrap secret set NAME` со скрытым вводом. Secret Service нужен на Linux, Keychain на macOS, Credential Manager на Windows.

Ansible Vault и adapter удалены. Blueprint создаёт native Swarm secret через stdin и монтирует password/key `/run/secrets` mode `0400`. При update failure проверьте native service status/rollback; secret contents не выводите. См. [Bootstrap Secrets](../docs/bootstrap-secrets.md).

### SSH secret или host key

Ansible читает `/run/secrets/ssh-key` через native `--private-key`. Проверьте наличие mount и root mode `0400` без вывода contents. Public host/port/user читаются из exec environment; private key env не используется.

`StrictHostKeyChecking=accept-new` принимает новые host keys и отклоняет изменившиеся. Known hosts сохраняются в `/root/.ssh/known_hosts` внутри persistent home. При mismatch сначала подтвердите причину изменения и target identity; не отключайте проверку и не удаляйте файл для маскировки ошибки.

### LightDM, containers или HTTPS

Проверьте фактический recap и ARA. Дополнительная диагностика с явным target:

```powershell
openstrap connect bootstrap-target --local --run "systemctl is-active lightdm docker fail2ban sshd"
```

ARA и Ansible output доступны для progress и ошибок; SQLite читается read-only. Исправьте соответствующую роль в source. Ручной service restart не должен подменять результат применения Ansible.

### Molecule или lint

Syntax/lint и ARA выполняются native Docker exec внутри текущей service task; команды приведены в [Ansible README](../ansible/README.md). Корневые Taskfile и Compose wrappers удалены; target-role Compose остаётся. Molecule работает в существующих `.github/workflows/molecule.yml` и `molecule-vagrant.yml`; controller не устанавливает Molecule.

Molecule работает в существующих `.github/workflows/molecule.yml` и `molecule-vagrant.yml`; запуск CI отдельный. Syntax/lint/full deployment не подтверждают все Molecule scenarios.

Сохраняйте полезный command/exit/error; unexecuted checks отмечайте unverified. Обычный запуск применяет workstation один раз. Повторное применение и проверка идемпотентности выбираются отдельно.

## Полезные read-only проверки

```powershell
openstrap connect bootstrap-target --local --run "uname -r"
openstrap connect ansible-control --local --run "sudo -n docker volume inspect bootstrap-control-plane-home"
```

Подробнее — [[Usage]] и [Test VM Workflow](standards/test-vm-workflow.md).

---

Назад к [[Home]]
