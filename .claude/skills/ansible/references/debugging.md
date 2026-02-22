# Debugging

Debugging Ansible is not debugging code. It's debugging the gap between what you declared and what the system actually is. The playbook says "this should be true." The error says "it isn't." Your job is to find why.

---

## The 5-Step Method

Most debugging fails because people jump to fixing before understanding. Follow this sequence:

### 1. Read the error

Not skim — read. Ansible error messages are verbose but precise. They tell you:
- Which task failed
- Which module was involved
- What the module tried to do
- What went wrong

The most common debugging mistake: reading the last line and guessing. The actual cause is usually in the middle of the output.

### 2. Reproduce minimally

Don't re-run the entire playbook. Isolate the failing task. Run the playbook with `--start-at-task` to skip everything before the failure, or create a minimal playbook with just the failing role or task. Faster iteration means faster diagnosis.

### 3. Increase verbosity (incrementally)

| Flag | Shows | Use when |
|------|-------|----------|
| `-v` | Task results | Default starting point |
| `-vv` | Task input parameters | Wrong values reaching the module |
| `-vvv` | Connection details | SSH/connectivity issues |
| `-vvvv` | Full plugin internals | Last resort — noisy |

Start with `-v`. Only escalate when the current level doesn't explain the failure. `-vvvv` on a full playbook produces thousands of lines — don't start there.

### 4. Check assumptions

The task assumes something about the system state. What is it? Check whether that assumption holds:
- Is the file actually there? (`stat`)
- Is the package installed? (`which`, package manager query)
- Is the service running? (`systemctl status`)
- Is the user in the right group? (`id`)
- Is the variable what you think it is? (`debug` module)

Most failures come from broken assumptions, not broken code.

### 5. Fix the root cause

Not the symptom. If a template fails because a variable is undefined, the fix is not `| default('')` — it's understanding why the variable is missing. Was it supposed to come from facts? From another role? From inventory? Trace the variable back to its source.

---

## Error Categories

### Connection failures

**Symptoms:** "Connection refused", timeouts, SSH errors.

**Diagnosis:** Is the target reachable? Is SSH running? Is the port correct? Is the user authorized? Can you SSH manually with the same credentials?

**Common traps:** Firewall blocking the port. Wrong SSH key. Host key changed (re-provisioned system). Bastion/jump host required but not configured.

### Privilege escalation

**Symptoms:** "a terminal is required", "sudo: a password is required", permission denied.

**Diagnosis:** Can the user sudo? Is `become_method` correct? Is the sudo password provided when needed? Is `NOPASSWD` configured for the right commands?

**Common traps:** `become: true` without `become_user`. Sudo requiring a password but Ansible running non-interactively. SELinux or AppArmor blocking the escalation.

### Module errors

**Symptoms:** "No module named X", "couldn't resolve module/action", import errors.

**Diagnosis:** Is the module installed? Is the correct Python environment active? Are collection dependencies met?

**Common traps:** Module exists in a collection you haven't installed. Python package required by the module is missing (e.g., `docker` Python package for `community.docker` modules). Ansible running with system Python instead of venv.

### Variable errors

**Symptoms:** "AnsibleUndefinedVariable", wrong values, unexpected behavior.

**Diagnosis:** Use `debug` module to print the variable. Check variable precedence — is an inventory value overriding a default? Is the variable set in the right scope?

**Common traps:** Variable precedence hierarchy (20+ levels in Ansible). Variable set in `vars:` overrides `defaults/main.yml`. Typo in variable name. Variable from one role not visible in another without explicit passing.

**Debugging tool:**
```yaml
- name: Show variable value
  ansible.builtin.debug:
    var: my_variable

- name: Show all variables for a host
  ansible.builtin.debug:
    var: hostvars[inventory_hostname]
```

### YAML / Jinja2 syntax

**Symptoms:** Parse errors, unexpected type coercion, template errors.

**Diagnosis:** YAML is whitespace-sensitive and has implicit type rules. `yes` becomes boolean `true`. `1.0` becomes a float. Unquoted Jinja2 at the start of a value breaks parsing.

**The rule:** Always quote values that contain Jinja2 expressions: `"{{ variable }}"`, never `{{ variable }}`.

**Common traps:** Indentation off by one space. Mixing tabs and spaces. Bare Jinja2 in YAML value position. Colon in an unquoted string. Multi-line strings missing the `|` or `>` indicator.

### Idempotency failures

**Symptoms:** `changed` count > 0 on second run.

**Diagnosis:** Which tasks report changed? Are they using `command`/`shell` without proper `changed_when`? Is a template re-rendering because of timestamp or ordering differences?

**Common traps:** Tasks using `command` without state checks. Templates with dynamic content (timestamps, random values). File permissions being reset by another process between runs. Handlers triggering unnecessary restarts.

### Template rendering

**Symptoms:** Wrong content in generated files, missing sections, syntax errors in generated config.

**Diagnosis:** Render the template locally to inspect output. Check that all variables used in the template are defined and have the expected types. Watch for whitespace control (`{%- -%}`) eating too much or too little.

**Common traps:** Variable is a string when the template expects a list (or vice versa). Loop over undefined variable. Filter applied to wrong type. Jinja2 `default()` hiding real configuration errors.

---

## General Principles

**Trust the error message.** Ansible is verbose for a reason. The answer is almost always in the output.

**Isolate aggressively.** The smaller the reproduction case, the faster you find the cause. One task, one host, one variable.

**Check the system, not just the code.** Ansible interacts with real infrastructure. The playbook might be perfect and the system might be in an unexpected state. Always verify system state independently.

**Don't fix what you don't understand.** If you can't explain WHY the error occurs, you can't be sure your fix is correct. A fix that silences the error without addressing the cause will break again — usually at a worse time.
