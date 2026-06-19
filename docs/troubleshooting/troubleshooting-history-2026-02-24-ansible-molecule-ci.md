# Troubleshooting History — Ansible / Molecule CI

Дата: 2026-02-24

## Решено

| Ошибка | Причина | Решение |
|--------|---------|---------|
| Массовые `ansible-lint` нарушения на production profile | Роли и molecule-сценарии расходились с актуальными lint-правилами проекта | Прогонять production lint до CI и исправлять паттерны системно, а не точечно после падения |
| `ansible.builtin.pacman` не работает в converge/prepare | Pacman-модуль живет в `community.general`, а не в `ansible.builtin` | Использовать `community.general.pacman` и держать collection в requirements/CI install |
| `command-instead-of-module` на проверках, где модуль реально непригоден | lint не знает контекст, например broken/неподходящий module для конкретной проверки | Оставлять точечный `# noqa` только с понятной причиной, не глушить правило широко |
| `syntax-check[specific]: 'ansible.builtin.*' is not a valid attribute for a Play` | `ansible-lint` сканировал task-only YAML как playbook и ожидал `hosts:` | Не хранить task-only файлы там, где lint читает их как playbook; делать verify валидным playbook или настраивать lint scope |
| Handler не найден: `The requested handler ... was not found` | `notify` и `name` handler сравниваются case-sensitive | Использовать единый регистр и `listen:` для стабильного имени handler |
| `AnsibleUndefinedVariable` в standalone `verify.yml` | Verify запускается отдельным playbook, defaults роли автоматически не загружаются | Явно подключать нужные переменные через `vars_files` или inventory verify-сценария |
| Converge не загружает нужный data file | Тест запускает роль без inventory/group vars, поэтому данные оказываются пустыми | В molecule converge/verify явно подключать нужные `vars_files` или задавать минимальный test inventory |
| Ansible 2.20+ не парсит `.ini` inventory через `auto` | `ini` plugin не был явно включен | Добавлять `ini` в `enable_plugins` или мигрировать inventory на YAML |
| Тест отключает сервис через `*_enable_service: false` и скрывает реальное поведение | Molecule-сценарий меняет бизнес-контракт роли ради прохождения теста | Тест должен готовить окружение, а не отключать проверяемое поведение роли |
| One-shot service всегда показывает `changed` при `state: started` | Запуск one-shot unit не является стабильным desired state | Проверять enabled/configured state и фактическое состояние через доменную команду, например `nft list tables` |
| Старые файлы остаются на тестовой VM после sync | SCP/rsync без удаления не убирает удаленные локально файлы | Синхронизация test target должна удалять stale files или начинаться с чистого состояния |
| Синхронизированные файлы получают слишком широкие права | Sync-инструмент выставляет `0666`/неправильный mode для конфигов | После sync нормализовать mode или настроить sync так, чтобы он сохранял безопасные права |
| Проверка `which`/`command -v` пропускает сломанный бинарь | Бинарь существует в PATH, но не запускается после обновления библиотек | Проверять исполняемость через реальный `--version`/smoke command |
| Assert по `.timer` не находит timer в `ansible_facts.services` | `service_facts` возвращает service units, но не timer units | Проверять timer через `systemctl is-enabled <unit>.timer` |
| `locale_gen ... not available on your system` | Тестовый образ не содержал locale data из-за `NoExtract`/минимального glibc | Исправлять контракт образа или prepare-сценарий: locale data должны существовать до converge |
| Standalone/default Molecule сценарий не видит роли | `ANSIBLE_ROLES_PATH` указывал на несуществующий каталог | В сценарии указывать путь к фактическому каталогу ролей относительно `MOLECULE_PROJECT_DIRECTORY` |
| `community.general.timezone` или другой collection module не найден | CI установил Ansible, но не установил collections | Устанавливать project requirements/collections до molecule run |
| CLI-команда возвращает `rc=0`, но не применяет ожидаемые данные | Был использован неверный режим CLI; команда тихо создавала пустой результат | Проверять реальный контракт команды через help/output и verify конечного состояния, а не только exit code |
| Неверный asset/download URL для архитектуры | Локальное имя архитектуры не совпадало с naming scheme релизных артефактов | Маппинг архитектур строить по фактическим release assets и валидировать наличие asset до скачивания |
| Проверка `stat.stat.executable` ломается или недоступна | Поведение `stat`/атрибутов зависит от версии Ansible и окружения | Для исполняемости проверять mode/permissions или явный `test -x` с controlled failure |
| `name[play]` на файле с `import_playbook` | `import_playbook` не является play, `name:` не удовлетворяет правилу lint | Для intentional wrapper-файла использовать точечный `# noqa: name[play]` |
| Переменные из `molecule.yml` не попали в Docker converge | Inventory/group vars сценария не совпали с фактическим execution path | Критичные test vars задавать в shared converge/vars или в проверенном inventory path сценария |
| Jinja condition падает на `regex_search()` как на не-bool значение | В новых версиях Ansible/Jinja строка из `regex_search` не является boolean assertion | Для boolean-проверок использовать Jinja test `is search(...)` или явное сравнение с `none` |
| JSON type assert не принимает строковое поле после `from_json` | `from_json` возвращает обычный `str`, а не `AnsibleUnsafeText` | В type assertions учитывать реальные типы после парсинга JSON |
| Verify видит старое состояние сервиса после изменения конфига | Handler выполняется в конце play, а verify запускается раньше | Перед verify добавлять `meta: flush_handlers`, если verify зависит от handler-applied state |
| Idempotence ломается на директории, созданной systemd | `LogsDirectoryMode`/`StateDirectoryMode` в unit-файле перезаписывает mode после старта сервиса | Согласовать Ansible file mode с systemd unit mode или передать нужный mode через drop-in |
| AUR установка требует sudo, но пользователь сборки не может его получить | AUR helper запускается под отдельным пользователем, а пароль/askpass не передан | Передавать sudo password через безопасный runtime secret/askpass; не использовать NOPASSWD как обход |
| AUR пакет конфликтует с official package | Пакеты предоставляют один и тот же binary/file set | До установки AUR пакета явно удалять/конфигурировать конфликтующие official packages |
| Ошибка проявилась только в изолированном CI-сценарии | Полный локальный playbook маскировал зависимость от соседних ролей или окружения | Тестировать сценарий изолированно и не полагаться на внешний playbook-контекст |
