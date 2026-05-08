# Best practices написания, проектирования, сопровождения и развития Ansible-кода в зрелой инженерной среде

**Формат:** исследовательский документ  
**Тема:** архитектура ролей, паттерны проектирования, композиция, maintainability, безопасность, anti-patterns и практики зрелых инженерных команд  
**Основа:** синтез исследования, подготовленного по исходному ТЗ

---

## Аннотация

Главный вывод исследования такой: в зрелой инженерной среде Ansible-код рассматривают не как “набор YAML-файлов”, а как **automation product** с интерфейсом, совместимостью, жизненным циклом, правилами композиции и требованиями к безопасности.

Хорошая роль — это не просто папка `tasks/`, а **узкая и понятная единица ответственности** с явным контрактом входов, предсказуемой моделью исполнения и документированными путями расширения. Большие кодовые базы живут долго только тогда, когда оркестрация отделена от reusable-content, переменные не превращаются в глобальный хаос, а внешние роли и коллекции проходят такой же review, как обычный production code.  
Источник-класс: [Linux System Roles](https://linux-system-roles.github.io/), [Ansible docs](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html), [Red Hat COP](https://redhat-cop.github.io/automation-good-practices/).

---

## Оглавление

1. [Введение](#1-введение)
2. [Карта источников](#2-карта-источников)
3. [Главный синтез: как зрелые команды думают об Ansible](#3-главный-синтез-как-зрелые-команды-думают-об-ansible)
4. [Границы и ответственность роли](#4-границы-и-ответственность-роли)
5. [Архитектура роли и паттерны decomposition](#5-архитектура-роли-и-паттерны-decomposition)
6. [Управление переменными и role contract](#6-управление-переменными-и-role-contract)
7. [Maintainability и масштабирование больших Ansible-кодовых баз](#7-maintainability-и-масштабирование-больших-ansible-кодовых-баз)
8. [Anti-patterns и типовые failure modes](#8-anti-patterns-и-типовые-failure-modes)
9. [Security, hardening и governance](#9-security-hardening-и-governance)
10. [Как оценивать сторонние роли и open-source automation content](#10-как-оценивать-сторонние-роли-и-open-source-automation-content)
11. [Практики зрелых команд / enterprise / platform engineering style](#11-практики-зрелых-команд--enterprise--platform-engineering-style)
12. [Сводка практических принципов](#12-сводка-практических-принципов)
13. [Как дальше расширять это исследование](#13-как-дальше-расширять-это-исследование)
14. [Приложение: базовый checklist для review](#приложение-базовый-checklist-для-review)
15. [Приложение: ключевые источники и репозитории](#приложение-ключевые-источники-и-репозитории)
16. [Заключение](#заключение)

---

## 1. Введение

### Что является предметом исследования

Предмет исследования — не синтаксис Ansible и не beginner-level style rules, а **архитектура automation content**: границы роли, композиция, интерфейсы, структура task trees, управление переменными, безопасность, совместимость, review-практики и организационные подходы, которые позволяют поддерживать крупную Ansible-кодовую базу годами.

Официальная документация полезна здесь как источник истины для механики (`include_role`, `import_role`, precedence, handlers, `argument_specs`, `no_log`, signatures), но архитектурные выводы лучше видны в сочетании с практиками зрелых проектов и инженеров:
- [Ansible official docs](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Red Hat COP Automation Good Practices](https://redhat-cop.github.io/automation-good-practices/)
- [DebOps docs](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html)
- [OpenStack-Ansible docs](https://docs.openstack.org/openstack-ansible/)
- [Arista AVD docs](https://avd.arista.com/)
- [Jeff Geerling](https://www.jeffgeerling.com/)
- [Will Thames](https://willthames.github.io/)

### Чем архитектура отличается от syntax/style/linting

Style, linting и тесты важны, но они не заменяют архитектуру.

Архитектура отвечает на другие вопросы:

- где проходит граница роли;
- какие переменные составляют публичный контракт;
- где должна жить оркестрация;
- когда расширять существующую роль, а когда выделять новую;
- как не превращать reuse в скрытую связанность;
- как обновлять automation content без каскада регрессий.

Именно эти решения, а не формат YAML, определяют maintainability зрелого Ansible.

### Метод исследования

Во всём документе полезно различать три уровня утверждений:

1. **Официально подтверждённая модель** — то, что прямо следует из документации Ansible: semantics reuse-механизмов, precedence, handlers, `argument_specs`, `no_log`, подписи коллекций и т.д.
2. **Широко повторяющаяся практика** — то, что совпадает у Red Hat COP, DebOps, OpenStack-Ansible, linux-system-roles, AVD, Jeff Geerling, Will Thames и других сильных источников.
3. **Контекстная или спорная рекомендация** — то, где есть несколько школ и где trade-offs зависят от масштаба, команды, inventory model, platform model или истории проекта.

Эта рамка важна, потому что многие архитектурные решения в Ansible не являются “единственно правильными”; они являются **устойчивыми компромиссами**.

---

## 2. Карта источников

### Официальная документация Ansible — максимальный вес для механики

Официальные docs использовались как source of truth для:

- структуры ролей;
- разницы между `defaults` и `vars`;
- `import_*` vs `include_*`;
- `public` / `private_role_vars`;
- tag inheritance;
- handlers;
- `meta/argument_specs.yml`;
- `no_log`;
- проверки подписи коллекций;
- перехода к collections;
- testing strategies.

Это самый надёжный слой, когда речь идёт о том, **что именно делает Ansible runtime**.

Ключевые страницы:
- [Roles](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Include role](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/include_role_module.html)
- [Import tasks](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/import_tasks_module.html)
- [Include tasks](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/include_tasks_module.html)
- [Tags](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_tags.html)
- [Handlers](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_handlers.html)
- [Logging and no_log](https://docs.ansible.com/projects/ansible/latest/reference_appendices/logging.html)
- [Testing strategies](https://docs.ansible.com/projects/ansible/latest/reference_appendices/test_strategies.html)
- [Collection verification](https://docs.ansible.com/projects/ansible/latest/collections_guide/collections_verifying.html)

### Зрелые open-source репозитории и их документация — максимальный вес для живой архитектуры

Для architectural patterns особенно ценны:

- [DebOps](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html)
- [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/)
- [Linux System Roles](https://linux-system-roles.github.io/)
- [Arista AVD](https://avd.arista.com/)

Они показывают не “как можно”, а **как реально живёт крупный automation codebase**:
- naming discipline;
- dependent variables;
- soft dependencies;
- generated docs;
- release pinning;
- совместимость интерфейсов;
- pipeline decomposition;
- Molecule / `ansible-test`;
- upgrade discipline.

### Блоги и персональные сайты инженеров — высокий вес для trade-offs и review heuristics

Материалы сильных практиков полезны тем, что обсуждают **ошибки реальных команд**:

- [Jeff Geerling — how to evaluate community roles](https://www.jeffgeerling.com/blog/2019/how-evaluate-community-ansible-roles-your-playbooks/)
- [Jeff Geerling — Molecule testing](https://www.jeffgeerling.com/blog/2018/testing-your-ansible-roles-molecule/)
- [Will Thames — ansible-review](https://willthames.github.io/2016/06/28/announcing-ansible-review.html)
- [Will Thames — using command and shell in Ansible](https://willthames.github.io/2016/09/21/using-command-and-shell-in-ansible.html)
- [Marco Antonio Carcano — pitfalls and caveats](https://grimoire.carcano.ch/blog/ansible-playbooks-best-practices-caveats-and-pitfalls/)

Это не runtime truth, а инженерная эвристика. Но именно на этом слое лучше всего видны failure modes и признаки зрелости.

### Конференционные доклады — полезны для organizational / platform-level взгляда

Конференционные выступления важны как индикатор тем, которые реально волнуют зрелые команды:

- maintainability;
- scalability;
- GitOps-like workflows;
- modular automation;
- centralized execution;
- reusable building blocks.

Хорошие отправные точки:
- [Notes on Jeff Geerling’s AnsibleFest talk](https://tisgoud.nl/2019/09/make-your-ansible-playbooks-flexible-maintainable-and-scalable/)
- [AutoCon / Network Automation Forum](https://networkautomation.forum/autocon4)

### Хабр — полезный вторичный источник для русскоязычной практики

Полезные материалы:
- [Just AI — компонентный подход к большой Ansible-кодовой базе](https://habr.com/ru/companies/just_ai/articles/772382/)
- [OTUS — практики и типовые замечания](https://habr.com/ru/companies/otus/articles/540716/)

Особенно полезен Just AI: это пример зрелой альтернативной школы, где основным unit композиции является playbook-компонент, а роли и includes выступают внутренней реализацией.

### Stack Overflow — низкий вес и только для edge semantics

Stack Overflow уместен точечно:
- для include/import subtleties;
- для tricky precedence;
- для execution semantics edge cases.

Но это слабый источник для архитектурных рекомендаций. По возможности такие вопросы лучше закрывать official docs.

---

## 3. Главный синтез: как зрелые команды думают об Ansible

Повторяющийся паттерн во всех сильных источниках такой: зрелая команда стремится сделать так, чтобы Ansible-код можно было **читать локально, безопасно запускать повторно, обновлять без сюрпризов и расширять без форков всего дерева**.

Отсюда появляются одни и те же архитектурные принципы:

- узкие роли;
- defaults как интерфейс;
- явная композиция;
- минимум глобального состояния;
- namespacing;
- soft integration через facts и contracts;
- release discipline;
- curated supply chain.

Это видно:
- в [Linux System Roles](https://linux-system-roles.github.io/), где automation content мыслится как API;
- в [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/), где важны pinning, compatibility и controlled overrides;
- в [Arista AVD](https://avd.arista.com/), где design / render / validate разведены по слоям;
- в материалах [Red Hat COP](https://redhat-cop.github.io/automation-good-practices/), [Jeff Geerling](https://www.jeffgeerling.com/), [Will Thames](https://willthames.github.io/).

Иначе говоря, зрелость Ansible-кода — это не “много ролей” и не “всё покрыто линтером”. Это прежде всего:

- **ясные границы ответственности**;
- **предсказуемая модель исполнения**;
- **документированный role contract**;
- **контролируемый reuse**;
- **совместимость и upgrade path**;
- **review и supply-chain governance**.

---

## 4. Границы и ответственность роли

*Источники раздела: official docs + Red Hat COP + DebOps + Just AI + practitioner blogs.*

### Краткий вывод

Устойчивый консенсус таков: **роль должна отвечать за один понятный outcome или capability**, обычно вокруг одного сервиса, подсистемы или чётко определённой функции, а не за “кусок инфраструктуры вообще”.

При этом зрелые команды различают:
- **reusable role** — building block;
- **orchestration layer** — композиция нескольких building blocks.

### Устойчивые практики

#### 4.1. Проектировать роль вокруг функции, а не вокруг реализации

[Red Hat COP](https://redhat-cop.github.io/automation-good-practices/) рекомендует design around functionality, not implementation. Хороший пример: роль для NTP может скрывать выбор между `chronyd` и `ntpd`, потому что user-facing outcome остаётся тем же — синхронизация времени.

Но если два варианта реализации слишком расходятся по поведению, интерфейсу, lifecycle и side effects, они обычно заслуживают разных ролей.

[DebOps](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html) формулирует ещё жёстче: роль должна фокусироваться на конкретном сервисе или приложении.

#### 4.2. Оркестрацию держать отдельным слоем

Red Hat COP рекомендует держать playbooks как можно проще и сводить их к композиции ролей. Сложная логика должна жить:
- в reusable roles;
- или, если YAML становится слишком процедурным, в plugins/modules.

Это хорошо видно в [Arista AVD](https://avd.arista.com/): одна роль создаёт structured config, другая рендерит CLI-конфигурацию, а общий pipeline собирается на более высоком уровне.

#### 4.3. Делить роль, когда расходятся lifecycle, owner, interface или platform matrix

Роль разумно разделять, если внутри неё появляются:
- большие альтернативные ветви под разные продукты;
- разные owners или команды сопровождения;
- разные privilege boundaries;
- разные наборы входов/выходов;
- разная логика релизов и тестирования.

Именно так устроены зрелые кодовые базы вроде DebOps, Linux System Roles и AVD: reuse достигается не “god role”, а набором узких сочетаемых сущностей.

### Спорные моменты и trade-offs

#### 4.4. Role-centric vs playbook-centric школа

Здесь нет полного консенсуса.

Одна школа:
- playbooks должны быть простыми;
- логика должна жить в ролях.

Другая школа — хорошо описана в статье [Just AI](https://habr.com/ru/companies/just_ai/articles/772382/):
- основным unit’ом является playbook-компонент;
- роли могут быть внутренней реализацией;
- внешние роли оборачиваются в собственные component-playbooks.

Это особенно хорошо работает там, где inventory topology и naming conventions сами являются частью платформенной модели.

Общее между школами одно: **orchestration и reusable implementation не должны быть смешаны хаотически**.

#### 4.5. “Generic role” — полезная идея, но опасная формулировка

“Generic” должен быть **интерфейс и функциональный outcome**, а не бесконечный scope.  
Хорошая reusable роль не должна превращаться в kitchen sink с десятками feature flags и provider-branches.

### Anti-patterns

#### 4.6. God-role

Роль, которая одновременно:
- ставит приложение;
- настраивает БД;
- управляет firewall;
- выпускает TLS;
- создаёт пользователей;
- настраивает backup;
- включает monitoring;
- знает про конкретное окружение.

Такой дизайн убивает reuse и усложняет сопровождение.

#### 4.7. Role explosion

Обратная проблема — чрезмерное дробление. Если система превращается в лабиринт микроролей, каждая из которых не несёт самостоятельной инженерной ценности, cognitive overhead начинает перевешивать выгоду.

#### 4.8. Пустая оболочка вокруг чужой роли

Если “своя роль” не добавляет:
- собственного контракта,
- документации,
- controlled interface,
- тестов,
- организационной стандартизации,

то это часто всего лишь лишний уровень indirection.

### Реальные примеры

- **Хорошая декомпозиция:** роль NTP, абстрагирующая конкретную реализацию, но сохраняющая один outcome.  
- **Хорошая декомпозиция:** [DebOps](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html) строит роли вокруг конкретных сервисов и опирается на композицию через playbooks.  
- **Альтернативная зрелая декомпозиция:** [Just AI](https://habr.com/ru/companies/just_ai/articles/772382/) делает unit’ом playbook-компонент, а не роль.  
- **Плохая декомпозиция:** “роль приложения”, которая тащит за собой половину платформы и implicitly знает всё о конкретном environment.

---

## 5. Архитектура роли и паттерны decomposition

*Источники раздела: official docs + Red Hat COP + AVD + Geerling + DebOps.*

### Краткий вывод

В зрелом Ansible `tasks/main.yml` обычно не является “местом, где происходит всё”. Его нормальная роль — быть **тонким entry point / router layer**, который подключает feature-, provider-, OS- или phase-specific task files.

Важная инженерная цель здесь одна: человек должен быстро понять:
- какой у роли входной контракт;
- какие у неё entry points;
- где проходят branch points;
- что является internal detail, а что extension seam.

### Устойчивые практики

#### 5.1. Делать `main.yml` тонким и читаемым

Официальные docs прямо показывают pattern, где `main.yml` импортирует/включает меньшие файлы, когда это оправдано. Практика зрелых команд совпадает: большие линейные `main.yml` с сотнями строк плохо читаются и плохо review’ятся.

Хороший `tasks/main.yml` чаще всего:
- описывает фазы;
- выбирает provider;
- подключает OS-specific tasks;
- вызывает feature-specific блоки.

#### 5.2. Использовать явные entry points и `argument_specs`

Современный Ansible поддерживает `meta/argument_specs.yml`, где можно задать validation для role entry points.

Это критично важно, потому что превращает роль из “папки с тасками” в сущность с **контрактом**:
- какие аргументы обязательны;
- какие типы ожидаются;
- какие значения допустимы;
- что является supported interface.

См.: [Role argument validation](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html).

#### 5.3. Выделять subtask file, когда contract общий, и отдельную роль, когда contract отдельный

Практический критерий такой:

**Subtask file** уместен, когда:
- это внутренняя декомпозиция той же роли;
- публичный контракт остаётся тем же;
- lifecycle и owner не меняются.

**Отдельная роль** уместна, когда:
- появляется самостоятельный набор входов/выходов;
- логика имеет независимую ценность и reuse potential;
- нужен отдельный release/test lifecycle.

[Arista AVD](https://avd.arista.com/) — хороший пример: `eos_designs` и `eos_cli_config_gen` — это не subtasks друг друга, а разные роли с разными функциями и артефактами.

#### 5.4. Packaging related roles into collections

[Red Hat COP](https://redhat-cop.github.io/automation-good-practices/) рекомендует упаковывать связанные роли в collections, если между ними есть:
- общий namespace;
- общие plugins;
- общая точка дистрибуции;
- совместный release engineering.

Это делает distribution boundary явным и уменьшает хаос вокруг “папки roles плюс самодельные library/”.

#### 5.5. Сложную процедурную логику выносить в plugins/modules

Если роль или playbook начинает:
- симулировать язык общего назначения,
- держать много вычислительной логики в Jinja,
- использовать длинные цепочки conditionals,
- строить сложные структуры данных на лету,

это сигнал, что часть логики пора выносить в filter plugin, lookup, action plugin или custom module.

### Include / import patterns: что действительно важно

#### 5.6. Static reuse: `import_tasks`, `import_role`, `roles:`

Static reuse даёт:
- более предсказуемый execution graph;
- parse-time visibility;
- inheritance для некоторых сущностей, в том числе тегов.

Это полезно там, где важна ясность структуры и предсказуемость.

Документация:
- [import_tasks](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/import_tasks_module.html)
- [roles and imports](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html)

#### 5.7. Dynamic reuse: `include_tasks`, `include_role`

Dynamic includes хороши для:
- runtime branching;
- feature flags;
- provider selection;
- условного расширения.

Но они усложняют mental model: loops, conditions и tags ведут себя не так, как при static reuse.

Документация:
- [include_tasks](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/include_tasks_module.html)
- [include_role](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/include_role_module.html)

#### 5.8. Практический вывод

Недостаточно “знать разницу”. В зрелом коде важно иметь **intentional default strategy**:

- static import — по умолчанию для предсказуемой композиции;
- dynamic include — только там, где действительно нужна runtime-ветвистость.

Mix без явной причины — частый источник труднообъяснимого поведения.

### Handlers как отдельный архитектурный слой

Официальная docs подчёркивает, что handlers существуют в **global play-level scope**. Это означает:

- имена должны быть глобально уникальными;
- возможны коллизии;
- полезен `listen` для decoupling;
- handler — плохое место для скрытой orchestration logic;
- handler’ы не следует использовать как substitute для обычных task flows.

См.: [Handlers](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_handlers.html).

### Спорные моменты и trade-offs

#### 5.9. Hard dependencies в `meta/main.yml` vs soft dependencies

Официально dependencies поддерживаются. Но [DebOps](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html) предпочитает soft dependencies через playbooks, facts и documented contracts.

Причина понятна:
- hard dependency уменьшает явность orchestration;
- execution graph становится более “магическим”;
- скрытые связи усложняют reuse и дебаг.

Это не абсолютный запрет, но в зрелых кодовых базах dependency magic используется осторожно.

### Anti-patterns

#### 5.10. Лабиринт include/import-деревьев

Если flow невозможно восстановить без прыжков по десяткам файлов, decomposition уже не помогает.

#### 5.11. Случайное смешение static и dynamic reuse

Типовая ошибка: автор ожидает tag inheritance, но использовал dynamic include; или рассчитывает на локальность переменных, а imported role уже сделал их видимыми в broader scope.

#### 5.12. Handlers как скрытый workflow

Handlers удобны для restart/reload semantics, но плохо подходят для моделирования сложной логики деплоя.

### Реальные примеры

- **Хорошая декомпозиция:** [Arista AVD](https://avd.arista.com/4.7/roles/eos_designs/index.html) делит design pipeline на structured config generation и config rendering.
- **Хорошая декомпозиция:** provider-specific task files и var files по примеру [Red Hat COP](https://redhat-cop.github.io/automation-good-practices/).
- **Плохая декомпозиция:** огромный `main.yml`, смешивающий OS branches, feature flags, providers, `set_fact` и handlers.

---

## 6. Управление переменными и role contract

*Источники раздела: official docs + Red Hat COP + DebOps + OpenStack-Ansible + Will Thames + OTUS.*

### Краткий вывод

Зрелый Ansible начинается там, где переменные перестают быть “удобным способом что-то прокинуть” и становятся **явным публичным интерфейсом**.

В production-коде вопрос “где лежит переменная и какой у неё precedence” — это вопрос архитектуры.

### Официальная модель, которую нельзя игнорировать

Официальная docs фиксирует два базовых факта:

- `defaults/main.yml` имеет очень низкий precedence и предназначен для легко переопределяемых значений роли;
- `vars/main.yml` имеет высокий precedence и годится для внутренних констант или намеренно “жёстких” значений.

Из этого следует простой, но важный вывод: ошибиться с выбором `defaults` или `vars` — значит реально изменить override behavior.

См.: [Role variable precedence](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html).

### Устойчивые практики

#### 6.1. `defaults/main.yml` — публичная поверхность роли

Сильный повторяющийся паттерн у [Red Hat COP](https://redhat-cop.github.io/automation-good-practices/), DebOps и практиков: всё, что роль принимает извне, должно по возможности иметь default в `defaults/main.yml` и быть описано в документации.

Это повышает:
- discoverability;
- override ergonomics;
- читаемость интерфейса;
- стабильность контракта.

#### 6.2. `vars/main.yml` — только для internal constants

`vars/` — это sharp tool. Его разумно использовать для:
- внутренних “magic values”;
- неизменяемых mapping tables;
- platform mappings;
- того, что не должно casually override’иться.

Хороший контрпример — [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/queens/reference/configuration/using-overrides.html), где role vars сознательно используются как protected layer. Это зрелое, но очень контекстное решение.

#### 6.3. Все публичные переменные префиксовать именем роли

Поскольку в Ansible нет полноценного namespace для vars, сильные проекты рекомендуют префиксы.

Паттерны:
- `rolename_*` — публичные переменные;
- `__rolename_*` — внутренние переменные;
- у [DebOps](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html) — строгий стиль вида `role__var`.

Это один из самых практичных и широко повторяющихся приёмов во всём корпусе.

#### 6.4. Не переопределять интерфейс роли через `set_fact`

[Red Hat COP](https://redhat-cop.github.io/automation-good-practices/) прямо предупреждает против этого. `set_fact` создаёт состояние, которое:
- живёт дальше в play;
- трудно “откатить”;
- усложняет reasoning;
- может неожиданно влиять на последующие вызовы роли.

#### 6.5. Inventory — source of truth, `host_vars` — только для действительно host-specific данных

[DebOps](https://docs.debops.org/en/stable-2.1/user-guide/debops-for-ansible.html) подчёркивает inventory-as-source-of-truth.  
[Will Thames](https://willthames.github.io/) рекомендует использовать `host_vars` только для реально уникальных свойств конкретного хоста, а не как общий склад окруженческих настроек.

#### 6.6. OS- / version-specific данные лучше выносить в var files

Вместо длинных `when:`-каскадов по платформам устойчивый паттерн такой:
- отдельные var files;
- отдельные provider-specific task files;
- ясная точка выбора.

Это улучшает локальную читаемость и облегчает добавление новых платформ.

#### 6.7. Межролевую интеграцию строить через facts и provider/consumer contracts

[DebOps](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html) особенно последовательно проводит мысль: роли не должны напрямую читать variables друг друга. Вместо этого лучше использовать:
- facts;
- dependent variables;
- documented interfaces;
- provider/consumer contracts.

Сильный пример — `ansible_local.*` как устойчивый источник данных для других ролей.

#### 6.8. Collection-wide variables — только через role defaults

Если у collection есть общие настройки, зрелый паттерн — пробрасывать их в роли через собственные defaults каждой роли, а не заставлять роли жёстко зависеть от shared globals.

### Спорные моменты и trade-offs

#### 6.9. Flat vars vs nested dicts

Jeff Geerling тяготеет к более плоским структурам ради читаемости и простоты override. Но есть исключения: [AVD](https://avd.arista.com/) использует rich structured data models вполне осознанно.

Практический вывод:
- nested structures хороши, если это действительно **data model**;
- они плохи, если это просто хаотическая группировка “всё в один dict”.

#### 6.10. Когда нет safe default

Если безопасного или осмысленного default нет, зрелая стратегия — fail fast. Placeholder в defaults допустим ради discoverability, но роль не должна тихо идти по опасному пути.

### Anti-patterns

#### 6.11. Var spaghetti

Признаки:
- непредсказуемый precedence;
- непонятно, где определяется значение;
- много `set_fact`;
- непонятные глобальные имена вроде `port`, `user`, `packages`;
- interface размазан между inventory, defaults, vars и task vars.

#### 6.12. Прямое чтение переменных другой роли

Это textbook hidden dependency.

#### 6.13. `vars/` как “ещё один defaults”

Такой дизайн делает роль формально reusable, но фактически ломает нормальный override model.

### Реальные примеры

- **Хороший пример contract discipline:** [DebOps design proposal](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html).
- **Хороший пример decoupling:** публикация фактов через `ansible_local.*`.
- **Контекстный, но зрелый пример sharp internal vars:** [OpenStack-Ansible overrides model](https://docs.openstack.org/openstack-ansible/queens/reference/configuration/using-overrides.html).

---

## 7. Maintainability и масштабирование больших Ansible-кодовых баз

*Источники раздела: OpenStack-Ansible + Linux System Roles + AVD + official docs + Geerling + Will Thames + Marco Carcano + Just AI.*

### Краткий вывод

Большая Ansible-кодовая база деградирует не от того, что в ней мало линтеров, а от того, что в ней **нет совместимой модели эволюции**.

Зрелые проекты удерживают качество через:
- versioning;
- pinning;
- compatibility promises;
- generated docs;
- CI against multiple versions;
- check-mode / idempotency discipline;
- curated override paths;
- Git-driven review.

### Устойчивые практики

#### 7.1. Роль или collection — это versioned artifact

[Red Hat COP](https://redhat-cop.github.io/automation-good-practices/) рекомендует semantic versioning.  
[Will Thames](https://willthames.github.io/) советует version common roles и pin revisions.  
[OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/) показывает зрелую форму этой идеи — жёсткий pinning ролей и связанного контента.

Главная идея: automation content должен быть **reproducible**.

#### 7.2. Документировать не только usage, но и совместимость

Зрелые проекты документируют:
- supported platforms;
- minimum Ansible/core version;
- supported interface;
- override paths;
- deprecations;
- migration notes.

Это видно у:
- [Linux System Roles](https://linux-system-roles.github.io/)
- [Arista AVD](https://avd.arista.com/)
- [DebOps](https://docs.debops.org/)
- [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/)

#### 7.3. Делать check mode и idempotency частью нормальной практики

Official docs рекомендует использовать `--check` не как экзотику, а как нормальный способ проверять drift.  
[Just AI](https://habr.com/ru/companies/just_ai/articles/772382/) делает регулярные прогоны `-CD` частью operational confidence.

Это важный зрелый паттерн: check mode — не просто CI-флаг, а средство удерживать код и реальность в синхроне.

#### 7.4. Встраивать review и quality gates в Git-процесс

Хороший review для Ansible — это не только “посмотреть YAML глазами”.

Нужны:
- linting;
- Molecule и/или `ansible-test`;
- idempotency checks;
- review именно diff’ов;
- проверка interface changes;
- проверка compatibility and blast radius.

Полезные источники:
- [ansible-review](https://willthames.github.io/2016/06/28/announcing-ansible-review.html)
- [Molecule testing by Jeff Geerling](https://www.jeffgeerling.com/blog/2018/testing-your-ansible-roles-molecule/)

#### 7.5. Не продвигать POC-структуру в production без переработки

[Marco Carcano](https://grimoire.carcano.ch/blog/ansible-playbooks-best-practices-caveats-and-pitfalls/) очень точно описывает типичную проблему: proof of concept случайно становится baseline для production и тянет за собой:
- дублирование;
- хаотичные имена;
- отсутствие boundaries;
- хрупкие playbooks;
- непредсказуемый upgrade path.

### Спорные моменты и trade-offs

#### 7.6. Monorepo vs per-role repos vs collections

Единого winner нет.

- AVD живёт как collection-centered проект.
- OpenStack использует интегрированную экосистему с большим release governance.
- Внутренние команды нередко держат monorepo для инфраструктурного content.

Практический вывод:
важнее не форма репозитория, а наличие:
- clear boundaries;
- versioning;
- docs;
- test pipeline;
- release policy.

#### 7.7. Hard dependencies vs explicit orchestration

Это повторяющийся trade-off: dependency magic уменьшает явность, но иногда упрощает интеграцию. Хороший вопрос для review не “можно ли так”, а “будет ли execution graph понятен через полгода”.

### Anti-patterns

#### 7.8. Документация живёт отдельно от кода

Когда contract роли описан в wiki, а код живёт отдельно, документация почти неизбежно начинает отставать.

#### 7.9. Непиненные зависимости

Внешняя роль или collection без pinning резко ухудшает воспроизводимость.

#### 7.10. Тестирование только YAML, но не deploy outcome

Бессмысленно тестировать “установился ли пакет”, если именно это уже делает модуль. Зрелые тесты должны подтверждать функциональное состояние системы, а не дублировать декларацию desired state.

### Реальные примеры

- **OpenStack-Ansible** — сильный пример release engineering, pinning и controlled overrides.
- **Linux System Roles** — пример идеи “automation API”.
- **Arista AVD** — пример collection-grade maintainability и CI discipline.
- **Just AI** — пример engineering governance вокруг check mode, idempotency и component-based composition.

---

## 8. Anti-patterns и типовые failure modes

*Источники раздела: synthesis over official docs, Red Hat COP, DebOps, Geerling, Will Thames, OTUS, Just AI.*

### Краткий вывод

Почти все антипаттерны зрелого Ansible — это разные формы одного и того же дефекта: **нарушение локальности reasoning**.

Если для понимания одной роли нужно знать:
- пол-репозитория,
- run order,
- десяток скрытых vars,
- поведение нескольких side-effectful `set_fact`,
- неочевидные теги и handlers,

то код перестаёт быть инженерным активом и становится источником incidental complexity.

### Основные anti-patterns

#### 8.1. Overly generic roles

“Универсальная роль” часто означает:
- бесконечный scope;
- накопление provider branches;
- feature toggles без границ;
- отсутствие ясного contract boundary.

#### 8.2. Hidden dependencies

Роль implicitly ожидает, что:
- до неё уже выполнилась другая роль;
- кто-то выставил нужные facts;
- нужные vars уже лежат в inventory;
- handlers имеют конкретные имена;
- определённый execution order “сам собой сложится”.

#### 8.3. Var spaghetti

Признаки:
- переменные размазаны по inventory, defaults, vars, task vars и `set_fact`;
- имена без префиксов;
- precedence непредсказуем;
- понять источник значения трудно даже автору.

#### 8.4. Excessive conditionals

Сотни строк `when:` по платформам, окружениям и фичам — почти всегда smell. В устойчивом дизайне большая часть этой сложности выражается структурой файлов и явными branch points.

#### 8.5. Role explosion

Слишком много мелких ролей создаёт nav-overhead и затрудняет понимание execution graph.

#### 8.6. Misuse of `include` / `import`

Когда автор не учитывает разницу между static и dynamic reuse, поведение с tags, loops и variable visibility начинает удивлять команду.

#### 8.7. Плохие практики с defaults и vars

Наиболее типичные:
- всё складывается в `vars/`;
- публичный интерфейс не виден в `defaults/`;
- роль нельзя нормально override’ить;
- внутренние константы смешаны с пользовательскими настройками.

#### 8.8. `command` / `shell` как основной механизм автоматизации

Это не всегда ошибка, но сильный smell. Если в экосистеме есть нормальный declarative module, его обычно нужно предпочесть. Если `command`/`shell` неизбежен, нужно внимательно работать с `changed_when`, `creates`, `removes`, `check_mode`.

См.: [Will Thames on command and shell](https://willthames.github.io/2016/09/21/using-command-and-shell-in-ansible.html)

#### 8.9. `ignore_errors` как control flow

Зрелый error handling обычно строится через `block` / `rescue` / `always`, а не через silent failure.

#### 8.10. Tag matrix как скрытый язык исполнения

Теги полезны как operational selector, но плохо подходят на роль главного архитектурного механизма. Слишком сложная tag matrix создаёт ещё один невидимый слой поведения.

### Реальные примеры

- **Показательно плохой пример:** Jeff Geerling’s “Bad Judgement” role из статьи про оценку community roles — хороший учебный пример архитектурного и quality smell’а: platform mismatch, неверные условия, test noise, misleading metadata.
- **Показательно хороший контраст:** AVD, OpenStack, DebOps и Linux System Roles не полагаются на магию “как-нибудь срастётся”; они делают interface, release behavior и test strategy частью продукта.

---

## 9. Security, hardening и governance

*Источники раздела: official docs + AWX docs + Automation Hub / Red Hat + SOPS docs + Geerling + OTUS + security-oriented roles.*

### Краткий вывод

Безопасность зрелого Ansible-кода — это не только “положить пароль в Vault”. Это комбинация:

- secret hygiene;
- privilege boundaries;
- supply-chain trust;
- controlled reuse;
- human review;
- governance вокруг automation content.

### Устойчивые практики

#### 9.1. Секреты должны быть first-class concern

Официальная экосистема даёт:
- [Ansible Vault](https://docs.ansible.com/)
- [community.sops guide](https://docs.ansible.com/projects/ansible/latest/collections/community/sops/docsite/guide.html)

Независимо от выбранного механизма, зрелая практика требует:
- не хранить секреты в открытых inventory/vars;
- иметь предсказуемую схему доступа;
- поддерживать review-friendly format;
- понимать, как secrets работают в CI/CD и при break-glass сценариях.

#### 9.2. `no_log` полезен, но не является полной защитой

Официальная docs подчёркивает: `no_log: true` защищает логирование задачи, но не делает секреты магически неуязвимыми. Они всё ещё могут утечь через:
- неосторожный `debug`;
- template content;
- registered vars;
- side effects в других задачах.

См.: [Logging and no_log](https://docs.ansible.com/projects/ansible/latest/reference_appendices/logging.html)

#### 9.3. Least privilege — и на controller side, и на managed hosts

[AWX security best practices](https://docs.ansible.com/projects/awx/en/24.6.1/administration/security_best_practices.html) напоминают: controller — это тоже production surface.

Зрелые практики:
- минимизировать число root/admin accounts;
- ограничивать `become`;
- делать escalation явным и локальным;
- разделять read-only, validate и mutating execution paths, где это возможно.

#### 9.4. Внешний automation content — это supply chain

[Automation Hub](https://www.redhat.com/en/technologies/management/ansible/automation-hub) и Private Automation Hub задают enterprise-ориентир:
- curated repositories;
- provenance;
- governance;
- trusted distribution channels.

Даже если команда не использует Automation Hub, сама мысль остаётся верной: community content нельзя считать “просто конфигом”. Это исполняемый код.

#### 9.5. Проверка подписей коллекций

Официальная docs описывает `ansible-galaxy collection verify --keyring` и одновременно указывает границы этой защиты: verification работает не для всех способов установки.

Практический вывод:
- установка “просто из git” не эквивалентна проверенному происхождению артефакта;
- provenance должен быть осмысленным аспектом review.

#### 9.6. Review внешних ролей и коллекций как production code

[Jeff Geerling](https://www.jeffgeerling.com/blog/2019/how-evaluate-community-ansible-roles-your-playbooks/) прямо советует не доверять витрине Galaxy как индикатору качества. Нужно смотреть:
- task structure;
- variable naming;
- README и examples;
- supported platforms;
- tests;
- declared version compatibility;
- license;
- signs of maintenance.

### Спорные моменты и trade-offs

#### 9.7. Vault vs SOPS vs внешние secret managers

Единого победителя нет. Выбор зависит от:
- инфраструктуры ключей;
- KMS/PKI landscape;
- требований аудита;
- удобства в CI/CD;
- требований к ротации;
- governance и доступов.

#### 9.8. Certified vs validated vs community content

Разные классы внешнего content несут разный уровень доверия и разную support model. Для зрелой команды это значит: governance всё равно остаётся вашей внутренней обязанностью.

### Anti-patterns

#### 9.9. “У нас есть `no_log`, значит всё безопасно”

Нет. Это лишь один слой защиты.

#### 9.10. Blind trust к GitHub / Galaxy-контенту

Если роль:
- не прочитана;
- не протестирована;
- не pinned;
- не имеет понятного provenance story,

то это uncontrolled code execution.

#### 9.11. Слишком широкий доступ к controller / AWX

Controller — это не просто “машина, откуда запускается playbook”, а часть production trust boundary.

### Реальные примеры

- **Хороший security-oriented пример:** [`konstruktoid/ansible-role-hardening`](https://github.com/konstruktoid/ansible-role-hardening) — role с documentation, tests, SECURITY.md, supported platforms и явными предупреждениями о необходимости локального тестирования.
- **Хороший supply-chain пример:** curated distribution model из [Automation Hub](https://www.redhat.com/en/technologies/management/ansible/automation-hub).
- **Небезопасный паттерн:** брать Galaxy role “по рейтингу”, без code review, pinning и tests.

---

## 10. Как оценивать сторонние роли и open-source automation content

*Источники раздела: Jeff Geerling + official docs + Red Hat content ecosystem + mature repos.*

### Краткий вывод

Community role или collection нельзя оценивать только по:
- количеству звёзд;
- Galaxy score;
- README badges;
- популярности автора.

Зрелая команда смотрит на **architecture signals**:
- есть ли ясный contract;
- разделены ли task files логично;
- есть ли tests и CI;
- перечислены ли supported platforms;
- есть ли versioning / pinning policy;
- понятен ли upgrade path;
- виден ли provenance.

### Практический чек-лист

#### Сильные сигналы качества

- логичная структура task includes и осмысленные имена файлов;
- `defaults/` как видимый интерфейс;
- наличие `meta/argument_specs.yml`;
- примеры использования;
- supported platforms и declared minimum Ansible/core version;
- Molecule и/или `ansible-test`;
- release tags / semver / pinning policy;
- документация по override paths и limitations;
- признаки активного сопровождения;
- нормальная license story.

#### Красные флаги

- platform-specific modules без OS guards;
- declared minimum Ansible version ниже реально используемых возможностей;
- `skip_ansible_lint` без убедимой причины;
- отсутствующие или декоративные тесты;
- скрытые зависимости;
- непонятная модель переменных;
- установка “с головы git main” без pinning;
- отсутствие указаний на совместимость и maintenance status.

### Практика зрелой команды

Перед подключением внешнего content команда обычно отвечает на вопросы:

1. Каков публичный интерфейс роли/collection?
2. Какие переменные считаются supported?
3. Что будет точкой расширения: vars, hooks, wrapper role, component playbook, fork?
4. Как это тестируется локально и в CI?
5. Что мы будем делать при breaking change?
6. Есть ли sane pinning strategy?
7. Кто owner внутри команды?

### Реальные примеры

- **Учебный bad example:** [Jeff Geerling — How to evaluate community roles](https://www.jeffgeerling.com/blog/2019/how-evaluate-community-ansible-roles-your-playbooks/)
- **Positive benchmark class:** [AVD](https://avd.arista.com/), [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/), [Linux System Roles](https://linux-system-roles.github.io/), [DebOps](https://docs.debops.org/)

---

## 11. Практики зрелых команд / enterprise / platform engineering style

*Источники раздела: Linux System Roles + OpenStack-Ansible + AVD + Geerling talk notes + Just AI + GitOps-style talks.*

### Краткий вывод

У сильных команд повторяются не одинаковые directory trees, а **архитектурные инварианты**. Они одинаково узнаваемы в enterprise infra, platform engineering, SRE и network automation:

- Git как control plane;
- build/controller как consistent execution environment;
- модульная композиция;
- интерфейсность ролей;
- curated content distribution;
- upgrade discipline;
- drift checks;
- разделение design / render / deploy / validate.

### Что повторяется особенно часто

#### 11.1. Automation content как API

[Linux System Roles](https://linux-system-roles.github.io/) говорит об automation “API” прямо.  
AVD и OpenStack фактически реализуют тот же принцип через стабильные входные модели и controlled overrides.

Это один из главных признаком зрелости: роль перестаёт быть “скриптом”, а становится интерфейсом.

#### 11.2. Git-driven changes, а не ручное изменение инфраструктуры

У зрелых команд:
- изменения проходят через Git;
- review выполняется до запуска;
- execution environment воспроизводим;
- ручные правки в managed state считаются drift.

Это видно и в практиках [Just AI](https://habr.com/ru/companies/just_ai/articles/772382/), и в GitOps-подобных обсуждениях на конференциях.

#### 11.3. Separation of design and execution

[Arista AVD](https://avd.arista.com/) особенно хорошо показывает зрелый pattern:
- input model;
- structured config;
- generated config / docs;
- post-deploy validation.

Это уже полноценный automation pipeline, а не просто последовательность YAML-задач.

#### 11.4. Явные extension seams лучше форков

Зрелые платформенные проекты стараются дать sanctioned way для расширения:
- variables;
- documented hooks;
- wrapper roles;
- structured config overlays;
- explicit plugin points.

Это сильно лучше, чем заставлять команду форкать upstream при каждом нестандартном сценарии.

#### 11.5. Governance вокруг distribution и execution

В зрелой среде важны:
- curated registries;
- execution environments;
- approved content sets;
- release trains;
- compatibility matrix;
- documented ownership.

### Где реально есть разные школы

#### 11.6. Role-first зрелость

Роль — основной reusable unit, orchestration живёт выше.

#### 11.7. Component-first зрелость

Playbook-компонент — основной публичный unit, роль — внутренняя реализация. Хороший пример: Just AI.

#### 11.8. Collection/API-first зрелость

Главная единица — collection как пакет ролей, plugins, docs и test tooling.

Эти подходы не взаимоисключающие. В большой организации они могут сосуществовать на разных уровнях платформы.

### Реальные примеры

- **Linux System Roles** — automation API mindset.
- **OpenStack-Ansible** — release engineering и controlled override model.
- **Arista AVD** — structured automation pipeline.
- **Just AI** — component-oriented internal engineering model.

---

## 12. Сводка практических принципов

Ниже — компактная версия выводов, которую можно использовать как внутренний engineering guide.

1. **Считайте роль versioned automation API, а не папкой с YAML.**
2. **Граница роли = одна capability / service / outcome.**
3. **Generic делайте интерфейс, а не бесконечный scope.**
4. **Оркестрацию держите выше reusable roles.**
5. **`defaults/main.yml` — это public interface; `vars/main.yml` — internal constants.**
6. **Все публичные переменные префиксуйте именем роли; внутренние — `__role_*`.**
7. **Не переопределяйте интерфейс роли через `set_fact`.**
8. **Используйте `meta/argument_specs.yml` и fail fast.**
9. **Static imports — для предсказуемой композиции; dynamic includes — для runtime branching.**
10. **OS/provider branching выражайте файлами и entry points, а не каскадами `when`.**
11. **Интеграцию между ролями стройте через facts, dependent vars и documented contracts.**
12. **Handlers держите простыми, локально понятными и уникально именованными.**
13. **Тестируйте не только YAML, но и deploy outcome.**
14. **Pin, review и документируйте внешние роли и collections.**
15. **Treat the controller as production surface.**
16. **Не продвигайте POC-структуру в production без архитектурной переработки.**
17. **Документируйте supported interface, supported platforms и upgrade path.**
18. **Любая скрытая связанность — кандидат на redesign.**
19. **Любая переменная без ясного owner и namespace — потенциальный баг.**
20. **Любой reuse без контроля совместимости со временем превращается в источник регрессий.**

---

## 13. Как дальше расширять это исследование

### Какие типы источников ещё стоит смотреть

- maintainer discussions в issues/PRs зрелых репозиториев;
- porting guides и release notes;
- conference transcripts, а не только анонсы и заметки;
- security advisories и supply-chain guidance;
- public postmortems и incident writeups по automation failures;
- internal engineering blogs platform/SRE команд, если они доступны.

### Какие репозитории и доклады стоит изучать глубже

- [DebOps](https://docs.debops.org/en/stable-3.3/dep/dep-0002.html) — variable architecture, dependent variables, soft dependencies.
- [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/) — release engineering, pinning, override governance.
- [Linux System Roles](https://linux-system-roles.github.io/) — automation API и consistency.
- [Arista AVD](https://avd.arista.com/) — collection-scale architecture, design/render separation, extension seams.
- [`konstruktoid/ansible-role-hardening`](https://github.com/konstruktoid/ansible-role-hardening) — security-oriented role design.
- [Jeff Geerling](https://www.jeffgeerling.com/) — maintainability talks and review heuristics.
- [Will Thames](https://willthames.github.io/) — review, module usage, quality practices.
- [Network Automation Forum / AutoCon](https://networkautomation.forum/autocon4) — modular Ansible и platform-level automation.

### Какие темы требуют отдельного исследования

- collections design как самостоятельная дисциплина;
- plugin design и custom module strategy;
- testing strategy: Molecule vs `ansible-test`, fixture design, ephemeral environments;
- security review process для automation content;
- enterprise governance вокруг approved content;
- execution environments и dependency locking;
- migration path от ad-hoc roles к structured collections;
- lifecycle management и deprecation policy для internal automation APIs.

---

## Приложение: базовый checklist для review

Этот список можно использовать в code review, design review или при приёмке новой роли.

### 1. Граница роли

- Есть ли у роли одна понятная responsibility boundary?
- Не смешивает ли роль orchestration с reusable implementation?
- Не тащит ли она в себя unrelated subsystems?

### 2. Интерфейс

- Видны ли пользовательские настройки в `defaults/`?
- Есть ли понятный namespace у переменных?
- Есть ли `argument_specs` или хотя бы документированный контракт?
- Понятно ли, какие переменные считаются supported interface?

### 3. Декомпозиция

- `tasks/main.yml` остаётся тонким entry point’ом?
- Разделены ли OS/provider/feature-specific ветви по файлам?
- Нет ли лабиринта includes/imports?
- Не нужна ли отдельная роль или plugin вместо ещё одного task file?

### 4. Execution semantics

- Используются ли static vs dynamic includes осознанно?
- Нет ли неочевидного поведения с tags?
- Нет ли hidden handlers logic?
- Не строится ли control flow на `ignore_errors`?

### 5. Переменные и state

- Нет ли `var spaghetti`?
- Не злоупотребляет ли код `set_fact`?
- Нет ли прямого чтения vars другой роли?
- Не спрятан ли user-facing interface в `vars/`?

### 6. Безопасность

- Где хранятся секреты?
- Используется ли `no_log` там, где нужно?
- Явно ли ограничены права `become`?
- Понятно ли provenance внешнего content?

### 7. Maintainability

- Есть ли examples, tests и documentation?
- Заявлены ли supported platforms и versions?
- Есть ли pinning policy для внешних зависимостей?
- Есть ли upgrade path или deprecation notes?

### 8. Reuse и расширяемость

- Можно ли расширить роль без форка?
- Есть ли sanctioned extension seams?
- Не создаёт ли роль unnecessary coupling?
- Не станет ли текущий дизайн ловушкой через 6–12 месяцев?

---

## Приложение: ключевые источники и репозитории

### Official docs

- [Ansible Roles](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Include role](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/include_role_module.html)
- [Import tasks](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/import_tasks_module.html)
- [Include tasks](https://docs.ansible.com/projects/ansible/latest/collections/ansible/builtin/include_tasks_module.html)
- [Tags](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_tags.html)
- [Handlers](https://docs.ansible.com/projects/ansible/latest/playbook_guide/playbooks_handlers.html)
- [Logging and no_log](https://docs.ansible.com/projects/ansible/latest/reference_appendices/logging.html)
- [Testing strategies](https://docs.ansible.com/projects/ansible/latest/reference_appendices/test_strategies.html)
- [Collection verification](https://docs.ansible.com/projects/ansible/latest/collections_guide/collections_verifying.html)
- [community.sops guide](https://docs.ansible.com/projects/ansible/latest/collections/community/sops/docsite/guide.html)
- [AWX security best practices](https://docs.ansible.com/projects/awx/en/24.6.1/administration/security_best_practices.html)

### Mature projects / repositories

- [DebOps](https://docs.debops.org/)
- [OpenStack-Ansible](https://docs.openstack.org/openstack-ansible/)
- [Linux System Roles](https://linux-system-roles.github.io/)
- [Arista AVD](https://avd.arista.com/)
- [`konstruktoid/ansible-role-hardening`](https://github.com/konstruktoid/ansible-role-hardening)

### Engineer blogs / practice-oriented material

- [Jeff Geerling](https://www.jeffgeerling.com/)
- [Jeff Geerling — evaluating community roles](https://www.jeffgeerling.com/blog/2019/how-evaluate-community-ansible-roles-your-playbooks/)
- [Jeff Geerling — testing with Molecule](https://www.jeffgeerling.com/blog/2018/testing-your-ansible-roles-molecule/)
- [Will Thames](https://willthames.github.io/)
- [Will Thames — ansible-review](https://willthames.github.io/2016/06/28/announcing-ansible-review.html)
- [Will Thames — using command and shell](https://willthames.github.io/2016/09/21/using-command-and-shell-in-ansible.html)
- [Marco Carcano — pitfalls and caveats](https://grimoire.carcano.ch/blog/ansible-playbooks-best-practices-caveats-and-pitfalls/)

### Talks / notes / conference-related material

- [Notes on Jeff Geerling’s AnsibleFest talk](https://tisgoud.nl/2019/09/make-your-ansible-playbooks-flexible-maintainable-and-scalable/)
- [Network Automation Forum / AutoCon](https://networkautomation.forum/autocon4)

### Russian-language secondary material

- [Just AI on Habr](https://habr.com/ru/companies/just_ai/articles/772382/)
- [OTUS on Habr](https://habr.com/ru/companies/otus/articles/540716/)

---

## Заключение

Если свести весь корпус к одной формуле, она будет такой:

> **зрелый Ansible — это explicit contracts, narrow boundaries, controlled composition, low hidden state, documented evolution и governed supply chain**

В этом и состоит разница между “набором playbooks, который пока работает” и инженерной системой автоматизации, которая может жить годами, переживать рост команды, смену платформ, смену зависимостей и неизбежные архитектурные изменения.

Именно поэтому сильные репозитории и сильные инженеры снова и снова приходят к одним и тем же решениям:

- namespacing;
- defaults-as-interface;
- soft integration;
- versioning;
- CI;
- curated content;
- Git-driven delivery;
- separation of orchestration from reusable automation content.

Все остальные техники — форматирование YAML, выбор линтеров, стиль именования отдельных тасков — важны лишь постольку, поскольку они поддерживают эти свойства, а не заменяют их.
