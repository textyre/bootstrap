#!/usr/bin/env python3

from typing import Optional

import argparse
from bootstrap.logging import Logger
from bootstrap.gui.deploy_dotfiles import DotfilesInstaller
from bootstrap.gui.check_required_bins import BinaryChecker
from bootstrap.gui.display.manager import DisplayManager
from bootstrap.gui import start_gui

logger = Logger(__name__)

def parse_args(argv: Optional[list] = None):
    parser = argparse.ArgumentParser(
        prog="launch.py",
        description="Install dotfiles and start GUI services (LightDM)",
    )
    sub = parser.add_subparsers(dest="command", help="sub-command to run")

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("target_user", nargs="?", help="target user to install dotfiles for")

    dots_p = sub.add_parser("dots", parents=[common], help="install dotfiles for target user")

    sub.add_parser("gui", help="enable/start the GUI (LightDM)")
    sub.add_parser("all", parents=[common], help="run dots then gui (default)")

    return parser.parse_args(argv)


def main(argv: Optional[list] = None) -> int:
    args = parse_args(argv)
    
    command = args.command or "all"
    
    checker = BinaryChecker()
    if not checker.check_all():
        return 3
    
    if command == "dots":
        installer = DotfilesInstaller()
        rc = installer.install(args.target_user)
        if rc != 0:
            return rc

        logger.info("Configuring display resolution...")
        display_manager = DisplayManager()
        if not display_manager.deploy_all():
            logger.warning("Failed to configure display, continuing anyway...")

        return rc
    
    if command == "gui":
        return start_gui.main() or 0
    
    if command == "all":        
        installer = DotfilesInstaller()
        target_user = getattr(args, "target_user", None)
        deploy_rc = installer.install(target_user)
        if deploy_rc != 0:
            return deploy_rc

        return start_gui.main() or 0
    
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
