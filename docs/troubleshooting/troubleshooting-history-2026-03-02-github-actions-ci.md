# Troubleshooting History — GitHub Actions CI

Дата: 2026-03-02

## Решено

| Ошибка | Причина | Решение |
|--------|---------|---------|
| Workflow не документирован и непонятно, кто кого вызывает | В `.github/workflows` нет карты trigger/callee/dependencies | Держать README/headers для workflow с purpose, triggers, inputs, dependencies и known issues |
| Wiki sync копирует только root markdown | Workflow использует `cp wiki/*.md`, игнорируя поддиректории | Копировать рекурсивно: `cp -r wiki/. "$WIKI_DIR/"` |
| Standalone scheduled workflow дублирует orchestrator и тестирует hardcoded role | Исторический workflow остался после появления общего orchestrator | Переносить schedule в основной orchestrator или делать standalone workflow параметризованным |
| Название workflow говорит “build”, но он только проверяет контракт | Имя файла/джоба не отражает реальное действие | Переименовывать workflow по фактическому contract, например `verify-*` |
| Self-hosted runner job висит бесконечно | Workflow требует label runner, но не задает `timeout-minutes` | Добавлять timeout и отдельную диагностику доступности runner |
| Pip cache не инвалидируется при изменении версий зависимостей | Cache key содержит hardcoded версии или не зависит от requirements | Использовать `hashFiles` по requirements/lockfile в cache key |
| Изменения workflow не запускают lint/action validation | Path filter покрывает только `ansible/**`, а workflow YAML не валидируется | Добавить `.github/workflows/**` в фильтры и отдельный `actionlint` |
| CI logs трудно читать в PR | Ошибки остаются только внутри длинного job log | Добавлять GitHub Actions annotations `::error`/`::warning` для ключевых failure summaries |
| Reusable workflow не передает обязательный env для образа | Caller/scenario ожидает env вроде `MOLECULE_UBUNTU_IMAGE`, но reusable workflow его не задает | Централизовать image env в reusable workflow и проверять fallback локально |
| Workflow зеленый, но тесты фактически не запускались | Detection job сформировал пустую matrix, test jobs были skipped | Проверять не только общий статус workflow, но и факт запуска нужных jobs |
| PR закрыт без доказательства успешных тестов | Решение принято по предположению о transient failure | Перед закрытием PR получать конкретный зеленый run/job как evidence |
| `wget: unrecognized option '--fail'` | Использован флаг `curl` у утилиты `wget` | Использовать `curl -fsSL ...` или корректные флаги `wget` |
| Ветка CI tracking не триггерит workflow | Workflow filters не покрывали служебную ветку | Запускать workflow на ветке/PR, который действительно попадает под trigger, или использовать разрешенный manual trigger |
| `vagrant box add` падает, хотя cache восстановлен | `actions/cache` restore-key hit восстанавливает файлы, но `cache-hit` остается `false`; шаг добавления не был идемпотентным | Проверять реальное состояние через `vagrant box list` перед `vagrant box add` |
| Workflow step ссылается на `steps.<id>.outputs`, но output пустой | У шага, на который ссылаются, не задан `id` | Добавлять явный `id` всем steps, outputs которых используются дальше |
