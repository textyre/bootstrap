# Post-Mortem: Molecule CI для роли `sysctl`

**Дата:** 2026-03-01
**Статус:** Завершено — CI зелёный (Docker + vagrant arch-vm + vagrant ubuntu-base)
**Итерации CI (vagrant):** 2 запуска, 2 уникальных ошибки (обе найдены в первом прогоне)
**Коммиты:** `710a73a` → `13a06bf` (4 коммита), PR #7

---

## 1. Задача

Довести molecule-тесты роли `sysctl` до зелёного в трёх средах:

| Среда | Платформы | Что тестирует |
|-------|-----------|---------------|
| Docker (`molecule/docker/`) | Archlinux-systemd + Ubuntu-systemd | Конфиг деплоится, шаблон рендерится, пакеты ставятся |
| Vagrant arch-vm | `arch-base` box (KVM) | Полный тест: реальные значения sysctl применены |
| Vagrant ubuntu-base | `ubuntu-base` box (KVM) | То же на Ubuntu |

**Роль `sysctl`:** деплоит `/etc/sysctl.d/99-ansible.conf` с hardening-параметрами
(KSPP, CIS, DISA STIG), применяет их через `sysctl`, управляет опциональным набором
(fs.*, net.*, kernel.*), позволяет задавать кастомные параметры через `sysctl_custom_params`.

---

## 2. Инциденты

### Инцидент #1 — Docker: handler `sysctl -e --system` падает с EPERM

**Коммит фикса:** `710a73a`
**Прогон:** до PR (обнаружено при анализе кода)
**Этап:** `converge`
**Симптом:**
```
TASK [sysctl : Apply sysctl settings]
fatal: [Archlinux-systemd]: FAILED! => {"rc": 1, "msg": "..."}
```

**Причина:**

Обработчик в `handlers/main.yml` выполнял:
```yaml
ansible.builtin.command: sysctl -e --system
```

Флаг `-e` подавляет ошибки **ENOENT** (unknown key — параметр не поддерживается ядром),
но **не** подавляет ошибки **EPERM** (permission denied). Внутри Docker-контейнера —
даже с `privileged: true` и `cgroupns_mode: host` — параметры ядра
(`kernel.randomize_va_space`, `kernel.kptr_restrict`, `fs.protected_fifos` и др.) находятся
в read-only пространстве имён. Попытка записи → EPERM → `sysctl` завершается с ненулевым
кодом → `converge` падает.

Это не баг `sysctl`. Ядерные параметры в network namespace контейнера inherited от хоста
и доступны только для чтения. Даже `--privileged` даёт capabilities, но не новый UTS/kernel
namespace с writable sysctl.

**Существующий precedent в коде:**

`molecule/shared/verify.yml` уже обрабатывал это корректно:
```yaml
vars:
  _sysctl_in_container: "{{ ansible_virtualization_type | default('') == 'docker' }}"
...
# Tier 2: live values — пропускаем в контейнерах
- name: "Tier 2 | skip in container"
  when: _sysctl_in_container
```

Handler требовал аналогичного обращения.

**Фикс:**
```yaml
- name: Apply sysctl settings
  listen: "reload sysctl"
  ansible.builtin.command: sysctl -e -p /etc/sysctl.d/99-ansible.conf
  changed_when: false
  when: ansible_virtualization_type | default('') != 'docker'
```

Обработчик молча пропускается в Docker. В Vagrant KVM VM запускается нормально,
и любой реальный сбой поверхностен.

**Урок:** Любой handler, выполняющий запись kernel-параметров, должен иметь
`when: ansible_virtualization_type | default('') != 'docker'`. Это та же логика,
что и Tier 2 в verify.yml — держать их синхронизированными.

---

### Инцидент #2 — Все среды: `{% raise %}` не существует в Jinja2

**Коммит фикса:** `32eab2a`
**Прогон:** первый Docker CI (ansible-lint не поймал — это runtime ошибка шаблона)
**Этап:** `converge` (при рендере шаблона)
**Симптом:**
```
TASK [sysctl : Deploy sysctl configuration]
fatal: [Archlinux-systemd]: FAILED! =>
  {"msg": "AnsibleError: template error while templating string:
    Encountered unknown tag 'raise'. ..."}
```

**Причина:**

