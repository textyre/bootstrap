# greeter

Deploys the complete ctOS greeter artifact produced by `task greeter:build`.

## Contract

The role has one responsibility: deploy the ready-to-use greeter filesystem
artifact onto the target host. It does not build the frontend, interpret the
artifact contents, collect machine information, or configure individual
greeter features.

The artifact owns everything required by the ctOS greeter, including its theme,
runtime configuration, backgrounds, metadata, and machine-information helper.
The `packages` and `lightdm` roles remain responsible for installing the greeter
runtime and managing the display manager.

## Execution flow

1. **Deploy** - extract `greeter/dist/ctos-greeter.tar` onto the target filesystem.
2. **Report** - record that the ctOS greeter artifact was deployed.

The role has no handlers, public variables, platform branches, or init-system
branches.

## Build requirement

Run the project build before the role:

```bash
task greeter:build
```

The build creates `greeter/dist/ctos-greeter.tar` with deterministic permissions
and `root:root` ownership. The workstation Taskfile and greeter CI jobs declare
this build as a dependency, so the role always receives a complete artifact.

## Machine information

Machine information displayed on the login screen belongs to the greeter
artifact. Its LightDM setup helper refreshes `system-info.json` when the greeter
starts. Ansible does not collect or render those values.

## Testing

Docker and Vagrant scenarios run on Arch Linux and Ubuntu. Each scenario copies
the real built artifact into the test host, converges the role, and runs the
idempotence pass. The tests cover artifact deployment; installing Nody and
starting LightDM belong to their respective role and workstation integration
tests.

Ansible, Molecule, package, and build commands run only on the remote VM or in
CI.
