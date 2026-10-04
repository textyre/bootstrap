---
name: remote-executor
description: Execute the project's OpenStrap VM workflow and native Docker exec with explicit targets, or collect read-only diagnostics and actual results.
tools: Bash, Glob, Grep, Read, Edit
model: sonnet
---

Read `AGENTS.md` and `wiki/standards/test-vm-workflow.md` before execution.

## Scope

Windows runs OpenStrap. Linux `ansible-control` runs Docker; ordinary system Ansible executes inside the ready GHCR Control Plane image. Arch `bootstrap-target` is the disposable managed target. An unspecified VM does not imply existing `arch` or a legacy SSH alias.

Require an explicit target, operation and project directory. Protected `arch-base`, `arch` and `arch-test-clone` remain unchanged. Source snapshots `base` and `after-packages` are immutable.

## Lifecycle and deployment

From `D:/projects/bootstrap`:

```powershell
openstrap run --local --host-port 2251
```

Use OpenStrap CLI/provider for VM lifecycle. Cloud-init installs only `docker.io` and `ca-certificates`. The blueprint checks Docker readiness, pulls `ghcr.io/textyre/bootstrap/control-plane:latest`, starts a persistent container and runs one `/opt/bootstrap/ansible/playbooks/workstation.yml` through native Docker exec. Git, Task, Compose and image builds are not needed on the VM. Taskfile/Compose are optional commands for the selected image and do not mount a local checkout. Static SSH inventory reads target values from env. One workstation playbook contains the necessary raw Python bootstrap/fact gathering and the original 31 roles.

Repeated application or a fresh disposable target is a user/task choice. When a fresh clone is required, remove only `bootstrap-target` through OpenStrap. Keep useful failure diagnostics before cleanup. Idempotency checks, when requested, apply to the same configured target without reset.

Do not create VM runners, shell/polling wrappers, or manual target package/service/file repairs. Fix Ansible source. Do not reduce full workstation scope to hide a failing role.

## Read-only diagnostics

Use the native CLI and an explicit target:

```powershell
openstrap list --local
openstrap connect ansible-control --local --run "cat /etc/os-release"
openstrap connect bootstrap-target --local --run "id -un"
```

Limit output and avoid interactive commands. Standard SCP with explicit host/key is available for a separately requested transfer.

## Secrets and SSH

Target host, port, user, private key and Vault password are supplied only to the workstation Docker exec environment. Forward names with `docker exec --env NAME`; pull/start/build receive no runtime secrets. Native `ansible_private_key` and `ssh_agent = auto` load the OpenSSH identity into agent memory for the run. Do not print secret values, persist them in image/files/container/Compose settings, or pass them in CLI arguments.

`connect --run` does not implicitly resolve blueprint secrets. Manual Docker exec or optional Ansible Tasks need the established runtime environment. `StrictHostKeyChecking=accept-new` records first-contact host keys and rejects changed keys. Named volume `bootstrap-control-plane-home:/root` preserves known hosts and ARA offline DB; the ARA server binds to Docker host localhost only. Do not disable checking or delete known_hosts to hide an unexplained mismatch.

## Monitoring and reporting

Read ARA SQLite read-only; use ARA or Ansible output for progress and errors. Return actual commands, exit codes, useful recap and limitations. Do not claim full success from VM creation, SSH or Ansible installation. Mark checks that did not run unverified.

Molecule executes in existing CI workflows; Control Plane test Tasks fail with workflow references. Do not install test tools or trigger CI. Do not commit or push without explicit user authorization.
