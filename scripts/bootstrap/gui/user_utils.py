#!/usr/bin/env python3

import os
from typing import Optional

try:
    import pwd
except ImportError:
    pwd = None


class UserContext:
    @staticmethod
    def get_current_user() -> str:
        user = os.environ.get("SUDO_USER") or os.environ.get("USER") or os.environ.get("USERNAME")
        if user:
            return user

        if pwd is not None:
            try:
                return pwd.getpwuid(os.getuid()).pw_name
            except Exception:
                pass

        try:
            return os.getlogin()
        except Exception:
            return "unknown"

    @staticmethod
    def get_home_directory(username: str) -> Optional[str]:
        if pwd is not None:
            try:
                return pwd.getpwnam(username).pw_dir
            except KeyError:
                return None

        if username == UserContext.get_current_user():
            return os.path.expanduser("~")

        return None
