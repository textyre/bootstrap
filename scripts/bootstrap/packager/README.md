Packager
========

This directory contains distro-specific wrappers that expose two functions:

- `pm_update [root]`  — update package database, optionally targeting `root`
- `pm_install [root] pkg...` — install packages, optionally targeting `root`

Supported distros (official): `arch`, `ubuntu`, `fedora`, `gentoo`.

Usage
-----

In scripts that need to perform package operations, source the top-level
`packager.sh` (it will auto-select the correct distro script):

```
. scripts/bootstrap/packager/packager.sh  # will define pm_update/pm_install
pm_update "/path/to/root"              # updates packages DB in root
pm_install "/path/to/root" pkg1 pkg2   # installs into root
```

If you prefer to execute `packager.sh` directly, it also supports a small
CLI: `packager.sh update [root]` and `packager.sh install [root] [packages...]`.

Notes
-----
- For Arch we use `pacman --root` with `--dbpath`/`--cachedir` so the target
  root maintains its own package DB.
- For Ubuntu/Debian we run `apt` inside a `chroot` when a `root` is provided —
  this requires a prepared chroot (debootstrap) or a reachable `/bin/sh` in
  the target root.
- For Fedora we use `dnf --installroot`.
- For Gentoo we attempt `emerge --root` where available; full Portage
  configuration in the target is typically required.
