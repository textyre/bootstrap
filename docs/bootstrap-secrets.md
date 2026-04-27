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

### 4. Render local archinstall JSON

```bash
scripts/render-archinstall-secrets.sh
```

This uses tracked templates plus local secrets to produce:

- `.local/bootstrap/archinstall/archinstall-config.json`
- `.local/bootstrap/archinstall/archinstall-creds.json`

### 5. Run bootstrap safely

```bash
./bootstrap.sh
```

### 6. Run bootstrap on a disposable VM without syncing plaintext secrets

```bash
bash scripts/ssh-scp-to.sh --project
bash scripts/ssh-run.sh --bootstrap-secrets "cd /home/textyre/bootstrap && ./bootstrap.sh --syntax-check"
```

The local vault/sudo secret is decrypted on the host and forwarded over SSH
stdin into the remote shell environment. The VM does not need `.local/bootstrap/`
or `ansible/.vault-pass` to reach the start of Ansible.

## Path and Resolution Rules

Bootstrap scripts resolve values in this order:

1. exported `BOOTSTRAP_*` environment variables
2. `.local/bootstrap/bootstrap.env`
3. GPG-encrypted runtime secret files referenced by those env variables
4. plaintext compatibility files referenced by those env variables

They do not fall back to tracked install credentials or tracked vault password
files.

## Sudo Artifact Policy

Previous insecure behavior:

- tracked install config created a persistent passwordless sudo rule for the
  bootstrap user
- `ssh-sudo.sh` depended on a password file stored on the VM

Current policy:

- tracked install templates no longer create the old persistent bootstrap sudo
  artifact
- `ssh-sudo.sh` resolves the password locally and pipes it directly into remote
  `sudo -S`
- `ssh-run.sh --bootstrap-secrets` resolves the vault/sudo secret locally and
  forwards it ephemerally into the remote bootstrap shell
- no persistent sudo password artifact is required on the VM by this helper

## Closed Security Findings

- tracked install credentials removed from the tracked tree
- predictable placeholder password defaults removed from tracked bootstrap files
- tracked bootstrap path no longer depends on a vault password file inside the
  Ansible tree
- canonical bootstrap runtime secret moved from plaintext local files to a
  GPG-encrypted project-local secret in `.local/bootstrap/`
- VM-side password artifact is no longer needed by `ssh-sudo.sh`
