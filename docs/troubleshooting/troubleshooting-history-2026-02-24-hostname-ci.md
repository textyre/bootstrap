# Troubleshooting History — 2026-02-24

## Post-Mortem: Hostname CI — 3 итерации + переработка подхода

### Контекст

Задача: добавить CI тесты для роли `hostname` (docker сценарий для GitHub Actions).
Итог: первая рабочая версия за 5 коммитов, затем полная переработка теста по требованию — 2 дополнительных коммита.
Финал: тест честный, зелёный.

---

## Хронология инцидента

```
Коммит 1  feat(hostname): add docker CI scenario + fix _hostname_check bug
          └─ FAIL: hostnamectl EBUSY при попытке set-hostname

Коммит 2  fix(hostname): add prepare.yml pre-set /etc/hostname
          └─ FAIL: hostname command not found (нет inetutils)

Коммит 3  fix(hostname): python3 socket.gethostname() + unsafe_writes
          └─ SUCCESS ✓ — но подход признан неудовлетворительным

--- Разбор подхода ---

Коммит 4  fix(hostname): proper Docker test via umount of bind mounts
          └─ SUCCESS ✓ — честный тест
```

---

## Решено

- [x] **hostname CI тест** — добавлен `molecule/docker/` сценарий с shared playbooks
- [x] **EBUSY при hostnamectl** — корень: Docker bind-монтирует `/etc/hostname`, systemd-hostnamed пишет атомарно (rename), rename через границы mount points → EXDEV. Решение: `umount /etc/hostname` в prepare.yml
- [x] **EBUSY при lineinfile на `/etc/hosts`** — та же природа. Решение: `umount /etc/hosts` в prepare.yml
- [x] **`hostname` command not found** — `inetutils` не установлен в arch-systemd образе. Попытка 1: `python3 -c "import socket; print(socket.gethostname())"`. После переработки: `hostnamectl status --static` (не требует внешних бинарей)
- [x] **Тест-плацебо** — исходный тест только проверял идемпотентность (hostname уже совпадал). После переработки роль реально меняет hostname из Docker-default в `archbox`

---

## Анализ первопричин

### Root Cause 1 — Docker bind mounts (PRIMARY)

Docker bind-монтирует три файла из своего storage directory в контейнер:

```
/etc/hostname   → /var/lib/docker/containers/<id>/hostname   (Type: "bind")
/etc/hosts      → /var/lib/docker/containers/<id>/hosts      (Type: "bind")
/etc/resolv.conf → /var/lib/docker/containers/<id>/resolv.conf (Type: "bind")
```

Источник: `moby/moby` — `daemon/initlayer/setup_unix.go` (создаёт заглушки),
`daemon/container/container_unix.go` (создаёт bind mount дескрипторы),
`daemon/oci_linux.go` (`Type: "bind"` в OCI spec).

### Root Cause 2 — Атомарный rename через границы mount points

`systemd-hostnamed` пишет `/etc/hostname` с `WRITE_STRING_FILE_ATOMIC` — это:
1. Создаёт temp файл в `/etc/` (на overlay filesystem)
2. `rename(tmp, /etc/hostname)` — target на bind mount, src на overlay

Linux `rename(2)`, man page:
> "EXDEV: oldpath and newpath are not on the same mounted filesystem. rename() does not work across different mount points, even if the same filesystem is mounted on both."

То же самое для Ansible `lineinfile` — он тоже пишет через atomic rename.

Ansible docs на параметре `unsafe_writes`:
> "One example is docker mounted filesystem objects, which cannot be updated atomically from inside the container and can only be written in an unsafe manner."

### Root Cause 3 — Неверное чтение Ansible hostname module source

Первоначально предполагалось что `SystemdStrategy` пишет `/etc/hostname` напрямую через Python `open()`. На деле — нет. Исходник `lib/ansible/modules/hostname.py`:

```python
class SystemdStrategy(BaseStrategy):
    def set_permanent_hostname(self, name):
        # Вызывает subprocess:
        cmd = [self.hostnamectl_cmd, '--pretty', '--static', 'set-hostname', name]
        rc, out, err = self.module.run_command(cmd)
```

`SystemdStrategy` делегирует запись `hostnamectl` → `systemd-hostnamed` → атомарный rename → EXDEV.

Также неожиданная находка: `use: generic` → `BaseStrategy` → `raise NotImplementedError`. Не работает вообще.

### Root Cause 4 — Тест-плацебо (SECONDARY)

Workaround через `hostname: archbox` в molecule.yml + `prepare.yml` с записью `/etc/hostname = archbox` привёл к тому что:
- Docker стартует контейнер с hostname = `archbox`
- Роль запускается, видит "уже `archbox`" → `ok`
- Idempotence: тоже `ok`
- Verify: подтверждает `archbox`

Тест проходил, но ничего не тестировал кроме того что роль не ломается при уже установленном hostname.

---

## Цепочка решения

### Итерация 1: `unsafe_writes` + `python3`

```
Проблема: hostnamectl EBUSY + hostname command not found
Решение:  - prepare.yml пишет /etc/hostname заранее (hostname уже совпадает → no-op)
           - hostname → python3 -c "import socket; print(socket.gethostname())"
           - lineinfile + unsafe_writes: true
Статус:   ✓ CI зелёный, но тест нечестный
```

### Итерация 2: Разбор подхода

Претензии:
1. `python3 socket.gethostname()` — хак, нестандартный способ проверить hostname
2. Тест не тестирует реальное изменение hostname, только идемпотентность

