# Постмортем: VM execution environment и управление состоянием clone

**Дата:** 2026-05-10
**Категория:** VM environment, snapshot workflow, clone lifecycle, evidence
**Статус:** draft
**Назначение:** классический постмортем по ошибкам работы с VM-средой и предотвращению смешивания состояний.

## Краткий итог

Во время работы возникала путаница между разными VM-состояниями, прогонами и выводами. Обсуждение смешивало clone, snapshot, run id, before/after reboot, ARA-записи, факты ядра и результаты ролей. Из-за этого принимающий не мог быстро понять, на какой машине был запуск, какой snapshot был источником, что реально произошло до reboot, что произошло после reboot и какие факты это подтверждают.

Проблема была не только технической. Основной сбой был в модели учета состояния: VM рассматривалась как “машина, на которой что-то запускалось”, а не как одноразовый проверяемый clone с обязательным run ledger.

## Проблема

VM workflow требует строгой дисциплины:

- source VM и source snapshots immutable;
- каждый fresh run стартует с disposable clone;
- Ansible выполняется на VM через Taskfile;
- после failure нельзя чинить VM руками или продолжать с точки падения;
- каждый claim о состоянии VM должен иметь команду и verbatim output.

В ходе работы эти правила не всегда были отражены в отчетности. Даже когда отдельные команды выполнялись корректно, reporting не давал цельной картины: “какой clone, какой snapshot, какой запуск, какой факт, какой вывод”.

## Влияние

| Последствие | Проявление |
| --- | --- |
| Потеря доверия к фактам | Разные ответы выглядели как противоречия о kernel/modules/reboot |
| Замедление приемки | Принимающий вынужден был выяснять, что именно запускалось |
| Риск неверного решения | Без run ledger можно чинить не тот слой проблемы |
| Риск загрязнения VM | При слабой дисциплине возникает соблазн ручных фиксов на VM |
| Риск смешивания прогонов | Факты с одного clone могут быть приписаны другому run |

## Причины проблемы

| Причина | Что произошло | Почему это опасно |
| --- | --- | --- |
| Нет обязательного run ledger | Не фиксировались единым блоком clone name, snapshot, port, commit, command, start/end state | Нельзя восстановить цепочку доказательств |
| Недостаточно before/after facts | Факты до reboot и после reboot не были представлены как связанная пара | Нельзя доказать, что reboot решил нужную проблему |
| Смешивались прогоны | Разные запуски обсуждались рядом без жесткой идентификации | Ответы выглядели взаимоисключающими |
| ARA трактовалась неаккуратно | Нужно было объяснять, что именно есть в ARA и что считается source of truth | Ревьюер не понимает, можно ли верить отчету |
| Snapshot semantics не всегда были первым ориентиром | Source snapshot и disposable clone требовали постоянного проговаривания | Возникает риск мутировать baseline |

## Что должно было быть сделано

Каждый VM-прогон должен начинаться с паспорта запуска.

| Поле | Пример значения | Зачем нужно |
| --- | --- | --- |
| `run_id` | `vm-run-2026-05-10-001` | Не смешивать запуски |
| `source_vm` | `arch-base` | Подтвердить immutable baseline |
| `snapshot` | `initial` или `after-packages` | Понять стартовое состояние |
| `clone_name` | `arch-test-clone` | Понять, где выполнялись команды |
| `ssh_host` | `arch-127.0.0.1-2223` | Воспроизводимость SSH |
| `commit_sha` | SHA рабочей копии после sync | Связать VM состояние с кодом |
| `sync_command` | `scripts/ssh-scp-to.sh --project` | Подтвердить, что код доставлен на VM |
| `task_command` | `task prepare:system` или `task workstation` | Подтвердить штатный execution surface |
| `ara_db` | путь или отметка unavailable | Понять источник прогресса |

## Минимальные факты для reboot-зависимых задач

Если задача касается обновления системы, reboot, kernel/modules или сервисов, факты должны быть парными.

| Момент | Команды | Что доказывает |
| --- | --- | --- |
| До prepare | `uname -r`, `cat /proc/sys/kernel/random/boot_id`, package query | Исходное kernel/runtime состояние |
| После prepare до reboot | `uname -r`, package query, `/usr/lib/modules` listing | Обновился ли installed state при старом running state |
| После reboot | `uname -r`, `boot_id`, `/usr/lib/modules/$(uname -r)` | Загрузилась ли система в согласованное состояние |
| После workstation | service checks, role-specific verification | Работает ли целевой функционал |
| Idempotency | повтор того же Taskfile command | Нет ли повторных изменений |

