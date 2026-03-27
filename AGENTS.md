# Project Instructions

## Remote execution

All project interactions (linting, testing, ansible-playbook runs, molecule tests, package operations) MUST be performed on the remote VM:
- Use the `remote-executor` subagent
- SSH commands to execute operations on the VM
- The local machine is only for editing files and git operations.

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


## Role Standards

All Ansible roles MUST comply with the Role Requirements Specification.

- **Full spec:** `wiki/standards/role-requirements.md` (11 requirements, post-creation checklist)
- **Security controls:** `wiki/standards/security-standards.md` (CIS/STIG/dev-sec mappings)
- **Profiles:** `wiki/standards/workstation-profiles.md` (base/developer/gaming/media/security)

Key constraints:
- 5 supported distros: Arch, Ubuntu, Fedora, Void, Gentoo — never add others
- 5 supported init systems: systemd, runit, openrc, s6, dinit
- Security baseline: CIS Level 1 Workstation


