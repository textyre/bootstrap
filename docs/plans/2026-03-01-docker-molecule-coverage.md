# Docker Molecule Coverage Gap-Fill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Cover three remaining test gaps in the Docker role molecule suite: `docker_storage_driver` positive path, handler restart-on-change, and runtime `docker info` verification.

**Architecture:** Two-pronged approach — (A) add `docker_storage_driver: "overlay2"` to an existing DinD platform to cover the daemon.json positive path; (B) enable docker service on `arch-vm` vagrant platform using `docker_storage_driver: "vfs"` (which avoids overlay2 kernel-module requirements) to unlock handler + runtime coverage on a real VM. `ubuntu-base` vagrant stays disabled (`docker_enable_service: false`) because APT postinstall auto-starts docker, making the handler restart fail within <1s.

**Tech Stack:** Ansible Molecule (docker driver + vagrant/libvirt driver), Ansible 2.19+, GitHub Actions CI, `docker info --format '{{json .}}'` for runtime checks.

---

## Known Constraints

- **ubuntu-base vagrant**: `apt install docker.io` auto-starts docker via postinstall → handler `state: restarted` fails in <1s. Proven across multiple CI runs. Keep `docker_enable_service: false`.
- **arch-vm overlay2 failure**: Previous CI showed docker fails to start with default overlay2 driver. Hypothesis: missing kernel overlay module. `vfs` driver requires no kernel modules — always works.
- **DinD containers** (`ansible_virtualization_type == 'docker'`): No systemd → service/runtime block always skipped by verify.yml guard. Cannot test service/handler/runtime there.
- **Ansible 2.19+**: `fail_msg:` with Jinja2 is evaluated at task finalization (not at skip-time) → all variables referenced in `fail_msg:` must be defined. Use `| default('')` on optional variables.
- **Handler guard**: `handlers/main.yml` already has `when: docker_enable_service | default(true)` — arch-vm with `docker_enable_service: true` will allow handler to fire.

---

## Task 1: Create worktree for this branch

**Branch:** `fix/docker-molecule-coverage`

**Step 1: Create worktree**
```bash
git -C d:/projects/bootstrap worktree add d:/projects/bootstrap-docker-coverage fix/docker-molecule-coverage 2>/dev/null || \
git -C d:/projects/bootstrap worktree add d:/projects/bootstrap-docker-coverage -b fix/docker-molecule-coverage master
```

**Step 2: Verify worktree**
```bash
git -C d:/projects/bootstrap worktree list
ls d:/projects/bootstrap-docker-coverage/ansible/roles/docker/molecule/
```

All subsequent work is done in `d:/projects/bootstrap-docker-coverage/`.

---

## Task 2: Add `storage-driver` positive path assertion to verify.yml

**File:** `ansible/roles/docker/molecule/shared/verify.yml`

**Context:** The existing negative-path assertion (line 286–291) checks that `storage-driver` is ABSENT when `docker_storage_driver` is empty. We need the mirror assertion for the non-empty case.

**Also add:** A runtime assertion inside the existing "Verify Docker runtime settings" block — `docker info` JSON key `Driver` contains the active storage driver.

**Step 1: Add daemon.json positive path assertion**

After the existing negative-path assertion (after line 291, before the Summary comment):

```yaml
    - name: Assert storage-driver in daemon.json (when non-empty)
      ansible.builtin.assert:
        that:
          - "'storage-driver' in _docker_verify_daemon_dict"
          - "_docker_verify_daemon_dict['storage-driver'] == docker_storage_driver"
        fail_msg: "storage-driver not set to '{{ docker_storage_driver | default('') }}' in daemon.json"
      when: docker_storage_driver | default('') | length > 0
```

**Step 2: Add runtime assertion inside the runtime block**

Inside the "Verify Docker runtime settings" block, after the existing `userns` assertion (after line 243, before the block closes):

```yaml
        - name: Assert storage driver at runtime matches variable (when non-empty)
          ansible.builtin.assert:
            that: "_docker_verify_info['Driver'] == docker_storage_driver"
            fail_msg: >-
              Storage driver mismatch:
              expected '{{ docker_storage_driver | default('') }}',
              got '{{ _docker_verify_info['Driver'] | default('') }}'
          when: docker_storage_driver | default('') | length > 0
```

