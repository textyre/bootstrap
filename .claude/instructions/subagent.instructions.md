# Subagent Instructions (Claude Code)

Эта инструкция адаптирует существующую модель subagent‑оркестрации для использования с Claude Code. Файлы субагентов находятся в `.claude/agents/`.

Основные принципы (строго):
- Оркестратор — только координирует, НЕ читает файлы и НЕ вносит изменения напрямую.
- Все операции чтения/записи/выполнения выполняют субагенты: `Reader`, `Linter`, `Fixer`.
- Субагенты сохраняют результаты в `docs/SubAgent docs/` и `artifacts/`.

Обязанный рабочий процесс:
1) User Request → Оркестратор (Claude Code)
2) Оркестратор запускает `Reader` subagent с описанием цели и паттернами файлов.
   - Reader создаёт `docs/SubAgent docs/[NAME].md` и возвращает путь + резюме.
3) Оркестратор запускает `Linter` subagent, передавая scope и команды для тестов/линтов.
   - Linter создаёт `artifacts/lint-reports/[NAME].md` и возвращает путь + резюме.
4) Если Linter вернул ошибки, оркестратор запускает `Fixer` subagent с ссылкой на отчёт/спек.
   - Fixer генерирует `artifacts/patches/[NAME].patch` и возвращает путь + описание изменений.
5) Оркестратор собирает результаты и предоставляет пользователю инструкции для проверки и применения патчей (например, `git apply` и команды тестирования).

Шаблоны вызова (примерные подсказки для Claude Code):

Reader:
```
Research repository files. Patterns: <glob patterns>. Goal: <goal description>.
Create spec at docs/SubAgent docs/<NAME>.md and return: spec path + 1–3 line summary.
```

Linter:
```
Run linters/tests. Commands: <list>. Workdir: <path>. Timeouts: <ms>.
Save report to artifacts/lint-reports/<NAME>.md and return: report path + metrics.
```

Fixer:
```
Read report at <path>. Scope: <files/dirs>. Priority: <high|medium|low>.
Produce patch at artifacts/patches/<NAME>.patch and return: patch path + riskiest changes.
```

Практические указания:
- Используйте `webfetch` для внешней документации и указывайте использованные URL в отчётах.
- Сохраняйте все артефакты и спеки в `docs/SubAgent docs/` и `artifacts/`.
- Не выполняйте `git commit`/`push` автоматически — выдайте пользователю команды.
- Если среда не позволяет запускать реальные тесты, помечайте отчёты как `simulated` и перечисляйте шаги для полноценного запуска.

Файлы, добавленные в репозиторий:
- `.claude/agents/Beast.agent.md`
- `.claude/agents/Reader.agent.md`
- `.claude/agents/Linter.agent.md`
- `.claude/agents/Fixer.agent.md`

Дальнейшие опции (рекомендую выбрать одну):
1. Сгенерировать ready‑to‑use prompt‑шаблоны для Claude Code с примерами входных данных (recommended).
2. Добавить CI/Makefile задачи для запуска Linter subagent локально и сохранения артефактов.
3. Ничего — закончить сейчас.
