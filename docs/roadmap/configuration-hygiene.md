# Configuration Hygiene Roadmap

Устранение технического долга в конфигурации Ansible: пути, валидация, источники правды.

Основано на аудите [RelativePaths.md](../SubAgent%20docs/RelativePaths.md) и анализе индустриальных практик (AWS, Netflix, Habr community).

---

## Текущее состояние

Документ `RelativePaths.md` описывает **предыдущую** версию кода. Рекомендации из него уже частично реализованы:
- `Taskfile.yml` задаёт env vars (`REPO_ROOT`, `ANSIBLE_CONFIG`, `ANSIBLE_ROLES_PATH`, `ANSIBLE_INVENTORY`, `ANSIBLE_VAULT_PASSWORD_FILE`)
- `system.yml` использует `lookup('env', 'REPO_ROOT')` вместо `inventory_dir`
- Role defaults используют `lookup('env', 'REPO_ROOT')` вместо `role_path`

Однако реализация создала **новые проблемы**, описанные ниже.

---

## Приоритет 1: Единый источник правды для путей

**Проблема:** `ansible.cfg` содержит относительные пути, а `Taskfile.yml` перекрывает их через env vars. Два конфликтующих источника конфигурации — классический configuration drift.

**Обоснование:**
- [Ansible docs](https://docs.ansible.com/ansible/latest/reference_appendices/general_precedence.html) — env vars имеют высший приоритет над `ansible.cfg`, создавая невидимый слой
- [Habr: «Управление многоступенчатым окружением»](https://habr.com/ru/articles/537126/) — `ansible.cfg` должен быть self-sufficient с безопасными defaults
- [Spacelift](https://spacelift.io/blog/ansible-configuration-drift-management) — дублирование конфигурации = configuration drift

**Чеклист:**

- [ ] Решить: `ansible.cfg` — единственный источник путей, env vars — только для выбора окружения
- [ ] Убрать `ANSIBLE_ROLES_PATH`, `ANSIBLE_INVENTORY`, `ANSIBLE_VAULT_PASSWORD_FILE` из `Taskfile.yml` env-блока
- [ ] Оставить `ANSIBLE_CONFIG` в Taskfile — он указывает **какой** файл загрузить
- [ ] Перенести `retry_files_enabled`, `host_key_checking`, `localhost_warning` и прочие settings в единый `ansible.cfg`
- [ ] Добавить комментарий в `ansible.cfg`: запуск только из `ansible/` директории (или через Taskfile)

---

## Приоритет 2: Fail fast — валидация `REPO_ROOT`

**Проблема:** если запустить `ansible-playbook` без Taskfile, `REPO_ROOT` не задан, и `dotfiles_base_dir` станет `/dotfiles` — тихая ошибка.

**Обоснование:**
- [Habr: «Как запилить годную ролюху»](https://habr.com/ru/articles/909636/) — `assert` + `fail` в pre_tasks для проверки пререквизитов
- [Habr: «Основы Ansible, часть 3»](https://habr.com/ru/articles/512036/) — оппортунистическая типизация: ошибки в переменных вылезают поздно и непредсказуемо
- [Puppeteers.net](https://www.puppeteers.net/blog/ansible-quality-assurance-part-1-ansible-variable-validation-with-assert/) — пирамида валидации: `is defined` → type check → value check
- [Ansible docs: argument_specs](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/validate_argument_spec_module.html) — декларативная валидация до начала тасков

**Чеклист:**

- [ ] Добавить `pre_tasks` в playbook с assert:
  ```yaml
  pre_tasks:
    - name: Validate REPO_ROOT is set
      ansible.builtin.assert:
        that:
          - lookup('env', 'REPO_ROOT') | length > 0
        fail_msg: "REPO_ROOT not set. Run via 'task run' or export REPO_ROOT manually."
    - name: Validate dotfiles directory exists
      ansible.builtin.assert:
        that:
          - dotfiles_base_dir is directory
        fail_msg: "dotfiles directory not found at {{ dotfiles_base_dir }}"
  ```
- [ ] Добавить precondition в `Taskfile.yml`: `test -d {{.TASKFILE_DIR}}/dotfiles`
- [ ] Рассмотреть `meta/argument_specs.yml` для ролей chezmoi, lightdm, xorg (декларативная валидация входных переменных)

---

## Приоритет 3: Тильда `~` в `roles_path`

**Проблема:** `ansible.cfg` содержит `~/.ansible/roles`. При `become: true` тильда может резолвиться в `/root` вместо домашней директории пользователя.

**Обоснование:**
- [Habr: «Домашняя директория пользователя в Ansible»](https://habr.com/ru/articles/575880/) — целая статья о проблеме. `~` и `ansible_user_dir` дают разные результаты при become. Ansible использует `UserFactCollector` → `pwd.getpwnam()` → `pw_dir`
- [GitHub issue #48818](https://github.com/ansible/ansible/issues/48818) — tilde expansion resolves to master user instead of managed node user
- [GitHub issue #82490](https://github.com/ansible/ansible/issues/82490) — creating user directory using tilde always reports «changed»

**Чеклист:**

- [ ] Проверить, используется ли `~/.ansible/roles` реально (скорее всего нет)
- [ ] Если не используется — убрать из `roles_path`
- [ ] Если используется — заменить на абсолютный путь или `$HOME/.ansible/roles`

---

## Приоритет 4: Аудит Molecule-конфигов

**Проблема:** `RelativePaths.md` не анализирует `molecule.yml` файлы, хотя пути в них — частый источник ошибок.

**Обоснование:**
- [Habr: Molecule тестирование, часть 1 (Slurm)](https://habr.com/ru/companies/slurm/articles/711432/) — настройка путей в molecule.yml критична
- [Habr: Ostrovok.ru — тестирование ролей](https://habr.com/ru/companies/ostrovok/articles/448136/) — подводные камни с путями и окружением при CI/CD
- [Ansible forum](https://forum.ansible.com/t/molecule-how-to-include-local-roles-path-to-test-playbook/10547) — частые вопросы про пути

**Чеклист:**

- [ ] Проверить `molecule/*/molecule.yml` во всех 17 ролях на хардкод-пути
- [ ] Убедиться что `MOLECULE_PROJECT_DIRECTORY` из Taskfile достаточен
- [ ] Проверить `provisioner.config_options` и `provisioner.inventory` в molecule-конфигах

---

## Приоритет 5: Архивация документа RelativePaths.md

**Проблема:** документ описывает предыдущую версию кода. Windows-пути (`d:\projects\bootstrap\`), устаревшие значения (`hosts.ini` вместо `hosts.yml`, `./roles` вместо `roles`), нереализованные рекомендации вперемешку с уже применёнными.

**Обоснование:**
- [Habr: «Как начать тестировать Ansible и не слететь с катушек»](https://habr.com/ru/articles/500058/) — «начиная со второго коммита любой код становится legacy». Документация, отстающая от кода — technical debt

**Чеклист:**

- [ ] Пометить `RelativePaths.md` как `ARCHIVED` (или удалить)
- [ ] Зафиксировать текущий контракт: «Ansible запускается только через Taskfile» — в README или CLAUDE.md

---

## Контекст: Immutable Infrastructure

Для справки — альтернативный подход, к которому движется индустрия.

[Habr: «Почему я советую людям не учить Ansible»](https://habr.com/ru/articles/556868/):
- Серверы накапливают изменения → «снежинки»
- Immutable infra сводит configuration drift к нулю
- Правило: **проблема → контекст → методология → инструмент**

[Netflix](https://leanpub.com/immutable-infrastructure-with-netflixoss) запекает конфиг в AMI-образы — вопрос «а что если переменная не задана» не возникает.

**Для данного проекта (персональный bootstrap для Arch Linux) Ansible уместен**, но fail fast и единый источник правды — обязательны, потому что immutable-гарантий нет.

---

## Источники

### Официальная документация
- [Ansible Configuration Precedence](https://docs.ansible.com/ansible/latest/reference_appendices/general_precedence.html)
- [Ansible Configuration Settings](https://docs.ansible.com/projects/ansible/latest/reference_appendices/config.html)
- [validate_argument_spec](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/validate_argument_spec_module.html)
- [Role Argument Specification](https://steampunk.si/blog/ansible-role-argument-specification/)

### Habr
- [«Домашняя директория пользователя в Ansible»](https://habr.com/ru/articles/575880/) — проблема тильды
- [«Как запилить годную ролюху»](https://habr.com/ru/articles/909636/) — assert, fail, валидация
- [«Основы Ansible, часть 3»](https://habr.com/ru/articles/512036/) — приоритеты переменных
- [«Управление многоступенчатым окружением»](https://habr.com/ru/articles/537126/) — разделение окружений
- [«44 совета по Ansible»](https://habr.com/ru/companies/slurm/articles/725788/) — best practices
- [«Почему я советую не учить Ansible»](https://habr.com/ru/articles/556868/) — immutable vs config sync
- [«Как начать тестировать и не слететь с катушек»](https://habr.com/ru/articles/500058/) — рефакторинг, Molecule
- [«Molecule — тестируем роли» (Slurm)](https://habr.com/ru/companies/slurm/articles/711432/) — Molecule best practices
- [«Пишем роли не ломая прод»](https://habr.com/ru/articles/746864/) — check_mode, идемпотентность

### Прочее
- [Ansible Variable Validation (Puppeteers.net)](https://www.puppeteers.net/blog/ansible-quality-assurance-part-1-ansible-variable-validation-with-assert/)
- [Configuration Drift Management (Spacelift)](https://spacelift.io/blog/ansible-configuration-drift-management)
- [Red Hat Good Practices](https://redhat-cop.github.io/automation-good-practices/)
- [Immutable Infrastructure with Netflix OSS](https://leanpub.com/immutable-infrastructure-with-netflixoss)
- [GitHub: tilde expansion issue #48818](https://github.com/ansible/ansible/issues/48818)
