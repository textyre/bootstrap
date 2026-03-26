# packages

Installs workstation packages via OS-native package managers (pacman, apt).

## Execution flow

1. **Guard** — skips entire role if `packages_enabled: false`
2. **Preflight assert** — fails fast with a clear message if the OS family is not in `_packages_supported_os`; supported: Archlinux, Debian, RedHat, Void, Gentoo
3. **Build package list** — aggregates 16 category lists plus `packages_distro[os_family]` into `packages_all`
4. **OS-specific install** (`tasks/install-archlinux.yml` or `tasks/install-debian.yml`)
   - **Arch:** runs `pacman -Syu` (full upgrade, tagged `upgrade`) then installs `packages_all` via `ansible.builtin.package`. Both steps retry up to 3 times on transient mirror failures. Skipped when `packages_all` is empty.
   - **Debian/Ubuntu:** updates apt cache (`cache_valid_time: 3600`) then installs `packages_all` via `ansible.builtin.package`. Install retries up to 3 times. Skipped when `packages_all` is empty.
5. **Verify** (`tasks/verify.yml`) — gathers `package_facts` and asserts every package in `packages_all` is present; skipped when `packages_all` is empty
6. **Report** — calls `common/report_phase.yml` and `common/report_render.yml` to emit a structured execution table (skipped via `--skip-tags report` in CI)

### Failure behavior

- **Step 2 (preflight):** hard fail with `fail_msg` listing supported OS families
- **Step 4 (install):** retries 3× with 5s delay; fails if all retries exhausted with the package manager's error message
- **Step 5 (verify):** fails with `fail_msg` naming the missing package and diagnostic commands to run

## Variables

### Configurable (`defaults/main.yml`)

Override via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `packages_enabled` | `true` | safe | Set `false` to skip this role entirely on a specific host |
| `packages_base` | `[]` | safe | Core CLI utilities (git, curl, htop, etc.) |
| `packages_editors` | `[]` | safe | Text editors and IDEs |
| `packages_docker` | `[]` | safe | Docker and container tools |
| `packages_xorg` | `[]` | safe | X.Org display server and drivers |
| `packages_wm` | `[]` | safe | Window manager and compositor |
| `packages_filemanager` | `[]` | safe | File manager tools |
| `packages_network` | `[]` | safe | Networking utilities |
| `packages_media` | `[]` | safe | Audio and video players |
| `packages_desktop` | `[]` | safe | Desktop environment extras |
| `packages_graphics` | `[]` | safe | Image viewers and graphics tools |
| `packages_session` | `[]` | safe | Session management and display managers |
| `packages_terminal` | `[]` | safe | Terminal emulators |
| `packages_fonts` | `[]` | safe | Fonts including Nerd Fonts |
| `packages_theming` | `[]` | safe | GTK/Qt themes and icon packs |
| `packages_search` | `[]` | safe | Search utilities (fzf, ripgrep) |
| `packages_viewers` | `[]` | safe | File viewers (bat, jq) |
| `packages_distro` | `{}` | safe | Distro-specific extras keyed by `os_family` (e.g. `Archlinux`, `Debian`) |
| `_packages_supported_os` | 5-entry list | internal | Do not change — defines the supported OS families for the preflight assert |

## Examples

### Installing packages on all hosts

```yaml
# In group_vars/all/packages.yml:
packages_base:
  - git
  - curl
  - htop
  - tmux

packages_editors:
  - vim
  - neovim

packages_search:
  - fzf
  - ripgrep

packages_distro:
  Archlinux:
    - base-devel
    - pacman-contrib
  Debian:
    - build-essential
```

### Disabling the role on a specific host

```yaml
# In host_vars/<hostname>/packages.yml:
packages_enabled: false
```

This skips all tasks including preflight and verification.

### Installing only base packages (minimal profile)

```yaml
# In host_vars/server01/packages.yml:
packages_base:
  - git
  - curl
  - tmux
# All other categories remain [] — role installs only packages_base
```

## Cross-platform details

| Aspect | Arch Linux | Debian / Ubuntu |
|--------|-----------|-----------------|
| Package manager | pacman (community.general.pacman for upgrade) | apt (ansible.builtin.apt for cache update) |
| Install module | `ansible.builtin.package` | `ansible.builtin.package` |
| System upgrade | `pacman -Syu` (tagged `upgrade`) | not performed by this role |
| Cache update | included in upgrade step | `apt update` with `cache_valid_time: 3600` |
| Package query | `pacman -Q <pkg>` | `dpkg-query -W -f='${Status}' <pkg>` |

## Logs

This role does not create log files. All output is written to Ansible stdout.

### Reading ansible output

