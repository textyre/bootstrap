# Post-Mortem: Molecule Vagrant (KVM) CI для роли `yay`

**Дата:** 2026-02-26
**Статус:** Завершено — CI зелёный (arch-vm + ubuntu-noble)
**Итерации CI:** 3 запуска, 2 уникальных ошибки
**Коммиты:** `f7c8b32` → `f5ce686`

---

## 1. Задача

Запустить и довести до зелёного vagrant-сценарий для роли `yay` (AUR helper).

`yay/molecule/vagrant/` уже существовал до сессии, но ни разу не запускался через
воркфлоу. Воркфлоу `molecule-vagrant.yml` принимает `role` через `workflow_dispatch`
и тестирует обе платформы из матрицы: `arch-vm` + `ubuntu-noble`.

**Особенность роли:** `yay` — Arch-only. На Ubuntu роль не имеет смысла. При этом
воркфлоу всегда запускает обе матричные платформы.

---

## 2. Инциденты

### Инцидент #1 — `ubuntu-noble`: Instances missing from platform section

**Запуск:** `22459087730` (первый запуск)
**Платформа:** ubuntu-noble
**Время до ошибки:** ~12 секунд (сразу при старте molecule)
**Статус:** ubuntu-noble: FAILURE / arch-vm: FAILURE (другая причина)

**Ошибка:**
```
ERROR   Instances missing from the 'platform' section of molecule.yml.
Process completed with exit code 4.
```

**Причина:**

В `molecule/vagrant/molecule.yml` была объявлена только одна платформа:

```yaml
platforms:
  - name: arch-vm
    box: generic/arch
```

Воркфлоу запускал `molecule test -s vagrant --platform-name ubuntu-noble` — но
Molecule не нашёл платформу с таким именем и завершился с exit code 4.

В отличие от других ролей (pam_hardening, package_manager), которые кроссплатформенны,
`yay` — исключительно Arch Linux (AUR helper). Ubuntu-сценарий должен проходить
**тривиально** (no-op), а не падать с ошибкой molecule.

**Фикс:**

Архитектурное решение — три изменения одновременно:

1. **Добавить ubuntu-noble в `molecule.yml`** — чтобы molecule не падал с "missing platform":
```yaml
platforms:
  - name: arch-vm
    box: generic/arch
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: bento/ubuntu-24.04
    memory: 2048
    cpus: 2
```

2. **Создать локальный `converge.yml`** вместо ссылки на `../shared/converge.yml`
   (shared converge запускает `role: yay` напрямую, что провалит assert на Ubuntu).
   Используется `meta: end_host` для graceful skip:
```yaml
tasks:
  - name: Skip yay role on non-Arch systems
    ansible.builtin.meta: end_host
    when: ansible_facts['os_family'] != 'Archlinux'

  - name: Apply yay role
    ansible.builtin.include_role:
      name: yay
```

3. **Создать локальный `verify.yml`** с тем же guard в начале — копия
   `shared/verify.yml` с `meta: end_host` первой задачей:
```yaml
tasks:
  - name: Skip verify on non-Arch systems
    ansible.builtin.meta: end_host
    when: ansible_facts['os_family'] != 'Archlinux'
  # ... все Arch-специфичные проверки
```

4. **Обновить `molecule.yml`** — указать на локальные файлы:
```yaml
provisioner:
  playbooks:
    prepare: prepare.yml
    converge: converge.yml    # было: ../shared/converge.yml
    verify: verify.yml        # было: ../shared/verify.yml
```

5. **Исправить `prepare.yml`** — добавить `when:` условия для Arch-задач,
   которые их не имели:
```yaml
- name: Refresh pacman keyring
  when: ansible_facts['os_family'] == 'Archlinux'   # ← добавлено

- name: Full system upgrade
  when: ansible_facts['os_family'] == 'Archlinux'   # ← добавлено

- name: Update apt cache (Ubuntu)
  ansible.builtin.apt: ...
  when: ansible_facts['os_family'] == 'Debian'       # ← новая задача
```

**Паттерн `meta: end_host` для Arch-only ролей:**

