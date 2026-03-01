# power_management Test Coverage Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand `power_management` molecule tests from "files deployed" to "role actually works" — enable behavioral checks (assert_strict: true), verify actual governor value, check timer is active, validate drift state values, and add a laptop scenario to cover the TLP/rfkill code path.

**Architecture:** Four independent layers: (1) bug-fix `is succeeded` in verify.yml (Ansible 2.20 compat), (2) enable assert_strict: true in converge, (3) add behavioral assertions to verify.yml, (4) new `vagrant-laptop` scenario with GHA infrastructure. Laptop scenario requires a one-time `scenario` parameter addition to `_molecule-vagrant.yml` to support non-`vagrant` scenario names.

**Tech Stack:** Ansible, Molecule, Docker (privileged systemd), Vagrant (libvirt/KVM), GitHub Actions

**Current state (what the tests do now):**
- Verify files exist with correct permissions and header content
- Verify package installed (cpupower)
- Verify conflicting services masked
- `assert_strict: false` → all behavioral checks in assert.yml SKIPPED
- Governor only checked against valid-list (not specific configured value)
- Timer checked `is-enabled` but not `is-active`
- Drift state checked for key presence only
- Laptop code path (TLP, rfkill) NEVER executed

---

### Task 1: Create worktree

**Files:** None

**Step 1: Create worktree**

```bash
git worktree add .worktrees/power-management-test-coverage -b feat/power-management-test-coverage
```

Expected: `.worktrees/power-management-test-coverage/` created on new branch.

**Step 2: Verify**

```bash
git worktree list
```

Expected: Three entries (main + new worktree).

---

### Task 2: Fix `is succeeded` bugs in verify.yml

**Files:**
- Modify: `ansible/roles/power_management/molecule/shared/verify.yml`

**Context:** Same Ansible 2.20 breakage fixed in PR #11 (role tasks), now fix verify.yml. Two locations: chassis detection (line 20) and governor assert (lines 328–334). In our test environments both files always exist so the bug doesn't crash today, but it will if environments change.

**Step 1: Fix laptop detection (line 19–21)**

```yaml
# Before (line 19–21):
    - name: Set laptop detection fact
      ansible.builtin.set_fact:
        pm_verify_is_laptop: >-
          {{ pm_verify_chassis is succeeded and
             (pm_verify_chassis.content | b64decode | trim) in ['8', '9', '10', '14', '30', '31', '32'] }}

# After:
    - name: Set laptop detection fact
      ansible.builtin.set_fact:
        pm_verify_is_laptop: >-
          {{ 'content' in pm_verify_chassis and
             (pm_verify_chassis.content | b64decode | trim) in ['8', '9', '10', '14', '30', '31', '32'] }}
```

**Step 2: Fix governor assert `that` list (lines 328–329)**

```yaml
# Before:
    - name: Assert governor is set (when cpufreq available)
      ansible.builtin.assert:
        that:
          - pm_verify_governor is succeeded
          - (pm_verify_governor.content | b64decode | trim) in ['schedutil', 'performance', 'powersave', 'ondemand', 'conservative']

# After:
    - name: Assert governor is set (when cpufreq available)
      ansible.builtin.assert:
        that:
          - "'content' in pm_verify_governor"
          - (pm_verify_governor.content | b64decode | trim) in ['schedutil', 'performance', 'powersave', 'ondemand', 'conservative']
```

**Step 3: Fix governor assert `when` condition (lines 333–334)**

```yaml
# Before:
      when:
        - pm_verify_cpufreq_available.stat.exists | default(false)
        - pm_verify_governor is succeeded

# After:
      when:
        - pm_verify_cpufreq_available.stat.exists | default(false)
        - "'content' in pm_verify_governor"
```

**Step 4: Commit**

```bash
cd .worktrees/power-management-test-coverage
git add ansible/roles/power_management/molecule/shared/verify.yml
git commit -m "fix(power_management/verify): replace 'is succeeded' with 'content' in (Ansible 2.20)

Same fix applied to role tasks in PR #11. Two locations:
chassis DMI detection and governor slurp assert."
```

