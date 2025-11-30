"""Monitor and resolution detection using xrandr or sysfs fallback."""

import subprocess
import os
import glob
from dataclasses import dataclass
from typing import List, Optional, Dict
from bootstrap.gui.logging import Logger

logger = Logger(__name__)


@dataclass
class Resolution:
    width: int
    height: int
    refresh_rate: Optional[float] = None

    def __str__(self) -> str:
        rate_str = f"@{self.refresh_rate}Hz" if self.refresh_rate else ""
        return f"{self.width}x{self.height}{rate_str}"


@dataclass
class Monitor:
    name: str
    connected: bool
    primary: bool = False
    current_resolution: Optional[Resolution] = None
    available_resolutions: List[Resolution] = None
    edid_size: int = 0
    edid_path: Optional[str] = None

    def __post_init__(self):
        if self.available_resolutions is None:
            self.available_resolutions = []


class DisplayDetector:

    PREFERRED_2K = Resolution(2560, 1440, 60.0)
    FALLBACK_1080P = Resolution(1920, 1080, 60.0)
    FALLBACK_720P = Resolution(1280, 720, 60.0)

    def __init__(self):
        self.logger = logger
        self.xrandr_available = self._check_xrandr()

    def _check_xrandr(self) -> bool:
        try:
            subprocess.run(['xrandr', '--version'], capture_output=True, check=True)
            self.logger.debug("xrandr is available")
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            self.logger.warning("xrandr not found or not executable")
            return False

    def get_xrandr_output(self) -> str:
        try:
            result = subprocess.run(['xrandr', '--query'], capture_output=True, text=True, check=True)
            return result.stdout
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to run xrandr: {e}")
            return ""

    def parse_monitors(self) -> List[Monitor]:
        output = ""
        if self.xrandr_available:
            output = self.get_xrandr_output()

        if output:
            monitors: List[Monitor] = []
            lines = output.split('\n')

            for line in lines:
                if ' connected' in line or ' disconnected' in line:
                    parts = line.split()
                    if not parts:
                        continue

                    name = parts[0]
                    connected = 'connected' in line and 'disconnected' not in line
                    primary = 'primary' in line

                    current_res = None
                    for part in parts:
                        if 'x' in part and '+' in part:
                            try:
                                res_part = part.split('+')[0]
                                width, height = map(int, res_part.split('x'))
                                current_res = Resolution(width, height)
                            except (ValueError, IndexError):
                                pass

                        monitor = Monitor(name=name, connected=connected, primary=primary, current_resolution=current_res, available_resolutions=[])
                    monitors.append(monitor)

            self._parse_resolutions(output, monitors)
            self.logger.info(f"Detected {len([m for m in monitors if m.connected])} connected monitor(s)")
            return monitors

        # sysfs fallback
        monitors = self._parse_sysfs_monitors()
        self.logger.info(f"Detected {len([m for m in monitors if m.connected])} connected monitor(s) via sysfs")
        return monitors

    def _parse_resolutions(self, xrandr_output: str, monitors: List[Monitor]):
        lines = xrandr_output.split('\n')
        current_monitor = None

        for line in lines:
            if ' connected' in line or ' disconnected' in line:
                parts = line.split()
                if parts:
                    current_monitor = next((m for m in monitors if m.name == parts[0]), None)

            elif current_monitor and line.strip() and current_monitor.connected:
                parts = line.strip().split()
                if parts and 'x' in parts[0]:
                    try:
                        width, height = map(int, parts[0].split('x'))
                        refresh_rate = float(parts[1]) if len(parts) > 1 else None
                        res = Resolution(width, height, refresh_rate)
                        current_monitor.available_resolutions.append(res)
                    except (ValueError, IndexError):
                        pass

    def _parse_sysfs_monitors(self) -> List[Monitor]:
        monitors: List[Monitor] = []
        paths = glob.glob('/sys/class/drm/*-*')
        for p in paths:
            try:
                name = os.path.basename(p)
                if '-' in name:
                    name = '-'.join(name.split('-')[1:])
                status_path = os.path.join(p, 'status')
                edid_path = os.path.join(p, 'edid')
                connected = False
                edid_size = 0
                if os.path.exists(status_path):
                    try:
                        with open(status_path, 'r', encoding='utf-8', errors='ignore') as fh:
                            status = fh.read().strip()
                            connected = (status == 'connected')
                    except Exception:
                        connected = False
                if os.path.exists(edid_path):
                    try:
                        edid_size = os.path.getsize(edid_path)
                    except Exception:
                        edid_size = 0
                monitor = Monitor(name=name, connected=connected, primary=False, current_resolution=None, available_resolutions=[], edid_size=edid_size, edid_path=edid_path if os.path.exists(edid_path) else None)
                monitors.append(monitor)
            except Exception:
                continue
        return monitors

    def get_best_resolution(self, monitor: Monitor) -> Optional[Resolution]:
        if not monitor.available_resolutions:
            return None

        for res in monitor.available_resolutions:
            if res.width == 2560 and res.height == 1440:
                self.logger.debug(f"2K resolution available on {monitor.name}")
                return Resolution(2560, 1440, 60.0)

        for res in monitor.available_resolutions:
            if res.width == 1920 and res.height == 1080:
                self.logger.debug(f"1080p resolution available on {monitor.name}")
                return Resolution(1920, 1080, 60.0)

        for res in monitor.available_resolutions:
            if res.height == 1440:
                self.logger.debug(f"1440p resolution available on {monitor.name}")
                return res

        if monitor.available_resolutions:
            best = monitor.available_resolutions[0]
            self.logger.debug(f"Using first available: {best.width}x{best.height}")
            return best

        return None

    def get_connected_monitors(self) -> List[Monitor]:
        monitors = self.parse_monitors()
        return [m for m in monitors if m.connected]

    def get_primary_monitor(self) -> Optional[Monitor]:
        monitors = self.get_connected_monitors()
        for m in monitors:
            if m.primary:
                return m
        return monitors[0] if monitors else None
