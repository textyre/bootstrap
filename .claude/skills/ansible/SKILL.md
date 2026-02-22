---
name: ansible
description: Ansible role design, execution, debugging, and review. Philosophy-first automation craft.
metadata:
  argument-hint: <command> [target]
  allowed-tools: Bash(bash scripts/ssh-run.sh *), Bash(bash scripts/ssh-scp-to.sh *), Bash(bash scripts/ssh-sudo.sh *)
---

# Ansible Craft

Design, deploy, debug, and review Ansible automation with intent.

## The Problem

You will generate shell scripts disguised as YAML. Your training has seen thousands of Ansible roles. The patterns are strong — and mostly wrong.

The most common pattern: `ansible.builtin.command` wrapping a shell one-liner, `changed_when: false` silencing the noise, `ignore_errors: true` papering over failures. It parses. It might even work once. But it lies about what it did, breaks on the second run, and teaches the operator nothing about the system's actual state.

This happens because LLMs treat Ansible as an execution format — a way to run commands on remote systems. But Ansible is a state declaration format. The difference is fundamental. A command says "do this." A state declaration says "this should be true." One is imperative. The other is a promise.

The gap between "parses" and "safe to run" is where systems break, operators lose trust, and automation becomes a liability instead of an asset.

The process below closes that gap. But process alone doesn't guarantee craft. You have to catch yourself reaching for `command` when a module exists, catch yourself writing `changed_when: false` instead of detecting real state, catch yourself treating tasks as steps instead of assertions.

---

## Where Defaults Hide

Defaults don't announce themselves. They disguise themselves as pragmatic choices — the parts that feel like they just need to work, not be designed.

**Variables feel like configuration.** Pick reasonable values, move on. But variables aren't holding your role — they ARE your role's public API. The name of a variable, its default value, its comment — these determine how operators understand and trust your role. `ntp_servers` tells a story. `servers` tells nothing. `ssh_permit_root_login: "no"` is a security decision. An uncommented variable with a magic number is a decision no one can audit.

**Handlers feel like callbacks.** The service changed, restart it, done. But handlers aren't responding to events — they're managing state transitions. A handler that restarts without validating config first takes down the service. A handler without `listen:` creates tight coupling between roles. A handler that restarts when a reload would suffice drops connections unnecessarily. If you're writing `notify: Restart X` without thinking about blast radius, you're not designing.

**`changed_when` feels like annotation.** Ansible asks you to report whether something changed. You write `false` and move on. But `changed_when` is not metadata — it's your role's truth-telling mechanism. When an operator sees `changed=3`, they need to know: did 3 things actually change? Or did 3 tasks always report changed because someone didn't bother to check? Broken `changed_when` erodes trust in the entire reporting pipeline.

**Task names feel like comments.** Something to label the task. But task names are the operator's only narrative during a run. They scroll past in real time during deployment. "Run command" tells the operator nothing. "Ensure NTP service is synchronized" tells them exactly what's happening and lets them spot problems as they occur.

**Templates feel like copies.** Take the config file, add some `{{ variables }}`, done. But a template isn't a config file with holes punched in it — it's a mapping from operator decisions to system configuration. Every `{{ variable }}` should trace back to `defaults/main.yml`. Every conditional block should correspond to a real operational choice, not implementation convenience.

The trap is thinking some decisions are technical and others are design. There are no technical decisions. Everything is craft. The moment you stop asking "why this?" is the moment defaults take over.

---

## State First

Before writing any task, answer these. Not internally — state them explicitly.

**What is the desired end state?** Not "install nginx" — that's an action. "Nginx is installed at version X, configured to serve from /var/www, listening on port 443 with TLS, and running." The end state is what you'd verify if you SSHed in manually.

**What are the assumptions?** What must be true before this role runs? A network connection? A package manager configured? DNS resolving? A user existing? Every unspoken assumption is a failure mode you haven't tested.

**What are the promises?** After this role runs, what can other roles depend on? A service running? A port open? A config file in a specific location? Promises are the role's contract with the rest of the system.

**What happens on the second run?** This is the idempotency question. If nothing changed on the system, will the role report `changed=0`? If something drifted, will the role correct it and report `changed=N` where N is the actual number of corrections? If your answer is "I don't know," you haven't designed the role — you've scripted it.

---

## Craft Foundations

### Idempotency Is Truth-Telling

Idempotency is not a property of code. It's a promise to the operator: "Run this as many times as you want. Nothing will break. Nothing will change unless it needs to."

When `changed_when: false` silences a task that actually changes state, you've broken this promise. The system changed but the report says it didn't. The operator trusts the report. Next time something actually breaks, they won't notice the signal in the noise because you trained them to ignore it.

The test: run your role twice on a configured system. Second run must show `changed=0`. If it doesn't, find out why and fix it. Not with `changed_when: false` — with actual state detection.

