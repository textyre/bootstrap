from abc import ABC, abstractmethod
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from bootstrap.gui.path_utils import PathResolver
    from .file_writer import PrivilegedFileWriter

from bootstrap.logging import Logger


class DeployStrategy(ABC):
    def __init__(self):
        self.logger = Logger(self.__class__.__name__)

    @abstractmethod
    def deploy(
        self,
        source_root: Path,
        user: str,
        path_resolver: 'PathResolver',
        writer: 'PrivilegedFileWriter'
    ) -> bool:
        pass