| Output | Meaning |
|--------|---------|
| `packages verify passed: all N packages confirmed installed` | In-role verify succeeded |
| `FAILED! => {"msg": "Package 'X' is not installed..."}` | A package failed to install; see package manager error above |
| `packages -- Execution Report` table | Structured phase summary (skipped in CI via `--skip-tags report`) |
| `Retrying... attempt N of 3` | Transient mirror failure; role will retry automatically |

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at preflight with "OS family not supported" | `ansible -m setup <host> \| grep os_family` — check actual os_family value | Add the host to a supported distro or check if `ansible_facts['os_family']` returns unexpected value |
| Package install fails with "target not found" (Arch) | `pacman -Ss <pkg>` on host — package may not exist or name is wrong | Check exact package name in Arch repos; Arch names differ from Debian (e.g. `openssh` vs `openssh-client`) |
| Package install fails with "unable to locate package" (Ubuntu) | `apt-cache search <pkg>` on host — package may need a PPA or different name | Check Ubuntu package name; some Arch packages have no direct apt equivalent |
| Verify fails with "Package X not found in package facts" | `pacman -Q <pkg>` or `dpkg -l <pkg>` on host | Package manager installed it but `package_facts` module used different name format — check for epoch prefix (e.g. `1:vim`) |
| Idempotence failure: second converge shows `changed=1` | Look for which task changed — usually `pacman -Syu` when system has pending updates | Add `--skip-tags upgrade` to molecule options; the upgrade step is intentionally non-idempotent when updates are available |
| Role skips silently with no output | Check `packages_enabled` in host/group vars — may be `false` | Set `packages_enabled: true` or remove the override |

## Testing

Both scenarios required. Run Docker for fast feedback; Vagrant for cross-platform validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, task logic, or adding packages | Logic correctness, idempotence, Arch + Ubuntu full list + empty-list edge cases |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic or when Docker results are suspicious | Real VM, real package manager, Arch VM + Ubuntu VM |

### Success criteria

- All steps complete: `syntax → create → prepare → converge → idempotence → verify → destroy`
- Idempotence step: `changed=0` (second run changes nothing — upgrade is skipped via `--skip-tags upgrade`)
- Verify step: all assert tasks pass; final line shows `packages verify passed`
- No `FAILED` tasks in output

### What the tests verify

| Category | What is checked | Test requirement |
|----------|----------------|-----------------|
| Packages | Every package in `packages_all` is installed (`pacman -Q` / `dpkg-query`) | TEST-008 |
| Package facts | Every package present in `ansible_facts.packages` after `package_facts` gather | TEST-008 |
| Empty list edge case | Role completes without error when all package lists are `[]` | TEST-011 |
| Idempotence | Second converge run shows `changed=0` | TEST-007 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `target not found: <pkg>` (Arch) | Package name doesn't exist in pacman repos | Check exact name: `pacman -Ss <pkg>` |
| `Unable to locate package <pkg>` (Ubuntu) | Package not in apt repos | Check Ubuntu name: `apt-cache search <pkg>` |
| `idempotence: changed=1` on upgrade | Arch has pending updates between converge runs | Molecule uses `--skip-tags upgrade`; if still failing, check which task changed |
| `Package X not found in package facts` | `package_facts` module uses different name format | Known for packages with epoch prefix; investigate with `pacman -Qi <pkg>` |
| `Assertion failed: OS family not supported` | Molecule platform uses unexpected os_family | Check image: `ansible -m setup localhost \| grep os_family` |
| Vagrant: `Python not found` | Bootstrap in prepare.yml skipped | Run full sequence: `molecule test -s vagrant`, not just `converge` |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `packages` | Entire role | Full apply |
| `packages,install` | Build list + install step only | Re-install packages without re-running verify or report |
| `packages,install,upgrade` | System upgrade + install (Arch only) | Force full upgrade |
| `report` | Report tasks only | Re-generate execution report |

```bash
# Run only the install phase (skip report and verify)
ansible-playbook site.yml --tags packages,install --skip-tags report

# Skip system upgrade (install only new packages, no pacman -Syu)
ansible-playbook site.yml --tags packages --skip-tags upgrade,report
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings and supported OS list | No — override via inventory |
| `tasks/main.yml` | Execution orchestrator: preflight → build list → install → verify → report | When adding/removing steps |
| `tasks/install-archlinux.yml` | Arch-specific: system upgrade + package install | When changing Arch install behavior |
| `tasks/install-debian.yml` | Debian/Ubuntu-specific: cache update + package install | When changing Debian install behavior |
| `tasks/verify.yml` | In-role post-install verification via package_facts | When changing verification logic |
| `meta/main.yml` | Role metadata and galaxy info | When updating supported platforms |
| `molecule/docker/` | Docker CI scenario (Arch + Ubuntu + empty-list edge cases) | When changing CI test coverage |
| `molecule/vagrant/` | Vagrant cross-platform scenario (Arch VM + Ubuntu VM) | When changing full-system test coverage |
| `molecule/shared/converge.yml` | Shared converge playbook used by docker and vagrant | Rarely |
| `molecule/shared/verify.yml` | Shared molecule verify playbook | When changing verification assertions |