Это стандартный способ сказать Molecule «эта роль не применима к этому хосту».
Задачи после `meta: end_host` на данном хосте не выполняются. Molecule продолжает
работу с остальными хостами, считает хост `ok`, и итоговый статус — success.

Преимущество перед `failed_when: false` или assert с ignore_errors: хост реально
«выходит» из play, не накапливает ложных ok/changed/failed.

**Урок:** Arch-only роль с vagrant-сценарием должна объявить ubuntu-noble платформу
и использовать `meta: end_host` в converge и verify. Иначе матрица CI всегда будет
красной.

---

### Инцидент #2 — `arch-vm`: DNS failure во время `go build`

**Запуск:** `22459087730` (первый запуск)
**Платформа:** arch-vm
**Время до ошибки:** ~25 секунд в converge (после успешного git clone)
**Статус:** FAILURE

**Ошибка:**
```
fatal: [arch-vm]: FAILED! => {
  "cmd": ["makepkg", "--noconfirm"],
  "rc": 4,
  "stderr": "clean.go:8:2: github.com/Jguer/aur@v1.2.3: Get
    \"https://proxy.golang.org/github.com/%21jguer/aur/@v/v1.2.3.zip\":
    dial tcp: lookup proxy.golang.org on [::1]:53:
    read udp [::1]:52512->[::1]:53: read: connection refused"
}
```

**Хронология задач converge:**

```
TASK [yay : Install build dependencies]   → ok (pacman, DNS не нужен)
TASK [yay : Clone yay from AUR]           → changed ✓ (git clone aur.archlinux.org работает)
TASK [yay : Build yay package]            → FAILED ✗ (go build, DNS [::1]:53 отказывает)
```

**Ключевое наблюдение:** git clone сработал, go build — нет. Оба выполняются
в одном ansible-playbook прогоне, разница во времени — около 6 секунд.

**Анализ причины:**

`dial tcp: lookup proxy.golang.org on [::1]:53` — DNS-сервер по адресу
`[::1]:53` (IPv6 loopback) отказывает в соединении.

Что происходит после `pacman -Syu`:

1. Обновляется `systemd` — одна из первых и наиболее высокоприоритетных посылок
2. После upgrade systemd-networkd или systemd-resolved перенастраивает сеть
3. `/etc/resolv.conf` перезаписывается. На Arch Linux с systemd `resolv.conf`
   обычно является симлинком на `/run/systemd/resolve/stub-resolv.conf`,
   который содержит `nameserver 127.0.0.53`. Однако в generic/arch Vagrant box
   с libvirt-сетью после полного upgrade конфигурация может вести к `[::1]:53` —
   IPv6-адресу systemd-resolved stub
4. `[::1]:53` отказывает (`connection refused`), а не таймаутит — значит там
   что-то слушает, но не готово принимать запросы (race condition после upgrade)

**Почему git clone прошёл, а go build — нет:**

Две гипотезы, обе правдоподобны:

- **Временной фактор:** git clone завершился за ~6 секунд до go build. За это
  время systemd-resolved успел перезапуститься после upgrade и перейти в режим
  IPv6-stub. DNS cache для `aur.archlinux.org` мог существовать с этапа prepare,
  а для `proxy.golang.org` — нет
- **Разные DNS-резолверы:** Go использует собственный DNS-резолвер (не libc/getaddrinfo).
  Go resolver агрессивнее пробует IPv6-адреса и может попасть в `[::1]:53` раньше,
  чем традиционный libc resolver. git использует curl/libgit2, которые идут через
  getaddrinfo и могут иметь другое поведение при IPv6

**Фикс:**

В `prepare.yml`, сразу после `pacman -Syu`, явно перезаписываем `/etc/resolv.conf`:

```yaml
- name: Fix DNS after system upgrade on Arch (systemd may replace resolv.conf with [::1]:53)
  ansible.builtin.copy:
    content: |
      nameserver 8.8.8.8
      nameserver 1.1.1.1
    dest: /etc/resolv.conf
    unsafe_writes: true
  when: ansible_facts['os_family'] == 'Archlinux'
```

