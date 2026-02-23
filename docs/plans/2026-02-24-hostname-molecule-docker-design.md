# hostname: Docker Molecule Test — Design

**Date:** 2026-02-24
**Status:** Approved

## Problem

The `hostname` role has a `molecule/default/` scenario (localhost), but CI only picks up roles
with `molecule/docker/molecule.yml`. As a result, hostname is excluded from the CI matrix.

Additionally, the existing test has two issues:
- `verify.yml` only checks that hostname is non-empty, not that it matches the expected value.
- `tasks/main.yml:41` references `_hostname_check.stdout` (undefined), but `register:
  hostname_check` (no underscore) — causes silent assert failure.

## Goal

Make the hostname role CI-ready by adding a Docker-based Molecule scenario, fixing the bug in
tasks, and bringing tests to project standards (like `locale` role).

## Design

### Pattern: shared playbooks (locale model)

Both `default` and `docker` scenarios reference the same `converge.yml` and `verify.yml` from
`molecule/shared/`. No duplication.

```
ansible/roles/hostname/molecule/
  shared/
    converge.yml     ← single role invocation, no vault, no arch-assert
    verify.yml       ← comprehensive verification (hostname exact + FQDN in hosts)
  default/
    molecule.yml     ← updated: ../shared/ references, idempotency added, vault removed
    (converge.yml)   ← DELETED (replaced by shared)
    (verify.yml)     ← DELETED (replaced by shared)
  docker/
    molecule.yml     ← NEW: docker driver, arch-systemd, ../shared/ references
```

### shared/converge.yml

```yaml
roles:
  - role: hostname
    vars:
      hostname_name: "archbox"
      hostname_domain: "example.com"
```

No `vars_files` — hostname role does not use vault variables.
No `pre_tasks` arch assert — always Arch in Docker; unnecessary on localhost too.

### shared/verify.yml

Three verification sections:

1. **Hostname exact match** — `ansible.builtin.command: hostname` → assert stdout == `"archbox"`
2. **FQDN in /etc/hosts** — `ansible.builtin.slurp /etc/hosts` → assert contains
   `127.0.1.1\tarchbox.example.com\tarchbox`
3. **No duplicate 127.0.1.1 entries** — assert exactly one line matching `^127\.0\.1\.1`

### molecule/docker/molecule.yml

Identical to `timezone/molecule/docker/molecule.yml`:
- driver: docker
- image: arch-systemd
- privileged: true, cgroup, tmpfs
- `skip-tags: report`
- `ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"`
- test_sequence: syntax → create → converge → idempotence → verify → destroy

### molecule/default/molecule.yml

Updated to match `locale/molecule/default/molecule.yml`:
- Remove `vault_password_file`
- Change `ANSIBLE_ROLES_PATH` to `"${MOLECULE_PROJECT_DIRECTORY}/../"`
- Add `idempotency` to test_sequence
- Reference `../shared/converge.yml` and `../shared/verify.yml`

### tasks/main.yml — bug fix

Line 41: `_hostname_check.stdout` → `hostname_check.stdout`
(register on line 33 is `hostname_check`, underscore prefix is erroneous).

## Out of Scope

- Other distros or init systems — Arch/systemd only for now.
- Negative test cases (invalid hostname, missing hostname_name) — validate at unit level, not
  molecule.
- `prepare.yml` — hostname role has no Docker-specific prerequisites.

## Success Criteria

1. `molecule test -s docker` passes in CI (syntax, converge, idempotence, verify, destroy).
2. `verify.yml` asserts exact hostname `archbox` and FQDN format in `/etc/hosts`.
3. `tasks/main.yml` assert no longer references undefined variable.
4. No playbook duplication between `default` and `docker` scenarios.
