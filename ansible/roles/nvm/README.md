# nvm

nvm in the target user's home (`~/.nvm`, a pinned tag of nvm-sh/nvm), the newest stable Node
through it as the default, and global npm packages (pnpm) in that Node.

- `nvm_node_version: latest` reads nodejs.org's release index and takes the newest version that is
  not a pre-release; an exact version (`v26.13.1`) pins it.
- nvm is loaded from system files, not the user's dotfiles (chezmoi owns those):
  `/etc/profile.d/nvm.sh` for login shells, and the same file at the top of `/etc/bash.bashrc` and
  `/etc/zsh/zshrc` for interactive shells and commands run over SSH.
- `nvm_link_node: true` links `/usr/local/bin/node` to the default Node, for programs that run
  outside the user's shell with `/usr/bin/env node`: the ctOS greeter helper, run by LightDM.
- `nvm_remove_system_node: true` removes the distribution's Node, npm and pnpm, so only nvm's Node
  is on PATH.

| Variable | Default |
|---|---|
| `nvm_user` | `target_user` |
| `nvm_version` | `v0.41.0` |
| `nvm_node_version` | `latest` |
| `nvm_global_packages` | `[pnpm]` |
| `nvm_link_node` | `true` |
| `nvm_remove_system_node` | `false` |
