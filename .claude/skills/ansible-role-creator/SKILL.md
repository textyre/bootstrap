---
name: ansible-role-creator
description: Scaffold a new Ansible role with all required files, tests, and integration points. Creates defaults, tasks, meta, handlers, molecule tests, Taskfile entry, and playbook entry.
metadata:
  argument-hint: <role_name> [description]
---

# Ansible Role Creator

Scaffold a complete Ansible role following project conventions.

## Argument parsing

`$ARGUMENTS` format: `<role_name> [description]`

- `role_name` — snake_case (e.g. `my_service`, `node_exporter`)
- `description` — optional, used in meta/main.yml

If no description provided, ask the user.

## What to create

All files go under `ansible/roles/<role_name>/`. Variable prefix: `<role_name>_`.

### 1. `defaults/main.yml`

```yaml
---
# === <Description> ===

# Включить роль
<role_name>_enabled: true
```

Add role-specific variables with sensible defaults. Use `<role_name>_` prefix for ALL variables.

### 2. `tasks/main.yml`

```yaml
---
# === <Description> ===

- name: <First task description>
  # ...
  when: <role_name>_enabled
  tags: ['<role_name>', '<category>']
```

Rules:
- Every task MUST have `tags:` with at least the role name
- Every task MUST have `when: <role_name>_enabled`
- Use `ansible.builtin.*` fully qualified module names
- Quote Jinja2 vars in YAML: `"{{ var }}"`, NEVER `{{ var }}`
- For command/shell tasks: always set `changed_when` based on actual change

### 3. `meta/main.yml`

```yaml
---
galaxy_info:
  role_name: <role_name>
  author: textyre
  description: <Description>
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
  galaxy_tags: [<lowercase_tags_no_hyphens>]
dependencies: []
```

Rules:
- `galaxy_tags` — only `[a-z0-9]`, no hyphens, no uppercase
- Add `dependencies` if the role requires other roles (e.g. `docker`, `caddy`)

### 4. `handlers/main.yml`

```yaml
---
# Handlers for <role_name> role
```

Add handlers only if the role needs them (service restarts, reloads). Every handler MUST have both `listen:` and `changed_when:`.

### 5. `molecule/default/molecule.yml`

```yaml
---
driver:
  name: default
  options:
    managed: false

platforms:
  - name: localhost

provisioner:
  name: ansible
  config_options:
    defaults:
      vault_password_file: ${MOLECULE_PROJECT_DIRECTORY}/vault-pass.sh
      callbacks_enabled: profile_tasks
  inventory:
    host_vars:
      localhost:
        ansible_connection: local
  playbooks:
    converge: converge.yml
    verify: verify.yml
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/roles"

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - converge
    - verify
```

### 6. `molecule/default/converge.yml`

```yaml
---
- name: Converge
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"

  roles:
    - role: <role_name>
```

Add `pre_tasks` for platform assertions if role is Arch-only.

### 7. `molecule/default/verify.yml`

```yaml
---
- name: Verify
  hosts: all
  become: true
  gather_facts: true
  vars_files:
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/inventory/group_vars/all/vault.yml"
    - "{{ lookup('env', 'MOLECULE_PROJECT_DIRECTORY') }}/roles/<role_name>/defaults/main.yml"

  tasks:
    - name: Check <what to verify>
      ansible.builtin.stat:
        path: <expected_path>
      register: _<role_name>_verify_<item>
      failed_when: not _<role_name>_verify_<item>.stat.exists

    - name: Show test results
      ansible.builtin.debug:
        msg:
          - "All checks passed!"
```

Write meaningful verification tasks that confirm the role worked.

## Integration points

After creating the role files, also update:

### 8. `Taskfile.yml` — add test task

Insert before `# --- Playbook execution ---`:

```yaml
  test-<role-hyphenated>:
    desc: "Run molecule tests for <role_name>"
    deps: [_ensure-venv, _check-vault]
    dir: '{{.ANSIBLE_DIR}}/roles/<role_name>'
    env:
      MOLECULE_PROJECT_DIRECTORY: '{{.TASKFILE_DIR}}/{{.ANSIBLE_DIR}}'
    cmds:
      - 'echo "==> Testing <role_name> role..."'
      - '{{.PREFIX}} molecule test'
```

Also add `- task: test-<role-hyphenated>` to the `test:` task's `cmds:` list (before the final echo).

Note: Taskfile task names use hyphens (`test-my-service`), while Ansible role dirs use underscores (`my_service`).

### 9. `ansible/playbooks/workstation.yml` — add role entry

Add the role in the appropriate phase section with tags:

```yaml
    - role: <role_name>
      tags: [<role_name>, <category>]
```

Phases:
- Phase 1: System foundation (base_system, vm, reflector)
- Phase 1.5: Hardware & Kernel (gpu_drivers, sysctl, power_management)
- Phase 2: Package infrastructure (yay, packages)
- Phase 3: User & access (user, ssh)
- Phase 4: Development tools (git, shell)
- Phase 5: Services (docker, firewall, caddy, vaultwarden)
- Phase 6: Desktop environment (xorg, lightdm, zen_browser)
- Phase 7: User dotfiles (chezmoi)

## Self-hosted service roles

If the role deploys a Docker service behind Caddy, read `.claude/skills/self-hosted/SKILL.md` for required patterns (Docker network, Caddy site config, TLS, secrets, /etc/hosts).

## After creation

Report to the user:
1. List all created files
2. Remind: fill in actual task logic in `tasks/main.yml`
3. Remind: fill in verification logic in `molecule/default/verify.yml`
4. Suggest running `/ansible check` to validate syntax
