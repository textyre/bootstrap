from pathlib import Path
from .strategies import DeployStrategy


class LightDMHookDeployStrategy(DeployStrategy):
    def deploy(
        self,
        source_root: Path,
        user: str,
        path_resolver,
        writer
    ) -> bool:
        hook_path = path_resolver.get_lightdm_hook_path()
        source_hook = source_root / "etc" / "lightdm" / "lightdm.conf.d" / "add-and-set-resolution.sh"

        if not self._check_source_exists(source_hook):
            return False

        content = self._read_source(source_hook)
        if not content:
            return False

        return self._write_hook(hook_path, content, writer)

    def _check_source_exists(self, source_path: Path) -> bool:
        if not source_path.exists():
            self.logger.error(f"Source hook not found: {source_path}")
            return False
        return True

    def _read_source(self, source_path: Path) -> str:
        try:
            return source_path.read_text()
        except Exception as e:
            self.logger.error(f"Failed to read source: {e}")
            return ""

    def _write_hook(self, target_path: Path, content: str, writer) -> bool:
        return writer.write(
            path=target_path,
            content=content,
            mode=0o755,
            owner="lightdm",
            group="lightdm"
        )