Note: `docker info` JSON uses `Driver` (not `StorageDriver`) for the storage driver field.

**Step 3: Verify verify.yml syntax with ansible-lint**
```bash
cd d:/projects/bootstrap-docker-coverage
ansible-lint ansible/roles/docker/molecule/shared/verify.yml
```
Expected: no errors.

**Step 4: Commit**
```bash
cd d:/projects/bootstrap-docker-coverage
git add ansible/roles/docker/molecule/shared/verify.yml
git commit -m "test(docker): add storage-driver positive-path and runtime assertions"
```

---

## Task 3: Enable storage-driver positive path in docker/molecule.yml (DinD)

**File:** `ansible/roles/docker/molecule/docker/molecule.yml`

**Goal:** Add `docker_storage_driver: "overlay2"` to one DinD platform so the daemon.json positive-path assertion (Task 2 Step 1) is exercised. Choose `Ubuntu-nosec` — it already tests all optional security features disabled; adding an explicit storage driver adds coverage without creating new platforms.

Note: `overlay2` is Docker's default driver, but we need to set it explicitly in daemon.json to trigger the positive path assertion.

**Step 1: Add storage-driver to Ubuntu-nosec host_vars**

Current `Ubuntu-nosec` host_vars (lines 81–87):
```yaml
      Ubuntu-nosec:
        docker_enable_service: false
        docker_icc: true
        docker_userns_remap: ""
        docker_live_restore: false
        docker_no_new_privileges: false
        docker_add_user_to_group: false
```

Change to:
```yaml
      Ubuntu-nosec:
        docker_enable_service: false
        docker_icc: true
        docker_userns_remap: ""
        docker_live_restore: false
        docker_no_new_privileges: false
        docker_add_user_to_group: false
        docker_storage_driver: "overlay2"
```

**Step 2: Commit**
```bash
cd d:/projects/bootstrap-docker-coverage
git add ansible/roles/docker/molecule/docker/molecule.yml
git commit -m "test(docker): add overlay2 storage-driver platform to DinD scenario"
```

---

## Task 4: Enable arch-vm service with vfs driver in vagrant/molecule.yml

**File:** `ansible/roles/docker/molecule/vagrant/molecule.yml`

**Goal:** Remove `docker_enable_service: false` from arch-vm so it inherits `true` from group_vars.all. Add `docker_storage_driver: "vfs"` to fix the overlay2 kernel-module issue that prevented docker from starting in previous CI runs.

This will enable on arch-vm:
- Docker service enabled and running (service assertions)
- Handler fires on first converge (implicit via service being running)
- Runtime `docker info` assertions including storage-driver check

**Step 1: Modify arch-vm host_vars**

Current arch-vm host_vars (lines 41–47):
```yaml
      arch-vm:
        docker_userns_remap: ""
        docker_icc: true
        docker_log_driver: "json-file"
        docker_live_restore: false
        docker_no_new_privileges: false
        docker_enable_service: false
```

Change to (remove `docker_enable_service: false`, add `docker_storage_driver: "vfs"`):
```yaml
      arch-vm:
        docker_userns_remap: ""
        docker_icc: true
        docker_log_driver: "json-file"
        docker_live_restore: false
        docker_no_new_privileges: false
        docker_storage_driver: "vfs"
```

**Step 2: Commit**
```bash
cd d:/projects/bootstrap-docker-coverage
git add ansible/roles/docker/molecule/vagrant/molecule.yml
git commit -m "test(docker): enable arch-vm service with vfs storage driver"
```

---

## Task 5: Push and watch CI

**Step 1: Push branch**
```bash
cd d:/projects/bootstrap-docker-coverage
git push -u origin fix/docker-molecule-coverage
```