---

### Task 3: Enable `assert_strict: true` in shared converge

**Files:**
- Modify: `ansible/roles/power_management/molecule/shared/converge.yml`

**Context:** `assert.yml` runs during converge and validates governor value, `sleep.conf HibernateMode`, `logind.conf HandleLidSwitch`. All desktop checks are safe:
- Governor: has `or == 'unknown'` fallback → passes when cpufreq absent (Docker)
- sleep.conf + logind.conf: pure file reads → always work
- TLP checks: gated on `power_management_is_laptop` → skipped for desktop

This enables 3 real behavioral checks in BOTH Docker and Vagrant at no risk.

**Step 1: Flip the flag**

```yaml
# Before (line 11):
        power_management_assert_strict: false

# After:
        power_management_assert_strict: true
```

**Step 2: Commit**

```bash
git add ansible/roles/power_management/molecule/shared/converge.yml
git commit -m "test(power_management): enable assert_strict: true in shared converge

Enables three post-deploy effectiveness checks in assert.yml:
- Governor matches configured value (with 'unknown' fallback for Docker)
- sleep.conf HibernateMode=platform
- logind.conf HandleLidSwitch=suspend
All safe for desktop scenario in Docker and Vagrant."
```

---

### Task 4: Add behavioral checks to verify.yml

**Files:**
- Modify: `ansible/roles/power_management/molecule/shared/verify.yml`

Three additions:
1. Governor matches configured value `schedutil` (not just "a valid value")
2. `power-audit.timer` is active (not just enabled)
3. Drift state `governor` field contains a valid value (not just the key)

**Step 1: Add specific governor value assert** — insert after the existing governor assert block (after line 334)

```yaml
    - name: Assert governor matches configured value (desktop, when cpufreq available)
      ansible.builtin.assert:
        that:
          - (pm_verify_governor.content | b64decode | trim) == 'schedutil'
        fail_msg: >-
          CPU governor is '{{ pm_verify_governor.content | b64decode | trim }}',
          expected 'schedutil' (converge configures desktop default).
          Run 'cpupower frequency-info' to diagnose.
        success_msg: "CPU governor 'schedutil' confirmed"
      when:
        - not pm_verify_is_laptop
        - pm_verify_cpufreq_available.stat.exists | default(false)
        - "'content' in pm_verify_governor"
```

**Step 2: Add timer active check** — insert after the `Assert power-audit.timer is enabled` task (after line 243)

```yaml
    - name: Check power-audit.timer is active
      ansible.builtin.command: systemctl is-active power-audit.timer
      register: pm_verify_audit_timer_active
      changed_when: false
      failed_when: false

    - name: Assert power-audit.timer is active
      ansible.builtin.assert:
        that: pm_verify_audit_timer_active.stdout | trim == 'active'
        fail_msg: "power-audit.timer is not active (got: {{ pm_verify_audit_timer_active.stdout | trim }})"
        success_msg: "power-audit.timer is active"
```

**Step 3: Add drift governor value check** — insert after the existing `Assert drift state file is valid JSON with expected keys` task (after line 314)

```yaml
    - name: Set drift state parsed fact
      ansible.builtin.set_fact:
        pm_verify_drift_json: "{{ pm_verify_drift_content.content | b64decode | from_json }}"

    - name: Assert drift governor field contains a valid value
      ansible.builtin.assert:
        that:
          - pm_verify_drift_json.governor in ['schedutil', 'performance', 'powersave', 'ondemand', 'conservative', 'unknown']
        fail_msg: "Drift state has unexpected governor value: '{{ pm_verify_drift_json.governor }}'"
        success_msg: "Drift state governor: '{{ pm_verify_drift_json.governor }}'"
```

**Step 4: Commit**

```bash
git add ansible/roles/power_management/molecule/shared/verify.yml
git commit -m "test(power_management/verify): add behavioral checks

- Assert governor == 'schedutil' (not just 'a valid governor')
- Assert power-audit.timer is active (was: is-enabled only)
- Assert drift state governor is a valid value (was: key exists only)"
```

