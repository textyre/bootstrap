# Постмортем: факты и диагностика в Infrastructure as Code

**Дата:** 2026-05-08
**Категория:** Факты и диагностика
**Статус:** Draft
**Область:** evidence collection, runtime diagnostics, VM state tracking, test interpretation, reviewer-facing reporting

## Итог

В ходе работы над IaC-задачей исполнитель неоднократно делал выводы быстрее, чем собирал факты. Это привело к противоречивым объяснениям, смешению разных запусков, неясным отчетам о состоянии VM и недоверию со стороны принимающего.

Проблема была не в отсутствии инструментов диагностики. Инструменты были доступны: shell-команды на VM, логи, ARA/offline database, package manager facts, kernel facts, CI checks, Taskfile targets. Проблема была в том, что факты не были собраны в правильном порядке, не были промаркированы состоянием системы и не были представлены как единая доказательная цепочка.

В результате принимающий не мог понять:

- на какой машине выполнялся запуск;
- какой именно run обсуждается;
- что было до изменения;
- что стало после изменения;
- был ли реально выполнен boundary-step;
- какие выводы подтверждены фактами, а какие являются гипотезами;
- почему последующий ответ противоречит предыдущему.

## Контекст

В IaC-проектах диагностика является частью архитектуры работы, а не вспомогательной активностью. Один и тот же код может вести себя по-разному в зависимости от:

- snapshot или clone, с которого стартовала VM;
- текущего boot state;
- версии running kernel;
- состояния package database;
- установленных packages;
- наличия runtime artifacts;
- порядка предыдущих запусков;
- того, был ли выполнен real run, dry-run, check-mode или CI simulation.

Поэтому любые утверждения о причине сбоя должны быть привязаны к evidence:

```text
где выполнено -> когда выполнено -> какая команда -> какой вывод -> какой вывод из этого следует
```

Без этой связки объяснение превращается в гипотезу, даже если сама гипотеза технически правдоподобна.

## Impact

Диагностические ошибки привели к следующим последствиям:

- принимающий получил несколько противоречивых объяснений одного и того же состояния;
- часть выводов выглядела как выдуманная, потому что не имела команд и verbatim outputs;
- разные VM-runs и состояния были смешаны в один narrative;
- dry-run/check-mode был воспринят как доказательство реального поведения;
- runtime facts были собраны уже после того, как выводы были озвучены;
- acceptance decision был невозможен без повторного сбора evidence;
- время ушло на восстановление доверия к данным, а не только на исправление кода.

## Root Cause

Корневая причина: исполнитель не вел строгий diagnostic ledger и не отделял verified facts от hypotheses.

Вместо последовательности:

```text
зафиксировать target environment -> собрать baseline facts -> выполнить один controlled action -> собрать after facts -> сравнить -> сделать вывод
```

фактически возникала последовательность:

```text
увидеть симптом -> объяснить вероятную причину -> смешать старые и новые данные -> получить возражение -> дособирать факты постфактум
```

Это создало пять ключевых диагностических ошибок.

## Ошибка 1: утверждения без полного evidence chain

### Что произошло

Исполнитель делал утверждения о runtime-состоянии системы без полного набора фактов. Отдельные факты присутствовали, но они не образовывали доказательную цепочку.

Типичный неполный набор выглядел так:

```text
есть сообщение об ошибке
есть предположение о причине
нет baseline до действия
нет after-state после действия
нет команды, которая проверяет ключевое условие
нет связи между ошибкой и конкретным run
```

### Почему это проблема

В IaC диагностике одиночный факт редко доказывает причину. Например, ошибка в downstream-компоненте может быть следствием:

- неверного порядка lifecycle steps;
- stale runtime state;
- отсутствующего package;
- mismatch между running state и installed state;
- пропущенного reboot или service restart;
- поведения test environment;
- unrelated regression в другой роли.

