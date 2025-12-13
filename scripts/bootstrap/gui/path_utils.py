#!/usr/bin/env python3

from pathlib import Path


class PathResolver:
    @staticmethod
    def get_script_dir() -> Path:
        return Path(__file__).parent.resolve()

    @staticmethod
    def get_bootstrap_dir() -> Path:
        return PathResolver.get_script_dir().parent

    @staticmethod
    def get_dotfiles_path() -> Path:
        bootstrap_dir = PathResolver.get_bootstrap_dir()
        return (bootstrap_dir / ".." / "dotfiles").resolve()

    @staticmethod
    def get_lightdm_conf_dir() -> Path:
        return Path("/etc/lightdm/lightdm.conf.d")

    @staticmethod
    def get_lightdm_hook_path() -> Path:
        return Path("/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh")

    @staticmethod
    def get_user_xinitrc(user: str) -> Path:
        from bootstrap.gui.user_utils import UserContext
        home = UserContext().get_home_directory(user)
        if not home:
            raise ValueError(f"Cannot resolve home for user: {user}")
        return Path(home) / ".xinitrc"
