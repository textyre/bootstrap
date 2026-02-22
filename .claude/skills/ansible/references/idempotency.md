# Idempotency

Idempotency is not a property of code. It's a promise to the operator: "Run this as many times as you want. Nothing will break. Nothing will change unless it needs to."

When that promise is kept, operators trust automation. When it's broken, they stop trusting and start reading every line before hitting enter. Broken idempotency turns infrastructure-as-code into infrastructure-as-script.

---

## The Two-Run Test

The simplest test of idempotency: run the playbook twice. The second run must show `changed=0`.

This is not a suggestion. It's a hard requirement. If the second run shows changes, something is lying — either the task is doing unnecessary work, or `changed_when` is reporting false positives.

A task that reports `changed` when nothing changed is not "mostly idempotent." It's broken. The operator cannot distinguish real drift from noise, and the entire reporting pipeline becomes untrustworthy.

---

## Module Hierarchy

Not all ways of achieving a state are equal. There is a clear hierarchy:

**Tier 1 — Native modules.** These are purpose-built for idempotency. `ansible.builtin.file` checks whether the file already matches the desired state before touching anything. `ansible.builtin.template` compares checksums. `ansible.builtin.user` reads `/etc/passwd`. They do the right thing without you asking.

Use native modules whenever one exists for your task. If you reach for `command` to do something a module handles, you're bypassing the safety net for no reason.

**Tier 2 — Command with pre-check.** When no module exists, use `command` or `shell` with a state check. First, read the current state. Then, only act if it differs from desired. The `creates:` and `removes:` parameters are the simplest form of this. For more complex state: register the current value, compare, then conditionally execute.

The key: the pre-check must be fast, reliable, and side-effect-free. It's a read operation, not a write.

**Tier 3 — Command with output parsing.** Sometimes you can't pre-check — you have to run the command and determine from its output whether anything actually changed. Parse stdout/stderr and set `changed_when` based on the actual result.

This is the most fragile tier. Output formats change between versions. Locale settings affect messages. Parse conservatively and test against real systems.

---

## The Three Lies

### Lie 1: `changed_when: false`

This tells Ansible "this task never changes anything." Sometimes that's true — a read-only query, a version check, a diagnostic command. But often it's used to silence a task that DOES change things. The operator sees green. The system silently drifts.

**The test:** If you removed `changed_when: false`, would the task ever legitimately report `changed`? If yes, you're lying.

**The fix:** Add a real state check. Register output, compare to desired state, set `changed_when` based on whether a change actually occurred.

### Lie 2: `changed_when: true`

This tells Ansible "this task always changes something." It's the opposite lie — used when someone can't be bothered to check. Every run reports yellow. After a week, operators ignore `changed` counts entirely.

**The test:** Run the task twice on an already-configured system. Did it actually change something the second time? If not, you're crying wolf.

**The fix:** Same as Lie 1 — detect real state change from command output or a pre-check.

### Lie 3: `ignore_errors: true`

This doesn't lie about change — it lies about success. "Something went wrong, but let's pretend it didn't." The task that follows may depend on the one that failed. Cascading silent failures are the hardest bugs to diagnose.

**When it's legitimate:** Checking for something that may not exist (a package, a file, a service). The absence IS the expected state.

**When it's a lie:** Wrapping a task you know sometimes fails because you don't want to deal with the error. If you need `ignore_errors`, you almost certainly need `failed_when` with specific conditions instead.

---

## Testing Idempotency

### The two-run test (minimum)

Run the playbook. Then run it again. The second run must show:
- `changed=0` — no task reported a change
- `failed=0` — no task failed
- Same end state — the system is configured correctly

If any task shows `changed` on the second run, investigate. Either the task is not idempotent, or `changed_when` is wrong.

### Check mode

`--check` runs the playbook without making changes. It's a dry run. Tasks that would change something report `changed`; tasks that wouldn't report `ok`.

Check mode has limits — `command` and `shell` tasks are skipped by default, and tasks that depend on previous changes may report incorrectly. But for module-heavy playbooks, it's a fast sanity check.

### Molecule integration

Molecule runs the full cycle: create environment → converge (first run) → idempotence check (second run) → verify (assertions) → destroy. The idempotence step is built in — it runs the playbook twice and fails if the second run shows changes.

This is the gold standard for automated idempotency testing. If your role has molecule tests, the two-run test happens automatically.

---

## The Mindset

Think of every task as answering a question: "Is this system already in the desired state?"

If yes: do nothing, report ok.
If no: make the change, report changed.
If you can't tell: you have a design problem.

The goal is not "make the system match my playbook." The goal is "ensure the system is in the desired state, whether this is the first run or the hundredth." The distinction matters. The first framing leads to imperative thinking — do this, then this, then this. The second leads to declarative thinking — this is what should be true.

Declarative thinking is what makes Ansible different from a shell script. Lose it, and you're writing shell scripts in YAML.
