# Bootstrap Secrets Model

## Goal

The bootstrap flow now uses a project-local secure directory and project-level
environment variables so that install credentials, vault passwords, and other
sensitive bootstrap parameters do not live in the tracked repository tree.

## Secure Directory

Chosen path:

- `D:/projects/bootstrap/.local/bootstrap/`

Why this path:

- project-local and explicit
- easy to keep outside git
- close to the repo without mixing secrets into tracked directories
- works for both local secret files and rendered local bootstrap configs

The directory is intentionally git-ignored.

## What Is Tracked vs Local-Only

### Tracked templates/examples

- [bootstrap.env.example](D:/projects/bootstrap/scripts/bootstrap.env.example)
- [archinstall-config.template.json](D:/projects/bootstrap/scripts/archinstall-config.template.json)
- [archinstall-creds.template.json](D:/projects/bootstrap/scripts/archinstall-creds.template.json)

### Local-only files

Expected local files under `.local/bootstrap/`:

- `.local/bootstrap/bootstrap.env`
- `.local/bootstrap/vault-pass.gpg`
- `.local/bootstrap/sudo-password.gpg` if sudo password differs from vault password
- `.local/bootstrap/archinstall/authorized_key.pub`
- `.local/bootstrap/archinstall/root-password`
- `.local/bootstrap/archinstall/user-password`
- `.local/bootstrap/archinstall/archinstall-config.json`
- `.local/bootstrap/archinstall/archinstall-creds.json`

The runtime secret baseline is now the GPG-encrypted vault secret. Plaintext
`vault-pass` / `sudo-password` files are only compatibility fallbacks and are
not part of the intended secure model.

## Environment Variables

### Directory and path variables

- `BOOTSTRAP_SECURE_DIR`
  - optional override for the secure directory
- `BOOTSTRAP_ENV_FILE`
  - optional override for the env file to source
- `BOOTSTRAP_ARCHINSTALL_CONFIG_FILE`
  - output path for rendered archinstall config JSON
- `BOOTSTRAP_ARCHINSTALL_CREDS_FILE`
  - output path for rendered archinstall credentials JSON

### Install flow variables

- `BOOTSTRAP_INSTALL_DISK`
  - required target disk, no tracked default
- `BOOTSTRAP_INSTALL_HOSTNAME`
  - required hostname
- `BOOTSTRAP_INSTALL_USERNAME`
  - required primary user
- `BOOTSTRAP_INSTALL_TIMEZONE`
  - optional install timezone
- `BOOTSTRAP_INSTALL_LOCALE`
  - optional install locale
- `BOOTSTRAP_INSTALL_KEYBOARD_LAYOUT`
  - optional keyboard layout
- `BOOTSTRAP_SSH_PUBLIC_KEY_FILE`
  - required path to the public key file to install
- `BOOTSTRAP_ROOT_PASSWORD_FILE`
  - required root password file unless direct env is used
- `BOOTSTRAP_USER_PASSWORD_FILE`
  - required user password file unless direct env is used
- `BOOTSTRAP_INSTALL_ROOT_PASSWORD`
  - optional direct env secret instead of `BOOTSTRAP_ROOT_PASSWORD_FILE`
- `BOOTSTRAP_INSTALL_USER_PASSWORD`
  - optional direct env secret instead of `BOOTSTRAP_USER_PASSWORD_FILE`

### Vault and sudo variables

- `BOOTSTRAP_VAULT_PASSWORD_GPG_FILE`
  - canonical GPG-encrypted local vault/sudo runtime secret
- `BOOTSTRAP_VAULT_GPG_RECIPIENT`
  - optional override for the GPG recipient used by `setup-vault-pass.sh`
- `BOOTSTRAP_VAULT_PASSWORD_FILE`
  - plaintext compatibility fallback only
- `BOOTSTRAP_VAULT_PASSWORD`
  - direct env alternative to the file above
- `BOOTSTRAP_SUDO_PASSWORD_GPG_FILE`
  - optional dedicated GPG-encrypted sudo secret
- `BOOTSTRAP_SUDO_PASSWORD_FILE`
  - optional plaintext compatibility fallback for sudo
- `BOOTSTRAP_SUDO_PASSWORD`
  - direct env alternative to the file above

If dedicated sudo values are not set, sudo helpers fall back to
`BOOTSTRAP_VAULT_PASSWORD` / `BOOTSTRAP_VAULT_PASSWORD_GPG_FILE`.

## Safe Bootstrap Flow

### 1. Prepare the secure directory

```bash
mkdir -p .local/bootstrap/archinstall
cp scripts/bootstrap.env.example .local/bootstrap/bootstrap.env
```

### 2. Add local secret files

Populate the files referenced from `.local/bootstrap/bootstrap.env`, for example:

- `.local/bootstrap/archinstall/root-password`
- `.local/bootstrap/archinstall/user-password`
- `.local/bootstrap/archinstall/authorized_key.pub`

### 3. Create the local encrypted vault secret

```bash
scripts/setup-vault-pass.sh
```

This creates `.local/bootstrap/vault-pass.gpg` using the local GPG keyring.

This is optional host credential provisioning. A VM run with an existing
Vault credential in its runtime source does not invoke this helper.

### 4. Render local archinstall JSON

```bash
scripts/render-archinstall-secrets.sh
```

This uses tracked templates plus local secrets to produce:

