#!/usr/bin/env python3

from typing import Optional

import subprocess
from bootstrap.logging import Logger

logger = Logger(__name__)


class LightDMStarter:
    @staticmethod
    def start() -> int:
        logger.info("enabling and starting LightDM (requires root)")
        try:
            subprocess.run(["sudo", "systemctl", "enable", "--now", "lightdm"], check=False)
        except Exception:
            logger.debug("systemctl enable/start failed or not available", exc_info=True)

        logger.info("done. Please log in via LightDM to start i3. Screen locker will be started by .xinitrc/session.")
        return 0


def main(argv: Optional[list] = None) -> int:
    return LightDMStarter.start()


if __name__ == "__main__":
    raise SystemExit(main())
