# Project Instructions

## Execution model

Windows edits project files and runs OpenStrap CLI. `ansible-control` is a Linux
Docker host. Native cloud-init installs `docker.io`/`ca-certificates`, initializes
a single-node Swarm using the route's local IP, and creates the persistent
`bootstrap-control-plane` service from `ghcr.io/textyre/bootstrap/control-plane:latest`
(master's), or a branch's image with `BOOTSTRAP_IMAGE_TAG=branch-<branch>` before it is merged.
The service has one replica, host networking and named volume
`bootstrap-control-plane-home:/root`. The Ubuntu 26.04 image contains system
APT Ansible/lint, ARA 1.7.3, collections and public `/opt/bootstrap/ansible` source.

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

`bootstrap-target` is a disposable full clone of `arch-base/base-2026-11`;
`ansible-control` uses Ubuntu 24.04. Both VMs run headless. Shared network
`bootstrap` connects target `172.28.51.10:22` to controller `172.28.51.11`;
Windows SSH ports are `2251` and `2252`. Cloud-init runs once on first boot as
root. Existing VMs do not adopt changed cloud-init/networking or convert an old
standalone container into Swarm without an explicit recreation/migration action.

After cloud-init, the only readiness requirement expects `1/1` from native
`docker service ls`. Two stdin steps create and rotate native Swarm secrets;
the final step runs one workstation playbook through native Docker exec. A
repeated run rotates the secret references/service task and applies workstation
once; it does not select/pull a new image. Workstation includes bare Arch Python
bootstrap, fact gathering and the original 31 roles. Deployment needs no Git,
Task, Compose, image build, dependency installation or custom secret helper.
Root Taskfile and Compose wrappers were removed; target-role Compose remains.

## Routing and role standards

Use applicable Ansible and dotfiles skills. Delegate independent work with an
explicit target, project directory and command scope. An unspecified VM never
means protected `arch` or a legacy SSH alias. Roles follow [Role Requirements](wiki/standards/role-requirements.md),
[Security Standards](wiki/standards/security-standards.md) and [Profiles](wiki/standards/workstation-profiles.md).

- Supported project distros: Arch, Ubuntu, Fedora, Void, Gentoo.
- Supported init families: systemd, runit, openrc, s6, dinit.
- Baseline: CIS Level 1 Workstation; use native Ansible modules and verification.
- Preserve full workstation scope. Success does not prove untested distro/init combinations.

## Test machines and delivery

Follow [Test VM Workflow](wiki/standards/test-vm-workflow.md).

- Protected `arch-base`, `arch`, `arch-test-clone` and source snapshots `base`/
  `after-packages` are never modified, rebooted, restored, rebuilt or deleted.
- VM lifecycle uses OpenStrap CLI/provider. Do not introduce lifecycle wrappers,
  polling scripts or replacement VBox orchestration.
- Local source changes require a new GHCR publication and explicit image/controller
  replacement to affect an existing environment. Use published `sha-<commit>` revisions.
- Do not commit or push without explicit user authorization.
- Run project Ansible/lint inside the Control Plane service task through native
  Docker exec. See [Ansible commands](ansible/README.md) for task discovery and checks.
- Static `inventory/openstrap.yml` uses public runtime env lookups. Do not apply
  workstation to the controller or silently substitute localhost.
- Fix packages/services/files in Ansible source; do not manually repair targets
  just to make later runs appear successful.
- Repeating workstation or creating a fresh disposable clone is a user/task choice.
- Molecule uses existing `.github/workflows/molecule.yml` and `molecule-vagrant.yml`.
  The Control Plane does not install Molecule or trigger CI implicitly.

## Runtime secrets

openstrap's `keychain` plugin (installed from npm) keeps the secrets in the OS
credential store. Save `ARCH_BASE_SSH_KEY` and `BOOTSTRAP_TARGET_SUDO_PASSWORD`
once per host with `openstrap secret set NAME` (hidden input); normal runs fetch
them automatically. The sudo entry supplies provider-owned clone network setup
and Ansible sudo; the blueprint names the SSH key with `identity`. There is no Bootstrap Ansible Vault or Vault
password adapter. [Bootstrap Secrets](docs/bootstrap-secrets.md) describes the flow.

Provider network preparation passes the password via SSH stdin to `sudo -S`.
The two controller steps pass sudo/key payloads via SSH stdin to native
`docker secret create NAME -`. Immutable secrets have unique names and project
labels. Synchronous service updates replace only the relevant mount, verify the
new reference and clean failed unattached new secrets; only old secrets labelled
for this service are deleted. Swarm mounts root-owned `0400` files at
`/run/secrets/sudo-password` and `/run/secrets/ssh-key`. Host/manager root is trusted.

The final Ansible command uses `--become-password-file` and `--private-key` at
those paths. Only public target host/port/user use Docker exec environment.
Never deliver passwords/private keys through environment, CLI arguments, build
arguments, image source, persistent home, env files or new secret folders.
`flock /run/lock/bootstrap-control-plane.lock` serializes rotation operations and
holds the lock for the whole Ansible exec. Different-target or credential-changing
runs to a shared controller must be serialized across the whole deployment.

OpenSSH `StrictHostKeyChecking=accept-new` records first-contact host keys and
rejects changed keys. Do not disable checking to hide mismatches or claim
independent first-contact attestation. The home volume preserves known_hosts
and ARA. ARA ignores `/run/secrets` and `.ansible/tmp` file contents. Its offline
server is started explicitly with `runserver 127.0.0.1:8000`; no Swarm port is
published. Cloud-init is root; readiness/rotation/exec use non-interactive sudo.

Never print secrets or put them in history. Arbitrary `openstrap connect --run`
does not inject blueprint secrets. Read-only diagnostics and SCP remain separate
operations with explicit targets/identities. `ansible/requirements.txt` remains
an input for existing CI/Vagrant environments.

## Validation and reporting

Use checks relevant to the change. Native Docker exec checks workstation syntax
and ansible-lint. ARA/Ansible output can be read for progress/errors; SQLite is
read-only. CI tests synthetic native Swarm secrets, real SSH and password sudo,
mount permissions and credential absence in ARA.

Report actual commands, exit status and findings. Distinguish source checks,
image build/publication and VM deployment; syntax/lint/image/SSH success does
not establish full workstation deployment. Mark unexecuted checks unverified.
