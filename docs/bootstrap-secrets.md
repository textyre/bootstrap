# Bootstrap Secrets Model

## OS credential store

openstrap's `keychain` plugin, installed from npm (`openstrap plugins install keychain`),
keeps secrets in the Windows Credential Manager, macOS Keychain or Linux Secret
Service. Save the target's SSH key and current sudo password once under the current OS user:

```powershell
Set-Location D:/projects/bootstrap
openstrap secret set ARCH_BASE_SSH_KEY
openstrap secret set BOOTSTRAP_TARGET_SUDO_PASSWORD
```

The command prompts with hidden input. `secret set NAME` replaces an entry;
`secret forget NAME` removes it. Normal `openstrap run` fetches the saved value
automatically. The blueprint names the SSH key with `identity: { secret: ARCH_BASE_SSH_KEY }`.
Linux requires an available Secret Service backend.

The same sudo entry is used for provider-owned second NIC preparation on the
clone of `arch-base/base` and for Ansible privilege escalation. The provider
passes it through SSH stdin to `sudo -S`. Bootstrap no longer uses Ansible Vault
or a separate Vault password. An old saved `BOOTSTRAP_VAULT_PASSWORD` entry is
unused and can be removed explicitly with `openstrap secret forget NAME`.

## Native Docker Swarm secrets

Cloud-init installs `docker.io` and `ca-certificates`, initializes a single-node
Swarm using the route's local IP, and starts the `bootstrap-control-plane`
service from the ready GHCR image. The service has one replica, host networking,
and `bootstrap-control-plane-home:/root`. Its initial configuration contains no
target credentials. OpenStrap checks that the service reports `1/1` replicas.

Two blueprint steps send credentials through SSH command stdin into native
`docker secret create NAME -`: the OS-store sudo password and the configured
SSH private key. Neither value is forwarded through environment variables or
command arguments. Docker mounts them in the service task at
`/run/secrets/sudo-password` and `/run/secrets/ssh-key`, owned by root with mode
`0400`. These Linux secret mounts use memory-backed storage; Swarm stores its
manager state encrypted at rest. Manager/host root remains a trusted principal.

Swarm secrets are immutable. Each run creates a uniquely named, labelled secret,
synchronously replaces its service reference, verifies the mounted reference,
and deletes the previous secret only when it belongs to this Bootstrap service.
A failed update removes an unattached new secret; rollback retains the previous
reference. Rotation replaces the service task while the named home volume is
preserved. It does not pull or replace the selected image.

Native `flock` serializes each secret update and holds the same lock throughout
the Ansible execution. Runs to a shared controller using different targets or
changing credentials must be serialized across the whole deployment, because
the password and key arrive in separate steps.

The final step runs one workstation playbook with
`--become-password-file /run/secrets/sudo-password` and
`--private-key /run/secrets/ssh-key`. Only the public target host, port and user
are supplied through `docker exec --env NAME`. No persistent plaintext secret
files are written to the project, controller home or image. Ansible Vault,
custom password adapters, local secret folders and runtime env files are absent.
Buildx remains the image builder in CI; its build secrets are unrelated to
these runtime Swarm mounts.

## SSH, ARA and updates

OpenSSH `StrictHostKeyChecking=accept-new` records a first-contact host key and
rejects a changed key. The named home volume preserves `/root/.ssh/known_hosts`
and ARA offline data in `/root/ara` across task replacement. ARA ignores loaded
files under `/run/secrets` and `.ansible/tmp`; it must never record credential
contents. The CI smoke test checks this with synthetic SSH/sudo credentials.

ARA is offline until its server is started explicitly. With host networking,
use `ara-manage runserver 127.0.0.1:8000` inside the current service task; no
Swarm port is published. See [Ansible commands](../ansible/README.md).

The image packages public `/opt/bootstrap/ansible` source. Local edits require
a new image publication and explicit image/controller replacement. Existing
VMs do not adopt changed cloud-init or convert an old standalone container into
a Swarm service on repeated `openstrap run`. VM recreation is a separate action.

Never print passwords or private keys, or put them in CLI arguments/history.
Arbitrary `openstrap connect --run` does not inject blueprint secrets.

[VM workflow](../wiki/standards/test-vm-workflow.md) · [Ansible commands](../ansible/README.md).
