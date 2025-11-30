#!/usr/bin/env python3

from typing import Optional

import shutil
import argparse
from bootstrap.gui.logging import Logger

logger = Logger(__name__)

DEFAULT_BINS = ["Xorg", "i3", "alacritty", "lightdm"]

PACKAGE_MAP = {
    "Xorg": "xorg",
    "i3": "i3",
    "alacritty": "alacritty",
    "lightdm": "lightdm",
}


class BinaryChecker:
    def __init__(self, bins: Optional[list] = None):
        self.bins_to_check = bins or DEFAULT_BINS

    def check_exists(self, binary: str) -> bool:
        return shutil.which(binary) is not None

    def check_all(self) -> bool:
        missing = [b for b in self.bins_to_check if not self.check_exists(b)]

        if missing:
            logger.error("missing required binaries: %s", " ".join(missing))
            pkgs = [PACKAGE_MAP.get(b, b) for b in missing]
            pkgs_unique = list(dict.fromkeys(pkgs))
            pkgs_str = " ".join(sorted(set(pkgs_unique)))
            logger.error("Suggested install (Arch): sudo pacman -S --needed %s", pkgs_str)
            logger.error("Or ensure these packages are present; see scripts/bootstrap/packager/packages.sh for package lists.")
            return False

        logger.info("required binaries present")
        return True


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description="Check for required binaries and print suggested package names if missing")
    parser.add_argument("bins", nargs="*", help="binaries to check")
    parsed = parser.parse_args(argv)

    checker = BinaryChecker(parsed.bins if parsed.bins else None)
    ok = checker.check_all()
    return 0 if ok else 3


if __name__ == "__main__":
    raise SystemExit(main())
