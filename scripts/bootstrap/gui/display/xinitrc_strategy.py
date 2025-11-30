"""Xinitrc deployment strategy."""

from .strategies import DeployStrategy


class XinitrcDeployStrategy(DeployStrategy):
    """Deploy xrandr commands to ~/.xinitrc."""
    
    def deploy(self) -> bool:
        """Inject xrandr commands into xinitrc between markers."""
        if not self.manager.xinitrc_path.exists():
            self.logger.error(f"xinitrc template not found: {self.manager.xinitrc_path}")
            return False
        
        try:
            content = self.manager.xinitrc_path.read_text()
            self.logger.debug("Read xinitrc template")
            
            display_section = self.manager.generator.generate_xinitrc_section()
            
            if not display_section:
                self.logger.error("Failed to generate display configuration")
                return False
            
            updated_content = self.manager.inject_display_config(content, display_section)
            
            self.manager.xinitrc_path.write_text(updated_content)
            self.manager.xinitrc_path.chmod(0o755)
            
            self.logger.info(f"Updated xinitrc: {self.manager.xinitrc_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to update xinitrc: {e}")
            return False
