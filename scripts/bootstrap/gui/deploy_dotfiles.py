#!/usr/bin/env python3

from typing import Optional

import subprocess
import argparse
from bootstrap.logging import Logger
from bootstrap.gui.path_utils import PathResolver
from bootstrap.gui.user_utils import UserContext

logger = Logger(__name__)


class DotfilesInstaller:
    def __init__(self):
        self.path_resolver = PathResolver()
        self.user_context = UserContext()

    def install(self, target_user: Optional[str] = None) -> int:
        user = target_user or self.user_context.get_current_user()
        home = self.user_context.get_home_directory(user)

        if not home:
            logger.error("cannot determine home dir for user '%s'", user)
            return 2

        logger.info("target user: %s (home: %s)", user, home)

        dotfiles_path = self.path_resolver.get_dotfiles_path()
        if not dotfiles_path.is_dir():
            logger.error("dotfiles repository not found at %s", dotfiles_path)
            return 3

        logger.info("installing dotfiles for %s using chezmoi (repo: %s)", user, dotfiles_path)

        try:
            subprocess.run(
                ["sudo", "-u", user, "chezmoi", "init", "--source", str(dotfiles_path), "--apply"],
                check=True
            )
            return 0
        except subprocess.CalledProcessError as e:
            logger.exception("chezmoi failed")
            return e.returncode or 1


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description="Install dotfiles for a target user using chezmoi")
    parser.add_argument("target_user", nargs="?", help="target user to install dotfiles for")
    parsed = parser.parse_args(argv)
    installer = DotfilesInstaller()
    return installer.install(parsed.target_user)


if __name__ == "__main__":
    raise SystemExit(main())
