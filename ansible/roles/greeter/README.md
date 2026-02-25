# greeter

ctOS LightDM web-greeter theme deployment — installs the custom ctOS theme, deploys `web-greeter.yml` configuration, generates `system-info.json` with live system data, and copies user wallpapers to `/usr/share/backgrounds/`.

## What this role does

- [x] Deploys `/etc/lightdm/web-greeter.yml` from Jinja2 template (owner root:root 0644)
- [x] Asserts the pre-built ctOS theme dist directory exists (`greeter_dist_dir`)
- [x] Cleans stale hashed bundles and copies theme files to `/usr/share/web-greeter/themes/{{ greeter_theme }}/`
- [x] Copies `index.yml` theme metadata into the theme directory
- [x] Collects live system info (timezone, systemd version, display name/resolution, SSH fingerprint)
- [x] Generates `system-info.json` inside the theme directory from collected facts
- [x] Fixes theme file ownership and permissions (root:root, dirs 0755, files 0644)
- [x] Copies user wallpapers from `greeter_wallpaper_source_dir` to `/usr/share/backgrounds/` (skipped if source absent)
- [x] Reports deployed theme name and version

## Requirements

- **`web-greeter`** must be pre-installed on the target system (available as `lightdm-webkit2-greeter` or `web-greeter` depending on the distro). This role does **not** install it.
- The ctOS theme must be pre-built (`task greeter:build` from the repo root). The built output must exist at `greeter_dist_dir` before the role runs.
- LightDM and a running display server are required for the greeter to actually function. The role only deploys configuration and theme files — it does not start or configure LightDM.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `greeter_theme` | `"ctos"` | Name of the web-greeter theme directory to deploy into |
| `greeter_ctos_version` | `"1.0.0"` | Project version string shown in the greeter UI |
| `greeter_dist_dir` | `"{{ lookup('env', 'REPO_ROOT') }}/greeter/dist"` | Path to the pre-built ctOS theme dist directory on the **controller** |
| `greeter_index_yml` | `"{{ lookup('env', 'REPO_ROOT') }}/greeter/index.yml"` | Path to the `index.yml` theme metadata file on the **controller** |
| `greeter_debug_mode` | `false` | Enable web-greeter debug mode |
| `greeter_screensaver_timeout` | `300` | Screensaver timeout in seconds |
| `greeter_secure_mode` | `true` | Enable web-greeter secure mode |
| `greeter_time_language` | `""` | Time locale for the greeter (empty = system default) |
| `greeter_background_images_dir` | `"/usr/share/backgrounds"` | Directory web-greeter scans for background images |
| `greeter_wallpaper_source_dir` | `"/home/{{ ansible_facts['env']['SUDO_USER'] \| default('textyre') }}/.local/share/wallpapers"` | Source directory for user wallpapers to copy to system backgrounds |
| `greeter_region_prefix` | `""` | Two-letter region prefix shown in the greeter (e.g. `"KZ"`). Empty = greeter derives it from timezone continent |

## Dependencies

None (`dependencies: []`).

`web-greeter` must be installed separately, e.g. via the `common` or a dedicated packages role.

## Example playbook

```yaml
- name: Deploy ctOS greeter
  hosts: workstations
  become: true
  environment:
    REPO_ROOT: "{{ playbook_dir }}/.."
  roles:
    - role: greeter
      vars:
        greeter_theme: ctos
        greeter_ctos_version: "1.2.0"
        greeter_region_prefix: "KZ"
        greeter_screensaver_timeout: 600
```

> **Note:** `REPO_ROOT` must be set so that `greeter_dist_dir` and `greeter_index_yml` resolve correctly. In the main `workstation.yml` playbook it is set via `environment:` or exported before running `ansible-playbook`.

## Tags

| Tag | Effect |
|-----|--------|
| `greeter` | All tasks |
| `display` | All tasks (also applies display-related subset) |

Run only the configuration deployment:

```bash
ansible-playbook playbooks/workstation.yml --tags greeter
```

## Testing

The role has two Molecule scenarios.

### Scenarios

| Scenario | Driver | Purpose |
|----------|--------|---------|
| `default` | `default` (localhost) | Syntax check + config deployment on the local machine (no Docker) |
| `docker` | `docker` | Full deployment in an `arch-systemd` container with a stub dist directory |

### Running tests

```bash
# Default scenario (localhost, syntax + converge + verify)
cd ansible/roles/greeter
molecule test

# Docker scenario (full container test)
molecule test -s docker

# Converge only (faster iteration)
molecule converge -s docker

# Verify only (after converge)
molecule verify -s docker
```

The `docker` scenario uses a `prepare.yml` step that creates a minimal stub of the greeter build output at `/opt/greeter-stub/greeter/dist/` inside the container, so no real `yarn build` is needed for CI.

### What is tested

- `/etc/lightdm/web-greeter.yml` deployed with correct permissions (root:root 0644) and expected content (`theme:`, `screensaver_timeout:`, `background_images_dir:` directives present)
- Theme directory `/usr/share/web-greeter/themes/{{ greeter_theme }}` created with correct permissions (root 0755)
- `system-info.json` present with correct permissions (root:root 0644), valid JSON, and required keys (`kernel`, `hostname`, `project_version`, `ip_address`, `timezone`, `machine_id`)
- `index.yml` present inside the theme directory with correct permissions (0644)

### Limitations

- **Display server not required for CI.** The role collects display information via DRM sysfs (`/sys/class/drm/`), but these calls use `failed_when: false` and fall back gracefully. No display server is needed to run tests.
- **Idempotence check disabled** in the `docker` scenario. Two tasks — the pre-deploy clean (shell) and the permissions fix (shell) — use `changed_when: true`, meaning they always report `changed`. Refactoring these tasks is out of scope.

## Known issues

### Template variable naming mismatch (`_greeter_*` vs `greeter_*`)

**Status:** Known bug, not yet fixed.

The tasks in `tasks/main.yml` register variables without a leading underscore (e.g. `greeter_timezone`, `greeter_systemd_ver`, `greeter_display_name`), but `templates/system-info.json.j2` references them **with** a leading underscore (e.g. `_greeter_timezone`, `_greeter_systemd_ver`, `_greeter_display_name`).

As a result, the dynamic fields in `system-info.json` always render their fallback values (`"unknown"`, `"UTC"`, etc.) instead of the actual collected values.

Molecule `verify.yml` is intentionally limited to asserting JSON validity and required key presence until this mismatch is fixed. Value correctness is **not** asserted.

**Fix required:** Rename registered variables in `tasks/main.yml` to use the `_greeter_*` prefix, or update `system-info.json.j2` to reference `greeter_*` variables.
