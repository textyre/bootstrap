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