`unsafe_writes: true` необходим — `/etc/resolv.conf` часто является симлинком
или лежит в директории с ограничениями на атомарный rename. Без флага Ansible
может получить `EBUSY` или `ETXTBSY` при попытке атомарного rename tmpfile.

**Почему не патчить Go или makepkg:**

Альтернативы (GONOSUMDB, GOPROXY=direct, GOFLAGS=-mod=vendor) решили бы симптом,
но не причину. DNS должен работать для других операций в роли (yay в дальнейшем
обращается к AUR). Правильное место для фикса — инфраструктурный prepare, не роль.

**Урок:** После `pacman -Syu` на generic/arch в Vagrant systemd меняет конфигурацию
DNS. Go's DNS resolver чувствительнее к проблемам IPv6-stub чем libgit2/curl.
Всегда фиксировать resolv.conf после upgrade в prepare.yml для Arch vagrant-сценариев.

---

## 3. Финальная структура

```
ansible/roles/yay/molecule/vagrant/
  molecule.yml    ← arch-vm (generic/arch) + ubuntu-noble (bento/ubuntu-24.04)
                     converge: converge.yml, verify: verify.yml (локальные)
  prepare.yml     ← raw python → gather_facts → keyring refresh (when: Archlinux)
                     → pacman -Syu (when: Archlinux) → DNS fix (when: Archlinux)
                     → apt update (when: Debian)
  converge.yml    ← meta: end_host (when: not Archlinux) → include_role: yay
  verify.yml      ← meta: end_host (when: not Archlinux) → все Arch-проверки
```

### prepare.yml (финальный)

```yaml
---
- name: Prepare
  hosts: all
  become: true
  gather_facts: false
  tasks:
    - name: Bootstrap Python on Arch (raw — no Python required)
      ansible.builtin.raw: >
        test -e /etc/arch-release && pacman -Sy --noconfirm python || true
      changed_when: false

    - name: Gather facts
      ansible.builtin.gather_facts:

    - name: Refresh pacman keyring (generic/arch has stale keys)
      ansible.builtin.shell: |
        sed -i 's/^SigLevel.*/SigLevel = Never/' /etc/pacman.conf
        pacman -Sy --noconfirm archlinux-keyring
        sed -i 's/^SigLevel.*/SigLevel = Required DatabaseOptional/' /etc/pacman.conf
        pacman-key --populate archlinux
      when: ansible_facts['os_family'] == 'Archlinux'
      changed_when: true

    - name: Full system upgrade (ensures openssl/go compatibility)
      community.general.pacman:
        update_cache: true
        upgrade: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Fix DNS after system upgrade (systemd may replace resolv.conf with [::1]:53)
      ansible.builtin.copy:
        content: |
          nameserver 8.8.8.8
          nameserver 1.1.1.1
        dest: /etc/resolv.conf
        unsafe_writes: true
      when: ansible_facts['os_family'] == 'Archlinux'

    - name: Update apt cache (Ubuntu)
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_facts['os_family'] == 'Debian'
```

### Результат второго запуска (22459412702)

```
yay — arch-vm:     SUCCESS  (~8 мин: prepare 5м + converge 1.5м + verify 1м)
yay — ubuntu-noble: SUCCESS (~6 мин: prepare 4м + converge ~0с + verify ~0с)
```

Ubuntu-noble: converge и verify мгновенны — `meta: end_host` срабатывает на первой
задаче, никакой работы не происходит.

---

## 4. Почему у других ролей этой проблемы не было

| Роль | Использует go build? | Vagrant сценарий |
|------|---------------------|-----------------|
| package_manager | Нет | arch-vm + ubuntu-noble, shared converge |
| pam_hardening | Нет | arch-vm + ubuntu-noble, shared converge |
| yay | **Да** (makepkg → go build) | arch-vm + ubuntu-noble (новое) |

`package_manager` и `pam_hardening` не запускают Go компилятор. DNS используется
только для `pacman -S ...` (через libc resolver) и для `pacman -Syu` во время prepare
(до изменения resolv.conf). Проблема DNS в `[::1]:53` существует и у них, но
проявляется только при использовании Go DNS-резолвера в converge.

