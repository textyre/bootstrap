# Molecule Overhaul — Lead Agent

You are the lead orchestrator for the molecule-overhaul team. Your job is to spawn 32 role agents (teammates), monitor their progress, and synthesize a final report.

## Step 1 — Create team and tasks

```
TeamCreate("molecule-overhaul")
```

Then create one task per role:

```
TaskCreate("molecule-overhaul", "locale",          { description: ROLE_AGENT_PROMPT("locale") })
TaskCreate("molecule-overhaul", "timezone",        { description: ROLE_AGENT_PROMPT("timezone") })
TaskCreate("molecule-overhaul", "hostname",        { description: ROLE_AGENT_PROMPT("hostname") })
TaskCreate("molecule-overhaul", "vconsole",        { description: ROLE_AGENT_PROMPT("vconsole") })
TaskCreate("molecule-overhaul", "shell",           { description: ROLE_AGENT_PROMPT("shell") })
TaskCreate("molecule-overhaul", "git",             { description: ROLE_AGENT_PROMPT("git") })
TaskCreate("molecule-overhaul", "greeter",         { description: ROLE_AGENT_PROMPT("greeter") })
TaskCreate("molecule-overhaul", "lightdm",         { description: ROLE_AGENT_PROMPT("lightdm") })
TaskCreate("molecule-overhaul", "packages",        { description: ROLE_AGENT_PROMPT("packages") })
TaskCreate("molecule-overhaul", "package_manager", { description: ROLE_AGENT_PROMPT("package_manager") })
TaskCreate("molecule-overhaul", "reflector",       { description: ROLE_AGENT_PROMPT("reflector") })
TaskCreate("molecule-overhaul", "yay",             { description: ROLE_AGENT_PROMPT("yay") })
TaskCreate("molecule-overhaul", "chezmoi",         { description: ROLE_AGENT_PROMPT("chezmoi") })
TaskCreate("molecule-overhaul", "ssh_keys",        { description: ROLE_AGENT_PROMPT("ssh_keys") })
TaskCreate("molecule-overhaul", "hostctl",         { description: ROLE_AGENT_PROMPT("hostctl") })
TaskCreate("molecule-overhaul", "xorg",            { description: ROLE_AGENT_PROMPT("xorg") })
TaskCreate("molecule-overhaul", "ntp",             { description: ROLE_AGENT_PROMPT("ntp") })
TaskCreate("molecule-overhaul", "ntp_audit",       { description: ROLE_AGENT_PROMPT("ntp_audit") })
TaskCreate("molecule-overhaul", "ssh",             { description: ROLE_AGENT_PROMPT("ssh") })
TaskCreate("molecule-overhaul", "caddy",           { description: ROLE_AGENT_PROMPT("caddy") })
TaskCreate("molecule-overhaul", "vaultwarden",     { description: ROLE_AGENT_PROMPT("vaultwarden") })
TaskCreate("molecule-overhaul", "docker",          { description: ROLE_AGENT_PROMPT("docker") })
TaskCreate("molecule-overhaul", "vm",              { description: ROLE_AGENT_PROMPT("vm") })
TaskCreate("molecule-overhaul", "zen_browser",     { description: ROLE_AGENT_PROMPT("zen_browser") })
TaskCreate("molecule-overhaul", "sysctl",          { description: ROLE_AGENT_PROMPT("sysctl") })
TaskCreate("molecule-overhaul", "pam_hardening",   { description: ROLE_AGENT_PROMPT("pam_hardening") })
TaskCreate("molecule-overhaul", "firewall",        { description: ROLE_AGENT_PROMPT("firewall") })
TaskCreate("molecule-overhaul", "fail2ban",        { description: ROLE_AGENT_PROMPT("fail2ban") })
TaskCreate("molecule-overhaul", "user",            { description: ROLE_AGENT_PROMPT("user") })
TaskCreate("molecule-overhaul", "gpu_drivers",     { description: ROLE_AGENT_PROMPT("gpu_drivers") })
TaskCreate("molecule-overhaul", "power_management",{ description: ROLE_AGENT_PROMPT("power_management") })
TaskCreate("molecule-overhaul", "teleport",        { description: ROLE_AGENT_PROMPT("teleport") })
```

## Step 2 — Spawn all 32 teammates in parallel

Spawn all 32 teammates at once using `Task` with `team_name: "molecule-overhaul"`. Each teammate receives the role agent prompt below as its instructions.

## Step 3 — Monitor

Poll `TaskList("molecule-overhaul")` every few minutes. When all tasks are `done`, send a shutdown broadcast:

```
SendMessage("molecule-overhaul", "all", "shutdown")
```

Then synthesize results from all `SendMessage` reports into a final summary table:

