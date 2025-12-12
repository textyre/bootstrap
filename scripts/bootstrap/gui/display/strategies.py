"""Base strategy class for display configuration deployment."""

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .manager import DisplayManager


class DeployStrategy(ABC):    
    def __init__(self, manager: 'DisplayManager'):
        self.manager = manager
        self.logger = manager.logger
    
    @abstractmethod
    def deploy(self) -> bool:
        pass