---

## 5. Ключевые паттерны

### Arch-only роль в кроссплатформенной CI-матрице

```
Проблема: воркфлоу тестирует arch-vm + ubuntu-noble
Роль работает только на Arch

Решение:
  1. Добавить ubuntu-noble платформу в molecule.yml (иначе: "Instances missing")
  2. Локальный converge.yml: meta: end_host when: os_family != Archlinux
  3. Локальный verify.yml:   meta: end_host when: os_family != Archlinux
  4. prepare.yml: when: условия для всех Arch-специфичных задач

НЕ нужно: убирать ubuntu-noble из матрицы, делать отдельный workflow,
           использовать failed_when/ignore_errors
```

### DNS после pacman -Syu на Vagrant generic/arch

```
Симптом: DNS работает в prepare (keyring, pacman), ломается в converge
Специфика: Go DNS-резолвер чувствительнее к IPv6-stub [::1]:53 чем curl/libgit2
Фикс: явная перезапись /etc/resolv.conf после pacman -Syu

Место фикса: prepare.yml, после community.general.pacman upgrade
Флаг: unsafe_writes: true (resolv.conf часто симлинк или в tmpfs)
```

### Стандартный порядок задач в prepare.yml для generic/arch

```
1. raw: pacman -Sy python (gather_facts: false)
2. gather_facts
3. SigLevel=Never → pacman -Sy archlinux-keyring → SigLevel=Required
4. pacman-key --populate archlinux
5. community.general.pacman: upgrade: true
6. copy: /etc/resolv.conf (8.8.8.8)        ← НОВЫЙ ОБЯЗАТЕЛЬНЫЙ ШАГ для ролей с Go/curl
7. обычные prepare-таски роли
```

---

## 6. Сравнение с предыдущими инцидентами

| Инцидент | Роль | Симптом | Причина | Фикс |
|----------|------|---------|---------|------|
| 2026-02-25 #7 | package_manager | SSL `unknown url type: https` | ABI mismatch после upgrade | pacman -Syu |
| 2026-02-26 #2 | yay | DNS `[::1]:53 connection refused` | systemd заменяет resolv.conf после -Syu | явная перезапись resolv.conf |

Инциденты связаны: `pacman -Syu` необходим (исправляет ABI), но имеет
побочный эффект — пересоздаёт сетевую конфигурацию. Фиксы накапливаются:
сначала добавили upgrade, теперь — DNS fix после upgrade. Это закономерная
эволюция шаблона prepare.yml.

---

## 7. Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/roles/yay/molecule/vagrant/molecule.yml` | Добавлена ubuntu-noble платформа; converge/verify переключены на локальные файлы |
| `ansible/roles/yay/molecule/vagrant/prepare.yml` | Добавлены `when:` guards для Arch-задач; apt update для Ubuntu; DNS fix после upgrade |
| `ansible/roles/yay/molecule/vagrant/converge.yml` | Создан: `meta: end_host` для не-Arch + `include_role: yay` |
| `ansible/roles/yay/molecule/vagrant/verify.yml` | Создан: `meta: end_host` + все Arch-проверки из shared/verify.yml |

---

## 8. Known gaps

- **Время прогона arch-vm:** ~8-10 минут из-за `pacman -Syu` + сборки yay из
  исходников (Go build ~4 минуты). Оптимизация: кастомный packer-образ с
  pre-installed Go module cache.
- **go module cache пустой на каждом прогоне:** yay каждый раз скачивает все
  Go-зависимости из proxy.golang.org. Vagrant box не кэшируется между запусками.
  Можно добавить `GOMODCACHE` на persistent volume, но это усложняет конфигурацию.
- **DNS fix не задокументирован в README:** Паттерн `resolv.conf после -Syu`
  должен быть добавлен в `ansible/molecule/README.md` как обязательный шаг
  для любого vagrant-сценария с Go или другими приложениями, использующими
  нативный DNS-резолвер.
