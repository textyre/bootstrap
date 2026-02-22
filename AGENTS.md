# Project Instructions

## Remote execution

All project interactions (linting, testing, ansible-playbook runs, molecule tests, package operations) MUST be performed on the remote VM:
- Use the `remote-executor` subagent
- SSH commands to execute operations on the VM
- The local machine is only for editing files and git operations.

## Mandatory subagent delegation

NEVER perform multi-file operations directly in the main conversation. ALWAYS delegate to the appropriate subagent using the Task tool.

### Available Skills

**Infrastructure & Operations:**
- `/remote` — Execute commands on the remote Arch Linux VM
- `/ansible` — Ansible automation craft: design, execute, debug, review (commands: `:create`, `:run`, `:role`, `:check`, `:lint`, `:verify`, `:tags`, `:debug`, `:review`)

**Configuration & Development:**
- `/dotfiles` — Deploy dotfile changes using chezmoi with service restarts
- `/self-hosted` — Reference patterns for self-hosted services with Caddy/Docker
- `/interface-design` — UI design system (dashboards, apps, tools)

**Research & Analysis:**
- `claudette-researcher` — Deep research with multi-source verification and synthesis. Use for technical investigations, literature reviews, comparative analysis, and fact-finding requiring authoritative sources with explicit citations.
- `supergrep` (MCP) — Search GitHub and Sourcegraph for real-world code examples. Use when you need to verify implementation patterns by looking at how other projects do it.

### Routing rules

**Prefer skills over generic agents when available.** Use `/skill-name` for specialized workflows.

| Task type | Delegate to | Example |
|-----------|------------|---------|
| Remote command execution | `/remote` skill | "Check if nginx is running on VM" |
| Dotfile deployment | `/dotfiles` skill | "Deploy ewwii config changes" |
| Ansible (all operations) | `/ansible` skill | "Run caddy role", "Debug docker failure", "Create ntp role", "Review firewall" |
| Research with citations | `claudette-researcher` | "Research React state management best practices across multiple sources" |
| Find real-world code patterns | `supergrep` MCP tool | "How do Arch packages configure faillock.conf?" |
| Explore/read code, gather context | `reader` | "Find all files using relative paths" |
| Run tests, linters, checks | `linter` | "Run shellcheck on all .sh files" |
| Fix errors, modify code | `fixer` | "Convert relative paths to absolute" |
| Complex multi-step task | `claudette-auto` | "Refactor authentication system" |
| Simple question, single-line fix | Do it yourself | "What does this function do?" |

## Git policy

Never run git write operations (commit, push, reset, rebase, merge). Show the user ready-to-run commands instead.

## Role Standards

All Ansible roles MUST comply with the Role Requirements Specification.

- **Full spec:** `wiki/standards/role-requirements.md` (11 requirements, post-creation checklist)
- **Security controls:** `wiki/standards/security-standards.md` (CIS/STIG/dev-sec mappings)
- **Profiles:** `wiki/standards/workstation-profiles.md` (base/developer/gaming/media/security)

Key constraints:
- 5 supported distros: Arch, Ubuntu, Fedora, Void, Gentoo — never add others
- 5 supported init systems: systemd, runit, openrc, s6, dinit
- Security baseline: CIS Level 1 Workstation
- Only `ansible.builtin.*` modules — no shell hacks
- Every role: verify.yml, dual logging (report_phase + JSON), molecule tests
- Reference implementation: `ansible/roles/ntp/`

### Execution Environment

All Ansible commands execute on the remote VM via SSH helpers:
- Command prefix: `bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg <command>"`
- Sudo commands: `bash scripts/ssh-sudo.sh "<command>"`
- File sync: `bash scripts/ssh-scp-to.sh -r <local-path> <remote-path>`
- Ansible dir: `/home/textyre/bootstrap/ansible/`
- Roles: `/home/textyre/bootstrap/ansible/roles/`
- Playbooks: `/home/textyre/bootstrap/ansible/playbooks/`

## Memory Management

After completing any non-trivial task, record findings in auto memory (`MEMORY.md` and topic files in the memory directory). This applies to the main agent — subagents invoked via Task cannot write to memory; summarize their findings yourself.

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
