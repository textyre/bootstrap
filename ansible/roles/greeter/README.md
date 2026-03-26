# greeter

Deploys the ctOS LightDM web-greeter theme, runtime system-info payload, and optional wallpapers.

## Execution flow

1. **Deploy web-greeter config** (`tasks/main.yml`) - renders `/etc/lightdm/web-greeter.yml` from `templates/web-greeter.yml.j2` with the selected theme, timeout, and background directory.
2. **Validate build artefacts** (`tasks/main.yml`) - checks that `greeter_dist_dir` exists on the managed host and fails early if the prebuilt theme output is missing.
3. **Prepare theme directory** (`tasks/main.yml`) - creates `/usr/share/web-greeter/themes/{{ greeter_theme }}` and removes stale `assets/`, `dist/`, and `index.html` files before deployment.
4. **Deploy theme files** (`tasks/main.yml`) - copies the built ctOS theme from `greeter_dist_dir` and writes `index.yml` into the theme directory.
5. **Collect runtime system info** (`tasks/main.yml`) - probes timezone, systemd version, DRM display info, and SSH host fingerprint; failures degrade to safe fallback values instead of aborting the role.
6. **Render runtime payload** (`tasks/main.yml`) - writes `/usr/share/web-greeter/themes/{{ greeter_theme }}/system-info.json` from `templates/system-info.json.j2`.
7. **Normalize ownership** (`tasks/main.yml`) - recursively enforces `root:root` ownership on the deployed theme tree.
8. **Copy optional wallpapers** (`tasks/main.yml`) - if `greeter_wallpaper_source_dir` exists, copies its contents into `/usr/share/backgrounds/`.
9. **Verify deployment** (`tasks/verify.yml`) - checks the rendered config values and validates `system-info.json` as real JSON with expected runtime content.
10. **Render report** (`tasks/main.yml`) - emits a structured execution report via `common/report_phase.yml` and `common/report_render.yml`.

### Handlers

This role has no handlers.

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory or play vars. Do not edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `greeter_theme` | `"ctos"` | safe | Theme directory name under `/usr/share/web-greeter/themes/` |
| `greeter_ctos_version` | `"1.0.0"` | safe | Version string rendered into `system-info.json` |
| `greeter_dist_dir` | `"{{ lookup('env', 'REPO_ROOT') }}/greeter/dist"` | careful | Path to the prebuilt theme files on the managed host; role fails if missing |
| `greeter_index_yml` | `"{{ lookup('env', 'REPO_ROOT') }}/greeter/index.yml"` | careful | Path to theme metadata file copied into the deployed theme directory |
| `greeter_debug_mode` | `false` | safe | Toggles `debug_mode` in `/etc/lightdm/web-greeter.yml` |
| `greeter_screensaver_timeout` | `300` | safe | Screensaver timeout in seconds for web-greeter |
| `greeter_secure_mode` | `true` | careful | Enables web-greeter secure mode |
| `greeter_time_language` | `""` | safe | Optional locale override for the greeter clock |
| `greeter_background_images_dir` | `"/usr/share/backgrounds"` | safe | Directory scanned by web-greeter for available backgrounds |
| `greeter_wallpaper_source_dir` | `"/home/{{ ansible_facts['env']['SUDO_USER'] \| default('textyre') }}/.local/share/wallpapers"` | careful | Optional source directory copied into `/usr/share/backgrounds/`; skipped if absent |
| `greeter_region_prefix` | `""` | safe | Optional region prefix rendered into `system-info.json` |

### Internal files

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `templates/web-greeter.yml.j2` | Rendered LightDM web-greeter configuration | When changing LightDM/web-greeter settings |
| `templates/system-info.json.j2` | Runtime JSON payload exposed to the ctOS frontend | When the greeter UI needs new system metadata |
| `tasks/verify.yml` | In-role verification checks required by ROLE-005 | When deployment semantics change and verification must follow |

## Examples

### Deploy a custom version string

```yaml
# host_vars/workstation/greeter.yml
greeter_ctos_version: "1.2.3"
greeter_region_prefix: "KZ"
```

This changes only the rendered runtime payload and does not affect theme assets.

### Use a different prebuilt theme path

```yaml
# group_vars/workstations/greeter.yml
greeter_dist_dir: /opt/greeter-build/greeter/dist
greeter_index_yml: /opt/greeter-build/greeter/index.yml
```

Use this when the build artefacts are staged outside the repository checkout on the managed host.

### Disable wallpaper import

```yaml
# host_vars/workstation/greeter.yml
greeter_wallpaper_source_dir: /nonexistent
```

The role skips the wallpaper copy phase when the source directory does not exist.

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian |
|--------|-----------|-----------------|
| Theme path | `/usr/share/web-greeter/themes/{{ greeter_theme }}` | `/usr/share/web-greeter/themes/{{ greeter_theme }}` |
| Config path | `/etc/lightdm/web-greeter.yml` | `/etc/lightdm/web-greeter.yml` |
| JSON validation command | `python3 -m json.tool` | `python3 -m json.tool` |

The role is currently tested on Arch Linux and Ubuntu via Molecule. Other project-supported distros are not yet covered by role-specific scenarios.

## Logs

### Files written by the role

| Path | Contents | Rotation |
|------|----------|----------|
| `/etc/lightdm/web-greeter.yml` | web-greeter runtime configuration | No rotation; managed config file |
| `/usr/share/web-greeter/themes/{{ greeter_theme }}/system-info.json` | Runtime metadata consumed by the ctOS greeter UI | No rotation; regenerated on each run |

### Runtime/debug logs

- `journalctl -u lightdm` shows LightDM startup and greeter launch failures after this role has deployed the config.
- Frontend asset load failures are usually visible in the LightDM greeter logs or browser console of the greeter session, not in separate files managed by this role.

## File map

| Path | Purpose |
|------|---------|
| `tasks/main.yml` | Main orchestration for deployment, data collection, verification, and reporting |
| `tasks/verify.yml` | In-role verification checks |
| `templates/web-greeter.yml.j2` | LightDM web-greeter config template |
| `templates/system-info.json.j2` | Runtime JSON template used by the frontend |
| `molecule/shared/verify.yml` | Shared Molecule verification playbook |
| `molecule/vagrant/prepare.yml` | VM bootstrap and greeter stub artefacts for Vagrant tests |

## Testing

The role has three Molecule scenarios.

| Scenario | Driver | Purpose |
|----------|--------|---------|
| `default` | `default` (localhost) | Fast local syntax/converge/verify workflow |
| `docker` | `docker` | Fast deployment and idempotence checks in Arch container |
| `vagrant` | `vagrant-libvirt` | Cross-platform verification on Arch and Ubuntu VMs |

### Running tests

```bash
cd ansible/roles/greeter
molecule test
molecule test -s docker
molecule test -s vagrant
```

All scenarios now include `idempotence`.

## Troubleshooting

### `Greeter dist не найден`

`greeter_dist_dir` must exist on the managed host before the role runs. Build or stage the ctOS frontend first, or override `greeter_dist_dir`/`greeter_index_yml` to a valid location.

### `system-info.json` contains fallback values

The role intentionally falls back to `UTC` or `unknown` when runtime probes fail. Check `timedatectl`, `systemctl --version`, `/sys/class/drm`, and SSH host key files on the target host.

### Wallpaper copy is skipped

This is expected when `greeter_wallpaper_source_dir` does not exist. Set the variable to a valid directory if wallpapers must be imported.
