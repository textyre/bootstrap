# Docker Molecule Tests — Fix Design (2026-03-01)

## Context

Branch: `fix/docker-molecule-overhaul` | PR: #37

Three CI failures block green tests for the `docker` role:
1. Molecule docker (DinD) scenario — all 4 platforms fail
2. Molecule vagrant arch-vm — converge fails
3. Molecule vagrant ubuntu-base — handler (restart docker) fails

---

## Gap Analysis: README vs Tests

| README Requirement | Test Coverage | Status |
|---|---|---|
| Creates `/etc/docker/` (root:root 0755) | ✅ verify.yml stat + assert | OK |
| Builds `docker_daemon_config` via `set_fact` | ✅ Indirect via daemon.json content | OK |
| Deploys `daemon.json` with JSON validation | ✅ stat + python3 json.load | OK |
| `docker` group exists | ✅ `getent group docker` | OK |
| User added to `docker` group | ✅ `id -nG` check | OK |
| Enables/starts service (skippable) | ✅ service_facts with DinD guard | OK |
| Restarts Docker on config change (handler) | ❌ Not tested | Gap |
| `docker_user` variable | ✅ Used in group membership check | OK |
| `docker_add_user_to_group` variable | ✅ Both positive and negative path | OK |
| `docker_enable_service` variable | ✅ Service block conditional | OK |
| `docker_log_driver` variable | ⚠️ Test exists but **BROKEN** | Fix needed |
| `docker_log_max_size` variable | ⚠️ Test exists but **BROKEN** | Fix needed |
| `docker_log_max_file` variable | ⚠️ Test exists but **BROKEN** | Fix needed |
| `docker_storage_driver` variable | ❌ No test at all | Gap |
| `docker_userns_remap` variable | ✅ Positive and negative tested | OK |
| `docker_icc` variable | ✅ Positive and negative tested | OK |
| `docker_live_restore` variable | ✅ Positive and negative tested | OK |
| `docker_no_new_privileges` variable | ✅ Positive and negative tested | OK |

**Handler behavior** and **`docker_storage_driver`** are genuine test gaps but not blocking CI green.
The three broken tests (`log_driver`, `log_max_size`, `log_max_file`) share a single root cause.

---

## Root Cause Analysis

### Failure 1: `docker_log_driver` undefined (DinD scenario — all 4 platforms)

**Error:**
```
Task failed: Finalization of task args for 'ansible.builtin.assert' failed:
Error while resolving value for 'fail_msg': 'docker_log_driver' is undefined
```

**Root cause:** `verify.yml` uses `include_role tasks_from: noop.yml` in `pre_tasks` to load role
defaults. In Ansible 2.19+, task argument finalization (including `fail_msg` Jinja2 evaluation)
happens eagerly — before the `pre_tasks` block completes. The role defaults are not yet in scope
when the task args are finalized.

**Fix:** Replace `include_role tasks_from: noop.yml` with `vars_files: ../../defaults/main.yml`.
This loads variables at playbook parse time, before any task runs.
This matches the project standard documented in `memory/molecule-testing.md`.

### Failure 2: Vagrant arch-vm — "Could not find the requested service docker: host"

**Root cause:** `molecule/vagrant/prepare.yml` has only Ubuntu tasks. Docker is never installed
on the Arch Linux VM. When the role runs with `docker_enable_service: true`, the `service` module
cannot find `docker.service`.

**Fix:** Add `community.general.pacman` task to install `docker` on Arch Linux in
`vagrant/prepare.yml`, and start the service to initialize its runtime state.

### Failure 3: Vagrant ubuntu-base — "Unable to restart service docker"

**Root cause:** Docker is installed in `vagrant/prepare.yml` but never started. When the role
deploys `daemon.json` with `userns-remap: "default"`, the restart handler fires. Docker fails
to start because:
- `uidmap` package (provides `newuidmap`/`newgidmap`) is not installed with `docker.io`
- The `dockremap` user is created by Docker on first start, but can't be created when
  `userns-remap` is already set in `daemon.json` before first start without `uidmap`

**Fix:** In `vagrant/prepare.yml` for Ubuntu:
1. Install `docker.io` AND `uidmap`
2. Start docker service to initialize its runtime (creates `dockremap` user + `subuid/subgid`)

---

## Design

### Change 1: `molecule/shared/verify.yml` — fix variable loading

Replace:
```yaml
pre_tasks:
  - name: Load docker role defaults (respects host_vars overrides)
    ansible.builtin.include_role:
      name: docker
      tasks_from: noop.yml
```
With:
```yaml
vars_files:
  - ../../defaults/main.yml
```

This makes all defaults available at playbook parse time. Host_vars from `molecule.yml` override
these at higher precedence (molecule inventory host_vars > role defaults), so the semantics
remain correct for the nosec platforms.

### Change 2: `molecule/vagrant/prepare.yml` — add Arch + uidmap + docker pre-start

Add:
- pacman update cache + install `docker` for Arch
- apt install `uidmap` for Ubuntu (alongside existing `docker.io`)
- Start docker service on both platforms after installation

### Change 3: Add `docker_storage_driver` test coverage (negative path only)

The default is `""` (empty), which means the key should be absent from `daemon.json`.
Add a negative-path assertion to verify.yml (similar to existing `userns-remap` negative path).

---

## What is NOT changed

- Role tasks (`tasks/main.yml`, `handlers/main.yml`) — no role logic changes needed
- Docker DinD `molecule/docker/molecule.yml` — no platform changes needed
- Handler-coverage testing — deferred (requires multi-run molecule test, out of scope)
- `docker:configure` / `docker:service` tag coverage — already implicitly tested

---

## Expected outcome

After these changes:
- `molecule test -s docker` passes on all 4 platforms (Arch/Ubuntu × systemd/nosec)
- `molecule test -s vagrant` passes on both arch-vm and ubuntu-base
- All README requirements have test coverage or documented gaps