Главное правило: reboot считается доказанным не фразой “reboot был”, а изменением boot id и проверкой состояния после загрузки.

## Что сработало

| Что сработало | Почему это полезно |
| --- | --- |
| В проекте есть `wiki/standards/test-vm-workflow.md` | Правила clone-only workflow уже описаны |
| Есть `scripts/clone-test-vm.sh` | Clone creation формализован |
| Есть проверка matching modules после clone boot | Частично защищает от старого kernel после package upgrade |
| Есть `scripts/ssh-run.sh --bootstrap-secrets` | Secrets передаются ephemeral, без plaintext на VM |
| Есть Taskfile commands | Execution surface не надо изобретать |

## Что не сработало

| Что не сработало | Почему |
| --- | --- |
| Reporting по VM был недостаточно связным | Не было единого run ledger |
| Факты не всегда группировались по времени | Before/after выводы теряли смысл |
| Наблюдение через ARA требовало пояснений | Нужно явно указывать таблицы, записи и raw fallback |
| Термины запусков были неочевидны | Пользователь не обязан угадывать, что такое run id или result records |
| Failure handling требовал повторного выравнивания | После ошибки нужно reset/re-run, а не продолжение из мутного состояния |

## Что делать в будущем

### 1. Ввести паспорт VM-запуска

Каждый свежий запуск должен иметь один отчетный блок:

| Раздел паспорта | Обязательное содержимое |
| --- | --- |
| Identity | run id, clone name, port, snapshot |
| Code state | branch, commit SHA, sync command |
| Execution | Taskfile command, start time, end time |
| Evidence | command + verbatim output для ключевых фактов |
| Result | recap, failed/changed, ARA link/path |
| Next action | reset/re-run, idempotency, close, blocked |

### 2. Не смешивать факты разных VM

Перед любым статусом нужно писать:

| Claim | Required qualifier |
| --- | --- |
| “Docker упал” | На каком clone, в каком run, после какой команды |
| “reboot прошел” | Boot id before/after |
| “kernel соответствует modules” | `uname -r` и наличие `/usr/lib/modules/$(uname -r)` |
| “workstation прошел” | Taskfile command и recap |
| “idempotency чистая” | Повторный run на той же VM без reset |

### 3. Reset discipline

| Сценарий | Правильное действие |
| --- | --- |
| Fresh run | Создать новый clone из snapshot |
| Failure в role | Починить код локально, sync, reset clone, re-run с начала |
| Idempotency run | Не reset, повторить тот же command на той же VM |
| Смена scope | Новый clone |
| Неясное состояние VM | Считать VM непригодной для доказательств и пересоздать clone |

### 4. ARA usage discipline

ARA можно использовать как primary progress source, но отчет должен быть понятен без догадок.

| Ситуация | Что делать |
| --- | --- |
| ARA доступна | Указать DB/source, play id, status, recap |
| ARA записи неполные | Сверить raw Ansible output |
| ARA и raw output расходятся | Остановиться и классифицировать discrepancy |
| Job еще идет | Использовать ARA для progress, не читать log без причины |
| Final failure | Читать Ansible log для failure evidence |

## Профилактические действия

| Priority | Action | Result |
| --- | --- | --- |
| P0 | Добавить шаблон VM run ledger в test workflow | Каждый запуск имеет паспорт |
| P0 | Сделать before/after facts обязательными для reboot/kernel задач | Reboot и kernel state доказываются фактами |
| P0 | Запретить отчеты без clone/snapshot/run id | Нельзя смешать разные VM |
| P1 | Документировать ARA evidence protocol | ARA не воспринимается как “магические result records” |
| P1 | Добавить короткий failure-handling checklist | После failure нет продолжения из грязного состояния |
| P2 | Добавить пример полного успешного run report | Будущим агентам есть эталон |

## Критерии исправления

VM workflow считается восстановленным, если:

- каждый fresh run начинается с clone passport;
- каждый reboot-sensitive claim имеет before/after facts;
- в отчете нельзя перепутать snapshot, clone и run;
- failure ведет к локальному fix + sync + reset + re-run;
- source VM и source snapshots не мутируются;
- ARA используется как источник прогресса, но итоговые claims подтверждаются конкретным evidence.

## Финальный вывод

VM в этом проекте должна восприниматься как одноразовая доказательная среда. Без run ledger любой запуск превращается в смесь состояний. Правильная модель: clone создан, код синхронизирован, команда выполнена через Taskfile, факты сняты, результат записан, VM либо идет на idempotency, либо пересоздается.
