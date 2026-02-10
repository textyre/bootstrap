---
name: ansible-debug
description: Diagnose Ansible failures on the remote VM. Use when playbooks fail, tasks error out, or roles produce unexpected results. Covers SSH pipeline, sudo, AUR, Docker, and module errors.
metadata:
  argument-hint: [error-message-or-symptom]
---

# Ansible Debugging on Remote VM

Diagnose and fix Ansible failures in our remote execution pipeline.

## How to use

`$ARGUMENTS` — optional error message or symptom to diagnose. If provided, match against the error patterns below and run the relevant diagnostic commands.

## Error categories

| Category | Symptoms | First check |
|----------|----------|-------------|
| SSH pipeline | "Connection refused", timeout | `bash scripts/ssh-run.sh "echo ok"` |
| Sudo/privilege | "a terminal is required", "sudo: a password is required" | Use `ssh-sudo.sh`, not `ssh-run.sh` with sudo |
| Ansible venv | "ansible: command not found", "No module named ansible" | `bash scripts/ssh-run.sh "source ansible/.venv/bin/activate && ansible --version"` |
| Module missing | "No module named docker", "couldn't resolve module" | Check pip deps and collections |
| AUR build | "makepkg cannot be run as root", SUDO_ASKPASS | Check `become_user`, ASKPASS helper |
| DISPLAY/GUI | "cannot open display", xdg-settings fails | Add `DISPLAY=:0` to environment |
| Jinja2/YAML | "AnsibleUndefinedVariable", YAML parse error | Check quoting, variable precedence |
| Idempotency | `changed=N` on second run (should be 0) | Check `changed_when` on command/shell tasks |

## Diagnostic commands

### 1. SSH connectivity

```bash
# Basic test
bash scripts/ssh-run.sh "echo ok"

# Verbose SSH (see handshake details)
bash scripts/ssh-run.sh "echo ok" 2>&1

# Check if VM is running
bash scripts/ssh-run.sh "uptime"
```

If SSH fails: VM may be off, NAT port 2222 not forwarded, or SSH service down.

### 2. Ansible environment

```bash
# Verify venv and ansible version
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible --version"

# Check installed collections
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-galaxy collection list"

# Check installed pip packages (for docker, etc.)
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && pip list | grep -i docker"
```

### 3. Vault decryption

```bash
# Test vault password
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-vault view ansible/inventory/group_vars/all/vault.yml"

# Check vault-pass.sh exists and works
bash scripts/ssh-run.sh "test -x /home/textyre/bootstrap/ansible/vault-pass.sh && echo ok || echo missing"
```

### 4. Sudo / privilege escalation

```bash
# Test sudo via ssh-sudo.sh (reads ~/.vault-pass)
bash scripts/ssh-sudo.sh "whoami"

# Test ansible become
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible localhost -m command -a 'whoami' --become"
```

**NEVER** use bare `sudo` via `ssh-run.sh` — BatchMode blocks interactive password. Always use `ssh-sudo.sh` or Ansible `--become`.

### 5. Syntax and lint

```bash
# Syntax check
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-playbook ansible/playbooks/workstation.yml --syntax-check"

# Lint
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-lint ansible/playbooks/ ansible/roles/"
```

### 6. Run with verbosity

```bash
# -v: task results, -vv: input params, -vvv: SSH details, -vvvv: full internals
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-playbook /tmp/run_role.yml -vvv"
```

Start with `-v`, increase only if the error is unclear.

## Common error patterns

### "a terminal is required to read the password"
**Cause:** `sudo` in `ssh-run.sh` (BatchMode=yes blocks interactive input).
**Fix:** Use `bash scripts/ssh-sudo.sh "<cmd>"` or Ansible `--become`.

### "makepkg cannot be run as root"
**Cause:** AUR package build running as root instead of user.
**Fix:** Add `become_user: "{{ <role>_user }}"` to the yay task. Ensure `<role>_user` resolves to a non-root user.

### "error: target not found: <package>"
**Cause:** Stale pacman cache.
**Fix:** Add `community.general.pacman: update_cache: true` task before install.

### "No module named 'docker'" / "docker_compose_v2 not found"
**Cause:** Missing Python package or Ansible collection.
**Fix:**
```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && pip install docker docker-compose"
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ansible-galaxy collection install community.docker"
```

### "cannot open display" / xdg-settings fails
**Cause:** Missing `DISPLAY` environment variable.
**Fix:** Add to task:
```yaml
environment:
  DISPLAY: "{{ ansible_facts['env']['DISPLAY'] | default(':0') }}"
```

### "AnsibleUndefinedVariable: '<var>' is undefined"
**Cause:** Variable not set or typo in name.
**Diagnose:**
```bash
# Check variable value
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible localhost -m debug -a 'var=<var_name>' -e '@ansible/inventory/group_vars/all/vault.yml'"
```
**Fix:** Check spelling, check `defaults/main.yml`, use `| default('fallback')`.

### "Vault password not found" / decryption error
**Cause:** `~/.vault-pass` missing or `vault-pass.sh` not executable.
**Fix:**
```bash
bash scripts/ssh-run.sh "test -f ~/.vault-pass && echo exists || echo missing"
bash scripts/ssh-run.sh "test -x /home/textyre/bootstrap/ansible/vault-pass.sh && echo ok || echo not-executable"
```

### Role files out of sync (local edits not reflected on remote)
**Cause:** Forgot to copy role to remote before running.
**Fix:** Sync first:
```bash
bash scripts/ssh-scp-to.sh -r ansible/roles/<role>/ /home/textyre/bootstrap/ansible/roles/<role>/
```

### "changed=N" on second run (idempotency failure)
**Cause:** `command`/`shell` tasks without proper `changed_when`.
**Diagnose:** Run twice, compare output. Look for tasks that always report "changed".
**Fix:** Add state check + `changed_when` based on actual change detection.

## Verbosity levels

| Flag | Shows | When to use |
|------|-------|-------------|
| `-v` | Task results | Default — start here |
| `-vv` | Task input parameters | Parameter mismatches |
| `-vvv` | Connection details | SSH/connectivity issues |
| `-vvvv` | Full plugin internals | Last resort |
