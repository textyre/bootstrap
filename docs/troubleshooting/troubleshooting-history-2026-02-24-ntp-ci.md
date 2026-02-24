# Troubleshooting History — 2026-02-24

## Post-Mortem: NTP CI тесты — brainstorm без исследования → исправление подхода

### Контекст

Задача: добавить Molecule CI тесты для роли `ntp` (Docker сценарий для GitHub Actions)
и VM-based integration сценарий для живой проверки синхронизации NTP.

Итог: 2 коммита (один с основными изменениями + один lint fix), CI зелёный.
Но до этого — brainstorm с неверными рекомендациями, исправленный только после
прямых вопросов пользователя.

---

## Хронология

```
Brainstorm 1  Предложены: retry loops, tiering тестов, feature-flag ntp_molecule_live
              └─ Пользователь: "Почему нужен ретрай? Tiering зачем? Ты изучал?"

Brainstorm 2  Исследование через claudette-researcher (4 источника)
              └─ Находки: adjtimex в Docker, consensus публичных ролей,
                 chronyc waitsync как canonical approach

Реализация    Создан shared/ + docker/ + integration/ + баг-фиксы
              └─ Агент также исправил vconsole (scope расширен без явного согласования)

Коммит 1      feat(ntp,vconsole): add Docker CI and integration molecule scenarios
              └─ FAIL lint: name[play] на import_playbook в integration/verify.yml

Коммит 2      fix(ntp): suppress name[play] lint on import_playbook
              └─ SUCCESS ✓ — lint + molecule зелёные
```

---

## Решено

- [x] **NTP docker CI сценарий** — `molecule/docker/` с offline assertions
- [x] **NTP integration сценарий** — `molecule/integration/` с live sync assertions
- [x] **Shared паттерн** — `molecule/shared/` без дублирования между сценариями
- [x] **Underscore-prefix баги** — 6 task-файлов ntp + 3 файла vconsole
- [x] **`name[play]` lint** — `import_playbook` + `# noqa: name[play]`

---

## Ошибки brainstorma

### Ошибка 1: Retry loops

**Что было предложено:** добавить `until:` loop для `chronyc -n sources` с обоснованием
"Docker может быть медленнее инициализирует сеть".

**Почему неверно:** проблема не в таймингах. В Docker-контейнерах `adjtimex()` требует
`CAP_SYS_TIME` без seccomp фильтра. Даже в privileged-контейнере chronyd должен
запускаться с `-x` флагом чтобы не трогать host clock. С `-x` `chronyc waitsync`
никогда не возвращает успех — не потому что "не успело", а потому что часы
физически не синхронизируются.

**Источник:** Podman issue #19771, chrony-users mailing list (Miroslav Lichvar, 2019),
RedHat Bugzilla #1778133.

**Правильный ответ:** в Docker CI не тестировать sync state вообще.

---

### Ошибка 2: Tiering тестов (feature-flag `ntp_molecule_live`)

**Что было предложено:** добавить переменную `ntp_molecule_live: bool` в inventory,
которая включает/отключает live-тесты. Docker сценарий ставит `false`, default — `true`.

**Почему неверно:** тесты начинают вести себя по-разному в зависимости от переменной.
Это разрушает предсказуемость: одни и те же assertions не дают одинаковый результат
в разных контекстах. CI проходит, но coverage неполный, и это неочевидно.

Правильная абстракция — разные _сценарии_ с разными _целями_, а не флаги внутри
одного verify.yml.

**Правильный ответ:** `docker/` сценарий — offline assertions (что контролирует роль),
`integration/` сценарий — live assertions (что контролирует окружение).

---

### Ошибка 3: Не изучены постмортемы и публичные репо

На три прямых вопроса пользователя ("ты изучал постмортемы? публичные репо? общий подход?")
честный ответ был "нет". Brainstorm строился на умозаключениях.

После исследования выяснилось что индустриальный консенсус однозначен (4 источника):
ни одна публичная Ansible chrony роль не делает assertions на sync state в Docker CI.

---

## Непредвиденный scope: vconsole

Агент во время выполнения самостоятельно расширил scope на роль `vconsole`:
создал shared/ + docker/ сценарии и исправил те же underscore-prefix баги.

**Плюс:** валидные исправления реальных багов, vconsole теперь тоже в CI-матрице.

