# aur_transport_proxy

Temporary transport adapter for AUR builds on Arch Linux.

This role is intentionally separate from `yay` and `packages`. It owns proxy
and mirror settings for upstream release downloads that are not part of the
normal `yay` contract.

Current responsibilities:

- override `makepkg` HTTPS downloads for GitHub Releases via a wrapper script
- expose an Electron download mirror through `/etc/npmrc` for npm-based AUR
  builds such as `nody-greeter`

Enable it with a single explicit role include before the `yay` install phase.
Disable it by removing that single include.
