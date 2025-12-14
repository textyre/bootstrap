from pathlib import Path
import pwd
import grp
import stat

from bootstrap.logging import Logger
from bootstrap.gui.path_utils import PathResolver
from bootstrap.gui.display.file_writer import PrivilegedFileWriter
from bootstrap.gui.display.lightdm_hook_strategy import LightDMHookDeployStrategy
from bootstrap.gui.display.lightdm_config_strategy import LightDMConfigDeployStrategy
from bootstrap.gui.display.config import DisplayConfig


class DisplayDotfilesManager:
    def __init__(self):
        self.logger = Logger(__name__)
        self.path_resolver = PathResolver()
        self.writer = PrivilegedFileWriter()
        self.hook_strategy = LightDMHookDeployStrategy()
        self.config_strategy = LightDMConfigDeployStrategy()

    def _get_owner_and_mode(self, path: Path):
        try:
            st = path.stat()
            owner = pwd.getpwuid(st.st_uid).pw_name
            group = grp.getgrgid(st.st_gid).gr_name
            mode = stat.S_IMODE(st.st_mode)
            return owner, group, mode
        except Exception:
            return None, None, None

    def _content_matches(self, source: Path, target: Path) -> bool:
        try:
            return source.read_text() == target.read_text()
        except Exception:
            return False

    def _check_file(self, source: Path, target: Path, mode_expected: int, owner_expected: str, group_expected: str) -> bool:
        if not source.exists():
            self.logger.error(f"Source missing: {source}")
            return False
        if not target.exists():
            self.logger.info(f"Target missing: {target}")
            return False

        if not self._content_matches(source, target):
            self.logger.info(f"Content mismatch: {target}")
            return False

        owner, group, mode = self._get_owner_and_mode(target)
        if owner != owner_expected or group != group_expected or mode != mode_expected:
            self.logger.info(f"Metadata mismatch: {target} (owner={owner}:{group} mode={oct(mode) if mode is not None else None}) expected ({owner_expected}:{group_expected} {oct(mode_expected)})")
            return False

        return True

    def validate(self, source_root: Path, user: str) -> bool:
        # Initial checks
        source_hook = source_root / DisplayConfig.SOURCE_LIGHTDM_HOOK_FILE
        target_hook = DisplayConfig.TARGET_LIGHTDM_HOOK_FILE
        hook_ok = self._check_file(
            source_hook,
            target_hook,
            DisplayConfig.LIGHTDM_HOOK_MODE,
            DisplayConfig.LIGHTDM_HOOK_OWNER,
            DisplayConfig.LIGHTDM_HOOK_GROUP,
        )

        source_conf = source_root / DisplayConfig.SOURCE_LIGHTDM_CONFIG_FILE
        target_conf = DisplayConfig.TARGET_LIGHTDM_CONFIG_FILE
        conf_ok = self._check_file(
            source_conf,
            target_conf,
            DisplayConfig.LIGHTDM_CONFIG_MODE,
            DisplayConfig.LIGHTDM_CONFIG_OWNER,
            DisplayConfig.LIGHTDM_CONFIG_GROUP,
        )

        # If everything is already fine, return True
        if hook_ok and conf_ok:
            return True

        # Deploy any missing/incorrect pieces
        if not hook_ok:
            self.logger.info("Deploying LightDM hook to fix issues")
            self.hook_strategy.deploy(source_root=source_root, user=user, path_resolver=self.path_resolver, writer=self.writer)

        if not conf_ok:
            self.logger.info("Deploying LightDM config to fix issues")
            self.config_strategy.deploy(source_root=source_root, user=user, path_resolver=self.path_resolver, writer=self.writer)

        # Re-check after attempted deployment; only return True if both now match
        hook_ok = self._check_file(
            source_hook,
            target_hook,
            DisplayConfig.LIGHTDM_HOOK_MODE,
            DisplayConfig.LIGHTDM_HOOK_OWNER,
            DisplayConfig.LIGHTDM_HOOK_GROUP,
        )
        conf_ok = self._check_file(
            source_conf,
            target_conf,
            DisplayConfig.LIGHTDM_CONFIG_MODE,
            DisplayConfig.LIGHTDM_CONFIG_OWNER,
            DisplayConfig.LIGHTDM_CONFIG_GROUP,
        )

        if hook_ok and conf_ok:
            return True

        # Still not okay
        return False