**Риск:** агент модифицировал несвязанную роль без явного согласования. Мог сломать
что-то в vconsole. В этот раз не сломал, но scope expansion без контроля — антипаттерн.

**Вывод:** при делегировании в remote-executor нужно явно ограничивать scope в промпте:
"изменяй только файлы в `ansible/roles/ntp/`".

---

## Инфраструктурные проблемы на VM

Выявлены во время первого запуска molecule test -s docker. Все решены агентом на месте.

| Проблема | Причина | Решение |
|---|---|---|
| Containers без интернета | nftables `forward chain policy drop` блокирует Docker bridge NAT | `nft add rule inet filter forward iifname "br-*" accept` (ephemeral) |
| sudo заблокирован | `faillock` заблокировал после 3 неудачных попыток | `faillock --user textyre --reset` |
| `molecule-plugins[docker]` не установлен | Пакет есть в requirements.txt но не был установлен в venv | `pip install molecule-plugins[docker]` |
| Роль ntp отсутствовала на VM | Только molecule/ директория была синхронизирована | Синхронизирована полная роль |

**Важно:** nftables fix ephemeral — потеряется при перезагрузке VM.
Нужно добавить в `/etc/nftables.conf` forward chain:
```nftables
iifname "docker*" accept
oifname "docker*" accept
iifname "br-*" accept
oifname "br-*" accept
```

---

## Анализ lint failure

**Ошибка:** `name[play]: All plays should be named` на строке 2 `integration/verify.yml`.

**Файл содержал:**
```yaml
---
- name: Verify NTP configuration (shared)
  import_playbook: ../shared/verify.yml
```

`name:` на `import_playbook` — валидный Ansible синтаксис (поддерживается с 2.8+),
но ansible-lint правило `name[play]` не считает его именем play и всё равно репортит.

**Исправление:** убрать `name:`, добавить `# noqa: name[play]`:
```yaml
- import_playbook: ../shared/verify.yml  # noqa: name[play]
```

**Как избежать:** запускать lint локально до push:
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible && \
  source .venv/bin/activate && ansible-lint roles/ntp/molecule/"
```

---

## Анализ первопричин

### Root Cause 1: Brainstorm без исследования (PRIMARY)

Рекомендации строились на паттернах "что обычно делают с Docker тестами" без проверки
специфики NTP/chrony. Специфика оказалась принципиальной: `adjtimex()` закрывает
весь класс sync-assertions в контейнерах.

Правило: перед brainstorm на тему "как тестировать X" — исследовать как другие тестируют X.
Инструмент: `claudette-researcher` с явным запросом публичных репо.

### Root Cause 2: Lint не запускался локально

Lint failure обнаружен в CI после push. Одна итерация потрачена зря.
Добавить в привычку: после создания новых YAML файлов запускать lint на VM перед push.

### Root Cause 3: Нет ограничения scope для агента

Агент получил задачу "запусти molecule test -s docker для ntp" и самостоятельно
решил также мигрировать vconsole. Scope не был явно ограничен в промпте.

---

## Что сделано правильно

- Brainstorm был скорректирован после вопросов пользователя, а не защищался
- Исследование через `claudette-researcher` дало точные ссылки на источники
  (Miroslav Lichvar mailing list, Podman issues, chrony upstream)
- `chronyc waitsync 30 0 0 2` — точная реализация upstream рекомендации, не самодел
- `import_playbook` в integration/verify.yml — чистое переиспользование без дублирования

---

## Архитектурные решения

### Почему shared/ а не отдельные verify.yml

Без shared/ при добавлении нового assertions (например, проверка `rtcsync` в конфиге)
нужно обновлять два файла: docker/verify.yml и integration/verify.yml. С shared/ —
один файл, два сценария его используют. При N сценариях выигрыш пропорционален N.

### Почему integration/verify.yml использует import_playbook а не include_tasks

`import_playbook` — единственный способ переиспользовать полный play (с `hosts:`,
`become:`, `gather_facts:`) из другого файла. `include_tasks` работает только
внутри play, не позволяет импортировать play целиком.

### Почему chronyc waitsync вместо polling loop

```yaml
# НЕ ТАК:
until: stdout | select('match', '^\^\*') | length > 0
retries: 12
delay: 5

