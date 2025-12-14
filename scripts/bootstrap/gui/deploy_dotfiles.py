#!/usr/bin/env python3

from typing import Optional, Tuple

import subprocess
import argparse
from bootstrap.logging import Logger
from bootstrap.gui.path_utils import PathResolver
from bootstrap.gui.user_utils import UserContext
from bootstrap.gui.display.display_manager import DisplayDotfilesManager

# Explicit source paths for user-level chezmoi apply. Adjust as needed.
USER_SOURCE_PATHS = [
    "dot_xinitrc",
    "dot_config",
]

# Explicit source paths for system-level chezmoi apply.
SYSTEM_SOURCE_PATHS = [
    "etc/lightdm",
    "etc/X11",
]

logger = Logger(__name__)


class DotfilesInstaller:
    def __init__(self):
        self.path_resolver = PathResolver()
        self.user_context = UserContext()

    def install(self, target_user: Optional[str] = None) -> int:
        user, dotfiles_path, code = self._validate_target(target_user)
        if code != 0:
            return code

        logger.info("installing dotfiles for %s using chezmoi (repo: %s)", user, dotfiles_path)

        user_deploy_code = self._deploy_user_dotfiles(user, dotfiles_path)
        if user_deploy_code != 0:
            return user_deploy_code

        # system_deploy_code = self._deploy_system_files(dotfiles_path)
        # if system_deploy_code != 0:
        #     return system_deploy_code

        manager = DisplayDotfilesManager()
        ok = manager.validate(dotfiles_path, user)
        return 0 if ok else 1

    def _deploy_user_dotfiles(self, user: str, dotfiles_path) -> int:
        try:
            logger.info("deploying user dotfiles for %s", user)
            cmd = ["sudo", "-u", user, "chezmoi", "apply", "--source", str(dotfiles_path)]
            # Use relative source-paths and run chezmoi with cwd set to the repo so
            # sudo doesn't affect how chezmoi resolves entries in the source tree.
            for sp in USER_SOURCE_PATHS:
                cmd += ["--source-path", sp]
            subprocess.run(cmd, check=True, cwd=str(dotfiles_path))
            return 0
        except subprocess.CalledProcessError as e:
            logger.exception("user dotfiles deploy failed")
            return e.returncode or 1

    def _deploy_system_files(self, dotfiles_path) -> int:
        try:
            logger.info("deploying system files")
            cmd = ["sudo", "chezmoi", "apply", "--source", str(dotfiles_path), "--destination", "/"]
            # Use relative source-paths and set cwd to the dotfiles repo so chezmoi
            # resolves entries against the repository regardless of sudo behavior.
            for sp in SYSTEM_SOURCE_PATHS:
                cmd += ["--source-path", sp]
            subprocess.run(cmd, check=True, cwd=str(dotfiles_path))
            return 0
        except subprocess.CalledProcessError as e:
            logger.exception("system files deploy failed")
            return e.returncode or 1

    

    def _resolve_user_and_home(self, target_user: Optional[str]) -> Tuple[str, Optional[str]]:
        user = target_user or self.user_context.get_current_user()
        home = self.user_context.get_home_directory(user)

        if not home:
            logger.error("cannot determine home dir for user '%s'", user)
            return user, None

        logger.info("target user: %s (home: %s)", user, home)
        return user, home

    def _ensure_dotfiles_repo(self) -> Optional[object]:
        dotfiles_path = self.path_resolver.get_dotfiles_path()
        if not dotfiles_path.is_dir():
            logger.error("dotfiles repository not found at %s", dotfiles_path)
            return None

        return dotfiles_path

    def _validate_target(self, target_user: Optional[str]) -> Tuple[str, Optional[object], int]:
        user, home = self._resolve_user_and_home(target_user)
        if not home:
            return user, None, 2

        dotfiles_path = self._ensure_dotfiles_repo()
        if dotfiles_path is None:
            return user, None, 3

        return user, dotfiles_path, 0


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(description="Install dotfiles for a target user using chezmoi")
    parser.add_argument("target_user", nargs="?", help="target user to install dotfiles for")
    parsed = parser.parse_args(argv)
    installer = DotfilesInstaller()
    return installer.install(parsed.target_user)


if __name__ == "__main__":
    raise SystemExit(main())
