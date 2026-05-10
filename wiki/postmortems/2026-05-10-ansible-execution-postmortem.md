# Постмортем: Ansible execution model и дисциплина playbook-работы

**Дата:** 2026-05-10
**Категория:** Ansible execution, Taskfile, facts, role boundaries, verification
**Статус:** draft
**Назначение:** классический постмортем по ошибкам понимания Ansible workflow и предотвращению неверного пути реализации.

## Краткий итог

Во время работы возникла путаница вокруг того, что именно должен делать Ansible workflow: где выполняется обновление системы, где должен быть reboot, когда запускается workstation, какие facts собираются, что означает check mode, что является доказательством успешного runtime behavior и какие изменения относятся к роли, playbook или тестам.

Главная проблема: Ansible execution model не был удержан как контракт. Вместо простого публичного lifecycle `prepare system -> reboot -> workstation` в обсуждении появлялись лишние фазы, термины и промежуточные сущности. Это создало риск реализовать не ту архитектуру и доказывать не то поведение.

## Проблема

В проекте Ansible должен выполняться через Taskfile на VM. Публичный workflow зафиксирован в документации и playbooks:

| Этап | Entry point | Смысл |
| --- | --- | --- |
| Syntax/lint | `task check`, `task lint` | Проверка структуры без изменения системы |
| Prepare system | `task prepare:system` | Bootloader maintenance и полное обновление ОС |
| Reboot | VM/system reboot | Переход на обновленное runtime state |
| Workstation | `task workstation` | Установка и настройка workstation поверх уже обновленной системы |
| Idempotency | повтор того же command на той же VM | Проверка отсутствия повторных изменений |

В ходе работы эта модель была размыта. Возникали вопросы:

- почему появились лишние фазы;
- почему часть package flow ушла после reboot;
- почему check mode воспринимался как доказательство reboot;
- почему использовались термины, которых не было в задаче;
- какие facts должны быть собраны до и после reboot;
- почему роль или playbook менялись не там, где должна быть граница ответственности.

## Влияние

| Последствие | Проявление |
| --- | --- |
| Архитектурная путаница | Простая последовательность была заменена сложной внутренней схемой |
| Неверные доказательства | Dry-run/check mode мог быть принят за proof runtime behavior |
| Слабая приемка | Ревьюер не видел прямую связь между задачей, facts и результатом |
| Риск сломать role boundaries | Workstation мог начать отвечать за update/reboot, хотя это отдельный lifecycle step |
| Риск тестировать не то | Тесты могли покрыть синтаксис или план, но не фактический reboot/runtime state |

## Причины проблемы

| Причина | Что произошло | Почему это опасно |
| --- | --- | --- |
| Execution contract не был записан перед изменениями | Агент начал менять структуру до фиксации целевой архитектуры | Можно реализовать лишние фазы и “resume” вместо нужного lifecycle |
| Check mode был недостаточно явно классифицирован | Сухой прогон объяснялся как часть доказательства поведения | Check mode не доказывает reboot и post-reboot execution |
| Facts не были первичным evidence | Не было строгого списка required facts до/после reboot | Нельзя доказать причинно-следственную связь |
| Role boundaries были размыты | Обновление системы, установка пакетов и workstation roles смешивались | Playbook становится грязным и трудно ревьюится |
| Отчеты не различали Ansible, VM и CI слои | Failure мог быть приписан не тому слою | Чинится не причина, а симптом |

## Что должно было быть архитектурным контрактом

| Контракт | Смысл |
| --- | --- |
| `prepare_system.yml` отвечает за подготовку и полное обновление ОС | Это pre-workstation lifecycle |
| Reboot происходит после prepare и до workstation | Workstation не должен стартовать на старом runtime state |
| `workstation.yml` отвечает за настройку workstation | Он не должен выполнять full OS upgrade |
| Facts собираются на каждом playbook run | После reboot facts должны быть заново собраны Ansible |
| Check mode не доказывает runtime execution | Он показывает planned changes, но не заменяет реальный run |
| Все execution идет через Taskfile | Не использовать прямой `ansible-playbook` как публичный путь |

## Обязательные Ansible facts и evidence

Для задач, где важны update/reboot/runtime consistency, minimum evidence должен быть таким.

| Evidence | Где собирать | Зачем |
| --- | --- | --- |
| `ansible_facts['os_family']` | В каждом relevant play | Не хардкодить distro behavior |
| Kernel release | До prepare, после prepare, после reboot | Проверить running kernel |
| Installed kernel/package state | После system update | Проверить installed state |
| Modules path for running kernel | До Docker/VM-sensitive ролей | Проверить kernel/modules consistency |
| Boot id | До и после reboot | Доказать, что reboot реально был |
| Ansible recap | После каждого run | Зафиксировать failed/changed |
| ARA play/task records | Во время long-running run | Наблюдать progress без чтения log |

Ключевое правило: facts должны не просто собираться Ansible, но и попадать в отчет, если на них строится вывод.

## Check mode: правильная классификация

Check mode полезен, но имеет ограниченный смысл.

| Что check mode доказывает | Что check mode не доказывает |
| --- | --- |
| Playbook синтаксически проходит до evaluated tasks | Что reboot реально был выполнен |
| Какие tasks могли бы измениться | Что service реально стартует после изменения |
| Что conditional logic вычисляется в текущем fact context | Что post-reboot facts будут такими же |
| Что часть modules поддерживает dry-run | Что все modules выполнили runtime side effects |

