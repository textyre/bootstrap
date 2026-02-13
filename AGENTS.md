# Project Instructions

## Remote execution

All project interactions (linting, testing, ansible-playbook runs, molecule tests, package operations) MUST be performed on the remote VM, not on the local Windows host. Use the `remote-executor` subagent or SSH commands to execute operations on the VM. The local machine is only for editing files and git operations.

## Mandatory subagent delegation

NEVER perform multi-file operations directly in the main conversation. ALWAYS delegate to the appropriate subagent using the Task tool.

### Available Skills

**Infrastructure & Operations:**
- `/remote` — Execute commands on the remote Arch Linux VM
- `/ansible` — Run Ansible playbooks, roles, syntax checks, and linting
- `/ansible-debug` — Diagnose Ansible failures (playbook errors, module issues)
- `/ansible-role-creator` — Scaffold new Ansible role with tests and integration

**Configuration & Development:**
- `/dotfiles` — Deploy dotfile changes using chezmoi with service restarts
- `/self-hosted` — Reference patterns for self-hosted services with Caddy/Docker
- `/interface-design` — UI design system (dashboards, apps, tools)

**Research & Analysis:**
- `claudette-researcher` — Deep research with multi-source verification and synthesis. Use for technical investigations, literature reviews, comparative analysis, and fact-finding requiring authoritative sources with explicit citations.

### Routing rules

**Prefer skills over generic agents when available.** Use `/skill-name` for specialized workflows.

| Task type | Delegate to | Example |
|-----------|------------|---------|
| Remote command execution | `/remote` skill | "Check if nginx is running on VM" |
| Dotfile deployment | `/dotfiles` skill | "Deploy ewwii config changes" |
| Ansible operations | `/ansible` skill | "Run caddy role" |
| Ansible debugging | `/ansible-debug` skill | "Why did the docker role fail?" |
| Research with citations | `claudette-researcher` | "Research React state management best practices across multiple sources" |
| Explore/read code, gather context | `reader` | "Find all files using relative paths" |
| Run tests, linters, checks | `linter` | "Run shellcheck on all .sh files" |
| Fix errors, modify code | `fixer` | "Convert relative paths to absolute" |
| Complex multi-step task | `claudette` | "Refactor authentication system" |
| Simple question, single-line fix | Do it yourself | "What does this function do?" |

### Chaining workflow

For tasks requiring **external research** (web sources, documentation, comparative analysis):

1. `claudette-researcher` — investigate questions across authoritative sources with citations
2. `reader` / `fixer` — apply findings to codebase (if implementation needed)

For tasks requiring **codebase research** + validation + fix, chain subagents sequentially:

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

## Memory Management

All agents MUST record findings in auto memory (`MEMORY.md` and topic files in the memory directory).

### What to record
- Patterns, architectural decisions, project conventions
- Research results: what works, what doesn't
- Dependencies, paths, configurations
- Problem solutions and workarounds

### Update rule
If new information **contradicts** previous records — DO NOT delete the old entry. Mark it:
> ⚠️ Old information, revisit later

Then add new information below.

### What NOT to record
- Temporary data (command output, intermediate logs)
