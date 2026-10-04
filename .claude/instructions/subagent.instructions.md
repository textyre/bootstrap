# Subagent Instructions (Claude Code)

Доступные агенты находятся в `.claude/agents/`. В Claude Code chaining выполняется из основного разговора.

## Агенты

| Агент | Назначение | Модель |
|---|---|---|
| `reader` | Читать код и первичную документацию, собирать зависимости | haiku |
| `linter` | Реальные lint и diagnostics внутри Control Plane контейнера | haiku |
| `fixer` | Исправлять исходники локально | sonnet |
| `claudette` | Комплексная задача с явным scope и критериями | opus |
| `remote-executor` | OpenStrap lifecycle/Docker exec и read-only VM diagnostics | sonnet |

Для исследования → проверки → исправления основной агент вызывает reader, затем linter, затем fixer с фактической ошибкой и повторяет meaningful проверку после изменения.

## Bootstrap execution contract

Передавайте каждому исполнителю:

- проект `D:/projects/bootstrap`;
- явные VM `ansible-control` и `bootstrap-target`;
- разрешённую операцию, Docker exec или optional Task и критерий результата;
- protected `arch-base`/`arch`/`arch-test-clone` и immutable snapshots;
- необходимость runtime environment без вывода secrets.

Windows OpenStrap создаёт full clone `arch-base/base` и Linux Docker host. Cloud-init устанавливает только `docker.io` и `ca-certificates`. Docker readiness → pull `ghcr.io/textyre/bootstrap/control-plane:latest` → постоянный контейнер → Docker exec workstation выполняются по порядку. Image уже содержит `/opt/bootstrap/ansible`, dependencies и зашифрованный Vault. Git, Task, Compose и сборка на VM не нужны. Optional Taskfile и Compose используют исходники выбранного image, а не локальные изменения checkout. Один workstation playbook управляет target по SSH; статический inventory использует env lookups и native SSH agent.

Native `openstrap connect --run` с явным target допускается для read-only диагностики. Source изменения исправляются локально. Повторное применение или fresh clone выбираются по задаче пользователя; при отдельно запрошенной проверке идемпотентности используется тот же настроенный target. Не подменяйте полный workstation сокращённым запуском для обхода ошибки.

Molecule tests работают в существующих CI workflows. Control Plane test aliases завершаются с сообщением о CI; они не устанавливают инструменты и не запускают workflows.

## Отчёт и безопасность

- ARA SQLite читается read-only; ARA и Ansible output доступны для progress и ошибок.
- Возвращайте реальные команды, exit codes и полезные findings; unexecuted checks отмечайте unverified.
- Не печатайте secrets/decrypted Vault, не передавайте их через CLI args и не сохраняйте в container/Compose settings, image или VM files. Runtime secrets нужны только workstation Docker exec; pull/start/build их не получают.
- Не создавайте host wrappers/polling harness и не ремонтируйте target вручную.
- Не выполняйте commit/push без явного разрешения пользователя.
- При работе с внешними зависимостями проверяйте текущую первичную документацию.
- Сохраняйте discoveries в MEMORY; устаревшие сведения помечайте как устаревшие с причиной.