Если не собрать цепочку before/after, принимающий видит только объяснение, но не доказательство.

### Детальный пример

В одном из прогонов обсуждалась проблема kernel/module mismatch. Сначала причина была описана правдоподобно, но без достаточного набора фактов. Принимающий справедливо остановил работу вопросами:

```text
Где факты? Где факты, которые собираются перед перезапуском, после перезапуска?
Какие вообще в целом должны быть собраны факты для решения задачи?
Почему сейчас устанавливаются headers не той версии, которая установлена на машине?
Какая версия установлена?
```

Правильный evidence chain должен был быть таким:

```text
1. VM identity
2. snapshot/clone source
3. before action boot_id
4. before action running kernel
5. before action module directories
6. before action installed kernel package
7. action command and output
8. after action before boundary boot_id
9. after action before boundary running kernel
10. after action before boundary module directories
11. boundary command and output
12. after boundary boot_id
13. after boundary running kernel
14. after boundary matching module tree
15. downstream run status
```

Когда факты были наконец собраны, evidence chain стал понятным:

```text
before action:
boot_id=08fc9372-388c-4b2e-ae1f-6851ab9de380
uname_r=6.19.13-arch1-1
module_dir=6.19.13-arch1-1
linux 6.19.13.arch1-1
linux-headers: not installed

after action before boundary:
boot_id=08fc9372-388c-4b2e-ae1f-6851ab9de380
uname_r=6.19.13-arch1-1
module tree for running kernel: absent
module_dir=7.0.3-arch1-2
linux 7.0.3.arch1-2
linux-headers: not installed

after boundary:
boot_id=ea22514c-022a-4f2c-8329-6e68f28a0976
uname_r=7.0.3-arch1-2
matching module tree: present
linux 7.0.3.arch1-2
```

Только после такого сравнения стало доказуемо, что проблема была не в downstream-компоненте как primary root cause, а в запуске downstream-компонентов до стабилизации system runtime state.

### Причина

Исполнитель пытался объяснить симптом через знание типового failure mode, но не доказал, что именно этот failure mode произошел в данном run.

### Что нужно делать иначе

Перед любым root-cause statement нужно заполнить минимальную evidence table:

| Evidence | Required |
|---|---|
| Environment identity | VM name, clone/source, SSH host/port |
| Run identity | command, timestamp, ARA ID или CI job ID |
| Baseline facts | state before action |
| Action output | command + verbatim output |
| After facts | state after action |
| Comparison | explicit before vs after |
| Conclusion | только то, что следует из comparison |

## Ошибка 2: смешение разных VM-состояний и запусков

### Что произошло

Исполнитель смешал данные из разных запусков и разных моментов жизненного цикла VM. В одном ответе могли оказаться факты из одного run, объяснение из другого run и вывод из третьего состояния.

Это породило прямые противоречия:

```text
сначала версии не совпадают -> потом версии совпадают -> потом снова говорится о mismatch
сначала reboot прошел -> потом возникает впечатление, что reboot не прошел
сначала роль дошла до одного места -> потом обсуждается другой failure point
```

### Почему это проблема

VM-state в IaC является mutable. Если не маркировать каждый факт состоянием, он быстро теряет смысл.

Один и тот же host может иметь разные состояния:

```text
fresh clone before run
after package update before boundary
after boundary before downstream roles
after first full configuration run
after failed regression run
after fixed regression run
after cleanup run
```

Факт из одного состояния нельзя использовать как доказательство другого.

### Детальный пример

В процессе были как минимум такие состояния:

| State | Evidence example |
|---|---|
| Fresh clone baseline | old boot_id, old running kernel, matching old module tree |
| After system-level action before boundary | same boot_id, old running kernel, new installed kernel, no matching module tree |
| After boundary | new boot_id, new running kernel, matching new module tree |
| First downstream run | ARA run completed, downstream module consumers passed |
| Regression run 1 | failed on ownership drift in an unrelated component |
| Regression run 2 | failed on non-interactive prompt in an unrelated component |
| Final regression run | completed, no boundary loop |
| Cleanup validation run | completed with scoped cleanup |

