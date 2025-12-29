from __future__ import annotations
from abc import ABC, abstractmethod
import subprocess
from typing import List


class Packager(ABC):
    """Abstract packager. Concrete implementations implement `install`."""

    def __init__(self, sudo: bool = True) -> None:
        self.sudo = sudo

    @abstractmethod
    def install(self, packages: List[str], update: bool = True, dry_run: bool = False) -> None:
        raise NotImplementedError


def _run(cmd: List[str], dry_run: bool) -> None:
    if dry_run:
        print("[dry-run]", " ".join(cmd))
        return
    subprocess.run(cmd, check=True)


class ArchPackager(Packager):
    def install(self, packages: List[str], update: bool = True, dry_run: bool = False) -> None:
        if update:
            _run(["sudo", "pacman", "-Sy"], dry_run)
        if packages:
            _run(["sudo", "pacman", "-S", "--noconfirm"] + packages, dry_run)


class UbuntuPackager(Packager):
    def install(self, packages: List[str], update: bool = True, dry_run: bool = False) -> None:
        if update:
            _run(["sudo", "apt-get", "update"], dry_run)
        if packages:
            _run(["sudo", "apt-get", "install", "-y"] + packages, dry_run)


class FedoraPackager(Packager):
    def install(self, packages: List[str], update: bool = True, dry_run: bool = False) -> None:
        if update:
            _run(["sudo", "dnf", "makecache"], dry_run)
        if packages:
            _run(["sudo", "dnf", "install", "-y"] + packages, dry_run)


class GentooPackager(Packager):
    def install(self, packages: List[str], update: bool = True, dry_run: bool = False) -> None:
        # Gentoo handles updates via world update; keep it simple here
        if packages:
            _run(["sudo", "emerge"] + packages, dry_run)