---

### Task 5: Add vagrant-laptop scenario

**Files:**
- Modify: `ansible/roles/power_management/molecule/shared/verify.yml`
- Create: `ansible/roles/power_management/molecule/vagrant-laptop/molecule.yml`
- Create: `ansible/roles/power_management/molecule/vagrant-laptop/converge.yml`
- Modify: `.github/workflows/_molecule-vagrant.yml`
- Modify: `.github/workflows/molecule.yml`

**Context:**

KVM VMs have non-laptop DMI chassis_type (typically Desktop), so `pm_verify_is_laptop` auto-detects as `false` even when we ran laptop converge. Fix: add `pm_verify_force_laptop` variable support to shared/verify.yml, pass it via molecule `extra-vars`.

`_molecule-vagrant.yml` currently hardcodes `-s vagrant`. Add a `scenario` input so it can run any scenario name.

`molecule.yml` auto-detects vagrant-capable roles by looking for `molecule/vagrant/molecule.yml`. Add parallel detection for `molecule/vagrant-laptop/molecule.yml`.

Charge threshold assert in assert.yml runs only when `power_management_tlp_bat0_charge_start | string | length > 0`. Default is `""` → assert skipped → no problem with VMs that have no battery.

**Step 1: Modify shared/verify.yml — add `pm_verify_force_laptop` support**

Replace the `Set laptop detection fact` task (lines 18–21):

```yaml
# Before:
    - name: Set laptop detection fact
      ansible.builtin.set_fact:
        pm_verify_is_laptop: >-
          {{ 'content' in pm_verify_chassis and
             (pm_verify_chassis.content | b64decode | trim) in ['8', '9', '10', '14', '30', '31', '32'] }}

# After:
    - name: Set laptop detection fact
      ansible.builtin.set_fact:
        pm_verify_is_laptop: >-
          {{ pm_verify_force_laptop | default(false) or
             ('content' in pm_verify_chassis and
              (pm_verify_chassis.content | b64decode | trim) in ['8', '9', '10', '14', '30', '31', '32']) }}
```

**Step 2: Modify shared/verify.yml — add TLP package and service checks**

Add after the Debian cpupower assert (after line 48):

```yaml
    # ---- TLP (laptop path) ----

    - name: Assert TLP package is installed (laptop)
      ansible.builtin.assert:
        that: "'tlp' in ansible_facts.packages"
        fail_msg: "TLP not installed on laptop"
        success_msg: "TLP package installed"
      when: pm_verify_is_laptop

    - name: Check TLP service state (laptop + systemd)
      ansible.builtin.command: systemctl is-active tlp.service
      register: pm_verify_tlp_active
      changed_when: false
      failed_when: false
      when: pm_verify_is_laptop

    - name: Assert TLP service is active (laptop)
      ansible.builtin.assert:
        that: pm_verify_tlp_active.stdout | trim == 'active'
        fail_msg: "TLP service is not active (got: {{ pm_verify_tlp_active.stdout | trim }})"
        success_msg: "TLP service is active"
      when:
        - pm_verify_is_laptop
        - pm_verify_tlp_active is not skipped
```

Also update the summary debug task (last task, currently line 358–369) to include TLP status:

```yaml
          - "TLP: {{ 'active' if pm_verify_is_laptop else 'not applicable (desktop)' }}"
```

**Step 3: Create `molecule/vagrant-laptop/molecule.yml`**

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: arch-base
    box_url: https://github.com/textyre/arch-images/releases/latest/download/arch-base.box
    memory: 2048
    cpus: 2
  - name: ubuntu-base
    box: ubuntu-base
    box_url: https://github.com/textyre/ubuntu-images/releases/latest/download/ubuntu-base.box
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  options:
    skip-tags: report
    extra-vars: "pm_verify_force_laptop=true"
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  playbooks:
    prepare: ../vagrant/prepare.yml
    converge: converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - prepare
    - converge
    - idempotence
    - verify
    - destroy
