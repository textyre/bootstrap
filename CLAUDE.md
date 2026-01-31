# Project Instructions

## Mandatory subagent delegation

NEVER perform multi-file operations directly in the main conversation. ALWAYS delegate to the appropriate subagent using the Task tool.

### Routing rules

| Task type | Delegate to | Example |
|-----------|------------|---------|
| Explore/read code, gather context | `reader` | "Find all files using relative paths" |
| Run tests, linters, checks | `linter` | "Run shellcheck on all .sh files" |
| Fix errors, modify code | `fixer` | "Convert relative paths to absolute" |
| Complex multi-step task | `beast-mode` | "Refactor authentication system" |
| Simple question, single-line fix | Do it yourself | "What does this function do?" |

### Chaining workflow

For tasks requiring research + validation + fix, chain subagents sequentially:

1. `reader` — gather context, identify affected files
2. `linter` — run checks, collect errors (if applicable)
3. `fixer` — apply fixes based on reader/linter output
4. `linter` — verify fixes pass (repeat fixer → linter until clean)

For autonomous complex tasks, delegate to `beast-mode` which handles the full cycle independently.

### How to delegate

Pass the subagent name as `subagent_type` in the Task tool. Include a specific, actionable prompt with file patterns, scope, and goal.

### When NOT to delegate

- Single-file, single-line trivial changes
- Answering questions about the project
- Git operations (always show commands to the user)

## Git policy

Never run git write operations (commit, push, reset, rebase, merge). Show the user ready-to-run commands instead.
