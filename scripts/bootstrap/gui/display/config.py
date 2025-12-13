from pathlib import Path


class DisplayConfig:
    # Source paths (relative to dotfiles repo root)
    SOURCE_LIGHTDM_HOOK_FILE = "etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh"
    SOURCE_LIGHTDM_CONFIG_FILE = "etc/lightdm/lightdm.conf.d/10-config.conf"

    # Target paths (absolute on system)
    TARGET_LIGHTDM_CONF_DIR = Path("/etc/lightdm/lightdm.conf.d")
    TARGET_LIGHTDM_HOOK_FILE = Path("/etc/lightdm/lightdm.conf.d/add-and-set-resolution.sh")
    TARGET_LIGHTDM_CONFIG_FILE = Path("/etc/lightdm/lightdm.conf.d/10-config.conf")

    # File metadata
    LIGHTDM_HOOK_MODE = 0o755
    LIGHTDM_HOOK_OWNER = "lightdm"
    LIGHTDM_HOOK_GROUP = "lightdm"

    LIGHTDM_CONFIG_MODE = 0o644
    LIGHTDM_CONFIG_OWNER = "root"
    LIGHTDM_CONFIG_GROUP = "root"