### Module Hierarchy

There is a clear hierarchy of approaches. Every step down the ladder trades safety for flexibility:

1. **Native modules** — `ansible.builtin.file`, `ansible.builtin.template`, `ansible.builtin.systemd`. These are idempotent by design. They check state before acting. Use them whenever one exists for your task.

2. **Collection modules** — `community.general.pacman`, `community.docker.docker_compose_v2`. Maintained by the community, usually idempotent. Prefer over raw commands for supported operations.

3. **Command with creates/removes** — `ansible.builtin.command` with `creates:` or `removes:` parameter. Simple file-existence gating. Good for one-time setup tasks.

4. **Command with pre-check** — Register current state, compare to desired, skip if already correct. More work, but properly idempotent.

5. **Shell** — Last resort. When you need pipes, redirects, or shell builtins. Always with explicit `changed_when` based on output parsing.

Every time you reach for `command` or `shell`, ask: "Is there a module for this?" If the answer is "I don't know," check before writing. The module exists more often than you expect.

### Variables Are Decision Points

A variable is not a parameterized string. It's a decision the operator makes. Design variables like you're designing a form:

- **Name it for the decision, not the implementation.** `ssh_permit_root_login` (clear) vs `sshd_config_line_47` (meaningless).
- **Default to the safest value.** The operator who includes your role without reading defaults should get a secure, working system.
- **Validate inputs.** Use `ansible.builtin.assert` to fail early with clear messages rather than producing broken config silently.
- **Prefix with role name.** Always. `firewall_ssh_port`, not `ssh_port`. Collisions between roles are silent and devastating.

### Handler Discipline

- **Reload over restart** unless the change requires a full restart. Reloads don't drop connections.
- **Validate before restart.** A handler that applies invalid config takes down the service. Check config syntax first.
- **Use `listen:` directives.** Decouple the handler from the task. Any role can trigger `"reload nginx"` without knowing the handler's internal name.
- **One handler, one action.** Don't chain multiple operations in a single handler. Separate validate, reload, and verify into distinct handlers.

### Verification Philosophy

There are three levels of verification, each progressively stronger:

1. **Config validation** — Does the generated config parse? (`nginx -t`, `sshd -t`, `nft -c -f`)
2. **State assertion** — Is the service in the expected state? (`systemctl is-active`, port listening, process running)
3. **Behavioral verification** — Does the service do what it should? (Can we connect? Does it respond correctly? Is the log format right?)

Level 1 is the minimum. Level 3 is the ideal. Write your `molecule/verify.yml` at level 2 or 3 — test the contract, not the implementation.

### Error Diagnosis Methodology

When things fail, follow a sequence: read the full error, reproduce minimally, increase verbosity incrementally, check system assumptions, fix the root cause. Most people skip straight to guessing and tweaking. Most people waste hours.

The `debug` module is your primary diagnostic tool for variable issues. Verbosity flags (`-v` through `-vvvv`) reveal progressively more about what Ansible is doing. Start low and escalate.

See `references/debugging.md` for the complete methodology.

---

## The Mandate

Before presenting any role, task, or playbook, run these checks against your output:

**The idempotency test.** Would every task report `ok` (not `changed`) on a second run against an already-configured system? For every `command`/`shell` task, can you explain what state it checks before acting?

**The module test.** Is every `command` or `shell` task genuinely necessary? Is there a native or collection module that does the same thing with built-in idempotency? If you can't name the module you rejected, you didn't look.

**The variable test.** Read your `defaults/main.yml` aloud. Can an operator understand every decision they're being asked to make? Are any variables named for implementation details instead of operational concepts? Is the prefix consistent?

**The verification test.** Does your `verify.yml` test the contract or the implementation? "File exists" is implementation. "Service is running and accepting connections" is contract.

**The blast radius test.** What's the worst thing that happens if this role runs with bad input? A failed task (acceptable)? A broken service (bad)? A locked-out operator (unacceptable)? Design for the failure mode, not just the happy path.

If any check fails, fix it before presenting. The first draft is the script. The mandate is the craft.

---

## Avoid

- **`ignore_errors: true`** — Use `failed_when` with specific conditions instead. Blanket error suppression hides real failures
- **`changed_when: false` on tasks that change state** — Detect real state change instead of silencing the report
- **`changed_when: true` on tasks that don't always change** — Crying wolf trains operators to ignore `changed` counts
- **Bare Jinja2 in YAML values** — Always quote: `"{{ var }}"`, never `{{ var }}`. Unquoted Jinja2 causes parse errors
- **`shell` when `command` suffices** — Shell opens attack surface (injection). Use only when you need pipes or redirects
- **`command` when a module exists** — Modules are idempotent by design. Commands aren't
- **Hardcoded paths or values** — Everything tunable goes in `defaults/main.yml` with a descriptive name
- **Missing handler validation** — Never restart a service without checking config validity first
- **`become: true` at playbook level** — Set it per task or per block. Least privilege
- **Unnamed tasks** — Every task needs a name that tells the operator what's being ensured, not what's being run
- **Giant `main.yml` files** — Split by phase: validate, install, configure, service. The router shows the flow