- `.local/bootstrap/archinstall/archinstall-config.json`
- `.local/bootstrap/archinstall/archinstall-creds.json`

### 5. Run the VM workflow through OpenStrap

From PowerShell on Windows:

```powershell
Set-Location D:/projects/bootstrap
openstrap run --local --host-port 2251
```

The blueprint creates disposable Arch `bootstrap-target` as a full clone of
`arch-base/base` and Ubuntu 24.04 `ansible-control`. System Ansible runs inside
the Docker container and reads target access from a static environment-based inventory. Both VMs
start headless. Source VM snapshots remain immutable.

Cloud-init installs only `docker.io` and `ca-certificates` on the Docker host.
OpenStrap pulls the ready `ghcr.io/textyre/bootstrap/control-plane:latest` image,
starts a persistent container and runs one workstation playbook through Docker
exec. The image already contains `/opt/bootstrap/ansible`, including the
existing encrypted `vault.yml`. Local `.local/`, private keys, Vault password
files and host runtime config are excluded from the image. Git, Task, Compose
and image builds are not needed on the VM.

### 6. Resolve the runtime credential locally

The read-only secret store in `openstrap.config.mjs` resolves only
`BOOTSTRAP_VAULT_PASSWORD`. The current resolver checks:

1. nonempty host `BOOTSTRAP_VAULT_PASSWORD`
2. explicitly selected host `BOOTSTRAP_VAULT_PASSWORD_FILE`
3. `BOOTSTRAP_VAULT_PASSWORD_GPG_FILE` or optional local
   `.local/bootstrap/vault-pass.gpg`, decrypted noninteractively
4. existing host `ansible/.vault-pass` as a compatibility fallback when the
   optional GPG source is unavailable

An explicitly selected GPG source that cannot be decrypted produces an error.
No password value is printed, passed in CLI arguments, or saved on the VM.
A local existing protected credential can be selected by path:

```powershell
$env:BOOTSTRAP_VAULT_PASSWORD_FILE = 'C:/path/to/existing/protected-vault-password'
openstrap run --local --host-port 2251
```

Blueprint secret references forward the resolved value only to the workstation
Docker exec process environment through allowed environment names. Image build,
pull and container start receive no runtime secrets. `ansible/vault-pass.sh` is a minimal
environment-only adapter for the native Ansible password-file interface.

The static inventory reads `BOOTSTRAP_TARGET_PRIVATE_KEY` from the Ansible process
environment. Ansible's native SSH agent loads this OpenSSH key in memory; no
controller role writes a private-key file. OpenSSH records newly accepted host
keys in `/root/.ssh/known_hosts` and rejects changed keys. Named volume
`bootstrap-control-plane-home:/root` preserves known hosts and ARA offline DB
in `/root/ara` when the container is recreated.
Ordinary `openstrap connect --run` does not inject blueprint secret environment
automatically. Manual Docker exec and optional development Tasks that require
Vault need the established runtime secret context.

## Path and Resolution Rules

The bare-metal installers and render helper retain their existing local
`bootstrap-env.sh` boundary and install-only files. They resolve exported
`BOOTSTRAP_*` variables and the ignored local bootstrap environment as defined
by that helper. The installation parameters and rendered archinstall JSON above
are separate from VM deployment.

The VM flow uses the read-only OpenStrap resolver described above; it does not
source the install environment or use host SSH/sudo wrappers. It cannot fall
back to tracked install credentials or tracked Vault password files.

## Sudo Artifact Policy

- Tracked install templates do not create the old persistent bootstrap
  passwordless sudo artifact.
- Ansible on the controller uses `become` with the encrypted Vault variables.
- Runtime Vault password is supplied only in the process environment and read
  by `ansible/vault-pass.sh`.
- No persistent Vault/sudo password file is required on the target or controller.
- Edit the encrypted source Vault with native `ansible-vault` before publishing
  a new image. Container-local edits are disposable and do not update source.
- Do not print decrypted Vault contents during diagnostics. `vault-view`
  exposes secrets and is not normal evidence collection.

## Closed Security Findings

These findings describe the earlier install/local-helper cleanup. The current
VM runtime boundary is specified above; old helper names are historical here.

- tracked install credentials removed from the tracked tree
- predictable placeholder password defaults removed from tracked bootstrap files
- tracked bootstrap path no longer depends on a vault password file inside the
  Ansible tree
- canonical bootstrap runtime secret moved from plaintext local files to a
  GPG-encrypted project-local secret in `.local/bootstrap/`
- VM-side password artifact is no longer needed by `ssh-sudo.sh`


## Initial private VM network

The new blueprint names `sudoPassword: { secret: BOOTSTRAP_TARGET_SUDO_PASSWORD }` for the Arch clone's provider-owned second NIC preparation. The runtime first reads an explicitly supplied `BOOTSTRAP_TARGET_SUDO_PASSWORD`, then an explicitly selected `BOOTSTRAP_TARGET_SUDO_PASSWORD_FILE`, otherwise authenticates and reads `ansible_become_password` from the existing encrypted Ansible Vault in local memory. The existing Vault password resolution order is unchanged. The separate installer `archinstall/user-password` is not selected implicitly: its password does not match the current base snapshot.

The provider sends sudo credentials through SSH environment/stdin to `sudo -S`; no password is written into cloud-init, arguments or guest files. Secret-bearing errors are redacted. No credential files are changed by this process.