| Role | Issues Found | Fixed | PR | CI | Merged |
|------|-------------|-------|----|----|--------|
| ...  | ...         | ...   | ...| ...| ...    |

Finish with `TeamDelete("molecule-overhaul")`.

---

# Role Agent Prompt (ROLE_AGENT_PROMPT template)

> The following is the full prompt for each role teammate. Replace `<ROLE>` with the role name.

---

You are a molecule-overhaul teammate. You own exactly ONE Ansible role: **`<ROLE>`**.

Your mission: bring the molecule tests for this role to full production quality, then merge a PR. Work autonomously start to finish.

## Phase 1 — Claim your task

```
TaskList("molecule-overhaul")          # find your task
TaskUpdate("molecule-overhaul", "<ROLE>", "in_progress")
```

## Phase 2 — Read the role

Read ALL of these files before writing a single line:

- `ansible/roles/<ROLE>/tasks/main.yml` and all other `tasks/*.yml`
- `ansible/roles/<ROLE>/defaults/main.yml`
- `ansible/roles/<ROLE>/handlers/main.yml` (if exists)
- `ansible/roles/<ROLE>/templates/` (all templates)
- `ansible/roles/<ROLE>/molecule/shared/converge.yml`
- `ansible/roles/<ROLE>/molecule/shared/verify.yml`
- `ansible/roles/<ROLE>/molecule/docker/prepare.yml`
- `ansible/roles/<ROLE>/molecule/docker/molecule.yml`
- `wiki/standards/role-requirements.md` (ROLE-001..011 checklist)

## Phase 3 — Audit against checklist

For each requirement, record: ✅ compliant / ❌ violation / ⚠️ partial.

### ROLE-001: OS dispatch
- `tasks/main.yml` uses `include_tasks` with `ansible_facts['os_family'] | lower`
- `vars/` has per-distro files (at minimum `archlinux.yml`)
- No raw `pacman -S` / `apt-get` in tasks
- `ansible.builtin.package` used (not distro-specific modules)

### ROLE-002: Init-agnostic
- `ansible.builtin.service` used (not `ansible.builtin.systemd`) for enable/start
- `ansible.builtin.systemd` only when guarded by `when: ansible_facts['service_mgr'] == 'systemd'`

### ROLE-003: Preflight assert
- `_<role>_supported_os` in `defaults/main.yml` with all 5: Archlinux, Debian, RedHat, Void, Gentoo
- First task in `main.yml` is `ansible.builtin.assert` checking `os_family` membership

### ROLE-004: Security tags
- Security tasks have CIS/STIG IDs in task name
- Boolean toggles per security subsystem

### ROLE-005: In-role verify.yml
- `tasks/verify.yml` exists
- Included from `tasks/main.yml`
- Uses `check_mode: true` or `changed_when: false`

### ROLE-006: Molecule test quality (PRIMARY FOCUS)
- `molecule/shared/verify.yml` checks ACTUAL system state (files, permissions, services)
- NOT just "role ran without errors"
- Every feature branch of the role has a corresponding verify assertion
- Register variables named `_<role>_verify_<check>`
- Services verified with `systemctl is-enabled` / `systemctl is-active`
- Config files verified with `stat`, `slurp`, or `lineinfile check_mode`
- Security settings verified (file permissions, ownership, content)

### ROLE-008: Dual logging
- `report_phase.yml` called per logical phase
- `report_render.yml` called as last task

### ROLE-011: Ansible-native only
- FQCN everywhere: `ansible.builtin.file`, not `file`
- No `ansible.builtin.shell` / `ansible.builtin.command` where a module exists
- All Jinja2 quoted: `"{{ var }}"`, never bare `{{ var }}`

## Phase 4 — Fix molecule tests

Focus on `molecule/shared/verify.yml` and `molecule/shared/converge.yml`.

### Mandatory patterns (from project memory — apply everywhere)

```yaml
# CORRECT: boolean test in assert
- assert:
    that: some_output is regex('^pattern')   # NOT | regex_search

# CORRECT: slurp content guard
- slurp: path: /etc/foo
  register: r
- assert:
    that: "'content' in r"                   # NOT r is succeeded

# CORRECT: absent resource test
- name: try getent for absent user
  ansible.builtin.command: getent passwd absent_user
  register: r
  ignore_errors: true
- assert:
    that: r is failed                        # NOT failed_when: r is not failed

# CORRECT: /etc/hosts edits in Docker
- ansible.builtin.lineinfile:
    path: /etc/hosts
    unsafe_writes: true                      # Docker bind-mount — always required

# CORRECT: read-only commands
- ansible.builtin.command:
    cmd: <some check>
  register: r
  changed_when: false                        # always for read-only

# CORRECT: password aging via chage (not user module — ansible-core < 2.17)
- ansible.builtin.command:
    cmd: chage -W {{ days }} {{ user }}
  changed_when: false
```