Смешение этих состояний привело к тому, что принимающий получил ответ, в котором невозможно было понять:

- какой clone обсуждается;
- был ли это первый run или повторный run;
- была ли система уже после boundary;
- относится ли ошибка к исходной проблеме или к следующему regression layer;
- почему одна и та же роль сначала "проходит", а потом "падает".

Прямая обратная связь:

```text
Разные прогоны, разные состояния, VM, ты смешал.
Что с чем ты смешал, блядь?
```

### Причина

Не было run ledger. Исполнитель не вел таблицу, где каждый вывод привязан к:

```text
VM -> command -> run ID -> state label -> result
```

### Что нужно делать иначе

В IaC-задачах с VM, snapshots, reboot или repeated runs каждый отчет должен начинаться с run ledger:

| Field | Example |
|---|---|
| VM identity | clone name, source snapshot, SSH endpoint |
| State label | before action, after action before boundary, after boundary, regression run |
| Command | exact command |
| Run ID | ARA ID, CI job ID, or explicit local sequence number |
| Status | completed, failed, skipped, pending |
| Key facts | only facts collected in that state |

Запрещено переносить факт из одного state label в другой без явного comparison.

## Ошибка 3: противоречивые выводы из-за отсутствия before/after comparison

### Что произошло

Исполнитель несколько раз давал выводы, которые выглядели взаимоисключающими. Проблема была не только в формулировках, а в отсутствии явного before/after comparison.

Когда comparison не показан, принимающий видит только набор statements:

```text
версия A старая
версия B новая
модули есть
модулей нет
ошибка должна быть
ошибки нет
роль прошла
роль не прошла
```

Без оси времени эти statements выглядят как хаос.

### Почему это проблема

Диагностический вывод должен быть сравнительным:

```text
Было X.
Выполнили Y.
Стало Z.
Из X -> Y -> Z следует причина C.
```

Если есть только "стало Z", невозможно доказать, что именно Y изменил состояние.

### Детальный пример

Принимающий указал:

```text
То ты присылаешь, что версии соответствуют, теперь не соответствуют.
Ничего не понятно, на каком этапе задача.
```

Фактически оба утверждения могли быть истинными, но относились к разным моментам:

```text
after action before boundary:
running version != installed/module tree version

after boundary:
running version == installed/module tree version
```

Проблема была не в самих фактах, а в том, что они были поданы без state label.

Правильное объяснение должно было выглядеть так:

| Moment | running state | installed/module state | Conclusion |
|---|---|---|---|
| Before action | old | old | consistent |
| After action before boundary | old | new | inconsistent; boundary required |
| After boundary | new | new | consistent; downstream roles may run |

### Причина

Исполнитель делал narrative report вместо diagnostic comparison. Narrative report пытается объяснить историю словами. Diagnostic comparison показывает таблицу состояний и делает вывод только после нее.

### Что нужно делать иначе

Для любой stateful IaC-проблемы обязательна таблица:

```text
state -> command -> observed value -> expected value -> interpretation
```

Минимальный шаблон:

| State | Command | Observed | Expected | Interpretation |
|---|---|---|---|---|
| Before | command A | value A | value A | consistent baseline |
| After mutation | command A | value B | value C | mismatch detected |
| After boundary | command A | value C | value C | boundary resolved mismatch |

Без такой таблицы нельзя писать "причина в X".

## Ошибка 4: dry-run/check-mode был принят за доказательство runtime behavior

### Что произошло

В процессе обсуждения check-mode/dry-run был использован как диагностический сигнал, но отчет был сформулирован так, будто он доказывает поведение полного runtime workflow.

Принимающий справедливо остановил это:

