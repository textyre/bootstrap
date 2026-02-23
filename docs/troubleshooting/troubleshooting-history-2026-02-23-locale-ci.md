# Troubleshooting History — 2026-02-23

## Post-Mortem: Locale CI — 6 итераций до зелёного

### Контекст

Задача: добавить CI тесты для роли `locale` (docker сценарий для GitHub Actions).
Итог: 6 коммитов, ~45 минут, 5 неудачных CI прогонов до успеха.

---

## Хронология инцидента

```
Коммит 1  test(locale): add docker CI scenario
          └─ FAIL: locale_gen "not available on your system"

Коммит 2  fix: add prepare.yml to populate /etc/locale.gen
          └─ FAIL: та же ошибка — prepare не запускался

Коммит 3  fix: add prepare step to test_sequence
          └─ FAIL: та же ошибка — prepare запустился, но не тот файл

Коммит 4  fix: populate /usr/share/i18n/SUPPORTED
          └─ FAIL: ru_RU.UTF-8 not found in locale -a (новая ошибка)

Коммит 5  debug: add locale -a and SUPPORTED debug output
          └─ FAIL + данные: locale -a = [C, C.utf8, POSIX], SUPPORTED=False

Коммит 6  fix: restore glibc locale data in Dockerfile + clean prepare
          └─ SUCCESS ✓
```

---

## Решено

### Категория: Molecule тесты / Docker образ

- [x] **locale CI тесты** — добавлен `molecule/docker/` сценарий с shared playbooks

- [x] **Дублирование converge/verify** — вынесены в `molecule/shared/`, оба сценария ссылаются через `provisioner.playbooks`

- [x] **glibc locale data отсутствовал в arch-systemd образе** — `archlinux:base` стрипает `/usr/share/i18n/locales/*` и `SUPPORTED` через `NoExtract` в `pacman.conf`. Исправлено в `Dockerfile.archlinux`: убраны `NoExtract` правила и переустановлен `glibc`

- [x] **ANSIBLE_ROLES_PATH в default сценарии** — указывал на несуществующий `${MOLECULE_PROJECT_DIRECTORY}/roles`, исправлено на `${MOLECULE_PROJECT_DIRECTORY}/../`

- [x] **vault_password_file в default сценарии** — мёртвый код, `vault.yml` не использует переменных locale роли, убран

- [x] **skip-tags: report в docker сценарии** — убран, репорт теперь виден в CI

---

## Анализ первопричин

### Root Cause 1 — Образ (PRIMARY)

`archlinux:base` Docker образ стрипает locale данные через `NoExtract` в `pacman.conf`:

```
/usr/share/i18n/SUPPORTED     → НЕ СУЩЕСТВУЕТ
/usr/share/i18n/locales/ru_RU → НЕ СУЩЕСТВУЕТ
/usr/share/i18n/locales/en_US → существует (исключение в NoExtract)
locale -a                     → только C, C.utf8, POSIX
```

`en_US.UTF-8` генерировался случайно — его definition file присутствовал как исключение. `ru_RU.UTF-8` — нет.

### Root Cause 2 — Неправильное понимание модуля (AMPLIFIER)

`community.general.locale_gen` имеет три разных проверки на три разных файла:

```
assert_available() → /usr/share/i18n/SUPPORTED  (availability check)
is_present()       → locale -a                  (state check)
apply_change()     → /etc/locale.gen + locale-gen
```

Первые 2 итерации чинили `/etc/locale.gen` — не тот файл для availability check.

### Root Cause 3 — Скрытый сигнал в логах (延長)

```
locale_gen для ru_RU.UTF-8: "ok"
```

Это выглядит как «локаль уже присутствует». На самом деле:
- `state_tracking` в начале = "absent" (локали нет)
- `locale-gen` вышел с RC=0, но тихо пропустил `ru_RU` (нет definition file)
- `state_tracking` в конце = "absent" (всё ещё нет)
- Нет изменения → Ansible сообщает `ok`

Нестандартное поведение: задача не зафейлилась, не показала `changed`, а показала `ok` — при этом желаемый результат не был достигнут.

---

## Почему так долго?