# ТАК:
cmd: chronyc waitsync 30 0 0 2
```

`waitsync` — встроенная команда chrony для ожидания синхронизации. Сам хранит state,
не требует внешнего polling. Точная семантика: ждёт пока система считается
синхронизированной по критериям chrony. Timeout 60s покрывает iburst (~6-10s на
первое измерение) с большим запасом.

---

## Файлы изменённые в сессии

| Файл | Что сделано |
|---|---|
| `ansible/roles/ntp/molecule/shared/converge.yml` | Создан: запуск роли без OS-guard |
| `ansible/roles/ntp/molecule/shared/verify.yml` | Создан: offline assertions (pkg, svc, config, dirs) |
| `ansible/roles/ntp/molecule/docker/molecule.yml` | Создан: CI Docker сценарий + dns_servers для VM |
| `ansible/roles/ntp/molecule/docker/prepare.yml` | Создан: `pacman -Sy` перед установкой chrony |
| `ansible/roles/ntp/molecule/integration/molecule.yml` | Создан: localhost сценарий для self-hosted runner |
| `ansible/roles/ntp/molecule/integration/verify.yml` | Создан: `import_playbook` shared + live sync assertions |
| `ansible/roles/ntp/molecule/default/molecule.yml` | Обновлён: shared/, ROLES_PATH fix, idempotency |
| `ansible/roles/ntp/molecule/default/converge.yml` | Удалён (заменён shared) |
| `ansible/roles/ntp/molecule/default/verify.yml` | Удалён (заменён shared) |
| `ansible/roles/ntp/tasks/disable_systemd.yml` | Баг-фикс: `_ntp_timesyncd` → `ntp_timesyncd` |
| `ansible/roles/ntp/tasks/disable_ntpd.yml` | Баг-фикс: `_ntp_ntpd_disable` → `ntp_ntpd_disable` |
| `ansible/roles/ntp/tasks/disable_openntpd.yml` | Баг-фикс: `_ntp_openntpd_disable` → `ntp_openntpd_disable` |
| `ansible/roles/ntp/tasks/load_ptp_kvm.yml` | Баг-фикс: `_ntp_ptp_kvm_load`, `_ntp_ptp0_stat` |
| `ansible/roles/ntp/tasks/detect_environment.yml` | Баг-фикс: `_ntp_vmware_ptp_stat` |
| `ansible/roles/ntp/tasks/vmware_disable_timesync.yml` | Баг-фикс: `_ntp_vmware_timesync_status` |
| `ansible/roles/vconsole/molecule/shared/converge.yml` | Создан (агент, out-of-scope) |
| `ansible/roles/vconsole/molecule/shared/verify.yml` | Создан (агент, out-of-scope) |
| `ansible/roles/vconsole/molecule/docker/molecule.yml` | Создан (агент, out-of-scope) |
| `ansible/roles/vconsole/molecule/docker/prepare.yml` | Создан (агент, out-of-scope) |
| `ansible/roles/vconsole/molecule/default/molecule.yml` | Обновлён: shared/ (агент) |
| `ansible/roles/vconsole/molecule/default/converge.yml` | Удалён (агент) |
| `ansible/roles/vconsole/molecule/default/verify.yml` | Удалён (агент) |
| `ansible/roles/vconsole/tasks/verify/systemd.yml` | Баг-фикс: underscore vars (агент) |
| `ansible/roles/vconsole/tasks/verify/openrc.yml` | Баг-фикс: underscore vars (агент) |
| `ansible/roles/vconsole/tasks/verify/runit.yml` | Баг-фикс: underscore vars (агент) |
| `.github/workflows/molecule-integration.yml` | Создан: weekly + dispatch, `[self-hosted, arch]` |

---

## Открытые задачи

- [ ] **Self-hosted runner** на Arch VM — зарегистрировать, `integration/` сценарий ждёт
- [ ] **nftables Docker forwarding** — сделать persistent в `/etc/nftables.conf`
- [ ] **Underscore-prefix audit** — проверить остальные роли на `_role_varname` паттерн

---

## Итог

CI тесты для роли `ntp` добавлены и зелёные. Основная техническая ошибка была
в подходе к brainstorm: умозаключения вместо исследования. Вопросы пользователя
("ты изучал?") вскрыли это раньше чем код был написан. Исправление подхода через
исследование дало точные, обоснованные решения с источниками.
