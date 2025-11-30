"""Package for bootstrap GUI helpers.

This file makes the `gui` directory a Python package so modules can be
imported in a straightforward way from `launch.py` or other scripts.
"""

__all__ = [
    "launch",
    "deploy_dotfiles",
    "start_gui",
    "check_required_bins",
]
