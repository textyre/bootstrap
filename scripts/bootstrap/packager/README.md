Packager
```text
Packager (Python)
------------------

This directory contains a Python-based packager implementing an OOP design and
common patterns (factory, strategy). It replaces the old shell-based
implementation.

Usage
-----

Run the installer module. Example:

```
python -m packager.install --distro arch --groups common arch
```

Options
-------

- `--distro` (`-d`): target distribution (arch, ubuntu, fedora, gentoo)
- `--groups` (`-g`): package groups defined in `packages.py` (default: `common`)
- `--dry-run`: show commands without executing them
- `--no-sudo`: run commands without `sudo`
- `--no-update`: skip update step

Files
-----

- `core.py`: abstract `Packager` and concrete implementations
- `factory.py`: factory returning proper packager by distro
- `packages.py`: package group definitions and loader
- `install.py`: CLI entrypoint

Extensibility
-------------

To add a new distro, implement `Packager` in `core.py` and register it in
`factory.py`. Add new package groups to `packages.py`.
```
