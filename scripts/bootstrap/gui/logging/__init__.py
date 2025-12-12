import logging
import sys
from typing import Optional, Union

LEVEL_COLORS = {
    "DEBUG": "\x1b[36m",
    "INFO": "\x1b[32m",
    "WARNING": "\x1b[33m",
    "ERROR": "\x1b[31m",
    "CRITICAL": "\x1b[41m",
}
RESET = "\x1b[0m"


class ColoredFormatter(logging.Formatter):
    def __init__(self, fmt: str):
        super().__init__(fmt)

    def format(self, record: logging.LogRecord) -> str:
        levelname = record.levelname
        color = LEVEL_COLORS.get(levelname, "")
        record.levelname = f"{color}{levelname}{RESET}" if color else levelname
        return super().format(record)


class Logger:
    def __init__(self, name: str, level: Union[str, int] = "INFO", log_file: Optional[str] = None):
        self.name = name
        self.logger = logging.getLogger(name)
        self._set_level(level)
        self._setup_handlers(log_file)

    def _set_level(self, level: Union[str, int]) -> None:
        from bootstrap.logging import Logger

        __all__ = ["Logger"]
            level_value = logging.getLevelName(level)
