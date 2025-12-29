from typing import Optional
from .core import ArchPackager, UbuntuPackager, FedoraPackager, GentooPackager, Packager


class PackagerFactory:
    """Factory that returns packager implementations by distro name."""

    _mapping = {
        "arch": ArchPackager,
        "manjaro": ArchPackager,
        "ubuntu": UbuntuPackager,
        "debian": UbuntuPackager,
        "fedora": FedoraPackager,
        "gentoo": GentooPackager,
    }

    @classmethod
    def get(cls, name: str, sudo: bool = True) -> Packager:
        key = (name or "").strip().lower()
        ctor = cls._mapping.get(key)
        if not ctor:
            raise ValueError(f"Unsupported distro: {name}")
        return ctor(sudo=sudo)


def get_packager(name: str, sudo: bool = True) -> Packager:
    return PackagerFactory.get(name, sudo=sudo)
