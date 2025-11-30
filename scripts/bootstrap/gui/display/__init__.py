"""Display configuration module for X11 setup."""

from .manager import DisplayManager
from .cli import main

__all__ = ['DisplayManager', 'main']