---

## Workflow

### Communication
Be direct. Don't announce modes or narrate internals. Jump into the work.

### Deployment Discipline

Every role deployment follows this sequence:

1. **Sync** — Copy role files to the remote execution environment
2. **Syntax check** — Verify the playbook parses before running
3. **Lint** — Check for common anti-patterns and style violations
4. **Deploy** — Run the role with `-v` for task-level visibility
5. **Verify** — Run the role again. Second run must show `changed=0`
6. **Assert** — Run molecule verify or manual checks against the contract

Never skip steps. Never deploy without syncing first. Never assume the second run will be clean — prove it.

### Project Standards

This skill teaches generic Ansible thinking. Your specific project may have additional standards — role naming conventions, required files, test frameworks, supported platforms, deployment pipelines.

When invoked, read `AGENTS.md` for:
- Execution environment (how to run commands, where files live)
- Role standards (what files are required, what conventions to follow)
- Links to detailed specifications

The separation is intentional: this skill teaches HOW to think about Ansible. The project docs tell you WHAT this specific project requires.

---

## Deep Dives

For detailed guidance on specific topics:
- `references/idempotency.md` — Why idempotency matters, the module hierarchy, the three lies, testing strategies
- `references/role-design.md` — Roles as contracts, structure, variables, handlers, templates, platform adaptation
- `references/debugging.md` — 5-step diagnostic method, verbosity guide, error categories, common patterns

---

## Commands

### `$ARGUMENTS` parsing

Interpret `$ARGUMENTS` as: `<command> [target] [options]`

### `:create <role-name> [description]`

Scaffold a new role. Before writing any files:

1. Read `AGENTS.md` for project role standards and reference implementations
2. Read the project's role requirements specification (if linked from AGENTS.md)
3. Read the reference implementation role (if one exists)
4. State the role's contract: promises, assumptions, boundaries
5. Scaffold all required files per project conventions
6. Every variable in `defaults/main.yml` must have a comment
7. `verify.yml` must test the contract, not the implementation

### `:run <playbook>`

Run a playbook on the remote environment.

1. Read `AGENTS.md` for execution environment
2. Sync any locally-modified role files first
3. Run syntax check before execution
4. Execute with `-v` for task-level output
5. Report results

### `:role <role-name>`

Run a single role via a temporary playbook.

1. Read `AGENTS.md` for execution environment
2. Sync role files to remote
3. Create a minimal temporary playbook targeting the role
4. Execute with `-v`
5. Report results, note any `changed` tasks

### `:check [playbook]`

Run `ansible-playbook --syntax-check`. Read `AGENTS.md` for execution environment and default playbook path.

### `:lint [path]`

Run `ansible-lint`. Read `AGENTS.md` for execution environment. Default to linting all playbooks and roles.

### `:verify <role-name>`

Run molecule verify (or equivalent test framework) for a role. Read `AGENTS.md` for execution environment and test configuration.

### `:tags <tag1,tag2>`

Run a playbook filtered by tags. Read `AGENTS.md` for execution environment and default playbook.

### `:debug [error-message-or-symptom]`

Diagnose an Ansible failure.

1. Read `references/debugging.md` for the diagnostic methodology
2. Read `AGENTS.md` for execution environment
3. If an error message is provided, match against known error patterns
4. Follow the 5-step method: read error → reproduce minimally → increase verbosity → check assumptions → fix root cause
5. For connection issues, test the SSH pipeline first
6. For module issues, verify the execution environment (venv, collections, pip packages)
7. For variable issues, use `debug` module to inspect values

### `:review <role-name>`

Review a role against both generic craft standards and project-specific requirements.

1. Read the role's files: defaults, tasks, handlers, templates, meta, molecule
2. Read `AGENTS.md` for project role standards
3. Check against Craft Foundations (this file): idempotency, module hierarchy, variables, handlers, verification
4. Check against project standards: required files, naming, testing, documentation
5. Report findings by severity: critical (blocks deployment), high (should fix), medium (improve), low (style)

---

## Project Integration

This skill is portable — it teaches Ansible thinking that applies to any project. Project-specific context is loaded at runtime:

- **`AGENTS.md`** — Execution environment (SSH commands, paths, venv activation), role standards, routing rules
- **Role requirements spec** (linked from AGENTS.md) — Required files, naming conventions, test framework, supported platforms
- **Reference implementation** (linked from AGENTS.md) — A complete role demonstrating all project conventions

When a command needs project context, it reads these files first. When no project context exists, the skill falls back to generic Ansible best practices.
