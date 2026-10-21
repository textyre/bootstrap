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
- разрешённую операцию, native Docker exec и критерий результата;
- protected `arch-base`/`arch`/`arch-test-clone` и immutable snapshots;
- public target environment и mounted Swarm secrets без вывода contents.

Windows OpenStrap создаёт full clone `arch-base/base` и Linux Docker host. First-boot cloud-init создаёт single-node Swarm и host-network service готового GHCR image. OpenStrap проверяет `1/1`, передаёт password/private key через stdin в native Docker secrets и выполняет один workstation exec с original 31 roles. Rotation заменяет service task и сохраняет home, но не выбирает новый image. Existing VM не принимает changed cloud-init автоматически. Root Task/Compose wrappers удалены; target-role Compose остаётся. Ansible использует native credential-file flags, inventory env содержит только public target values.

Native `openstrap connect --run` с явным target допускается для read-only диагностики. Source изменения исправляются локально. Повторное применение или fresh clone выбираются по задаче пользователя; при отдельно запрошенной проверке идемпотентности используется тот же настроенный target. Не подменяйте полный workstation сокращённым запуском для обхода ошибки.

Molecule tests работают в существующих CI workflows; controller не устанавливает инструменты и не запускает workflows автоматически.

## Отчёт и безопасность

- ARA SQLite читается read-only; ARA и Ansible output доступны для progress и ошибок.
- Возвращайте реальные команды, exit codes и полезные findings; unexecuted checks отмечайте unverified.
- Не печатайте credentials, не помещайте их в environment, CLI args, image или persistent home. Native Swarm mounts под `/run/secrets` root `0400`; ARA игнорирует этот путь. `flock` защищает rotation/Ansible; different-target/credential-changing shared deployments сериализуются целиком.
- Не создавайте host wrappers/polling harness и не ремонтируйте target вручную.
- Не выполняйте commit/push без явного разрешения пользователя.
- При работе с внешними зависимостями проверяйте текущую первичную документацию.
- Сохраняйте discoveries в MEMORY; устаревшие сведения помечайте как устаревшие с причиной.