Необходимое исследование:
- Прочитан исходник `moby/moby` — подтверждены bind mounts
- Прочитан `rename(2)` man page — EXDEV задокументирован
- Прочитан `lib/ansible/modules/hostname.py` — найдено что SystemdStrategy вызывает `hostnamectl`, не пишет напрямую
- Найдено: в privileged контейнере можно сделать `umount /etc/hostname` изнутри

### Итерация 3: Правильное решение

```
prepare.yml:  umount /etc/hostname && umount /etc/hosts
              → файлы становятся обычными overlay файлами
              → hostnamectl пишет атомарно без EXDEV
              → lineinfile пишет атомарно без unsafe_writes

molecule.yml: убран hostname: archbox
              → контейнер стартует с Docker-default hostname
              → роль реально меняет hostname

verification: python3 → hostnamectl status --static
              → идиоматичный systemd, без внешних бинарей

Статус:       ✓ CI зелёный, тест честный
```

---

## Почему так долго?

| Этап | Что произошло | Потеря |
|------|---------------|--------|
| Workaround вместо root cause | Не прочитали исходник модуля и moby source сразу | 3 итерации CI |
| `python3` как "временное" решение | Приняли работающий CI за "готово" | Дополнительный раунд ревью |
| Предположение о `generic` стратегии | Не проверили — `use: generic` = NotImplementedError | Часть дискуссии |

---

## Что было сделано неправильно

| # | Что сделано | Лучше было бы |
|---|-------------|---------------|
| 1 | Не прочитали `hostname.py` перед первым фиксом | Прочитать исходник до написания workaround |
| 2 | Не прочитали moby source — заявляли что "Docker bind-монтирует" без источника | Сначала найти источник, потом утверждать |
| 3 | Назвали подход "Pattern A" — термин не существует в документации | Не называть решения красивыми терминами без источника |
| 4 | Приняли "CI зелёный" за "тест правильный" | Оценивать что именно тестируется, а не только статус CI |

---

## Ключевые факты для будущих тестов в Docker

### Docker всегда bind-монтирует эти файлы (кроме `--net=host`):

```
/etc/hostname    → atomics fail (EXDEV)
/etc/hosts       → atomics fail (EXDEV)
/etc/resolv.conf → atomics fail (EXDEV)
```

### Решение для Molecule privileged контейнеров:

```yaml
# prepare.yml
- name: Unmount Docker bind mounts for writable overlay files
  ansible.builtin.command: umount {{ item }}
  loop:
    - /etc/hostname
    - /etc/hosts
  changed_when: true
  failed_when: false
```

Работает потому что `privileged: true` даёт `CAP_SYS_ADMIN` → `umount` разрешён внутри контейнера.

### Ansible hostname module — какая стратегия что делает:

| `use:` | Пишет /etc/hostname | Transient hostname |
|--------|---------------------|--------------------|
| `systemd` | через `hostnamectl` subprocess (atomic) | через `hostnamectl --transient` |
| `debian` | алиас для `systemd` — то же самое | то же самое |
| `generic` | `raise NotImplementedError` | no-op |
| `alpine` | `open(file, 'w+')` — прямая запись | `hostname -F /etc/hostname` |

### Verification без внешних бинарей:

```yaml
ansible.builtin.command: hostnamectl status --static
```

Читает `/etc/hostname` через systemd-hostnamed. D-Bus read path работает в Docker без проблем.

---

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/roles/hostname/tasks/main.yml` | Исправлен баг `_hostname_check` → `hostname_check`; verification: `python3` → `hostnamectl status --static` |
| `ansible/roles/hostname/tasks/hosts.yml` | Добавлен и затем убран `unsafe_writes: true` |
| `ansible/roles/hostname/molecule/shared/converge.yml` | Создан: `hostname_name: archbox`, `hostname_domain: example.com` |
| `ansible/roles/hostname/molecule/shared/verify.yml` | Создан: проверка hostname, FQDN в /etc/hosts, отсутствие дублей; `python3` → `hostnamectl status --static` |
| `ansible/roles/hostname/molecule/docker/molecule.yml` | Создан: Docker driver, arch-systemd, privileged; убран `hostname: archbox` |
| `ansible/roles/hostname/molecule/docker/prepare.yml` | Создан как workaround (pre-set hostname), переработан в `umount /etc/hostname && umount /etc/hosts` |
| `ansible/roles/hostname/molecule/default/molecule.yml` | Обновлён: убран vault, исправлен ROLES_PATH, подключены shared playbooks, добавлен idempotence |
| `ansible/roles/hostname/molecule/default/converge.yml` | Удалён (заменён shared) |
| `ansible/roles/hostname/molecule/default/verify.yml` | Удалён (заменён shared) |
| `ansible/roles/locale/molecule/docker/prepare.yml` | Фикс: добавлен `mode: '0644'` для risky-file-permissions lint |

---

## Итог

CI тесты для роли `hostname` работают. Тест честный: роль реально меняет hostname из Docker-default в `archbox` через `hostnamectl`, без предварительного прописывания значений.

Ключевые уроки:
1. **Читай исходник модуля и runtime (moby)** до написания workaround, не после
2. **"CI зелёный" ≠ "тест правильный"** — оценивай что именно тестируется
3. **`umount` в privileged контейнере** — стандартный способ обойти Docker bind mount ограничения без изменения логики роли
4. **Не называй решения терминами без источника** — "Pattern A" не существует в документации