В `templates/sysctl.conf.j2`, строки 173–181:
```jinja2
{% if sysctl_custom_params | length > 0 %}
# ---- Custom parameters ----
{% for param in sysctl_custom_params %}
{%   if param.name is not defined or param.value is not defined %}
{%     raise "sysctl_custom_params entry missing 'name' or 'value': " ~ (param | string) %}
{%   endif %}
{{ param.name }} = {{ param.value }}
{% endfor %}
{% endif %}
```

`{% raise %}` — не стандартный блочный тег Jinja2. В стандартном Jinja2 не существует
тегов `raise`, `throw`, `error`. Jinja2 обрабатывает шаблон через парсинг сначала целиком,
и **на этапе парсинга** выбрасывает `TemplateSyntaxError: Encountered unknown tag 'raise'`
— **до того** как Jinja2 вычисляет условие `{% if sysctl_custom_params | length > 0 %}`.

Это означало, что ошибка возникала **во всех средах** при любом вызове template-таски,
даже когда `sysctl_custom_params = []` (по умолчанию в тестах). Ansible-lint не поймал
ошибку, потому что не рендерит шаблоны.

**Правильный инструмент:**

Ansible предоставляет фильтр `mandatory` именно для этой цели — выбросить ошибку если
значение не определено или пусто. Доступен с ansible-core 2.8.

**Фикс:**
```jinja2
{% if sysctl_custom_params | length > 0 %}
# ---- Custom parameters ----
{% for param in sysctl_custom_params %}
{{ param.name | mandatory("sysctl_custom_params[" ~ loop.index0 ~ "] is missing 'name'") }} = {{ param.value | mandatory("sysctl_custom_params[" ~ loop.index0 ~ "] is missing 'value'") }}
{% endfor %}
{% endif %}
```

Проверка `is not defined` убрана: фильтр `mandatory` возвращает значение если оно
определено и непусто, иначе выбрасывает ошибку с понятным сообщением. Inline-проверка
работает при итерации, а не при парсинге шаблона.

**Урок:** Jinja2 парсит шаблон целиком до вычисления условий. Нестандартные теги
(`raise`, `throw`) приводят к `TemplateSyntaxError` на этапе парсинга независимо от
ветки выполнения. Для ошибок валидации переменных в шаблонах — использовать
`{{ var | mandatory("message") }}`.

---

### Инцидент #3 — Ubuntu Vagrant: `fs.protected_fifos` ожидается 2, получено 1

**Коммит фикса:** `13a06bf`
**Прогон:** второй vagrant CI (arch-vm прошёл, ubuntu-base упал)
**Этап:** `verify`
**Симптом:**
```
TASK [Tier 2 | Assert sysctl live values match config]
failed: [ubuntu-base]: FAILED! =>
  {"assertion": "sysctl_live['fs.protected_fifos'] | int == 2",
   "msg": "Assertion failed: expected 2, got 1"}
```

**Причина:**

После фикса #1 handler был `sysctl -e --system`. Задача отрабатывала (`ok` в Vagrant),
но значение не применялось. Расследование:

`sysctl --system` обрабатывает **все** файлы конфигурации в лексикографическом порядке
из нескольких директорий:
```
/usr/lib/sysctl.d/*.conf     (наименьший приоритет)
/run/sysctl.d/*.conf
/etc/sysctl.d/*.conf
/etc/sysctl.conf             (наибольший приоритет)
```

В пределах `/etc/sysctl.d/` файлы обрабатываются в алфавитном порядке.
На Ubuntu `ubuntu-base` присутствует:
```
/etc/sysctl.d/99-sysctl.conf → /etc/sysctl.conf
```

Лексикографически: `99-ansible.conf` < `99-sysctl.conf` (`a` < `s`).

Результат:
```
1. /etc/sysctl.d/99-ansible.conf обрабатывается → fs.protected_fifos = 2 (наш файл)
2. /etc/sysctl.d/99-sysctl.conf  обрабатывается → fs.protected_fifos = 1 (Ubuntu default)
```

Ubuntu-дефолтный `sysctl.conf` перезаписывает наши значения, потому что идёт
**лексикографически после** нашего файла. Наш `--system` сам себя перекрывает.

Почему Arch-VM прошёл: у `arch-base` нет файла с тем же `99-` префиксом и более
поздним именем. Конфликт специфичен для Ubuntu.

