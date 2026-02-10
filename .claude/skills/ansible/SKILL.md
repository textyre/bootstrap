---
name: ansible
description: Run Ansible playbooks, individual roles, syntax checks, and linting on the remote VM. Use for provisioning, role testing, and infrastructure changes.
metadata:
  argument-hint: <action> [role-or-playbook]
  allowed-tools: Bash(bash scripts/ssh-run.sh *), Bash(bash scripts/ssh-scp-to.sh *), Bash(bash scripts/ssh-sudo.sh *)
---

# Ansible Operations on Remote VM

Run Ansible operations on the remote Arch Linux VM.

## Remote paths

- Project root: `/home/textyre/bootstrap/`
- Ansible dir: `/home/textyre/bootstrap/ansible/`
- Roles: `/home/textyre/bootstrap/ansible/roles/`
- Playbooks: `/home/textyre/bootstrap/ansible/playbooks/`
- Venv activation: `source ansible/.venv/bin/activate`
- Config: `ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg`

## Command prefix

All Ansible commands on remote must use:
```
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg <command>"
```

## Actions

### `run <playbook>` — Run a full playbook
```
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-playbook ansible/playbooks/<playbook>.yml -v"
```

### `role <role-name>` — Run a single role via temp playbook
Create a temporary playbook and run it:
```
bash scripts/ssh-run.sh "cat > /tmp/run_role.yml << 'EOF'
---
- name: Run single role
  hosts: workstations
  become: true
  gather_facts: true
  roles:
    - role: <role-name>
EOF"

bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-playbook /tmp/run_role.yml -v"
```

### `check` — Syntax check
```
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-playbook ansible/playbooks/workstation.yml --syntax-check"
```

### `lint` — Run ansible-lint
```
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-lint ansible/playbooks/ ansible/roles/"
```

### `verify <role-name>` — Run molecule verify for a role
```
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg MOLECULE_PROJECT_DIRECTORY=/home/textyre/bootstrap/ansible ansible-playbook /home/textyre/bootstrap/ansible/roles/<role-name>/molecule/default/verify.yml -v"
```

### `tags <tag1,tag2>` — Run playbook with specific tags
```
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-playbook ansible/playbooks/workstation.yml --tags '<tags>' -v"
```

## Pre-deploy checklist (for new/modified roles)

Before running a role on remote:
1. Sync role files: `bash scripts/ssh-scp-to.sh -r ansible/roles/<role>/ /home/textyre/bootstrap/ansible/roles/<role>/`
2. Run `ansible-playbook --syntax-check` ON THE REMOTE (ansible is only on the VM, not on Windows)
3. NEVER copy `workstation.yml` to remote if role names diverge — use a temporary single-role playbook instead
4. For xdg/GUI tasks: add `environment: { DISPLAY }` and `become_user` (not root)
5. For i3 assign: launch app on remote → `bash scripts/ssh-run.sh "DISPLAY=:0 xprop WM_CLASS"` → use the REAL value, not a guess
6. Run the role
7. Run it a second time — verify `changed=0` (idempotency)

## Pre-creation checklist (for new roles)

When creating a new Ansible role, verify ALL components exist:
- `defaults/main.yml` — role variables
- `tasks/main.yml` — main logic
- `meta/main.yml` — galaxy metadata
- `handlers/main.yml` — handlers (even if empty)
- `molecule/default/molecule.yml` — molecule config
- `molecule/default/converge.yml` — test scenario
- `molecule/default/verify.yml` — assertions
- Entry `test-<role>` in `Taskfile.yml` + added to `test:` task list
- Role added to `ansible/playbooks/workstation.yml`

## YAML / Jinja2 quality checklist (for every role)

BEFORE committing or deploying any role, verify:
- [ ] Jinja2 vars in YAML values are ALWAYS quoted: `name: "{{ var }}"`, NEVER `name: {{ var }}`
- [ ] Every handler has BOTH `listen:` AND `changed_when:`
- [ ] Galaxy tags in `meta/main.yml` use only `[a-z0-9]` — no hyphens, no uppercase
- [ ] Runtime package deps are in `packages.yml` (e.g. `python-requests` for docker modules, `cronie` for cron, `sqlite` for backups)
- [ ] `ansible-lint` passes with 0 violations before deploy

> For self-hosted service roles (Caddy + Docker, TLS, secrets) — see `.claude/skills/self-hosted/SKILL.md`

## Pre-AUR-role checklist

Before writing a role that installs an AUR package, run on remote BEFORE writing code:
1. `bash scripts/ssh-run.sh "yay -Si <package>"` — get .desktop file name, depends, provides
2. `bash scripts/ssh-run.sh "ls /home/textyre/bootstrap/ansible/roles/"` — verify role names match local
3. ALWAYS include `community.general.pacman: update_cache: true` as a task in the role — mirrors go stale, deps return 404 without it
4. For xdg/GUI tasks: add `environment: { DISPLAY }` and `become_user` (not root)

## Idempotency checklist

For EVERY task using `ansible.builtin.command` or `ansible.builtin.shell`:
1. Is there a pre-check of current state? (get current value → compare → set only if different)
2. Does `changed_when` reflect the real change? (NEVER use `changed_when: true` blindly)
3. After deploying: run the playbook TWICE — second run MUST show `changed=0`

## Argument handling

Interpret `$ARGUMENTS` as: `<action> [target]`

Examples:
- `/ansible check` — syntax check
- `/ansible role zen_browser` — run zen_browser role
- `/ansible run workstation` — run workstation playbook
- `/ansible lint` — run linter
- `/ansible verify zen_browser` — run molecule verify
- `/ansible tags zen_browser,browser` — run specific tags