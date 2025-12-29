"""Command line entrypoint for the packager Python module."""
from __future__ import annotations
import argparse
from .factory import get_packager
from .packages import load
from typing import List


def main(argv: List[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="packager-python")
    p.add_argument("--distro", "-d", required=True, help="Target distribution (arch, ubuntu, fedora, gentoo)")
    p.add_argument("--groups", "-g", nargs="*", default=["common"], help="Package groups to install")
    p.add_argument("--dry-run", action="store_true", help="Don't execute commands, only print them")
    p.add_argument("--no-sudo", dest="sudo", action="store_false", help="Run commands without sudo")
    p.add_argument("--no-update", dest="update", action="store_false", help="Skip update step")
    args = p.parse_args(argv)

    pkgr = get_packager(args.distro, sudo=args.sudo)
    packages = load(args.groups)
    if not packages:
        print("No packages to install for groups:", args.groups)
        return 0

    print(f"Distro: {args.distro}")
    print(f"Packages: {packages}")
    print(f"Dry run: {args.dry_run}")

    pkgr.install(packages, update=args.update, dry_run=args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
