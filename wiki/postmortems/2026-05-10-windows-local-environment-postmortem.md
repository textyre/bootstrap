# Постмортем: Windows local environment и быстрые фиксы окружения

**Дата:** 2026-05-10
**Категория:** Windows local environment, host tooling, venv, shell boundary
**Статус:** draft
**Назначение:** практическое руководство для устранения повторяющихся проблем локального Windows-окружения без обходных workflow.

## Краткий итог

Во время работы локальное Windows-окружение несколько раз становилось источником ложных блокеров: инструменты то находились, то исчезали из PATH; `rg` из bundled-пути Codex не стартовал с `Access is denied`; `git` в одном процессе был доступен, а в другом потребовал полный путь; возникала путаница между Windows venv и Linux venv на VM; вместо быстрого определения причины появлялся риск обходить проблему ad hoc-командами.

Главная проблема: Windows host не был формально описан как отдельный слой выполнения со своим preflight, fallback-правилами и границей ответственности. Из-за этого локальный сбой инструмента выглядел как сбой проекта или VM.

## Цель документа

Этот документ должен стать основой для практического guide или skill, который отвечает на вопросы:

- что проверять на Windows перед началом работы;
- какие локальные инструменты обязательны;
- какие ошибки окружения уже встречались;
- когда можно использовать fallback;
- когда нельзя идти обходным путем;
- что нужно поправить в проекте, чтобы агент не терял время на диагностику среды.

## Целевая модель Windows host

Windows host в этом проекте не является местом выполнения Ansible.

| Слой | Что разрешено на Windows | Что запрещено считать Windows-задачей |
| --- | --- | --- |
| Editing | Правка файлов, просмотр diff, подготовка коммитов | Исполнение ролей Ansible |
| Git | `git status`, branch, commit, push | Подмена VM-проверок локальным прогоном |
| VM management | `VBoxManage`, запуск clone helpers, SSH/SCP | Ручная правка состояния внутри VM |
| Remote execution | Вызов существующих `scripts/ssh-*.sh` | Самодельные runner/polling/wrapper scripts |
| Diagnostics | Проверка наличия локальных инструментов | Установка пакетов на VM руками |

Ключевой принцип: если проблема в Windows PATH, Bash, Git, `rg`, `VBoxManage`, SSH key или GPG, это проблема host preflight. Ее нельзя маскировать изменением Ansible-кода или обходным запуском нештатного workflow.

## Что произошло

| Симптом | Наблюдение | Почему это важно |
| --- | --- | --- |
| `rg` не стартует | `rg.exe` из bundled-пути Codex вернул `Access is denied` | Быстрый поиск по репозиторию стал ненадежным |
| `rg` затем не найден | В следующем процессе PowerShell `rg` отсутствовал в PATH | PATH внутри инструментальных процессов нестабилен |
| `git` временно не найден | Один `git status` вернул “The term 'git' is not recognized” | Нельзя считать PATH стабильным без preflight |
| Полный путь к Git сработал | `C:\Program Files\Git\cmd\git.exe` был найден через `where.exe git` | Должен быть документированный fallback |
| Windows venv смешивалась с Linux venv | Обсуждалось сохранение или пересоздание venv, хотя Windows venv не равна VM venv | Риск чинить не тот runtime |
| Возникали обходные действия | При сбое среды появлялся соблазн запускать альтернативные команды | Нарушается project execution surface |

## Первопричины

| Причина | Объяснение | Исправление |
| --- | --- | --- |
| Нет host preflight | Перед работой не было обязательной проверки Windows-зависимостей | Добавить официальный preflight для host tools |
| Не разделены host venv и VM venv | `ansible/.venv` в Taskfile рассчитан на Linux path `bin`, а не Windows `Scripts` | Зафиксировать: Ansible venv создается и используется на VM/Linux |
| `_ensure-venv` проверяет только директорию | В `Taskfile.yml` status проверяет `test -d ansible/.venv`, но не валидность Python/imports | Проверять исполняемый Python и ключевые imports или вызывать idempotent setup |
| Нет invalidation по requirements | Старый venv может остаться после изменения зависимостей | Пересоздавать venv при изменении `requirements*.txt` |
| Tool fallback не описан | Агент сам выбирал обходной путь вместо стандарта | Ввести таблицу допустимых fallback-ов |
| Ошибка среды смешивалась с ошибкой задачи | Сбой `rg`/`git` мог попасть в общий поток работы как будто это проблема проекта | Отдельно классифицировать host-tool failures |

## Практическое руководство по исправлению

### 1. Быстрая диагностика Windows host

Перед началом работы агент должен проверить host tools и сохранить вывод, если дальше будут claims о среде.

| Проверка | Команда PowerShell | Ожидаемый результат |
| --- | --- | --- |
| Git доступен | `where.exe git` | Путь к `git.exe`, например `C:\Program Files\Git\cmd\git.exe` |
| Bash доступен | `where.exe bash` | Git Bash или WSL bash, который может запускать `scripts/*.sh` |
| SSH доступен | `where.exe ssh` | OpenSSH или Git for Windows SSH |
| SCP доступен | `where.exe scp` | SCP доступен для sync |
| VBoxManage доступен | `where.exe VBoxManage` | VirtualBox CLI найден |
| Task доступен на VM, не обязательно локально | Проверяется через SSH на VM | Локальный Windows не обязан запускать Ansible task |
| GPG доступен, если нужны bootstrap secrets | `where.exe gpg` | GPG найден или documented secret fallback доступен |

Если команда не найдена, нужно чинить host PATH или использовать документированный полный путь. Нельзя из-за этого менять Ansible role или запускать playbook другим способом.

