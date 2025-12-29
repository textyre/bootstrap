"""Package definitions and simple loader.

The file provides a small, extensible structure for package groups.
"""
from typing import Iterable, List

PACKAGES = {
    "common": [
        "git",
        "curl",
        "wget",
    ],
    "arch": [
        "base-devel",
    ],
    "ubuntu": [
        "build-essential",
    ],
    "fedora": [
        "gcc",
    ],
    "gentoo": [
        "app-portage/gentoolkit",
    ],
}


def load(groups: Iterable[str]) -> List[str]:
    result: List[str] = []
    for g in groups:
        result.extend(PACKAGES.get(g, []))
    # dedupe while preserving order
    seen = set()
    out = []
    for p in result:
        if p in seen:
            continue
        seen.add(p)
        out.append(p)
    return out