### verify.yml structure to aim for

```yaml
---
- name: Verify <ROLE>
  hosts: all
  become: true
  gather_facts: false
  tasks:
    # 1. Config files exist and have correct content
    - name: Stat main config
      ansible.builtin.stat:
        path: /etc/<config>
      register: _<role>_verify_conf
    - name: Assert config exists
      ansible.builtin.assert:
        that: _<role>_verify_conf.stat.exists
        fail_msg: "Config file missing"

    # 2. Service state (if applicable)
    - name: Check service enabled
      ansible.builtin.command:
        cmd: systemctl is-enabled <service>
      register: _<role>_verify_svc_enabled
      changed_when: false
      failed_when: false
    - name: Assert service enabled
      ansible.builtin.assert:
        that: "'enabled' in _<role>_verify_svc_enabled.stdout"

    # 3. File permissions (security-relevant)
    - name: Check config permissions
      ansible.builtin.stat:
        path: /etc/<config>
      register: _<role>_verify_perms
    - name: Assert permissions
      ansible.builtin.assert:
        that:
          - _<role>_verify_perms.stat.mode == '0644'
          - _<role>_verify_perms.stat.pw_name == 'root'

    # 4. Functional verification (the role actually did something)
    - name: Verify <key feature>
      ansible.builtin.command:
        cmd: <verification command>
      register: _<role>_verify_func
      changed_when: false
    - name: Assert functional result
      ansible.builtin.assert:
        that: "'expected output' in _<role>_verify_func.stdout"
```

## Phase 5 — Worktree and commit

```bash
# Create isolated worktree
git worktree add worktrees/<ROLE> -b fix/<ROLE>-molecule-overhaul

# Stage and commit (work inside the worktree)
git -C worktrees/<ROLE> add ansible/roles/<ROLE>/molecule/
git -C worktrees/<ROLE> commit -m "test(<ROLE>): molecule tests to production quality

- verify.yml: genuine state assertions (files, services, permissions)
- converge.yml: representative config covering all feature branches
- apply mandatory patterns (is regex, unsafe_writes, changed_when: false)
- coverage: <list what was added>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"

git -C worktrees/<ROLE> push -u origin fix/<ROLE>-molecule-overhaul
```

## Phase 6 — Create PR

```bash
gh pr create \
  --base master \
  --head fix/<ROLE>-molecule-overhaul \
  --title "test(<ROLE>): molecule tests to production quality" \
  --body "$(cat <<'EOF'
## Summary

- verify.yml rewritten with genuine state assertions (not just Ansible return codes)
- converge.yml updated to cover all feature branches
- Applied project-standard patterns from MEMORY.md
- Full ROLE-006 compliance

## Coverage added

- [ ] Config file existence and content
- [ ] Service enabled/active state
- [ ] File permissions and ownership
- [ ] Functional verification

## Test plan

GitHub Actions CI runs molecule/docker automatically on this PR.
EOF
)"
```

## Phase 7 — Wait for CI and fix until green

```bash
# Get the PR number
PR=$(gh pr view --json number -q .number)

# Watch CI status
gh pr checks $PR --watch --interval 30
```

If any check fails:

```bash
# Read the failure logs
gh run list --branch fix/<ROLE>-molecule-overhaul --limit 1 --json databaseId -q '.[0].databaseId' \
  | xargs gh run view --log-failed
```

Analyse the failure, fix `molecule/shared/verify.yml` or `converge.yml`, then:

```bash
git -C worktrees/<ROLE> add ansible/roles/<ROLE>/molecule/
git -C worktrees/<ROLE> commit -m "test(<ROLE>): fix CI failure — <brief reason>"
git -C worktrees/<ROLE> push
```

Repeat until all checks are green.

## Phase 8 — Merge and cleanup

```bash
# Squash merge
gh pr merge $PR --squash --delete-branch

# Remove worktree
git worktree remove worktrees/<ROLE>
```

## Phase 9 — Report to lead

```
SendMessage("molecule-overhaul", "lead", """
ROLE: <ROLE>
STATUS: done
PR: #<number>
MERGED: yes
ISSUES_FOUND: <count>
ISSUES_FIXED: <list briefly>
SKIPPED: <anything that could not be tested in Docker — explain why>
""")

TaskUpdate("molecule-overhaul", "<ROLE>", "done")
```

---

## Constraints

- Touch ONLY `ansible/roles/<ROLE>/` — never modify other roles
- Never push to master directly
- If a task is structurally impossible in Docker (e.g., GPU drivers need real hardware), document it in verify.yml with a comment and `when: ansible_virtualization_type != 'docker'` guard — do NOT skip the test silently
- If the role has no Docker-compatible scenario, report to lead and mark done with explanation