### 2. Правильное отношение к venv

В проекте есть `scripts/setup-venv.sh`, который создает `ansible/.venv` и ставит зависимости. Этот venv должен рассматриваться как Linux/VM runtime, потому что Taskfile использует путь `ansible/.venv/bin`.

| Вопрос | Правильный ответ |
| --- | --- |
| Нужно ли переносить Windows venv на VM | Нет |
| Нужно ли сохранять старый venv после изменения зависимостей | Нет, если dependency set изменился |
| Нужно ли вручную активировать venv | Нет |
| Нужно ли вручную делать `pip install` на VM | Нет |
| Что делать, если venv сломан | Запустить штатный `task bootstrap` или `scripts/setup-venv.sh` через разрешенный VM workflow |

Практический вывод: venv должен быть disposable artifact. Его можно и нужно пересоздавать, если он несовместим, неполный или создан под другой runtime.

### 3. Что поправить в проекте для venv

| Проблема | Практический фикс |
| --- | --- |
| `_ensure-venv` проверяет только наличие директории | Проверять `ansible/.venv/bin/python` и imports `ansible`, `ara` |
| При изменении requirements старый venv может остаться | Добавить checksum marker, например `.venv/.requirements.sha256` |
| Сбой venv ведет к ручным действиям | Сделать `_ensure-venv` либо понятным fail-fast, либо idempotent bootstrap |
| Непонятно, где должен жить venv | Документировать: Windows host не использует этот venv для Ansible |

Рекомендуемая логика:

| Состояние | Действие |
| --- | --- |
| `.venv` отсутствует | Создать через `scripts/setup-venv.sh` |
| `.venv/bin/python` отсутствует | Удалить и пересоздать |
| `python -c "import ansible"` падает | Удалить и пересоздать |
| requirements checksum изменился | Удалить и пересоздать |
| venv создан на Windows | Не использовать для VM Ansible, создать Linux venv на VM |

### 4. Допустимые fallback-и

Fallback разрешен только если он не меняет execution model проекта.

| Сбой | Допустимый fallback | Недопустимый обход |
| --- | --- | --- |
| `rg` не запускается | `Select-String`, `Get-ChildItem`, полный путь к исправному `rg` | Пропустить поиск и сделать вывод без фактов |
| `git` не найден в PATH | Полный путь `C:\Program Files\Git\cmd\git.exe` после `where.exe git` | Считать рабочую копию непроверенной |
| `bash` не найден | Починить Git Bash/WSL PATH | Переписывать bash scripts в PowerShell для разового запуска |
| `VBoxManage` не найден | Починить VirtualBox PATH или использовать полный путь | Мутировать VM через GUI без следов |
| SSH key не найден | Проверить documented key path и SSH_HOST | Создавать новый ключ без подтверждения |
| GPG secret недоступен | Проверить `.local/bootstrap` и `BOOTSTRAP_*` | Создавать plaintext secret на VM |

### 5. Stop rules

Агент должен остановиться и назвать blocker, если:

- не найден `bash`, а нужно запускать существующие `scripts/*.sh`;
- не найден `VBoxManage`, а нужно создать или заменить VM clone;
- не удается получить bootstrap secrets через documented helper;
- не работает SSH к clone после штатного clone workflow;
- приходится придумывать новый runner или wrapper для VM execution;
- локальная ошибка заставляет менять Ansible-код без доказанной связи.

## Что делать иначе в будущем

| Ситуация | Старое поведение | Новое поведение |
| --- | --- | --- |
| Tool не найден | Искать обходной путь по ходу работы | Сначала host preflight, затем documented fallback |
| venv исчез или сломан | Разбираться вручную и сохранять старое состояние | Пересоздать disposable venv штатным bootstrap-путем |
| Windows и VM paths конфликтуют | Смешивать `Scripts` и `bin` | Явно разделять Windows host и Linux VM runtime |
| Команда работает в одном процессе и не работает в другом | Продолжать как будто PATH стабилен | Зафиксировать PATH instability и использовать полный путь |
| Нужен новый helper | Быстро написать wrapper | Остановиться, если helper меняет VM execution surface |

## Профилактические действия

| Priority | Action | Result |
| --- | --- | --- |
| P0 | Добавить host preflight checklist в документацию | Агент быстро отличает host failure от project failure |
| P0 | Уточнить venv contract: Linux VM venv, не Windows venv | Прекращается путаница с переносом/сохранением venv |
| P1 | Усилить `_ensure-venv` проверкой Python/imports | Broken venv не считается готовым |
| P1 | Добавить requirements checksum invalidation | Старый venv не переживает изменение зависимостей |
| P1 | Документировать fallback для `git`, `rg`, `bash`, `VBoxManage` | Агент не тратит время на случайные обходы |
| P2 | Добавить неисполняющий preflight task для host diagnostics | Проверка среды не запускает VM и не меняет состояние |

## Критерии исправления

Проблема считается устраненной, если:

- Windows host preflight можно выполнить за одну минуту.
- Отсутствие `rg`, `git`, `bash`, `VBoxManage`, SSH или GPG классифицируется отдельно от ошибки задачи.
- Агент не запускает Ansible локально на Windows.
- Агент не активирует venv вручную.
- Старый venv пересоздается при поломке или изменении зависимостей.
- Любой fallback сохраняет исходный execution model проекта.

## Финальный вывод

Windows local environment должен быть управляемым host layer, а не серой зоной. Если локальный инструмент сломан, нужно чинить или документированно обходить именно host tooling. Нельзя из-за Windows-сбоя менять архитектуру Ansible, создавать ad hoc runner или делать выводы о VM без фактов.
