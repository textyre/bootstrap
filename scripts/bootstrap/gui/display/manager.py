"""Display configuration manager - main module."""

import re
import subprocess
from pathlib import Path
from typing import Optional, Tuple
from .detector import DisplayDetector
from .generator import XrandrCommandGenerator
from .modeutils import ModeUtils
from .xinitrc_strategy import XinitrcDeployStrategy
from bootstrap.gui.logging import Logger

logger = Logger(__name__)


class DisplayManager:    
    DISPLAY_MARKER_START = "# [DISPLAY_CONFIG_START]"
    DISPLAY_MARKER_END = "# [DISPLAY_CONFIG_END]"
    
    def __init__(self, xinitrc_path: Optional[str] = None):
        self.logger = logger
        self.detector = DisplayDetector()
        self.generator = XrandrCommandGenerator()
        
        try:
            if xinitrc_path:
                self.xinitrc_path = Path(xinitrc_path).expanduser().resolve(strict=True)
            else:
                self.xinitrc_path = Path('/home/textyre/scripts/dotfiles/dot_xinitrc').expanduser().resolve(strict=True)
        except FileNotFoundError as e:
            # Friendly error: log suggestion and re-raise to keep strict behavior
            self.logger.error(f"xinitrc template not found: {e.filename}")
            self.logger.error("Provide a valid path or create the template at the fallback location:")
            self.logger.error("  - pass path: DisplayManager(xinitrc_path='/home/user/scripts/dotfiles/dot_xinitrc')")
            self.logger.error("  - or create: /home/textyre/scripts/dotfiles/dot_xinitrc")
            raise

        self.logger.debug(f"xinitrc path: {self.xinitrc_path}")
        
        # Initialize strategies
        self._init_strategies()
    

    def inject_display_config(self, content: str, display_section: str) -> str:
        if self.DISPLAY_MARKER_START in content and self.DISPLAY_MARKER_END in content:
            return self.replace_between_markers(content, display_section)
        else:
            return self.insert_after_comments(content, display_section)
    
    def replace_between_markers(self, content: str, display_section: str) -> str:
        pattern = f"{re.escape(self.DISPLAY_MARKER_START)}.*?{re.escape(self.DISPLAY_MARKER_END)}"
        updated = re.sub(
            pattern,
            f"{self.DISPLAY_MARKER_START}\n{display_section}\n{self.DISPLAY_MARKER_END}",
            content,
            flags=re.DOTALL
        )
        self.logger.debug("Replaced display config between markers")
        return updated
    
    def insert_after_comments(self, content: str, display_section: str) -> str:
        lines = content.split('\n')
        insert_pos = self.find_insert_position(lines)
        
        lines.insert(
            insert_pos,
            f"\n{self.DISPLAY_MARKER_START}\n{display_section}\n{self.DISPLAY_MARKER_END}\n"
        )
        
        self.logger.debug(f"Inserted display config at line {insert_pos}")
        return '\n'.join(lines)
    
    def find_insert_position(self, lines: list) -> int:
        insert_pos = 0
        
        for i, line in enumerate(lines):
            if line.startswith('#!'):
                insert_pos = i + 1
            elif line.strip().startswith('#'):
                insert_pos = i + 1
            else:
                break
        
        return insert_pos
    
    def get_display_info(self) -> str:
        monitors = self.detector.get_connected_monitors()
        
        if not monitors:
            return "No connected monitors detected"
        
        info_lines = [f"Connected monitors: {len(monitors)}"]
        
        for monitor in monitors:
            info_lines.append(f"\n  {monitor.name}:")
            
            if monitor.primary:
                info_lines.append("    [PRIMARY]")
            
            if monitor.current_resolution:
                info_lines.append(f"    Current: {monitor.current_resolution}")
            
            best = self.detector.get_best_resolution(monitor)
            if best:
                info_lines.append(f"    Best: {best}")
            
            if monitor.available_resolutions:
                resolutions = [f"{r.width}x{r.height}" for r in monitor.available_resolutions[:5]]
                info_lines.append(f"    Available: {', '.join(resolutions)}")
        
        return '\n'.join(info_lines)
    

    def _init_strategies(self) -> None:
        """Initialize all deployment strategies."""
        self.strategies = [
            XinitrcDeployStrategy(self),
        ]
    
    def deploy_all(self) -> bool:
        """Deploy ALL display configurations through all strategies."""
        self.logger.info("Deploying display configuration...")
        
        success = True
        for strategy in self.strategies:
            strategy_name = strategy.__class__.__name__
            try:
                self.logger.debug(f"Executing {strategy_name}...")
                if not strategy.deploy():
                    self.logger.warning(f"{strategy_name} failed")
                    success = False
                else:
                    self.logger.info(f"{strategy_name} succeeded")
            except Exception as e:
                self.logger.error(f"{strategy_name} raised exception: {e}")
                success = False
        
        return success
