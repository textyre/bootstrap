import subprocess
import shutil
import os
from typing import Optional, Tuple


class ModeUtils:
    @staticmethod
    def _parse_modeline_from_output(output: str) -> Optional[Tuple[str, str]]:
        for line in output.splitlines():
            line = line.strip()
            if line.startswith('Modeline'):
                parts = line.split(None, 2)
                if len(parts) >= 3:
                    name = parts[1].strip('"')
                    params = parts[2]
                    return name, params
        return None

    @staticmethod
    def _external_modeline(width: int, height: int, refresh: int) -> Optional[Tuple[str, str]]:
        for cmd in (('cvt', str(width), str(height), str(refresh)), ('gtf', str(width), str(height), str(refresh), '1')):
            exe = shutil.which(cmd[0])
            if not exe:
                continue
            try:
                p = subprocess.run(cmd, capture_output=True, text=True, check=True)
                parsed = ModeUtils._parse_modeline_from_output(p.stdout)
                if parsed:
                    return parsed
            except subprocess.CalledProcessError:
                continue
        return None

    pass

    @staticmethod
    def preferred_from_edid(edid_path: str) -> Optional[Tuple[int, int, int]]:
        if not os.path.exists(edid_path):
            return None
        try:
            with open(edid_path, 'rb') as fh:
                data = fh.read()
            if len(data) < 128:
                return None

            base = 54
            for i in range(4):
                off = base + i * 18
                block = data[off:off+18]
                if len(block) < 18:
                    continue
                pixclock = block[0] + (block[1] << 8)
                if pixclock == 0:
                    continue
                pixel_clock_hz = pixclock * 10000

                h_active = ((block[4] & 0xF0) << 4) | block[2]
                h_blanking = ((block[4] & 0x0F) << 8) | block[3]
                v_active = ((block[7] & 0xF0) << 4) | block[5]
                v_blanking = ((block[7] & 0x0F) << 8) | block[6]

                h_total = h_active + h_blanking
                v_total = v_active + v_blanking
                if h_total == 0 or v_total == 0:
                    continue
                refresh = round(pixel_clock_hz / (h_total * v_total))
                return h_active, v_active, int(refresh)
        except Exception:
            return None

    @staticmethod
    def get_modeline(width: int, height: int, refresh: Optional[int] = 60, edid_path: Optional[str] = None) -> Optional[Tuple[str, str]]:
        if edid_path:
            pref = ModeUtils.preferred_from_edid(edid_path)
            if pref and pref[0] == width and pref[1] == height:
                refresh = pref[2]

        if refresh is None:
            refresh = 60

        return ModeUtils._external_modeline(width, height, refresh)