```

**Step 4: Create `molecule/vagrant-laptop/converge.yml`**

```yaml
---
- name: Converge (laptop scenario)
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: power_management
      vars:
        power_management_device_type: laptop
        power_management_assert_strict: true
        power_management_audit_battery: false
        # Charge thresholds: empty = don't configure (VMs have no battery)
        # assert.yml skips the threshold check when these are empty strings
        power_management_tlp_bat0_charge_start: ""
        power_management_tlp_bat0_charge_stop: ""
```

**Step 5: Add `scenario` input to `_molecule-vagrant.yml`**

Add after the existing `platform` input (after line 13):

```yaml
      scenario:
        required: false
        type: string
        default: 'vagrant'
        description: "Molecule scenario name (default: vagrant)"
```

Change `Run Molecule` step (line 146):

```yaml
# Before:
          molecule test -s vagrant --platform-name ${{ inputs.platform }}

# After:
          molecule test -s ${{ inputs.scenario }} --platform-name ${{ inputs.platform }}
```

**Step 6: Add vagrant-laptop matrix detection to `molecule.yml`**

In the `Build role matrix` step (currently ends around line 108), add after the `vagrant_matrix` output block:

```bash
          # Vagrant-laptop roles = those with molecule/vagrant-laptop/molecule.yml
          ALL_VAGRANT_LAPTOP=$(find ansible/roles -name molecule.yml -path "*/vagrant-laptop/molecule.yml" \
            | sed 's|ansible/roles/||;s|/molecule.*||' | sort -u)
          VAGRANT_LAPTOP_ROLES=$(comm -12 \
            <(printf '%s\n' $ROLES | sort -u | grep -v '^$') \
            <(printf '%s\n' $ALL_VAGRANT_LAPTOP | grep -v '^$'))
          VAGRANT_LAPTOP_MATRIX=$(printf '%s\n' $VAGRANT_LAPTOP_ROLES | grep -v '^$' \
            | jq -Rsc '[split("\n")[] | select(length > 0)]')
          echo "vagrant_laptop_matrix=$VAGRANT_LAPTOP_MATRIX" >> "$GITHUB_OUTPUT"
          if [ "$VAGRANT_LAPTOP_MATRIX" = "[]" ]; then
            echo "vagrant_laptop_empty=true" >> "$GITHUB_OUTPUT"
          else
            echo "vagrant_laptop_empty=false" >> "$GITHUB_OUTPUT"
          fi
```

Add the new outputs to the `detect` job:

```yaml
      vagrant_laptop_matrix: ${{ steps.build.outputs.vagrant_laptop_matrix }}
      vagrant_laptop_empty: ${{ steps.build.outputs.vagrant_laptop_empty }}
```

Add a new job `test-vagrant-laptop` at the end of `molecule.yml`:

```yaml
  test-vagrant-laptop:
    needs: detect
    if: needs.detect.outputs.vagrant_laptop_empty == 'false'
    strategy:
      matrix:
        role: ${{ fromJSON(needs.detect.outputs.vagrant_laptop_matrix) }}
        platform: [arch-vm, ubuntu-base]
      fail-fast: false
    uses: ./.github/workflows/_molecule-vagrant.yml
    with:
      role_name: ${{ matrix.role }}
      platform: ${{ matrix.platform }}
      scenario: vagrant-laptop
```

**Step 7: Commit**

```bash
git add \
  ansible/roles/power_management/molecule/shared/verify.yml \
  ansible/roles/power_management/molecule/vagrant-laptop/ \
  .github/workflows/_molecule-vagrant.yml \
  .github/workflows/molecule.yml
git commit -m "feat(power_management): add vagrant-laptop molecule scenario

Tests the laptop code path: TLP install + service active, rfkill masked
(Arch), governor managed by TLP, assert_strict: true.

