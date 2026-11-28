# ewwii

ewwii, the status bar's widget system (Ewwii/NBCL), built from the head of its `main` branch on Arch.

The AUR's `ewwii-git` builds `main`, but its `pkgver()` runs `git describe --tags`, and `main` no
longer shares history with any tag, so the package does not build as published. The role builds that
AUR package (pinned to `ewwii_aur_ref`) with `pkgver()` replaced by `ewwii_pkgver`: the crate's
version, the commit count and the commit, e.g. `0.10.0.r1387.g84eb7a1`.

- `main`'s current commit is read with `git ls-remote`; when the installed `ewwii-git` is of that
  commit, nothing is built.
- Rust and the GTK libraries come from pacman; `makepkg` runs as the AUR build user (`aur_builder`).
- `ewwii-bin` and `ewwii`, which conflict with it, are removed; so is the debug package makepkg splits off.

| Variable | Default |
|---|---|
| `ewwii_branch` | `main` |
| `ewwii_aur_ref` | the AUR commit of the PKGBUILD used |
| `ewwii_build_user` | `yay_builder_user` (`aur_builder`) |
