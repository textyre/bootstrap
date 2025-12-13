from pathlib import Path
from .strategies import DeployStrategy


class LightDMConfigDeployStrategy(DeployStrategy):
    def deploy(
        self,
        source_root: Path,
        user: str,
        path_resolver,
        writer
    ) -> bool:
        conf_dir = path_resolver.get_lightdm_conf_dir()
        source_conf = source_root / "etc" / "lightdm" / "lightdm.conf.d" / "10-config.conf"
        target_conf = conf_dir / "10-config.conf"

        if not self._check_source_exists(source_conf):
            return False

        content = self._read_source(source_conf)
        if not content:
            return False

        return self._write_config(target_conf, content, writer)

    def _check_source_exists(self, source_path: Path) -> bool:
        if not source_path.exists():
            self.logger.error(f"Source config not found: {source_path}")
            return False
        return True

    def _read_source(self, source_path: Path) -> str:
        try:
            return source_path.read_text()
        except Exception as e:
            self.logger.error(f"Failed to read source: {e}")
            return ""

    def _write_config(self, target_path: Path, content: str, writer) -> bool:
        return writer.write(
            path=target_path,
            content=content,
            mode=0o644,
            owner="root",
            group="root"
        )