Infrastructure:
- _molecule-vagrant.yml: add 'scenario' input (default: vagrant)
- molecule.yml: auto-detect vagrant-laptop scenarios via directory
  presence, add test-vagrant-laptop job to CI matrix

verify.yml:
- pm_verify_force_laptop var overrides DMI detection (KVM VMs report
  non-laptop chassis_type even when running laptop converge)
- Add TLP package + service active checks (laptop path)"
```

---

### Task 6: Push branch, open PR, monitor CI, merge

**Step 1: Push**

```bash
cd .worktrees/power-management-test-coverage
git push -u origin feat/power-management-test-coverage
```

**Step 2: Open PR**

```bash
gh pr create \
  --title "test(power_management): expand molecule test coverage" \
  --body "$(cat <<'EOF'
## Summary

- Fix `is succeeded` → `'content' in` in verify.yml (Ansible 2.20 compat, 3 locations)
- Enable `assert_strict: true` in shared converge — unlocks governor match, sleep.conf HibernateMode, logind.conf HandleLidSwitch checks
- Add specific governor value assertion (schedutil, not just "a valid governor")
- Add `power-audit.timer` active check (was: enabled only)
- Add drift state governor value assertion
- Add `vagrant-laptop` scenario: tests TLP install, TLP service active, rfkill masking (Arch)
- CI infrastructure: `_molecule-vagrant.yml` gains `scenario` input; `molecule.yml` auto-detects `vagrant-laptop` scenarios

## Test plan

- [ ] `test / power_management` (Docker, Arch+Ubuntu/systemd) — green
- [ ] `test-vagrant / power_management / arch-vm` — green
- [ ] `test-vagrant / power_management / ubuntu-base` — green
- [ ] `test-vagrant-laptop / power_management / arch-vm` — green
- [ ] `test-vagrant-laptop / power_management / ubuntu-base` — green

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Monitor CI**

```bash
gh pr checks <PR-NUMBER> --watch
```

Five jobs must pass:
- `test / power_management (Arch+Ubuntu/systemd)` — Docker
- `power_management — arch-vm` — Vagrant desktop
- `power_management — ubuntu-base` — Vagrant desktop
- `power_management — arch-vm` (vagrant-laptop) — Vagrant laptop
- `power_management — ubuntu-base` (vagrant-laptop) — Vagrant laptop

**Step 4: Common failure modes and fixes**

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `power-audit.timer is not active` | systemd timer didn't start | Add `state: started` to timer enable task in audit.yml |
| `CPU governor is X, expected schedutil` | cpufreq set but different governor | Check assert.yml ran — may indicate conflict; investigate |
| `TLP not installed on laptop` | Package install failed | Check laptop install.yml ran; check Arch/Debian path |
| `TLP service is not active` | TLP started but no modules | Check `systemctl status tlp` in VM; may need `modprobe acpi-cpufreq` |
| `pm_verify_force_laptop not defined` | molecule extra-vars not passing | Check molecule.yml options.extra-vars syntax |
| `vagrant-laptop jobs not triggered` | detect script not finding scenario | Check directory exists + molecule.yml path correct |

**Step 5: If any job fails, investigate**

```bash
gh run view <RUN-ID> --log-failed
```

Each fix gets its own commit.

**Step 6: Merge**

```bash
gh pr merge <PR-NUMBER> --squash --delete-branch
cd /Users/umudrakov/Documents/bootstrap
git pull origin master
git worktree remove .worktrees/power-management-test-coverage
```

---

## Execution notes

- **Worktree required**: All commits happen in `.worktrees/power-management-test-coverage`
- **Task ordering**: Tasks 2–4 are independent but modify same file (verify.yml) — do sequentially
- **Task 5 risk**: Laptop scenario may fail first CI run; Task 5 fix loop is expected
- **assert_strict: true risk (Task 3)**: Low — desktop checks have safe fallbacks. If Docker CI fails on governor assert, check if assert.yml `or == 'unknown'` fallback works
- **`pm_verify_force_laptop` syntax**: In molecule.yml `extra-vars: "key=value"` — this is a string passed to `--extra-vars`
