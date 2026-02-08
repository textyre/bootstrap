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

**Задача:** Настройка начального bootstrap окружения

**Проблемы:**
1. Ansible не установлен на свежей системе
2. Vault password не настроен
3. Python venv отсутствует

**Решение:** bootstrap.sh автоматизация:
```bash
# Проверка Arch Linux
# Установка ansible + go-task
# Запрос vault password
# Создание venv
# Запуск playbook
```

**Vault setup:**
```bash
# Первый запуск
./bootstrap.sh  # запросит пароль, сохранит в ~/.vault-pass

# Альтернатива через pass
pass insert ansible/vault-password
```

---

## Типичные проблемы и решения

### SSH "Permission denied"

**Проблема:** SSH отказывает в доступе

**Решение:**
```bash
# Проверить права
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys

# Проверить ключ
ssh-add -l

# Проверить sshd config
sudo systemctl status sshd
```

### LightDM черный экран

**Проблема:** LightDM не запускается или черный экран

**Решение:**
```bash
# Проверить логи
sudo journalctl -u lightdm
cat /var/log/Xorg.0.log | grep "(EE)"

# Проверить display-setup-script
ls -la /etc/lightdm/lightdm.conf.d/

# Переключиться на TTY
Ctrl + Alt + F2

# Перезапустить
sudo systemctl restart lightdm
```

### Polybar не отображается

**Проблема:** Polybar не видим после login

**Решение:**
```bash
# Проверить процессы
ps aux | grep polybar

# Запустить вручную
~/.config/polybar/launch.sh

# Проверить логи
tail -f ~/.local/share/polybar.log

# Проверить i3 config
grep polybar ~/.config/i3/config
```

### Ansible vault ошибка

**Проблема:** "Decryption failed" при запуске playbook

**Решение:**
```bash
# Проверить vault-pass.sh
ls -la ansible/vault-pass.sh
chmod +x ansible/vault-pass.sh

# Проверить ~/.vault-pass
cat ~/.vault-pass
chmod 600 ~/.vault-pass

# Или использовать pass
pass show ansible/vault-password
```

### Molecule тесты падают

**Проблема:** Molecule тесты не проходят

**Решение:**
```bash
# Очистить старые контейнеры
molecule destroy

# Проверить vault password
echo 'test_password' > ~/.vault-pass

# Запустить с verbose
molecule --debug test

# Проверить специфичную роль
molecule test -s default
```

---

## Полезные команды для отладки

```bash
# Проверить состояние системы
systemctl status
journalctl -xe

# Проверить X-сервер
cat ~/.local/share/xorg/Xorg.0.log
xrandr --verbose

# Проверить SSH
ssh -vvv user@host

# Проверить Ansible
ansible-playbook --syntax-check playbooks/workstation.yml
ansible-playbook --check playbooks/workstation.yml

# Проверить i3
i3-msg -t get_tree
i3-msg -t get_workspaces
```

---

Назад к [[Home]]