**Проверка:**
```bash
# На ubuntu-base после converge:
$ sysctl fs.protected_fifos
fs.protected_fifos = 1     ← Ubuntu default, не наше значение

$ ls /etc/sysctl.d/
99-ansible.conf   99-sysctl.conf → /etc/sysctl.conf

$ grep protected_fifos /etc/sysctl.conf
# (не задано → Ubuntu default остаётся 1)

$ grep protected_fifos /etc/sysctl.d/99-ansible.conf
fs.protected_fifos = 2     ← наша настройка, но перекрыта следующим файлом
```

**Фикс:**

Изменить handler с `--system` (все файлы в порядке) на `-p <файл>` (только наш файл,
применяется последним в ручном порядке):

```yaml
# БЫЛО:
ansible.builtin.command: sysctl -e --system

# СТАЛО:
ansible.builtin.command: sysctl -e -p /etc/sysctl.d/99-ansible.conf
```

`sysctl -p <файл>` применяет **только** указанный файл. Поскольку он запускается после
`--system` по смыслу (handler срабатывает при изменении конфига), наши значения
гарантированно применяются последними и не перекрываются ничем.

Также: `-p` + `when: != docker` в одном handler решили оба инцидента #1 и #3.

**Почему `--system` изначально казался правильным:**

Документация `sysctl(8)` описывает `--system` как "apply all system configuration".
Интуитивно кажется более полным решением. На практике — это обходной путь который
ломается при конкурирующих файлах с той же числовой приставкой. `-p <наш файл>` — точный
и предсказуемый.

**Урок:** `sysctl --system` — это "apply everything in order". Не использовать как handler
для конкретного config-файла: любой системный файл с лексикографически бо́льшим именем
перекроет ваши настройки. Всегда применять конкретный файл через `-p /path/to/file.conf`.

---

## 3. Временная шкала

```
── Начало сессии (2026-03-01) ──────────────────────────────────────────────────

[Анализ кода] — обнаружена ошибка handler'а через код-ревью (без CI)
               — обнаружена ошибка {% raise %} через код-ревью (без CI)

710a73a  fix(sysctl): skip sysctl --system handler in Docker containers
         ↓ Adds: when: ansible_virtualization_type != 'docker'
         ↓ Change: --system → -p /etc/sysctl.d/99-ansible.conf (начальная версия)

f43df2e  fix(sysctl): add vagrant prepare.yml for package cache update
         ↓ Creates: molecule/vagrant/prepare.yml

32eab2a  fix(sysctl): replace {% raise %} with mandatory filter in template
         ↓ Fixes: sysctl.conf.j2 template parse error

         PR #7 открыт → Docker CI триггерится автоматически

         ↓ Docker run:     SUCCESS ✓ (1m52s)
         ↓ Ansible Lint:   SUCCESS ✓

         Vagrant CI — workflow_dispatch (run 22537452000-approx):
         ↓   arch-vm:    SUCCESS ✓ (3m36s)
         ↓   ubuntu-base: FAIL — fs.protected_fifos expected 2 got 1 (Инцидент #3)

13a06bf  fix(sysctl): use -p instead of --system to apply our sysctl config
         ↓ Обновляет комментарий + закрепляет -p вместо --system

         Vagrant CI — workflow_dispatch (run 22537842716):
         ↓   arch-vm:    SUCCESS ✓ (3m36s)
         ↓   ubuntu-base: SUCCESS ✓ (2m56s)
         ↓ Docker:        SUCCESS ✓
         ↓ Ansible Lint:  SUCCESS ✓
         ↓ YAML Lint:     SUCCESS ✓

         PR #7 merging with --squash → master fa9359e
```

---

## 4. Финальная структура

**Изменения роли:**

```
ansible/roles/sysctl/
├── handlers/main.yml          ← when: != docker; sysctl -e -p (не --system)
├── templates/sysctl.conf.j2   ← mandatory filter вместо {% raise %}
└── molecule/vagrant/
    └── prepare.yml            ← НОВЫЙ: pacman (Arch) | apt (Ubuntu)
```

**Изменения не потребовались:**

```
molecule/shared/verify.yml     ← уже корректно обрабатывает docker vs. vagrant
molecule/docker/molecule.yml   ← структура правильная (privileged, cgroupns)
defaults/main.yml              ← sysctl_custom_params: [] по умолчанию
tasks/main.yml                 ← template-таска уведомляет handler через notify
```

---

## 5. Ключевые паттерны

### Handler: применять конкретный файл, пропускать Docker

