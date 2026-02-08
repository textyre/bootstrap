# Project Instructions

## Remote execution

All project interactions (linting, testing, ansible-playbook runs, molecule tests, package operations) MUST be performed on the remote VM, not on the local Windows host. Use the `remote-executor` subagent or SSH commands to execute operations on the VM. The local machine is only for editing files and git operations.

### Deploying dotfile changes (chezmoi)

`chezmoi apply` on the remote reads from its own local source at `/home/textyre/.local/share/chezmoi/`, NOT from the Windows host. After editing templates locally, sync them before applying:

1. **Copy changed files** to remote chezmoi source:
   ```
   bash scripts/ssh-scp-to.sh dotfiles/<path> /home/textyre/.local/share/chezmoi/<path>
   ```
2. **Apply and restart ewwii:**
   ```
   bash scripts/ssh-run.sh "chezmoi apply && pkill ewwii; sleep 1; nohup ~/.config/ewwii/launch.sh > /dev/null 2>&1 & disown"
   ```

Notes:
- If renaming a file (e.g. `.conf` to `.conf.tmpl`), delete the old file from remote chezmoi source first
- Helper scripts: `scripts/ssh-scp-to.sh` (copy), `scripts/ssh-run.sh` (execute)

## Mandatory subagent delegation

NEVER perform multi-file operations directly in the main conversation. ALWAYS delegate to the appropriate subagent using the Task tool.

### Routing rules

| Task type | Delegate to | Example |
|-----------|------------|---------|
| Explore/read code, gather context | `reader` | "Find all files using relative paths" |
| Run tests, linters, checks | `linter` | "Run shellcheck on all .sh files" |
| Fix errors, modify code | `fixer` | "Convert relative paths to absolute" |
| Complex multi-step task | `claudette` | "Refactor authentication system" |
| Simple question, single-line fix | Do it yourself | "What does this function do?" |

### Chaining workflow

For tasks requiring research + validation + fix, chain subagents sequentially:

1. `reader` — gather context, identify affected files
2. `linter` — run checks, collect errors (if applicable)
3. `fixer` — apply fixes based on reader/linter output
4. `linter` — verify fixes pass (repeat fixer → linter until clean)

For autonomous complex tasks, delegate to `claudette` which handles the full cycle independently.

### How to delegate

Pass the subagent name as `subagent_type` in the Task tool. Include a specific, actionable prompt with file patterns, scope, and goal.

### When NOT to delegate

- Single-file, single-line trivial changes
- Answering questions about the project
- Git operations (always show commands to the user)

## Git policy

Never run git write operations (commit, push, reset, rebase, merge). Show the user ready-to-run commands instead.

## MEMORY — запись находок и открытий

Все агенты при работе ДОЛЖНЫ записывать найденную информацию в auto memory (`MEMORY.md` и тематические файлы в директории memory).

### Что записывать
- Найденные паттерны, архитектурные решения, конвенции проекта
- Результаты исследований: какие подходы работают, какие нет
- Обнаруженные зависимости, пути, конфигурации
- Решения проблем и workaround-ы

### Правило обновления
Если новая информация **противоречит** ранее записанной — старую запись **НЕ удалять**. Пометить её:
> ⚠️ Старая информация, вернуться позже

Затем добавить новую информацию ниже.

### Чего НЕ делать
- Не записывать временные данные (текущий вывод команд, промежуточные логи)
