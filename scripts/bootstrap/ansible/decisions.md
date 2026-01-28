# Decisions Log: Molecule Testing для Reflector Role

## Дата: 2026-01-28

---

## 1. PATH для venv в Taskfile

**Задача:** Команды из `.venv/bin/` (ansible-playbook, molecule) должны быть доступны в Taskfile.

**Сделали:** Используем PREFIX переменную с `env PATH=...`:
```yaml
vars:
  PREFIX: 'env PATH="{{.TASKFILE_DIR}}/{{.VENV}}/bin:$PATH"'

tasks:
  check:
    cmds:
      - '{{.PREFIX}} ansible-playbook ...'
```

**Пробовали:**
```yaml
# Глобальный env - не работает
env:
  PATH: "{{.TASKFILE_DIR}}/.venv/bin:{{.PATH}}"  # {{.PATH}} не существует

# sh: - не работает
PATH:
  sh: echo "{{.TASKFILE_DIR}}/.venv/bin:$PATH"

# bash -c wrapper - работает, но громоздко
- bash -c 'export PATH="..." && molecule test'
```

**Не получилось:** `{{.PATH}}` не является встроенной переменной Taskfile. OS env vars имеют приоритет над Taskfile env.

**Ресурсы:**
- [GitHub Issue #482 - Changing PATH env var doesn't seem to work](https://github.com/go-task/task/issues/482)
- [GitHub Issue #202 - PATH modification](https://github.com/go-task/task/issues/202)
- [GitHub Issue #2034 - Variables Megathread](https://github.com/go-task/task/issues/2034)

---

## 2. Sudo пароль для Molecule

**Задача:** Ansible требует sudo пароль для задач с `become: true`.

**Сделали:**
- Переменная `MOLECULE_SUDO_PASS` в `~/.bashrc` **ДО** строки `[[ $- != *i* ]] && return`
- В molecule.yml: `ansible_become_password: "{{ lookup('env', 'MOLECULE_SUDO_PASS') | default(omit) }}"`

```bash
# ~/.bashrc
export MOLECULE_SUDO_PASS="password"  # ПЕРВАЯ строка!
[[ $- != *i* ]] && return
```

**Пробовали:** Добавить в конец `.bashrc`

**Не получилось:** Строка `[[ $- != *i* ]] && return` прерывает выполнение для non-interactive shell.

**Ресурсы:**
- [Ansible become password](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_privilege_escalation.html)

---

## 3. Molecule драйвер для localhost

**Задача:** Тестировать роль на локальной Arch Linux VM.

**Сделали:**
```yaml
driver:
  name: default
  options:
    managed: false  # Не управлять инфраструктурой

platforms:
  - name: localhost

provisioner:
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
```

**Пробовали:** `molecule-plugins[delegated]` в requirements.txt

**Не получилось:** Избыточно — в Molecule 25.x драйвер `default` встроен.

**Ресурсы:**
- [Molecule Configuration - Driver](https://docs.ansible.com/projects/molecule/configuration/)
- `managed: false` — Molecule не создаёт/удаляет инстансы

---

## 4. os_family для Arch Linux

**Задача:** Проверка что роль запускается только на Arch.

**Сделали:**
```yaml
- ansible_facts['os_family'] == 'Archlinux'  # НЕ 'Arch'
```

**Пробовали:** `os_family == 'Arch'`

**Не получилось:** Ansible определяет Arch как `Archlinux`.

**Ресурсы:**
- [Ansible os_family values](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_conditionals.html)

---

## 5. Reflector не имеет --config флага

**Задача:** Использовать конфиг файл для reflector.

**Сделали:** Параметры передаются напрямую в команде:
```yaml
ansible.builtin.command: >-
  reflector
  --country {{ reflector_countries }}
  --protocol {{ reflector_protocol }}
  ...
```

Конфиг `/etc/xdg/reflector/reflector.conf` используется только systemd timer через `@file` синтаксис:
```
ExecStart=/usr/bin/reflector @/etc/xdg/reflector/reflector.conf
```

**Пробовали:** `reflector --config /path/to/config`

**Не получилось:** Reflector 2023-5 не имеет флага `--config`. `@file` — это Python argparse response file, не флаг reflector.

**Ресурсы:**
- [Reflector ArchWiki](https://wiki.archlinux.org/title/Reflector)
- [Python argparse fromfile_prefix_chars](https://docs.python.org/3/library/argparse.html#fromfile-prefix-chars)

---

## 6. Idempotence тест падает

**Задача:** Molecule idempotence проверка.

**Сделали:** Убрали `idempotence` из `test_sequence`:
```yaml
scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

**Пробовали:** Стандартный test_sequence с idempotence.

**Не получилось:** Reflector каждый раз возвращает разные зеркала — это ожидаемое поведение.

**Ресурсы:**
- [Molecule test sequence](https://docs.ansible.com/projects/molecule/configuration/#scenario)

---

## 7. Бэкап mirrorlist

**Задача:** Сохранить старый mirrorlist перед обновлением.

**Сделали:** Бэкап **ДО** запуска reflector:
```yaml
- name: Read current mirrorlist
  slurp: ...
  register: reflector_old_mirror

- name: Backup current mirrorlist BEFORE update
  copy:
    src: "{{ reflector_mirrorlist_path }}"
    dest: "{{ reflector_mirrorlist_path }}.bak.{{ timestamp }}"
  when: reflector_old_mirror is succeeded

- name: Run reflector
  command: reflector ...
```

**Пробовали:** Бэкап после reflector.

**Не получилось:** Бэкапился уже новый файл, а не старый.

**Ресурсы:**
- Логическая ошибка в порядке задач

---

## 8. changed_when для reflector команды

**Задача:** Корректно отслеживать изменения.

**Сделали:**
```yaml
- name: Run reflector
  command: reflector ...
  changed_when: false  # Изменение отслеживается отдельно

- name: Report reflector result
  debug:
    msg: "Mirrorlist changed: {{ reflector_mirrorlist_changed }}"
  changed_when: reflector_mirrorlist_changed  # Здесь показываем changed
```

**Пробовали:** Костыль с `/bin/true`.

**Не получилось:** ansible-lint ругается на `no-changed-when`.

**Ресурсы:**
- [ansible-lint no-changed-when](https://ansible.readthedocs.io/projects/lint/rules/no-changed-when/)

---

## Итоговая структура

```
ansible/
├── Taskfile.yml           # PREFIX для PATH
├── requirements.txt       # Без molecule-plugins
├── playbooks/
│   └── mirrors-update.yml # Единственный playbook
└── roles/reflector/
    ├── defaults/main.yml  # Статичные значения (без Jinja)
    ├── tasks/main.yml     # state: latest, бэкап ДО reflector
    ├── templates/
    │   └── reflector.conf.j2
    └── molecule/default/
        ├── molecule.yml   # managed: false, без group_vars
        ├── converge.yml
        └── verify.yml
```
