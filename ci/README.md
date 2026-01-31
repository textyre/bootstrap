ShellCheck helper

This folder contains a small helper to run ShellCheck on repository scripts.

Usage:

```bash
sudo pacman -S shellcheck  # on Arch
./scripts/ci/run-shellcheck.sh
```

Integrate this script into CI by executing it as a build step. It exits
non-zero when `shellcheck` is not installed; the script itself prints issues
to stdout/stderr but currently does not fail on lints (adjust as needed).
