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

## 2. Sudo пароль для Ansible (Ansible Vault)

**Задача:** Ansible требует sudo пароль для задач с `become: true`. Нужно безопасное решение, работающее через SSH сессии.

**Сделали:** Ansible Vault — пароль зашифрован (AES-256), безопасен для git.

1. `inventory/group_vars/all/vault.yml` — зашифрованный файл с `ansible_become_password`
2. `vault-pass.sh` — каскадный скрипт для vault пароля: `pass` → `~/.vault-pass` → ошибка
3. `ansible.cfg` → `vault_password_file = ./vault-pass.sh`
4. Molecule: `config_options.defaults.vault_password_file` + `vars_files` в converge/verify

```bash
# Первоначальная настройка (один раз):
echo 'vault_password' > ~/.vault-pass && chmod 600 ~/.vault-pass
ansible-vault create inventory/group_vars/all/vault.yml
# Содержимое: ansible_become_password: "your_sudo_password"

# Запуск тестов — пароль не нужен:
task test

# После bootstrap: vault пароль можно перенести в pass
pass insert ansible/vault-password
```

**Пробовали:**
1. `MOLECULE_SUDO_PASS` в `~/.bashrc` — не работает через SSH (non-interactive shell), небезопасно
2. `sudo -v` + keep-alive — не сохраняется между SSH сессиями
3. Environment variable — не персистентна, требует `.bashrc` хаки

**Почему Ansible Vault:**
- Шифрование AES-256, безопасен для git
- Работает через SSH (файл на диске, не в памяти)
- Разделение паролей (vault пароль ≠ sudo пароль)
- CI/CD: `ANSIBLE_VAULT_PASSWORD_FILE` env var
- Enterprise стандарт (Red Hat, AWS)

**Ресурсы:**
- [Ansible Vault](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
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

## 9. Централизация пакетов в group_vars/all/packages.yml

**Задача:** Убрать дублирование пакетов между ролями и отделить данные от логики.

**Проблема:**
- `base-devel`, `git` — дублировались в `packages/defaults/main.yml` и хардкод в `yay/tasks/main.yml`
- `go` — хардкод в `yay/tasks/main.yml` без переменной
- Все данные привязаны к роли `packages`, нет разделения "код vs данные"

**Сделали:** Перенесли все пакетные переменные в `inventory/group_vars/all/packages.yml`:
1. `packages_*` переменные (из `roles/packages/defaults/main.yml` — файл удалён)
2. `yay_*` переменные (из `roles/yay/defaults/main.yml` — файл удалён)
3. `yay_build_deps` — новая переменная, заменила хардкод в `yay/tasks/main.yml`

**Как роли работают standalone:**
- `ansible.cfg` задаёт `inventory = ./inventory/hosts.ini`
- Ansible автоматически подхватывает `inventory/group_vars/all/*.yml`
- Molecule: переменные задаются в `molecule.yml` provisioner `group_vars`

**Почему `group_vars/all/`:**
- Ansible-стандартное место для "data layer" (данные отдельно от логики)
- Precedence уровень 4: выше role defaults (2), ниже host_vars (8) и `-e` (22)
- Per-host override: создать `inventory/host_vars/<hostname>/packages.yml`

**Почему reflector не тронули:**
- Пакет `reflector` = идентичность роли, параметризация бессмысленна

**Ресурсы:**
- [Ansible Sample Setup](https://docs.ansible.com/projects/ansible/latest/tips_tricks/sample_setup.html)
- [Red Hat CoP — Good Practices](https://redhat-cop.github.io/automation-good-practices/)
- [Ansible Variable Precedence](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_variables.html)

---

## Итоговая структура

```
ansible/
├── Taskfile.yml           # PREFIX для PATH
├── ansible.cfg            # vault_password_file = ./vault-pass.sh
├── vault-pass.sh          # Каскадный resolver: pass → ~/.vault-pass → error
├── requirements.txt       # Без molecule-plugins
├── inventory/
│   ├── hosts.ini
│   └── group_vars/all/
│       ├── vault.yml      # Зашифрованный ansible_become_password (Ansible Vault)
│       └── packages.yml   # Центральный реестр пакетов (data layer)
├── playbooks/
│   ├── mirrors-update.yml
│   └── workstation.yml
└── roles/*/
    ├── tasks/main.yml
    └── molecule/default/
        ├── molecule.yml   # vault_password_file + group_vars для тестов
        ├── converge.yml   # vars_files → vault.yml
        └── verify.yml     # vars_files → vault.yml
```