Практическое правило: если задача про reboot, kernel state, Docker service, VM guest integration или package runtime, check mode может быть только вспомогательным сигналом. Основное доказательство должно быть real run + facts + verification.

## Правила границ ролей

| Область | Где должна жить | Где не должна жить |
| --- | --- | --- |
| Full OS upgrade | `system_update` через `prepare_system.yml` | В `workstation.yml` package install flow |
| Package manager bootstrap | `package_manager` | В unrelated service roles |
| Workstation package set | `packages` | В system update role |
| AUR/workstation packages | Workstation package layer | В post-reboot cleanup phase без причины |
| Docker/runtime services | После reboot в workstation | До согласования kernel/modules state |
| VM integration | Роль `vm` с distro/init guards | В ручных VM командах |

Если role boundary не ясен, агент должен остановиться и сформулировать контракт до изменения кода.

## Что сработало

| Что сработало | Почему это полезно |
| --- | --- |
| В проекте появился явный `prepare_system.yml` | Полное обновление ОС вынесено перед workstation |
| `workstation.yml` сохранил роль настройки системы | Workstation не обязан быть reboot/checkpoint engine |
| Taskfile содержит `prepare:system` и `workstation` | Публичный lifecycle можно запускать предсказуемо |
| `gather_facts: true` есть в ключевых playbooks | Ansible может пересобрать facts после reboot |
| Test VM workflow запрещает прямой `ansible-playbook` | Execution surface защищен от ad hoc-путей |

## Что не сработало

| Что не сработало | Почему |
| --- | --- |
| Архитектура не была зафиксирована до правок | Из-за этого появились лишние термины и фазы |
| Отчеты не давали полного fact chain | Пользователь не видел доказательство причины и решения |
| Check mode был плохо объяснен | Dry-run воспринимался как странный второй запуск |
| Тесты на update/reboot появились не сразу | Поведение не было доказано TDD-путем с начала |
| Playbook cleanliness пострадала | Логика выглядела грязной из-за условий и fail messages |

## Что делать в будущем

### 1. Перед кодом фиксировать Ansible contract

Минимальный contract block:

| Поле | Содержание |
| --- | --- |
| Entry points | Какие `task ...` команды являются публичными |
| Role boundaries | Какая роль за что отвечает |
| Required facts | Какие facts нужны для доказательства |
| Reboot semantics | Кто инициирует reboot и как доказывается post-reboot state |
| Tests | Какие molecule/integration проверки доказывают поведение |
| Stop conditions | Когда агент обязан остановиться |

### 2. Писать tests до финальной реализации

Для Ansible behavior changes нужны два уровня:

| Уровень | Что покрывает |
| --- | --- |
| Role tests | Module arguments, idempotency, supported distro guards |
| Workflow tests | Порядок `prepare -> reboot -> workstation`, facts before/after, runtime verification |

Если поведение связано с reboot, unit-like role test недостаточен. Нужен workflow или VM-level evidence.

### 3. Упростить playbook logic

Playbook должен быть читаемым manifest of roles, а не контейнером сложной procedural logic.

| Если нужна сложная логика | Делать так |
| --- | --- |
| Validation | В отдельной role/task file с понятным именем |
| Long fail message | Вынести в vars или короткий assert с конкретным remediation |
| Distro-specific behavior | Использовать facts и vars files |
| Phase ordering | Делать через отдельные public playbooks, если это lifecycle boundary |
| Reboot barrier | Делать явным lifecycle step, а не скрытым checkpoint |

### 4. Отчитываться Ansible-фактами, а не словами

Каждый важный claim должен иметь форму:

| Claim | Evidence |
| --- | --- |
| “Prepare выполнил full update” | Taskfile command, recap, package manager output |
| “Reboot был выполнен” | boot id before/after |
| “Facts пересобраны после reboot” | новый Ansible run с `gather_facts: true` и observed facts |
| “Docker стартует после fix” | service/container verification command |
| “Idempotency сохранена” | second run recap with expected changed state |

## Профилактические действия

| Priority | Action | Result |
| --- | --- | --- |
| P0 | Добавить Ansible execution contract template в docs/skills | Агент фиксирует lifecycle до правок |
| P0 | Ввести required facts checklist для reboot/update задач | Нельзя принять решение без evidence |
| P0 | Запретить использовать check mode как доказательство runtime behavior | Dry-run больше не смешивается с real run |
| P1 | Добавить правило playbook cleanliness | Сложная логика уходит в роли/task files |
| P1 | Добавить тестовый шаблон для update/reboot roles | Поведение покрывается до merge |
| P2 | Добавить пример хорошего Ansible final report | Отчеты становятся короткими и проверяемыми |

## Критерии исправления

Ansible workflow считается здоровым, если:

- есть явный lifecycle `prepare:system -> reboot -> workstation`;
- full OS upgrade не живет внутри workstation setup;
- check mode всегда называется dry-run и не используется как runtime proof;
- facts before/after reboot представлены рядом;
- role boundaries понятны из playbook и docs;
- tests покрывают не только syntax/lint, но и critical behavior;
- execution идет через Taskfile на VM;
- любое отклонение от workflow считается blocker, а не творческим обходом.

## Финальный вывод

Ansible должен оставаться декларативным и проверяемым слоем, а не местом для импровизированных фаз и resume-механик. Правильный путь: сначала зафиксировать execution contract, затем написать или обновить tests, затем изменить роли/playbooks, затем доказать результат facts и real run. Без этой дисциплины агент легко начинает решать не исходную задачу, а собственную случайно созданную архитектуру.
