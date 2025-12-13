import subprocess
from pathlib import Path
from typing import Optional
from bootstrap.logging import Logger

logger = Logger(__name__)


class PrivilegedFileWriter:
    def write(
        self,
        path: Path,
        content: str,
        mode: int = 0o644,
        owner: Optional[str] = None,
        group: Optional[str] = None
    ) -> bool:
        try:
            self._ensure_parent_dir(path)
            self._write_content(path, content)
            self._set_mode(path, mode)
            if owner or group:
                self._set_owner(path, owner, group)
            logger.info(f"Wrote file: {path}")
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to write {path}: {e}")
            return False

    def ensure_dir(
        self,
        path: Path,
        mode: int = 0o755,
        owner: Optional[str] = None,
        group: Optional[str] = None
    ) -> bool:
        try:
            subprocess.run(
                ["sudo", "mkdir", "-p", str(path)],
                check=True,
                capture_output=True
            )
            self._set_mode(path, mode)
            if owner or group:
                self._set_owner(path, owner, group)
            return True
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to create dir {path}: {e}")
            return False

    def _ensure_parent_dir(self, path: Path) -> None:
        parent = path.parent
        subprocess.run(
            ["sudo", "mkdir", "-p", str(parent)],
            check=True,
            capture_output=True
        )

    def _write_content(self, path: Path, content: str) -> None:
        subprocess.run(
            ["sudo", "tee", str(path)],
            input=content,
            text=True,
            check=True,
            capture_output=True
        )

    def _set_mode(self, path: Path, mode: int) -> None:
        subprocess.run(
            ["sudo", "chmod", oct(mode)[2:], str(path)],
            check=True,
            capture_output=True
        )

    def _set_owner(self, path: Path, owner: Optional[str], group: Optional[str]) -> None:
        owner_spec = f"{owner or ''}:{group or ''}"
        subprocess.run(
            ["sudo", "chown", owner_spec, str(path)],
            check=True,
            capture_output=True
        )