**Step 2: Open PR**
```bash
gh pr create \
  --repo textyre/bootstrap \
  --base master \
  --title "test(docker): fill remaining coverage gaps (storage-driver, service, runtime)" \
  --body "$(cat <<'EOF'
## Summary
- Add `storage-driver` positive-path assertion to `verify.yml` (daemon.json content)
- Add `storage-driver` runtime assertion to `verify.yml` (via `docker info`)
- Enable `docker_storage_driver: "overlay2"` on `Ubuntu-nosec` DinD platform
- Enable docker service on `arch-vm` vagrant with `docker_storage_driver: "vfs"` (avoids overlay2 kernel-module requirement)

## Coverage after this PR
| Platform | daemon.json | service enabled | service running | runtime docker info | handler |
|---|---|---|---|---|---|
| DinD Arch/Ubuntu-systemd | ✅ | skip (DinD) | skip (DinD) | skip (DinD) | skip (DinD) |
| DinD Arch/Ubuntu-nosec | ✅ | skip (DinD) | skip (DinD) | skip (DinD) | skip (DinD) |
| DinD Ubuntu-nosec (+overlay2) | ✅ storage-driver | skip (DinD) | skip (DinD) | skip (DinD) | skip (DinD) |
| vagrant arch-vm (+vfs) | ✅ | ✅ | ✅ | ✅ | ✅ (implicit) |
| vagrant ubuntu-base | ✅ | skip (apt conflict) | skip | skip | skip |

## Known accepted gap
- `ubuntu-base` vagrant: `docker_enable_service: false` because APT postinstall auto-starts docker, making handler restart fail within <1s.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: Watch CI**

Get the run ID after push:
```bash
gh run list --repo textyre/bootstrap --branch fix/docker-molecule-coverage --limit 3
```

Wait for run to finish (typically ~10-15 min for vagrant):
```bash
gh run watch <RUN_ID> --repo textyre/bootstrap
```

---

## Task 6: If arch-vm fails — diagnose and pivot

If CI shows arch-vm failing to start docker (service not running), diagnose first:

**Collect logs from failed CI run:**
```bash
gh run view <RUN_ID> --repo textyre/bootstrap --log | grep -A 20 "arch-vm.*docker"
```

**Possible failure causes and fixes:**

### Cause A: vfs still fails (unlikely but possible)
- Try `docker_storage_driver: "devicemapper"` — not recommended, probably worse
- OR: accept the gap, revert arch-vm change, document

### Cause B: journald log driver issue
- arch-vm uses `docker_log_driver: "json-file"` (from host_vars) — this should be fine
- If somehow journald is used, change to `json-file`

### Cause C: iptables/nftables conflict
- arch-vm might have nftables from a base image
- Add `docker_iptables_disabled: false` investigation
- Check: does prepare.yml need `iptables-nft` package on Arch?

**Pivot plan if arch-vm cannot be fixed in one CI attempt:**
```bash
cd d:/projects/bootstrap-docker-coverage
# Revert arch-vm change only, keep storage-driver assertions + DinD platform
git revert HEAD  # or manually restore vagrant/molecule.yml
git push
```

Then document the gap in a commit message or docs/plans note.

---

## Task 7: Merge and clean up

**Step 1: Merge PR (squash)**
```bash
gh pr merge <PR_NUMBER> --repo textyre/bootstrap --squash --delete-branch
```

**Step 2: Remove worktree**
```bash
git -C d:/projects/bootstrap fetch origin master
git -C d:/projects/bootstrap pull origin master
git -C d:/projects/bootstrap worktree remove d:/projects/bootstrap-docker-coverage --force
```

**Step 3: Verify clean state**
```bash
git -C d:/projects/bootstrap worktree list
git -C d:/projects/bootstrap log --oneline -5
```

---

## Summary of Coverage After This Plan

| Gap | Before | After |
|-----|--------|-------|
| `storage-driver` positive path (daemon.json) | ❌ no platform | ✅ Ubuntu-nosec DinD (overlay2) + arch-vm vagrant (vfs) |
| `storage-driver` positive path (runtime) | ❌ no platform | ✅ arch-vm vagrant (vfs, if service enabled) |
| Handler restart-on-change | ❌ `docker_enable_service: false` everywhere | ✅ arch-vm vagrant (implicit: service running after converge) |
| Runtime `docker info` | ❌ no platform | ✅ arch-vm vagrant |
| `ubuntu-base` service/handler/runtime | ❌ APT conflict | accepted gap (documented) |
