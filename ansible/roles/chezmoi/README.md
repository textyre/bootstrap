# chezmoi

Applies the standalone dotfiles repository to the project-wide `target_user`
with chezmoi.

The `packages` role installs chezmoi before this role runs. This role does not
install, download, or select a chezmoi version.

## Execution flow

1. **Detect** (`tasks/detect/main.yml`) - resolves the existing `target_user` account.
2. **Configure** (`tasks/configure/main.yml`) - clones the dotfiles repository
   and creates the chezmoi config on first use, sets the selected theme, and
   applies the desired state.
3. **Report** (`tasks/main.yml`) - records the user, source, and theme.

There is no init-system logic, service management, handlers, or role-level
verification. Chezmoi calculates the target state and returns an error if
rendering or deployment fails.

## Variables

### Role variables

| Variable | Default | Description |
|----------|---------|-------------|
| `chezmoi_repo_url` | `https://github.com/textyre/dotfiles.git` | Git repository with the chezmoi source. |
| `chezmoi_repo_ref` | `""` | Optional branch or tag passed to `chezmoi init`; empty uses the remote default branch. |
| `chezmoi_theme_name` | `dracula` | Theme written to chezmoi data. Allowed by the current source template: `dracula`, `monochrome`. |

### Project variables

| Variable | Purpose |
|----------|---------|
| `target_user` | Existing workstation user that receives the dotfiles. |

The role has no user, source-path, install-method, version, or enable/disable
aliases.

## Example

```yaml
# inventory/host_vars/workstation/chezmoi.yml
chezmoi_theme_name: monochrome
```

## Managed state

The dotfiles repository owns the resulting user files, including wallpapers
under `~/.local/share/wallpapers/`. Chezmoi applies executable helpers,
desktop configuration, and shell configuration.

The layout-constants script uses chezmoi's `run_onchange_after` attribute. It
runs on first apply and when its rendered layout/theme input changes, rather
than rewriting the generated file on every role run.

On the first run, `chezmoi init <repo-url>` clones the source into the user's
default chezmoi source directory and generates
`~/.config/chezmoi/chezmoi.toml`. Every run then sets the requested theme and
runs `chezmoi apply --verbose`. The apply task reports `changed` only when
chezmoi reports applied file changes.

## Platform boundary

The configuration process is independent of the distribution and init system.
The complete workstation pipeline currently provides the system-wide chezmoi
executable on Arch Linux and Ubuntu. Fedora, Void Linux, and Gentoo remain
blocked by their unimplemented `packages` backends; this role does not hide
that gap with a private installer.

## Testing

Docker and Vagrant scenarios run on Arch Linux and Ubuntu. Both run convergence
and idempotence.

- Both scenarios build a minimal local git repository as the chezmoi source,
  point `chezmoi_repo_url` at it with a `file://` URL, and verify that its
  neutral marker is deployed to the target user's home. The tests need no
  network access.
- Docker checks the contract in a container; Vagrant checks the same contract
  with a normal VM user and filesystem.

The tests verify the role's deployment contract. They do not validate the
meaning or runtime behavior of individual project dotfiles.

All Ansible, Molecule, lint, and package operations run on the remote VM or in
CI.

## Troubleshooting

| Symptom | Cause | Resolution |
|---------|-------|------------|
| Chezmoi binary is missing | The `packages` role did not provide chezmoi | Inspect the package stage before running this role. |
| Source cannot be cloned | `chezmoi_repo_url` is unreachable from the target | Check network access and the repository URL; do not add a second source variable to the role. |
| Target account is missing | `target_user` does not identify an existing user | Create the account in the `user` role before this role runs. |
| Template rendering fails | Source data and templates are inconsistent | Fix the source template or data reported by chezmoi, then rerun the role. |
| Theme does not change | Value is not one of the choices in `.chezmoi.toml.tmpl` | Use `dracula` or `monochrome`, or update the source template and role documentation together. |
