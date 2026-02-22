# Role Design

A role is a contract. It promises: "Give me a host and these variables, and I will ensure this service or capability is correctly configured." The contract has two sides — what the role assumes, and what the role guarantees.

When the contract is clear, roles compose. When it's vague, roles collide.

---

## The Contract

Before writing a role, state explicitly:

**Promises:** What will be true after this role runs? Not "installs nginx" — that's an action. "The nginx service is installed, configured with the provided settings, enabled, and serving traffic on the specified port." Promises are end states.

**Assumptions:** What must be true before this role runs? A network connection? A specific user existing? A package manager configured? Unspoken assumptions are the #1 cause of role failures on new systems.

**Boundaries:** What does this role NOT do? A database role does not configure backups. A firewall role does not manage application ports. Clear boundaries prevent roles from growing into monoliths.

---

## Structure

A role has a fixed directory structure. Not every directory is required, but the ones you use must follow conventions:

```
roles/<name>/
  defaults/main.yml    — Variables the operator can override
  tasks/main.yml       — Entry point (often a router)
  tasks/<phase>.yml    — Phase-specific tasks
  handlers/main.yml    — Event-driven actions
  templates/           — Jinja2 templates
  files/               — Static files
  meta/main.yml        — Dependencies, metadata
  molecule/            — Test scenarios
```

### defaults/main.yml — The Interface

This file IS the role's public API. Every variable here is a decision the operator can make. Variables not here are internal implementation details.

**Naming:** Prefix every variable with the role name. `ntp_servers`, not `servers`. `firewall_ssh_port`, not `ssh_port`. This prevents collisions when roles compose.

**Defaults must be safe.** The role should do something reasonable with zero configuration. An operator who includes the role without setting any variables should get a working, secure baseline — not an error, not an insecure configuration.

**Document inline.** Each variable needs a comment explaining what it controls, what values are valid, and what the default means. The operator reads `defaults/main.yml` to understand the role. If they need to read `tasks/` to understand a variable, the documentation failed.

**Group logically.** Related variables together, with section comments. Package selection, then service configuration, then security settings, then advanced tuning. The order should match the operator's mental model.

### tasks/main.yml — The Router

For simple roles, `main.yml` contains all tasks. For complex roles, it routes to phase-specific files:

```yaml
- name: Validate inputs
  ansible.builtin.include_tasks: validate.yml

- name: Install packages
  ansible.builtin.include_tasks: install.yml

- name: Configure service
  ansible.builtin.include_tasks: configure.yml

- name: Manage service state
  ansible.builtin.include_tasks: service.yml
```

Phase-based splitting keeps files focused and readable. Each phase has one job. The router shows the overall flow at a glance.

**OS dispatch:** When tasks differ by distribution, route by OS family:

```yaml
- name: Include OS-specific tasks
  ansible.builtin.include_tasks: "{{ ansible_os_family | lower }}.yml"
```

Keep shared logic in common files. Only put OS-specific differences in the OS files. If 90% of tasks are the same across distributions, don't duplicate them.

### handlers/main.yml — Discipline

Handlers are not callbacks. They're deferred state transitions — "when the config changes, reload the service." Design principles:

**Reload over restart.** Reloading picks up config changes without dropping connections. Only restart when the change requires it (binary upgrade, fundamental config change). Make this explicit in the handler name.

**Validate before restart.** A handler that restarts a service with invalid config takes down the service. Validate first:

```yaml
- name: Reload nginx
  ansible.builtin.command: nginx -t
  notify: Apply nginx reload
  listen: "reload nginx"

- name: Apply nginx reload
  ansible.builtin.systemd:
    name: nginx
    state: reloaded
```

**Use `listen:` directives.** This decouples the handler from the task. Any task, in any role, can trigger `"reload nginx"` without knowing the handler's internal name. This is how roles compose cleanly.

### templates/ — Not Copies

A template is not a config file with variables pasted in. It's a declaration of how configuration maps to the operator's decisions. Every `{{ variable }}` should trace back to a variable in `defaults/main.yml` with a clear meaning.

**Conditional blocks** should be rare and well-justified. If a template has many `{% if %}` blocks, consider whether you're building one template or several. Multiple simple templates are clearer than one complex one.

**Comments in templates** should explain WHY, not WHAT. The operator reading the generated config on the target system should understand the intent.

### meta/main.yml — Dependencies

Declare role dependencies explicitly. If your role requires another role to run first, say so:

```yaml
dependencies:
  - role: base_system
```

Keep dependencies minimal. A role that depends on five other roles is a role that's hard to test and hard to reuse. Question every dependency: is this a real requirement, or just a convenience?

### molecule/ — Proof

Tests are not optional. A role without tests is a role you're afraid to change. Molecule provides the structure:

- **converge.yml** — runs the role
- **verify.yml** — asserts the promises hold
- **molecule.yml** — environment configuration

Verify against promises, not tasks. Don't test "did the file get created?" — test "is the service listening on the right port?" The former tests implementation; the latter tests the contract.

---

## Platform Adaptation

Roles that support multiple distributions need a strategy. The cleanest pattern:

1. **Package maps** in defaults — translate role concepts to package names per OS
2. **Service maps** in defaults — translate role concepts to service names per init system
3. **OS-specific task files** — only for tasks that truly differ
4. **Shared task files** — for everything else

The goal: an operator on any supported platform reads `defaults/main.yml` and sees the same interface. The OS differences are implementation details, invisible to the consumer.

---

## The Smell Test

Read your role from the perspective of someone who has never seen it. Can they understand:

1. What the role does — from `meta/main.yml` description and README
2. How to configure it — from `defaults/main.yml` alone
3. What will change — from task names in `main.yml`
4. How to verify — from `molecule/default/verify.yml`

If any answer is "they'd need to read the source," the role's contract is unclear.
