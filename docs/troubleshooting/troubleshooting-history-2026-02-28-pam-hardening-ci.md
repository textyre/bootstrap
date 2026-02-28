# Post-Mortem: Molecule CI для роли `pam_hardening`

**Дата:** 2026-02-28
**Статус:** Завершено — CI зелёный (Docker + vagrant arch-vm + vagrant ubuntu-base)
**PR:** #3 `fix/pam-hardening-molecule-tests`
**Коммиты:** `a816cf4` → `3f263f7` (4 итерации)

---

## 1. Задача

Запустить molecule-тесты роли `pam_hardening` в трёх средах:

| Среда | Что тестирует |
|-------|---------------|
| Docker (`molecule/docker/`) | Быстрая проверка синтаксиса + идемпотентности на Arch + Ubuntu |
| Vagrant arch-vm | Полный тест на реальной KVM VM с systemd + PAM |
| Vagrant ubuntu-base | Полный тест на реальной KVM VM с ubuntu-base образом |

Дополнительное требование: тесты запускаются только при изменении роли (уже реализовано
через `detect` job в `molecule.yml`).

---

## 2. Инциденты

### Инцидент #1 — Docker: `pacman` вызывается на Ubuntu-контейнере

**Коммит:** `a816cf4`
**Ошибка:**
```
TASK [Update pacman package cache] *********************************************
fatal: [Ubuntu-systemd]: FAILED! => {
  "msg": "Failed to find required executable \"pacman\" in paths: /usr/local/sbin:/usr/local/bin:..."
}
```

**Причина:**

`molecule/docker/prepare.yml` содержал:

```yaml
- name: Prepare
  hosts: all
  become: true
  gather_facts: false    # ← нет фактов об ОС
  tasks:
    - name: Update pacman package cache
      community.general.pacman:
        update_cache: true
        # ← нет when-условия
```

Docker-сценарий (`molecule/docker/molecule.yml`) определяет две платформы: `Archlinux-systemd`
и `Ubuntu-systemd`. `gather_facts: false` означает что `ansible_facts['os_family']` недоступен.
Таск запускается на ВСЕХ хостах, включая Ubuntu, где `pacman` отсутствует.

**Диагностика:** Ошибка прямолинейна — `pacman` не найден. Причина — отсутствие `when`-условия.
Аналогичный паттерн уже использовался в `molecule/vagrant/prepare.yml` (правильно):

```yaml
- name: Update apt cache (Ubuntu)
  ansible.builtin.apt:
    update_cache: true
    cache_valid_time: 3600
  when: ansible_facts['os_family'] == 'Debian'
```

**Фикс:**

```yaml
- name: Prepare
  hosts: all
  become: true
  gather_facts: true    # ← включаем для os_family
  tasks:
    - name: Update pacman package cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

**Урок:** В Docker-сценарии с несколькими ОС `gather_facts: false` в `prepare.yml` запрещает
использование условий на `os_family`. Всегда: `gather_facts: true` + явные `when` по OS-семейству.
Никогда не вызывать пакетный менеджер без `when` если в сценарии есть несколько платформ.

---

### Инцидент #2 — Vagrant: `No usable default provider could be found`

**Коммиты:** `e9fdb87` (первый push), `0b74d9e` (repair), `3f263f7` (финальный фикс)
**Прогоны:** 3 итерации (все провальные до финального фикса)

**Ошибка (при каждом прогоне, оба платформы):**
```
TASK [Create molecule instance(s)]
fatal: [localhost]: FAILED! => {
  "msg": "Failed to validate generated Vagrantfile: b'No usable default provider could be
  found for your system.\n\nVagrant relies on interactions with 3rd party systems, known
  as \"providers\"..."
}
```

---

#### Фаза 2.1 — Гипотеза: стартовая CI-флакость

**Первоначальный диагноз (ошибочный):** В предыдущем CI-прогоне (`00571a3`) arch-vm прошёл,
а ubuntu-base упал — это приписали случайной флакости GitHub Actions runner.

**Почему ошибочный:** В ЭТОМ PR (одной ветке) упали ОБА платформы в ОБА прогона.
При random-флакости вероятность двух последовательных двойных провалов мала.
Это был сигнал к углублённой диагностике, а не ретрай.

**Урок:** Два подряд полных провала → не флакость, а детерминированная ошибка.

---

#### Фаза 2.2 — Анализ CI логов

Ключевые наблюдения из логов:

| Шаг | Статус | Вывод |
|-----|--------|-------|
| `Install libvirt + vagrant` | ✓ | libvirt установлен |
| `Cache vagrant plugins` | `Cache hit for: vagrant-gems-Linux-2.4.9` | Гемы восстановлены из кэша |
| `Install vagrant-libvirt plugin` | `-` (skipped) | Пропущен из-за cache hit |
| `Repair vagrant plugins` | ✓ `"Installed plugins successfully repaired!"` | Запустили, но не помогло |
| `Run Molecule` | ✗ | "No usable default provider" |

Паттерн: когда cache miss (первый прогон новой ветки) — vagrant работает. Когда cache hit — падает.

**Вывод:** Проблема не в runner KVM-поддержке, не в libvirt daemon, а в кэше гемов.

---

#### Фаза 2.3 — Попытка: `vagrant plugin repair`

**Гипотеза:** Нативные расширения (`.so` файлы) `vagrant-libvirt` скомпилированы против
старой версии libvirt. Команда `vagrant plugin repair` должна перекомпилировать их.

**Что происходит:** `vagrant plugin repair` запускает `gem pristine` на все установленные плагины.
Команда выводит `"Installed plugins successfully repaired!"` и завершается успешно.

**Результат:** Vagrant по-прежнему не видит libvirt провайдера.

**Почему не сработало:** `gem pristine` восстанавливает гем из локального gem-кэша (`.gem` файл),
но если исходный `.gem` файл отсутствует в `~/.vagrant.d/gems/ruby/3.x.x/cache/` — перекомпиляция
не происходит. Команда завершается успешно (exit 0) даже если реального recompile не было.

**Урок:** `vagrant plugin repair` не является надёжным способом перекомпиляции нативных расширений.
Положительный exit code вводит в заблуждение.

---

#### Фаза 2.4 — Root cause

**Механизм сбоя:**

```
1. Workflow #1 (свежий runner):
   libvirt-dev = 10.0.0-2ubuntu8.10
   vagrant plugin install vagrant-libvirt
     → компилирует .so против libvirt 10.0.0-2ubuntu8.10
     → сохраняет в ~/.vagrant.d/gems/
   Кэш сохранён под ключом: vagrant-gems-Linux-2.4.9

