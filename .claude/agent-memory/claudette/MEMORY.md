# Claudette Agent Memory - Bootstrap Project

## Project Structure
- Ansible roles at `ansible/roles/`
- Docker role is the base pattern for all container-based roles
- Molecule tests use `default` driver with localhost, vault password from `vault-pass.sh`
- All remote execution via SSH scripts (`scripts/ssh-run.sh`, `scripts/ssh-scp-to.sh`)

## Ansible Role Patterns
- Comments in Russian, section headers: `# ---- Описание ----`
- Top-of-file header: `# === Название роли ===`
- Variable prefix matches role name: `docker_*`, `caddy_*`
- Tags: role name + functional tags like `configure`, `service`
- FQCN for all modules: `ansible.builtin.file`, `community.docker.docker_network`
- Handlers use `listen:` for cross-role notification
- meta/main.yml: `dependencies:` as list (not `[]` unless empty)
- molecule/default/molecule.yml: exact copy pattern from docker role
- verify.yml: `_rolename_verify_*` register variable naming convention

## Caddy Role (created 2026-02-09)
- Reverse proxy for all self-hosted services
- Depends on docker role
- TLS modes: "internal" (self-signed) or "acme" (Let's Encrypt)
- Docker network "proxy" for service connectivity
- Site configs imported from `/etc/caddy/sites/*.caddy`

## ntp_audit Role - Research Findings (2026-02-21)

Role location: `ansible/roles/ntp_audit/`
Templates: ntp-audit.sh.j2, alloy-ntp-audit.alloy.j2, loki-ntp-audit-rules.yaml.j2, ntp-audit.service.j2, ntp-audit.timer.j2

### Known Bug: Offset Sign Lost
- `ntp-audit.sh.j2` uses `awk '/System time/ {print $4}'` which drops the "slow"/"fast" suffix
- `ntp_offset_s` field contains unsigned magnitude only - Loki alert `| float > 0.1` misses negative offsets
- Fix: use `chronyc -c tracking` (CSV mode, available since chrony 3.3) - field 5 is signed offset in seconds

### Canonical NTP Metrics (industry standard, all in seconds)
- system_time / sys_offset (signed) - our field ntp_offset_s (BUGGY - unsigned)
- last_offset (signed) - MISSING from our JSON
- rms_offset - MISSING from our JSON
- root_delay - MISSING from our JSON
- root_dispersion - MISSING from our JSON
- skew_ppm - MISSING from our JSON
- frequency_ppm - our field ntp_freq_error_ppm (OK)
- stratum (int) - our field ntp_stratum (OK)
- reference_id (string) - our field ntp_reference (OK)
- leap_status / sync_status - our field ntp_sync_status (OK)

### Production Alert Thresholds (consensus)
- Offset WARNING: 10ms (0.01s) - ntpmon default, RFC 8633 basis
- Offset CRITICAL: 50ms (0.05s) - ntpmon default, RFC 8633 basis; our default is 100ms (lenient)
- Sync loss CRITICAL: 2-5 min; our NtpUnsynchronised is 15min+5min (too long)
- Stratum > 4: warning (our setting OK for VM environments)
- Stratum alert in isolation considered unreliable by community

### Python-chrony: No mature library exists
- All Python tools shell out to chronyc (ntpmon, nagios-plugin-chrony, Diamond collector)
- libchrony: official C library (GitLab gitlab.com/chrony/libchrony, 2023, no Python bindings)
- Use `chronyc -c tracking` CSV mode for robust parsing instead of awk

### PHC Monitoring Gap
- Current check: device presence only ([ -c /dev/ptp0 ])
- Missing: verify chrony actually uses PHC as source (chronyc sources shows #* prefix)

### No Dedicated NTP Audit Ansible Roles Exist
- All Galaxy roles are config-only; no role combines audit script + structured log + Alloy/Loki pipeline
- Our role is architecturally unique in this space

### Key External Tools for Reference
- chrony_exporter (SuperQ): metric chrony_tracking_last_offset_seconds (signed seconds)
- Telegraf chrony plugin: measurement "chrony", stratum as tag, all offsets as float seconds
- awesome-prometheus-alerts: HostClockSkew threshold +-0.05s / HostClockNotSynchronising sync_status==0 for 2min
- ntpmon (paulgear): WARN>=10ms CRIT>=50ms, RFC 8633 basis, shells out to chronyc

## Ansible Playbook & Role Architecture (2026-02-21)

### Playbook Organization
**File:** `ansible/playbooks/workstation.yml`
- All roles in one playbook, ordered by dependencies and phases
- Role execution ordered by setup sequence (system foundations → packages → services → UI)
- Tags enable selective execution: `task workstation -- --tags "packages,docker"`
- Becomes `true` (sudo) for entire playbook

**Phase 1: System Foundation (before packages)**
- timezone, locale, hostname, hostctl, vconsole, ntp, ntp_audit
- **package_manager** runs HERE (line 51) BEFORE reflector/yay/packages
- pam_hardening, vm

**Phase 1.5: Hardware & Kernel**
- gpu_drivers, sysctl, power_management

**Phase 2: Package Infrastructure (after system, before yay)**
- **yay** runs here (line 75)
- **packages** runs here (line 79)

**Phase 3-7:** User setup, dev tools, services, UI, dotfiles

### Playbook Mirrors
**File:** `ansible/playbooks/mirrors-update.yml`
- Standalone playbook: hosts localhost, connection local, become true
- Runs ONLY: reflector role

### Package Manager Role (pacman/apt/dnf/xbps)
**Location:** `ansible/roles/package_manager/`

**meta/main.yml pattern:**
```yaml
galaxy_info:
  role_name: package_manager
  author: textyre
  description: Конфигурация пакетного менеджера (pacman, apt, dnf, xbps)
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
    - name: Ubuntu
      versions: [all]
    - name: Fedora
      versions: [all]
    - name: Void Linux
      versions: [all]
  galaxy_tags: [packages, pacman, apt, dnf, xbps, system]
dependencies: []
```

**defaults/main.yml pattern:**
- All variables have `pkgmgr_` prefix
- Distro-specific sections (Arch, Debian, Ubuntu, Fedora, Void)
- For Arch: `pkgmgr_pacman_parallel_downloads`, `pkgmgr_paccache_enabled`, `pkgmgr_makepkg_enabled`
- For Debian: `pkgmgr_apt_parallel_queue_mode`, `pkgmgr_apt_retries`
- For Fedora: `pkgmgr_dnf_parallel_downloads`, `pkgmgr_dnf_fastestmirror`
- For Void: `pkgmgr_xbps_cache_cleanup_enabled`

**tasks/main.yml pattern:**
- Include distribution-specific tasks via: `include_tasks: "{{ ansible_distribution | lower }}.yml"`
- Conditional: `when: ansible_distribution in _pkgmgr_supported_distributions`
- Supports task files: `tasks/archlinux.yml`, `tasks/debian.yml`, `tasks/ubuntu.yml`, `tasks/fedora.yml`, `tasks/void.yml`
- Nested subtask files for OS-specific config (e.g., `archlinux/pacman.yml`, `archlinux/paccache.yml`)

**molecule/default/ tests:**
- molecule.yml: no vault requirement (unlike yay/reflector), simple driver config
- converge.yml: assert os_family==Archlinux (Arch-specific test role)
- verify.yml: check pacman.conf markers, paccache.timer, makepkg.conf existence

### Reflector Role (mirrors)
**Location:** `ansible/roles/reflector/`

**meta/main.yml pattern:**
```yaml
galaxy_info:
  role_name: reflector
  author: textyre
  description: Настройка и запуск reflector для обновления зеркал Arch Linux
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
  galaxy_tags: [archlinux, mirrors, reflector, pacman]
dependencies: []
```

**defaults/main.yml:**
- All variables have `reflector_` prefix
- Config values: `reflector_countries`, `reflector_protocol`, `reflector_latest`, `reflector_sort`, `reflector_age`
- Timer: `reflector_timer_schedule`
- Paths: `reflector_conf_path`, `reflector_mirrorlist_path`
- Execution: `reflector_backup_mirrorlist`, `reflector_retries`, timeouts, proxy

**molecule test pattern:**
- molecule.yml: vault_password_file required, callbacks_enabled: profile_tasks
- converge.yml: assert os==Archlinux, load vault.yml, apply reflector role
- verify.yml: check package installed, .conf exists, timer enabled/active, mirrorlist has servers
- test_sequence: syntax → converge → verify (NO idempotence check in reflector)

### Yay Role (AUR helper)
**Location:** `ansible/roles/yay/`

**meta/main.yml pattern:**
```yaml
galaxy_info:
  role_name: yay
  author: textyre
  description: Сборка и установка yay AUR helper из исходников
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
  galaxy_tags: [archlinux, aur, yay]
dependencies: []
```

**defaults/main.yml:**
- `yay_aur_url`, `yay_build_user`, `yay_build_deps` (base-devel, git, go)
- Also declares `packages_aur`, `packages_aur_remove_conflicts` (noqa: var-naming)

**tasks/main.yml:**
```yaml
# Order:
- assert os==Archlinux
- include_tasks: install-yay-binary.yml
- include_tasks: configure-sudoers.yml
- include_tasks: install-aur-packages.yml (when packages_aur | length > 0)
```

**tasks/install-yay-binary.yml:**
- Check if yay exists (yay --version)
- Install yay_build_deps
- Create temp dir as yay_build_user
- Git clone yay AUR repo
- makepkg, find .pkg.tar.*, install via pacman, cleanup

**tasks/install-aur-packages.yml:**
- Build combined official package list (for conflict validation)
- Remove conflicting packages
- Validate AUR packages via `validate-aur-conflicts.sh` script
- Install via kewlfft.aur.aur module (backend: yay)

**molecule test pattern:**
- molecule.yml: vault required, variables in group_vars section
- converge.yml: assert os==Archlinux, load vault, apply yay role
- verify.yml: check build deps, yay binary, temp dirs cleaned, sudoers file, AUR packages installed
- test_sequence: syntax → converge → **idempotence** → verify (HAS idempotence!)

### Packages Role (meta-installer)
**Location:** `ansible/roles/packages/`

**meta/main.yml pattern:**
```yaml
galaxy_info:
  role_name: packages
  author: textyre
  description: Установка пакетов рабочей станции (pacman, apt, AUR)
  license: MIT
  min_ansible_version: "2.15"
  platforms:
    - name: ArchLinux
      versions: [all]
    - name: Debian
      versions: [all]
  galaxy_tags: [packages, pacman, apt, workstation]
dependencies: []
```

**defaults/main.yml:**
- All variables `packages_*`: packages_base, packages_editors, packages_docker, packages_xorg, packages_wm, packages_filemanager, packages_network, packages_media, packages_desktop, packages_graphics, packages_session, packages_terminal, packages_fonts, packages_theming, packages_search, packages_viewers
- Also `packages_distro: {}` (dict keyed by os_family)

**tasks/main.yml:**
- Full system upgrade: `pacman: update_cache=true, upgrade=true` (Arch-specific when clause)
- Build combined package list from all packages_* variables
- Include distribution-specific install: `install-{{ ansible_distribution | lower }}.yml`
- Debug report

**molecule test pattern:**
- molecule.yml: HAS dependency section (galaxy: requirements.yml), group_vars with packages_base/editors/etc
- test_sequence: dependency → syntax → converge → **idempotence** → verify → create_sequence/check_sequence
- converge.yml: simple role apply
- verify.yml: build combined list, verify each package installed (pacman -Q for Arch, dpkg -l for Debian)

### Inventory Structure
**File:** `ansible/inventory/hosts.ini` / `hosts.yml`
- Single group: `[workstations]`
- localhost with ansible_connection=local, ansible_python_interpreter=/usr/bin/python3

**ansible.cfg:**
- roles_path = roles:playbooks/roles:~/.ansible/roles:/usr/share/ansible/roles
- inventory = inventory/hosts.yml
- stdout_callback = pretty
- vault_password_file = vault-pass.sh
- ARA callback enabled (ara_default)

### Taskfile.yml Runner (Task automation)
**Key tasks:**
- `bootstrap`: setup venv + galaxy requirements
- `check`: syntax check on workstation.yml + mirrors-update.yml
- `lint`: ansible-lint on playbooks/ + roles/
- `test`: full test suite (check + lint + all role molecule tests)
- Individual role tests: `test-reflector`, `test-yay`, `test-packages`, etc.
- `run` / `workstation`: execute playbook with confirmation prompt
- `vault-create`, `vault-edit`, `vault-view`: Ansible Vault management

Each test task:
- deps: [_ensure-venv, _check-vault]
- dir: ansible/roles/{role}
- env: MOLECULE_PROJECT_DIRECTORY=${TASKFILE_DIR}/ansible
- runs: molecule test

### Key Dependencies & Sequencing Rules
1. **package_manager** runs FIRST in Phase 1 (before any package install)
2. **reflector** runs in Phase 1.5 (after package_manager, BEFORE yay/packages for faster mirrors)
3. **yay** runs in Phase 2 (depends on reflector for fast AUR downloads)
4. **packages** runs in Phase 2 (depends on yay if AUR packages needed)
5. Only **reflector** has direct "mirrors-update.yml" playbook (standalone use case)

### Design Patterns for New Roles
1. **meta/main.yml**: always include galaxy_info, author, description, license, min_ansible_version, platforms, galaxy_tags; dependencies: [] if no deps
2. **defaults/main.yml**: variable prefix = role name (e.g., myrole_var), all settings documented
3. **tasks/main.yml**: assert, include_tasks, tags
4. **molecule/default/molecule.yml**: driver (default, managed: false), provisioner with vault/callbacks, verifier (ansible), test_sequence
5. **molecule/default/converge.yml**: name+hosts+become+gather_facts, assert os if needed, load vault.yml, apply role
6. **molecule/default/verify.yml**: check role effects via package/file/command checks, use _rolename_verify_* for registers
7. **Tags**: consistent across playbook + roles (e.g., packages, mirrors, aur, install)
8. **Idempotence**: include in test_sequence if role is idempotent; skip if one-time install (reflector omits it)