```text
Он показал только одно: что вручную видно, что ребут нужен,
но не доказывает, что полный плейбук делает ребут.
```

### Почему это проблема

Check-mode отвечает на вопрос:

```text
что Ansible считает потенциально изменяемым без реального применения?
```

Он не отвечает на вопросы:

```text
был ли выполнен реальный boundary?
изменился ли boot_id?
перезапустился ли host?
собрались ли fresh facts после нового boot?
дошли ли downstream roles до нужного состояния?
```

В IaC-задачах, где важны reboot, service restart, package transaction, kernel/module state или VM orchestration, check-mode не является acceptance evidence.

### Детальный пример

Неверный диагностический вывод:

```text
check-mode показал, что boundary был бы нужен -> значит workflow корректен
```

Правильный вывод:

```text
check-mode показал только потенциальную необходимость mutation.
Для acceptance нужны real-run facts:
1. command executed
2. boot_id before
3. boundary command completed
4. boot_id after
5. fresh facts after boundary
6. downstream run completed
```

### Причина

Исполнитель смешал simulation signal и runtime proof. Это произошло из-за недостаточного разделения уровней доказательности.

### Что нужно делать иначе

Каждый diagnostic signal должен иметь evidence class:

| Evidence class | Что доказывает | Чего не доказывает |
|---|---|---|
| Static read | Что написано в коде | Что код работает |
| Syntax check | Что playbook парсится | Что поведение корректно |
| Lint | Что нет известных anti-pattern violations | Что lifecycle выполнен |
| Check-mode | Что могло бы измениться | Что реально изменилось |
| Real run | Что команда выполнилась | Что downstream state корректен |
| Before/after facts | Что state изменился | Почему изменился без action output |
| CI scenario | Что контракт воспроизведен в test env | Что все production variants покрыты |

Acceptance должен ссылаться только на evidence class, который доказывает конкретный acceptance criterion.

## Ошибка 5: непонятные diagnostic terms и "result records"

### Что произошло

Исполнитель использовал термины, которые не были объяснены принимающему: result records, ARA records, check mode, resume run, phase, completed status. Некоторые из этих терминов были технически связаны с инструментами, но в отчете они не были переведены в понятные операционные факты.

Прямая обратная связь:

```text
Что такое резалт рекордс?
То есть ансибл не умеет записывать записи?
Какие есть таблицы в ара?
То есть в таблице нет записей?
```

### Почему это проблема

Diagnostic terms должны помогать принимать решение. Если термин требует отдельного расследования, он ухудшает отчет.

Например, statement:

```text
result records отсутствуют
```

непонятен без объяснения:

```text
какая база?
какая таблица?
какой run ID?
что считается record?
какое expected count?
это failure Ansible, ARA callback, или query mistake?
```

### Детальный пример

Правильная форма отчета про ARA должна быть такой:

```text
ARA run id=3
path=/home/textyre/bootstrap/ansible/playbooks/...
status=completed
tasks=7
results=7

Interpretation:
ARA callback recorded every task result for this run.
This run is usable as evidence for task-level sequence.
```

Для другого run:

```text
ARA run id=4
status=completed
tasks=1389
results=1376
selected evidence:
- fact gathering completed
- package/AUR task completed
- kernel version detection tasks completed
- downstream verification completed
```

Если есть расхождение `tasks` и `results`, его нельзя называть "ARA лжет" или "Ansible не умеет записывать". Нужно объяснить возможные причины на уровне инструмента:

- skipped/optimized/internal tasks;
- callback не пишет некоторые event types;
- query смотрит не ту таблицу или не тот run;
- UI/API aggregate отличается от task result rows.

### Причина

Исполнитель докладывал внутренний diagnostic artifact вместо понятного evidence statement.

### Что нужно делать иначе

Любой tool-specific термин должен быть раскрыт:

