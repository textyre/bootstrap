"""CLI entry point for display configuration manager."""

import sys
import argparse
from .manager import DisplayManager


def main():
    parser = argparse.ArgumentParser(description="Display configuration manager")
    parser.add_argument('--xinitrc', help="Path to xinitrc template")
    parser.add_argument('--info', action='store_true', help="Show display information")
    parser.add_argument('--generate', action='store_true', help="Generate xrandr commands")
    
    args = parser.parse_args()
    
    manager = DisplayManager(args.xinitrc)
    
    if args.info:
        print(manager.get_display_info())
    elif args.generate:
        commands = manager.generator.generate_commands()
        if commands:
            print(commands)
    else:
        if manager.update_xinitrc():
            print("✓ xinitrc updated successfully")
        else:
            print("✗ Failed to update xinitrc")
            sys.exit(1)


if __name__ == '__main__':
    main()