2. GitHub Actions: runner pool обновляется, libvirt обновляется до 10.0.0-2ubuntu8.11

3. Workflow #2 (любой следующий прогон):
   libvirt-dev = 10.0.0-2ubuntu8.11 (новая версия!)
   Cache hit для: vagrant-gems-Linux-2.4.9
   Install vagrant-libvirt plugin → SKIPPED (cache hit)
   ~/.vagrant.d/gems/ содержит .so скомпилированный против 10.0.0-2ubuntu8.10
   Vagrant пытается загрузить vagrant-libvirt plugin
     → dlopen() на .so, скомпилированный против другого libvirt ABI → silent fail
     → плагин не загружается
     → Vagrant: "No usable default provider found"
```

Ключевое: `dlopen()` failure поглощается Vagrant — он не выводит ошибку динамического линкера,
а молча игнорирует плагин и переходит к "No usable default provider".

**Доказательство:** Кэш-ключ `vagrant-gems-Linux-2.4.9` не содержит версию libvirt.
Один и тот же ключ → один и тот же кэш → независимо от версии libvirt на runner.

---

#### Фаза 2.5 — Финальный фикс: libvirt version в ключе кэша

**Фикс:**

```yaml
- name: Get libvirt version
  id: libvirt-ver
  run: echo "version=$(dpkg -s libvirt-dev | grep '^Version:' | cut -d' ' -f2)" >> $GITHUB_OUTPUT

- name: Cache vagrant plugins
  uses: actions/cache@v4
  id: vagrant-gems-cache
  with:
    path: ~/.vagrant.d/gems
    key: vagrant-gems-${{ runner.os }}-${{ steps.vagrant-ver.outputs.version }}-libvirt${{ steps.libvirt-ver.outputs.version }}
    restore-keys: |
      vagrant-gems-${{ runner.os }}-${{ steps.vagrant-ver.outputs.version }}-
      vagrant-gems-${{ runner.os }}-
```

**Логика:**
- При обновлении libvirt на runner → полный cache miss → `vagrant plugin install` запускается
  → нативные расширения компилируются против текущей libvirt → сохраняются в новый кэш
- При стабильной libvirt → cache hit → плагин уже скомпилирован правильно → всё работает
- `restore-keys` обеспечивает fallback-кэш для ускорения gem-download при version mismatch

**Результат (прогон после фикса):**

```
✓ Get libvirt version          → 10.0.0-2ubuntu8.11
✓ Cache vagrant plugins        → cache miss (новый ключ с libvirt версией)
✓ Install vagrant-libvirt plugin → запущен, скомпилирован
✓ Run Molecule (arch-vm)       → 2m40s — SUCCESS
✓ Run Molecule (ubuntu-base)   → 2m25s — SUCCESS
```

**Урок:** Любой кэш нативных расширений должен включать версию системной библиотеки в ключ.
Для vagrant-libvirt это libvirt-dev. Аналогично для любых гемов с нативными расширениями
против системных библиотек (nokogiri → libxml2, pg → postgresql-dev и т.д.).

---

### Инцидент #3 — Vagrant molecule.yml: нестандартная структура

**Не вызывал падений, но был cleanup-поводом.**

`molecule/vagrant/molecule.yml` содержал лишний блок, отсутствующий во всех остальных ролях:

```yaml
provisioner:
  inventory:
    host_vars:
      localhost:
        ansible_python_interpreter: "{{ ansible_playbook_python }}"