```yaml
- name: Apply sysctl settings
  listen: "reload sysctl"
  # -e = игнорировать ENOENT (unknown key, например kernel.unprivileged_userns_clone
  #      отсутствует на upstream ядре)
  # -p = применить ТОЛЬКО наш файл; --system читает всё в алфавитном порядке и
  #      может быть перезаписан файлом с лексикографически большим именем
  #      (Ubuntu's 99-sysctl.conf → /etc/sysctl.conf идёт после 99-ansible.conf)
  # when: в Docker kernel params read-only (EPERM), даже с privileged:true
  ansible.builtin.command: sysctl -e -p /etc/sysctl.d/99-ansible.conf
  changed_when: false
  when: ansible_virtualization_type | default('') != 'docker'
```

### Валидация переменных в Jinja2-шаблонах

```jinja2
{# НЕПРАВИЛЬНО — {% raise %} не существует в Jinja2, ошибка при парсинге: #}
{%   if param.name is not defined %}
{%     raise "message" %}
{%   endif %}
{{ param.name }} = {{ param.value }}

{# ПРАВИЛЬНО — mandatory фильтр, проверка при вычислении: #}
{{ param.name | mandatory("сообщение об ошибке") }} = {{ param.value | mandatory("сообщение") }}
```

### sysctl.d конфликты на Ubuntu

```
# Ubuntu ships /etc/sysctl.d/99-sysctl.conf → /etc/sysctl.conf
# Лексикографически: 99-ansible.conf < 99-sysctl.conf
# sysctl --system обрабатывает в алфавитном порядке → Ubuntu default перекрывает наш файл

# Решение: НЕ использовать --system как handler для конкретного config-файла.
# Использовать: sysctl -e -p /etc/sysctl.d/99-ansible.conf
```

---

## 6. Сравнение с историей проекта

| Инцидент | Дата | Роль | Ошибка | Класс |
|----------|------|------|--------|-------|
| Docker hostname EPERM | 2026-02-24 | hostname | hostnamectl EBUSY | container restriction |
| Docker /etc/hosts EBUSY | 2026-02-24 | hostname | lineinfile atomic rename | bind-mount restriction |
| **Docker sysctl EPERM** | **2026-03-01** | **sysctl** | **handler sysctl --system** | **container restriction** |
| {% raise %} parse error | 2026-03-01 | sysctl | Jinja2 unknown tag | template syntax |
| Ubuntu sysctl.d ordering | 2026-03-01 | sysctl | --system перекрыт 99-sysctl.conf | OS-specific gap |

Инцидент #1 воспроизводит класс ошибок "контейнер не может писать в kernel namespace".
Hostname-роль решала это через `when` + `unsafe_writes`. Sysctl-роль решает так же.

---

## 7. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `sysctl -e` подавляет только ENOENT (unknown key), не EPERM. В Docker kernel params read-only | Любая роль, работающая с kernel sysctl |
| 2 | Handler, пишущий kernel params, должен иметь `when: != 'docker'`. Синхронизировать с verify.yml Tier 2 | sysctl, ядерные модули, cgroups |
| 3 | `{% raise %}` — не Jinja2. Парсер отклоняет шаблон до вычисления условий. Использовать `mandatory` | Все Jinja2-шаблоны с валидацией переменных |
| 4 | `sysctl --system` = "apply все файлы по алфавиту". На Ubuntu `99-sysctl.conf` идёт после `99-ansible.conf` и перекрывает настройки. Всегда `-p <наш файл>` | Все роли с sysctl.d файлами |
| 5 | Arch проходит там, где Ubuntu падает из-за дополнительных system-файлов. Тестировать обе платформы | Cross-platform Molecule tests |
| 6 | Ansible-lint и синтаксис-проверки не ловят ошибки рендеринга шаблонов (ENOENT файлов, unknown tags в Jinja2 runtime) | Шаблоны с условной логикой |

---

## 8. Known gaps

- **Docker: sysctl не применяется.** Verify Tier 2 (live values) пропускается в контейнерах,
  Tier 1 (config content) и Tier 3 (параметры присутствуют в файле) работают. Полная проверка
  применённых значений — только в Vagrant. Это ожидаемое поведение, не пробел.

- **`kernel.unprivileged_userns_clone`** всегда записывается в конфиг (`sysctl_enable_user_namespaces`)
  через шаблон, но на стандартных upstream ядрах (Arch, Ubuntu) этот параметр отсутствует.
  `sysctl -e` молча игнорирует (`-e` = ignore errors для неизвестных ключей). Tier 3 verify
  проверяет только содержимое файла, не live-значение — корректно.
