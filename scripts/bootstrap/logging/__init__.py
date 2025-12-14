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
        if isinstance(level, int):
            level_value = level
        else:
            level_value = logging.getLevelName(level)
            if isinstance(level_value, str):
                level_value = logging.INFO
        self.logger.setLevel(level_value)

    def _setup_handlers(self, log_file: Optional[str]) -> None:
        for handler in list(self.logger.handlers):
            self.logger.removeHandler(handler)

        console_format = "[%(levelname)s] %(name)s: %(message)s"
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setFormatter(ColoredFormatter(console_format))
        self.logger.addHandler(console_handler)

        if log_file:
            file_format = "%(asctime)s - %(name)s - [%(levelname)s] %(message)s"
            file_handler = logging.FileHandler(log_file)
            file_handler.setFormatter(logging.Formatter(file_format))
            self.logger.addHandler(file_handler)

    def debug(self, msg: str, *args, **kwargs) -> None:
        self.logger.debug(msg, *args, **kwargs)

    def info(self, msg: str, *args, **kwargs) -> None:
        self.logger.info(msg, *args, **kwargs)

    def warning(self, msg: str, *args, **kwargs) -> None:
        self.logger.warning(msg, *args, **kwargs)

    def error(self, msg: str, *args, **kwargs) -> None:
        self.logger.error(msg, *args, **kwargs)

    def critical(self, msg: str, *args, **kwargs) -> None:
        self.logger.critical(msg, *args, **kwargs)

    def exception(self, msg: str, *args, **kwargs) -> None:
        self.logger.exception(msg, *args, **kwargs)