| Итерация | Гипотеза | Почему неверна | Потеря времени |
|----------|----------|----------------|----------------|
| 1→2 | «Нужно добавить locale.gen» | Модуль проверяет SUPPORTED, не locale.gen | 1 цикл CI |
| 2→3 | «prepare не запускается» | Верно, но фикс не помог — проблема глубже | 1 цикл CI |
| 3→4 | «prepare запускается, locale.gen заполнен» | Нужен SUPPORTED, не locale.gen | 1 цикл CI |
| 4→5 | «SUPPORTED заполнен, должно работать» | ru_RU definition file отсутствует | 1 цикл CI |
| 5→6 | «нужны данные» | Debug показал реальную картину | 1 цикл CI |

**Главная причина задержки**: каждая гипотеза требовала CI цикла (~1.5 мин). Нет способа быстро проверить состояние контейнера без запуска CI. Debug вывод (`locale -a`, `stat SUPPORTED`) нужно было добавить в первую итерацию.

---

## Что было сделано неправильно

| # | Что сделано | Лучше было бы |
|---|-------------|---------------|
| 1 | Чинили `/etc/locale.gen` без чтения исходника модуля | Прочитать исходник `locale_gen.py` перед первым фиксом |
| 2 | Debug вывод добавлен на 5-й итерации | Debug-first: собрать факты, потом фиксить |
| 3 | Не проверили содержимое образа до написания тестов | `docker run --rm образ ls /usr/share/i18n/` перед написанием сценария |
| 4 | `"ok"` от модуля принят за «локаль присутствует» | Понимать семантику: `ok` = no state change, не = success |

---

## Что делать, чтобы не повторилось

### 1. Image Smoke Test в CI

Добавить в `_molecule.yml` проверку базовых возможностей образа перед запуском тестов:

```yaml
- name: Verify base image capabilities
  run: |
    docker run --rm $MOLECULE_ARCH_IMAGE \
      ls /usr/share/i18n/SUPPORTED \
      /usr/share/i18n/locales/en_US \
      /usr/bin/locale-gen
```

Падает сразу с понятным сообщением — а не после нескольких итераций.

### 2. Документировать контракт образа

```markdown
# ansible/molecule/README.md — что гарантирует arch-systemd образ:
- systemd как PID 1 (cgroupns, privileged)
- python, sudo
- glibc с полными locale данными (/usr/share/i18n/locales/*, SUPPORTED)
- locale-gen
```

### 3. Debug-first подход в prepare.yml

Стандартный блок для любой роли с system dependencies:

```yaml
- name: Debug - verify system prerequisites
  ansible.builtin.command: "{{ item }}"
  loop:
    - "locale -a"
    - "ls /usr/share/i18n/SUPPORTED"
    - "ls /usr/share/i18n/locales/ | head -5"
  changed_when: false
  failed_when: false
  register: _prereq_debug

- name: Debug - show prerequisites
  ansible.builtin.debug:
    msg: "{{ _prereq_debug.results | map(attribute='stdout_lines') | list }}"
```

Запускать всегда в первой итерации при любых системных зависимостях.

### 4. Checklist для новых ролей с system dependencies

```
Перед написанием molecule/docker/:
□ Какие системные файлы нужны роли?
□ Присутствуют ли они в arch-systemd образе?
□ Прочитан ли исходник Ansible-модулей которые использует роль?
□ Добавлен ли debug output в prepare.yml?
```

### 5. Последовательность build → test в workflows

Сейчас: Dockerfile изменился → `build-arch-image` и `molecule` запускаются параллельно → тест использует старый образ.

Нужно: добавить зависимость `needs: build` в molecule workflow при изменении Dockerfile.

---

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/roles/locale/molecule/docker/molecule.yml` | Новый CI сценарий (docker driver, systemd, shared playbooks) |
| `ansible/roles/locale/molecule/docker/prepare.yml` | Заполняет SUPPORTED и locale.gen перед converge |
| `ansible/roles/locale/molecule/shared/converge.yml` | Общий converge без vault и Arch assertion |
| `ansible/roles/locale/molecule/shared/verify.yml` | Общий verify с нормализацией locale имён |
| `ansible/roles/locale/molecule/default/molecule.yml` | Убраны vault_password_file и неверный ROLES_PATH, указаны shared playbooks |
| `ansible/molecule/Dockerfile.archlinux` | Убраны NoExtract, переустановлен glibc с полными locale данными |

## Итог

CI тесты для роли `locale` работают. Docker сценарий проходит полный цикл: syntax → create → prepare → converge → idempotence → verify → destroy.

Ключевой урок: проблема была в инфраструктуре (образе), а не в тестах или подходе. Тесты — правильные. Подход с `shared/` — правильный. Время потеряно из-за отсутствия наблюдаемости на старте.