| Term | Нужно объяснить |
|---|---|
| ARA run | ID, playbook path, status, duration |
| Result record | task result row, к какому task/run относится |
| Check-mode | dry-run simulation, не real mutation |
| CI job | workflow, job name, status, URL |
| VM clone | source snapshot, clone name, SSH endpoint |
| Fact | command/source, value, time/state |

## Detection Gaps

Эти ошибки не были пойманы сразу, потому что отсутствовали диагностические gates:

| Gap | Что должно было сработать |
|---|---|
| Утверждения делались без команд | Evidence-required rule before RCA |
| Разные VM states смешивались | Run ledger before every report |
| Check-mode попал в acceptance narrative | Evidence class labeling |
| Tool terms не объяснялись | Reviewer-facing diagnostics glossary |
| ARA/CI statuses докладывались без IDs | Run/job ID required in report |
| Причина называлась до comparison | Before/after comparison required before root cause |

## Что сработало

Процесс был восстановлен, когда принимающий потребовал:

- не объяснять без фактов;
- явно показать before и after;
- назвать конкретную машину и конкретный run;
- перестать смешивать разные состояния;
- не считать dry-run доказательством;
- показать, где именно хранится evidence;
- обновлять основной task artifact только после проверки.

После этого были собраны:

- baseline facts;
- after-action facts;
- after-boundary facts;
- ARA run IDs;
- selected task evidence;
- final run statuses;
- regression evidence;
- CI job statuses.

## Preventive Rules

### Для исполнителя

1. Не писать root cause без before/after comparison.
2. Не использовать факт без state label.
3. Не смешивать runs в одном абзаце без таблицы.
4. Не использовать check-mode как runtime proof.
5. Не вводить tool-specific terms без определения.
6. Отделять verified facts от hypotheses.
7. Если принимающий спрашивает "где факты?", остановить narrative и собрать evidence.

### Для принимающего

1. Требовать command + verbatim output для каждого critical claim.
2. Не принимать "похоже на" как root cause.
3. Требовать run ledger при VM/reboot/snapshot задачах.
4. Требовать explicit evidence class для check/lint/dry-run/real-run/CI.
5. Останавливать работу, если ответы начинают противоречить друг другу.

### Для ревьюера

1. Проверять, что acceptance evidence доказывает именно acceptance criteria.
2. Проверять, что facts соответствуют одному и тому же environment.
3. Проверять, что CI evidence отделено от local VM evidence.
4. Проверять, что tool statuses не интерпретированы сверх того, что они доказывают.

## Action Items

| Priority | Action | Owner | Status |
|---|---|---|---|
| P0 | Добавить обязательный run ledger для VM/snapshot/reboot задач | Исполнитель | Proposed |
| P0 | Ввести правило: root cause statement только после before/after table | Исполнитель | Proposed |
| P0 | Размечать evidence class: static, lint, check-mode, real-run, CI | Исполнитель + ревьюер | Proposed |
| P1 | Добавить в issue template секцию `Facts to collect` | Принимающий + исполнитель | Proposed |
| P1 | В отчетах писать ARA/CI IDs рядом со статусом | Исполнитель | Proposed |
| P1 | Запрещать acceptance через dry-run для lifecycle boundaries | Ревьюер | Proposed |
| P2 | Поддерживать reviewer-facing glossary для diagnostic terms | Исполнитель | Proposed |

## Критерий, что проблема не повторяется

Похожая задача считается диагностически готовой к реализации или acceptance только если можно ответить:

```text
1. Какая машина или environment проверялись?
2. Какой run ID или job ID обсуждается?
3. Какие факты были до действия?
4. Какая команда изменила состояние?
5. Какие факты стали после действия?
6. Какой evidence class доказывает acceptance criterion?
7. Какие утверждения остаются гипотезами?
8. Есть ли хотя бы одно противоречие между текущим отчетом и предыдущими отчетами?
```

Если хотя бы один ответ отсутствует, диагностика не готова для root cause или acceptance.
