# Molecule Testing

This role has two meaningful Molecule contracts:

- `docker`: offline contract. Installs/configures reflector, enables the timer, deploys the pacman hook, and checks idempotence with `--skip-tags update`.
- `vagrant`: full Arch VM contract. Runs the online mirrorlist update, checks idempotence, verifies check mode does not mutate mirrorlist state, then validates mirrorlist and backup rotation.

## Docker

Docker is the fast CI path. It intentionally skips `update` because mirror selection is network-dependent and writes `/etc/pacman.d/mirrorlist`.

Checks:

- `reflector` package is installed.
- `reflector.conf` exists, is root-owned, mode `0644`, and contains expected directives.
- `reflector.timer` drop-in exists and contains expected schedule values.
- `reflector.timer` is enabled.
- Optional pacman hook exists and references `pacman-mirrorlist` plus `--config`.
- Idempotence passes for the offline contract.

## Vagrant

Vagrant is the full contract test for the role on an Arch VM.

Checks:

- Everything from the Docker/offline contract.
- Full role idempotence after the first converge.
- Check mode does not mutate the mirrorlist content or backup count.
- `reflector_mirrorlist_path` exists, is non-empty, and contains active `Server =` entries.
- The mirrorlist is not older than `reflector_conf_path`.
- Backup count does not exceed `reflector_backup_keep`.

## Running

Project policy requires role tests to run through the VM/Taskfile workflow. The scenario commands below document the underlying Molecule targets used by that workflow.

Typical role commands:

```bash
molecule test -s docker
molecule test -s vagrant --platform-name arch-vm
```

The delegated `default` scenario applies the full role to the current host and is not the CI path. Use it only on a disposable Arch VM snapshot.
