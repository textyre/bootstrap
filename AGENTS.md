# Project Instructions

## Execution model

Windows edits project files and runs the installed OpenStrap CLI. `ansible-control` is a Linux Docker host. OpenStrap pulls the ready `ghcr.io/textyre/bootstrap/control-plane:latest` image, starts a persistent container and uses native Docker exec to run one workstation playbook. The container contains ordinary APT-installed Ansible, lint, Vault and ARA. Workstation targets `bootstrap-target` over SSH. The container may run on a cloud VM, VPS or another Linux Docker host.

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

`bootstrap-target` is a disposable full clone of `arch-base/base`; `ansible-control` uses Ubuntu 24.04 and the container image uses Ubuntu 26.04. Both VMs run headless. Shared network `bootstrap` connects target `172.28.51.10:22` to controller `172.28.51.11`; Windows SSH ports are `2251` and `2252`. Cloud-init installs only `docker.io` and `ca-certificates`. Existing VMs do not automatically adopt changed blueprint networking.

The default chain is Docker readiness (`sudo -n docker info`), image pull, persistent container start, then one native Docker exec of `/opt/bootstrap/ansible/playbooks/workstation.yml`. GitHub Actions installs Python, system Ansible, ARA and Galaxy collections and packages public Ansible source and encrypted Vault at image build time. One workstation playbook contains the necessary raw Python bootstrap/fact gathering and the original 31 roles. Deployment does not need Git, Task, Compose, image builds, dependency installations, version gates or preliminary Vault decryption on the VM.

## Routing and role standards

Use applicable specialized skills for Ansible design, execution, debugging and review, and for dotfile deployment. Delegate useful independent work with an explicit target, project directory and command scope. An unspecified VM never means protected `arch` or a legacy SSH alias.

Roles follow [Role Requirements](wiki/standards/role-requirements.md), [Security Standards](wiki/standards/security-standards.md) and [Profiles](wiki/standards/workstation-profiles.md).

- Supported project distros: Arch, Ubuntu, Fedora, Void, Gentoo.
- Supported init families: systemd, runit, openrc, s6, dinit.
- Baseline: CIS Level 1 Workstation.
- Use native Ansible modules and meaningful verification; preserve the full workstation scope.
- A successful run does not establish compatibility with untested distro/init combinations.

## Test machines and delivery

Follow [Test VM Workflow](wiki/standards/test-vm-workflow.md).

- Protected `arch-base`, `arch` and `arch-test-clone` are never changed, deployed to, rebooted, restored, rebuilt or deleted by this workflow. Snapshots `base` and `after-packages` remain immutable.
- VM lifecycle uses OpenStrap CLI/provider. Do not introduce host lifecycle wrappers, polling scripts or replacement VBox orchestration.
- Project delivery uses a published GHCR image with bundled `/opt/bootstrap/ansible` source. Local Windows edits enter deployment only after a new image publication. Use `sha-<commit>` to select a published revision.
- Do not commit or push without explicit user authorization.
- Run project Ansible and lint inside the Control Plane container through native Docker exec. Taskfile and Compose are optional conveniences where those files and tools are available, not VM deployment prerequisites. They use image-bundled source; local checkout edits do not affect checks or deployment until a new image is selected.
- `inventory/openstrap.yml` is committed SSH inventory using runtime env lookups. Do not apply workstation to the controller or silently substitute localhost.
- Keep target changes in Ansible source. Do not manually repair packages, services or files merely to make a later run appear successful.
- Repeating workstation or creating a fresh disposable clone is a user/task choice.
- Molecule uses existing `.github/workflows/molecule.yml` and `molecule-vagrant.yml`. Control Plane test Tasks fail explicitly with these references; they do not install tools or trigger CI.

## Runtime secrets

`openstrap.config.mjs` resolves the existing Vault credential through a local read-only secret store. Target host, port, user, private key and Vault password are delivered only to the workstation step environment. Provider shared-NIC preparation resolves the base snapshot sudo credential locally and passes it through SSH stdin. Installer user-password and base snapshot sudo credential are different inputs.

Native `ansible_private_key` and image-owned `ANSIBLE_SSH_AGENT=auto` load the OpenSSH identity into an agent for the run. Do not write private keys or Vault passwords to project files, persistent container settings, Compose service environment, build arguments or environment files. Forward permitted environment names only with `docker exec --env NAME` to the required process. Image pull and container start receive no runtime secrets. The public `ansible/vault-pass.sh` adapter reads only `BOOTSTRAP_VAULT_PASSWORD`; actual Ansible execution decrypts Vault.

OpenSSH `StrictHostKeyChecking=accept-new` stores first-contact host keys and refuses changed keys. Named volume `bootstrap-control-plane-home` preserves `/root`, including `.ssh/known_hosts` and `ara/`. ARA is offline by default; its server port is bound to Docker host localhost only. Do not disable checking to hide a mismatch or claim independently verified first-contact trust.

Docker operations use non-interactive sudo; secret-bearing exec preserves only allowed environment names. Optional development Tasks use `CONTROL_PLANE_RUNTIME=docker` for root or direct Docker access. `ansible/requirements.txt` remains input for existing CI/Vagrant environments; Control Plane dependencies are installed in the root Dockerfile by GitHub Actions.

Never print secrets or put them in CLI arguments/history. Arbitrary `openstrap connect --run` does not automatically receive blueprint secrets. Explicit read-only diagnostics and standard SCP remain independent operations with an explicit target and identity.

## Validation and reporting

Use checks relevant to the actual change. Optional development Task `check` checks workstation syntax; `lint:openstrap` checks workstation and `user`/`chezmoi`, while `lint` covers the wider project. ARA or Ansible output may be read for progress and errors; inspect SQLite read-only.

Report actual commands, exit status and useful findings. Distinguish source checks, image build/publication and VM deployment. Do not claim that syntax, lint, image publication or SSH success proves complete deployment, and mark unexecuted checks unverified.

## Separate bare-metal installation

Preserved bare-metal installers, render helpers, templates and `bootstrap-env.sh` are outside this VM chain. Use them only for an explicitly selected live-ISO installation target.
