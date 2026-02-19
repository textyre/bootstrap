# Design: keymap role improvement

**Date:** 2026-02-19
**Scope:** `ansible/roles/keymap`
**Approach:** A + B — точечные фиксы + доведение до уровня `locale` роли

---

## Context

Роль `keymap` настраивает раскладку клавиатуры TTY/консоли в Phase 1 (system foundation) через init-диспатч (`with_first_found`). Поддерживает systemd, openrc, runit.

**Найденные пробелы:**
- Verify существует только для systemd
- Molecule тест ограничен Arch Linux, хотя `meta/main.yml` заявляет Debian/Ubuntu/EL/Alpine
- Нет handler для немедленного применения (без ребута)
- Шрифтовые переменные закомментированы в defaults — не видны пользователю
- Verify для systemd потенциально fragile (substring match вместо regex по "VC Keymap:" строке)
- Нет validate-фазы до применения

---

## Business criteria

| Критерий | Приоритет |
|---|---|
| Идемпотентность | Critical |
| Корректность с первого раза | Critical |
| Немедленный эффект (без ребута) | High |
| Верификация для всех init-систем | High |
| Отказоустойчивость (unsupported init → warn) | High |
| Тестируемость на задекларированных платформах | Medium |
| Обнаруживаемость переменных | Medium |
| Валидация входных данных | Medium |

---

## File structure changes

```
keymap/
├── defaults/main.yml          # раскомментировать font-переменные
├── handlers/
│   └── main.yml              # НОВЫЙ
├── tasks/
│   ├── main.yml              # добавить validate-фазу + notify
│   ├── validate/
│   │   └── main.yml          # НОВЫЙ
│   ├── init/
│   │   ├── systemd.yml       # добавить notify: apply keymap
│   │   ├── openrc.yml        # добавить notify: apply keymap
│   │   └── runit.yml         # добавить notify: apply keymap
│   └── verify/
│       ├── systemd.yml       # улучшить: regex по "VC Keymap:" строке
│       ├── openrc.yml        # НОВЫЙ
│       └── runit.yml         # НОВЫЙ
└── molecule/default/
    └── converge.yml          # убрать assert os_family == Archlinux
```

---

## Design decisions

### 1. Validate phase

Новый `tasks/validate/main.yml` — выполняется до apply:

```yaml
- name: Assert keymap_console is defined and non-empty
  ansible.builtin.assert:
    that:
      - keymap_console is defined
      - keymap_console | length > 0
    fail_msg: "keymap_console must be set (e.g. 'us', 'ru')"
```

Не проверяем существование раскладки в `/usr/share/kbd/keymaps/` — пакет `kbd` может отсутствовать.

### 2. Handler — немедленное применение

Один listen-хендлер, разная реализация по init:

```yaml
- name: Apply console keymap (systemd)
  ansible.builtin.systemd:
    name: systemd-vconsole-setup.service
    state: restarted
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] == 'systemd'

- name: Apply console keymap (openrc/runit)
  ansible.builtin.command: "loadkeys {{ keymap_console }}"
  listen: "apply keymap"
  when: ansible_facts['service_mgr'] in ['openrc', 'runit']
  failed_when: false
  changed_when: false
```

`failed_when: false` для openrc/runit — `loadkeys` может отсутствовать в CI/контейнерах.

### 3. Verify для openrc и runit

`tasks/verify/openrc.yml`:
```yaml
- name: Verify console keymap (openrc)
  ansible.builtin.command: "grep -i 'keymap=\"{{ keymap_console }}\"' /etc/conf.d/keymaps"
  register: _keymap_check_openrc
  changed_when: false
  failed_when: _keymap_check_openrc.rc != 0
```

`tasks/verify/runit.yml`:
```yaml
- name: Verify console keymap (runit)
  ansible.builtin.command: "grep -i 'KEYMAP={{ keymap_console }}' /etc/rc.conf"
  register: _keymap_check_runit
  changed_when: false
  failed_when: _keymap_check_runit.rc != 0
```

### 4. Systemd verify — уточнить regex

Было: `keymap_console in _keymap_check.stdout` — даёт false positive если имя раскладки встречается в другом поле.

Стало:
```yaml
- name: Assert keymap is set (systemd)
  ansible.builtin.assert:
    that:
      - "_keymap_check.stdout | regex_search('VC Keymap:\\s+' + keymap_console)"
    fail_msg: "Keymap '{{ keymap_console }}' not found in localectl status"
    quiet: true
```

### 5. Defaults — раскомментировать font-переменные

```yaml
keymap_console: "us"
keymap_console_font: ""
keymap_console_font_map: ""
keymap_console_font_unimap: ""
```

Пустая строка = не применять (template уже использует `| default('')`).

### 6. main.yml — добавить validate-фазу

```yaml
- name: Validate keymap configuration
  ansible.builtin.include_tasks: validate/main.yml
  tags: ['keymap']

- name: Configure console keymap ...
  # ... существующий диспатч
```

### 7. Molecule — убрать Arch-ограничение

Удалить из `converge.yml` `pre_tasks` с `assert os_family == Archlinux`. Тест работает на любой системе с systemd.

---

## Out of scope

- X11/Wayland keymap (xkb) — отдельная ответственность, не TTY
- Валидация по списку допустимых раскладок (`/usr/share/kbd/keymaps/`) — требует `kbd` как зависимость
- Мульти-сценарийные Molecule тесты (openrc/runit контейнеры) — отдельная задача

---

## Summary

7 изменений, все хирургические. Архитектура не меняется. После реализации роль соответствует всем business criteria.