```

И отсутствовал стандартный:
```yaml
provisioner:
  options:
    skip-tags: report
```

Эти отличия копировались из ранней версии до стандартизации шаблона.

**Фикс:** Привели к стандарту, совпадающему с fail2ban, locale, git, ntp и другими ролями.

**Урок:** Новые роли должны копировать molecule-шаблон из актуальной референсной роли (`ntp`).

---

## 3. Временная шкала

```
00571a3  feat: integrate ubuntu-base into all cross-platform tests
          ↓ CI push на master: Docker-тест pam_hardening падает
          ↓ Vagrant ubuntu-base падает (~1m7s — подозрение на флакость)

PR #3 создан
e9fdb87  fix: vagrant molecule.yml alignment
a816cf4  fix: docker prepare.yml — conditional pacman/apt
          ↓ CI прогон #1: Docker PASS ✓ | arch-vm FAIL ✗ | ubuntu-base FAIL ✗
          ↓ Оба vagrant: "No usable default provider", ~1m10s
          ↓ Диагноз: cache hit → stale .so

0b74d9e  fix: vagrant plugin repair on cache hit
          ↓ CI прогон #2: Docker PASS ✓ | arch-vm FAIL ✗ | ubuntu-base FAIL ✗
          ↓ vagrant plugin repair: exit 0, но .so не перекомпилированы
          ↓ Диагноз подтверждён: repair не работает

3f263f7  fix: libvirt version in cache key
          ↓ CI прогон #3: Docker PASS ✓ | arch-vm PASS ✓ | ubuntu-base PASS ✓
          ↓ PR #3 смержен в master
```

---

## 4. Финальные изменения

| Файл | Что сделано |
|------|-------------|
| `ansible/roles/pam_hardening/molecule/docker/prepare.yml` | `gather_facts: false → true`; разделён на Arch (pacman) и Ubuntu (apt) с `when` |
| `ansible/roles/pam_hardening/molecule/vagrant/molecule.yml` | Удалён `inventory.host_vars.localhost`; добавлен `options: skip-tags: report` |
| `.github/workflows/_molecule-vagrant.yml` | Добавлен шаг `Get libvirt version`; ключ кэша включает версию libvirt-dev |

---

## 5. Ключевые паттерны

### Vagrant gems cache key

```yaml
key: vagrant-gems-${{ runner.os }}-${{ steps.vagrant-ver.outputs.version }}-libvirt${{ steps.libvirt-ver.outputs.version }}
restore-keys: |
  vagrant-gems-${{ runner.os }}-${{ steps.vagrant-ver.outputs.version }}-
  vagrant-gems-${{ runner.os }}-
```

Получить libvirt версию: `dpkg -s libvirt-dev | grep '^Version:' | cut -d' ' -f2`

### Docker prepare.yml с несколькими ОС

```yaml
- name: Prepare
  gather_facts: true    # обязательно для os_family
  tasks:
    - name: Update pacman cache (Arch)
      community.general.pacman:
        update_cache: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

### Диагностика "No usable default provider"

```
Вопрос 1: cache hit или miss для vagrant-gems?
  miss → свежий install, проблема в другом (runner без KVM, libvirtd не стартовал)
  hit  → стартуй с подозрения на ABI mismatch нативных расширений

Вопрос 2: `vagrant plugin repair` помогает?
  да → ABI mismatch, исходный .gem доступен (редко)
  нет → исходный .gem не в кэше → нужен force-reinstall или libvirt version в cache key

Вопрос 3: два подряд провала? → не флакость → детерминированный баг
```

---

## 6. Ретроспективные выводы

| # | Урок | Применимость |
|---|------|-------------|
| 1 | `gather_facts: false` + пакетный менеджер без `when` → fatal на других ОС | Docker prepare.yml с несколькими платформами |
| 2 | Vagrant gems cache key ДОЛЖЕН включать libvirt-dev версию | `_molecule-vagrant.yml` и любой workflow с vagrant-libvirt |
| 3 | `vagrant plugin repair` выходит с кодом 0 даже если перекомпиляция не произошла — не надёжен | Vagrant debugging |
| 4 | `dlopen()` failure плагина в Vagrant поглощается молча → "No usable default provider" вместо реальной ошибки | Диагностика vagrant provider issues |
| 5 | Два последовательных провала обоих платформ → не флакость runner, а детерминированный баг | CI debugging heuristics |
| 6 | Любые нативные расширения против системных библиотек: версия библиотеки в ключе кэша | Все кэши с .so файлами |

---

## 7. Known gaps

- **`vagrant plugin repair` оставлен без использования:** команда не удалена из знаний, но
  не должна использоваться как workaround для ABI mismatch — только финальный фикс с cache key.
- **`_molecule-vagrant.yml` использует Ubuntu-специфичный `dpkg -s`:** если runner когда-либо
  сменится на не-Debian, шаг `Get libvirt version` упадёт. Текущее состояние: GH Actions
  `ubuntu-latest` — только Ubuntu, риск минимален.
