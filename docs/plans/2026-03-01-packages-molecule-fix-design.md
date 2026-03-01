# packages molecule test fix — Design

**Date:** 2026-03-01
**Status:** Approved
**Scope:** Fix molecule tests for `packages` role so all 3 CI environments pass with real package verification (Docker Arch+Ubuntu, Vagrant Arch, Vagrant Ubuntu).

## Context

The `packages` role has molecule tests (docker + vagrant scenarios) written in `00571a3`. The tests currently pass CI — but trivially, without checking anything useful. A static analysis found a critical precedence bug in `verify.yml`.

## Confirmed Bug

### `molecule/shared/verify.yml` — vars_files overrides molecule inventory (CRITICAL)

`verify.yml` loads role defaults via `vars_files`:

```yaml
vars_files:
  - "../../defaults/main.yml"
```

Ansible variable precedence:
- `vars_files` in a play = **precedence 14**
- molecule inventory `group_vars` (from `molecule.yml` provisioner) = **precedence 4**

Result: `vars_files` overrides the molecule-configured packages (`packages_base: [git, curl, ...]` etc.) with the role defaults (`packages_base: []`). Additionally, `packages_distro: {}` means the distro-specific list also resolves to `[]`.

Final `packages_verify_expected = []` → the assertion loop is empty → the verify step passes trivially without checking a single installed package.

The converge step is NOT affected (no `vars_files` in `converge.yml`), so packages ARE installed correctly. Only verification is broken.

## Fix

### `molecule/shared/verify.yml`

Two changes:

1. **Remove `vars_files`** — molecule inventory group_vars (precedence 4) are correctly picked up without interference.

2. **Add `| default([])` guards** to every list in `set_fact` — makes verify.yml robust for any scenario where a category variable is not explicitly defined (e.g., the `default` local scenario).

3. **Remove the check_mode idempotence section** — the tasks that run `community.general.pacman` and `ansible.builtin.apt` in `check_mode: true` are redundant. Molecule's built-in `idempotence` step (re-running converge and asserting no changes) already covers this. Removing them simplifies verify.yml and eliminates a potential failure point.

### Resulting verify.yml logic

```
1. Build packages_verify_expected from molecule inventory vars (no vars_files)
2. Gather package_facts (manager: auto)
3. Assert each expected package is in ansible_facts.packages
4. Print summary
```

### No other changes

All other files are correct:
- `docker/molecule.yml` — correct platform config, DNS, image refs
- `docker/prepare.yml` — correctly updates cache for both Arch (pacman) and Ubuntu (apt)
- `vagrant/molecule.yml` — correct boxes and provisioner config
- `vagrant/prepare.yml` — correct (apt update for Ubuntu; Arch install task has `update_cache: true`)
- `tasks/main.yml` — correct, skip-tags: upgrade prevents pacman -Syu in idempotence
- `defaults/main.yml` — correct

## Expected packages verified after fix

| Scenario | Arch packages | Ubuntu packages |
|----------|--------------|-----------------|
| docker   | git curl htop tmux unzip rsync vim fzf ripgrep jq base-devel | git curl htop tmux unzip rsync vim fzf ripgrep jq build-essential |
| vagrant  | git curl htop tmux unzip rsync vim fzf jq base-devel | git curl htop tmux unzip rsync vim fzf jq build-essential |

(docker includes `ripgrep`, vagrant does not — by design in existing molecule.yml)

## Files Changed

| File | Change |
|------|--------|
| `ansible/roles/packages/molecule/shared/verify.yml` | Remove `vars_files`, add `\| default([])` guards, remove redundant check_mode idempotence section |

## Success Criteria

All 3 CI jobs green in GHA with real package assertions:
1. `test / packages` (Docker, Arch + Ubuntu platforms)
2. `test-vagrant / packages / arch-vm`
3. `test-vagrant / packages / ubuntu-base`
