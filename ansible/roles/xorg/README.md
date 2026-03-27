# xorg

Deploys Xorg configuration files into `/etc/X11/xorg.conf.d/` from managed dotfiles already present on the target host.

## Execution flow

1. **Gate role** (`tasks/main.yml`) — skips the role entirely when `xorg_enabled: false`.
2. **Validate platform** (`tasks/main.yml`) — fails immediately if `ansible_facts['os_family']` is not one of the five supported families.
3. **Load OS mappings** (`vars/archlinux.yml`, `vars/debian.yml`, `vars/redhat.yml`, `vars/void.yml`, `vars/gentoo.yml`) — resolves internal platform metadata such as the target config directory.
4. **Dispatch OS-specific tasks** (`tasks/archlinux.yml`, `tasks/debian.yml`, `tasks/redhat.yml`, `tasks/void.yml`, `tasks/gentoo.yml`) — each file calls the shared deploy logic so support can extend one platform without touching all others.
5. **Resolve source directory** (`tasks/configure.yml`) — checks `xorg_source_dir` on the managed host. Fails if the directory is missing or not a directory.
6. **Create config directories** (`tasks/configure.yml`) — ensures parent directories for every target file exist as `root:root` with mode `0755`.
7. **Deploy config files** (`tasks/configure.yml`) — copies every file from `xorg_system_files` with `remote_src: true` into `/etc/X11/xorg.conf.d/`.
8. **Report deploy phase** (`tasks/main.yml`) — writes a compact execution row via `common/report_phase.yml`.
9. **Verify result** (`tasks/verify.yml`) — checks directory ownership/mode, file ownership/mode, required X11 stanza content, and file count. Fails if deployed state does not match configuration.
10. **Render execution report** (`tasks/main.yml`) — prints the final report table via `common/report_render.yml`.

### Handlers

This role has no handlers. It only deploys static Xorg configuration files and does not restart services.

## Variables

### Configurable (`defaults/main.yml`)

Override these in inventory or playbook vars. Do not edit `defaults/main.yml` directly.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `xorg_enabled` | `true` | safe | Set `false` to skip this role completely. |
| `xorg_supported_os` | `['Archlinux', 'Debian', 'RedHat', 'Void', 'Gentoo']` | internal | Allowed OS families. Change only if project support policy changes. |
| `xorg_source_dir` | `{{ dotfiles_base_dir \| default(lookup('env', 'REPO_ROOT') ~ '/dotfiles', true) }}` | careful | Absolute path to dotfiles on the managed host. Wrong value makes the role fail before deployment. |
| `xorg_system_files` | 2 file descriptors | careful | List of `{src, dest, owner, group, mode}` objects to deploy. Wrong paths or modes lead to broken Xorg config or misplaced files. |

### Internal mappings (`vars/`)

These files are role internals. Edit them only when changing platform support.

| File | What it contains | When to edit |
|------|------------------|--------------|
| `vars/archlinux.yml` | Arch Linux mapping for Xorg config directory and platform label | When Arch-specific Xorg paths diverge |
| `vars/debian.yml` | Debian/Ubuntu mapping for Xorg config directory and platform label | When Debian-family paths diverge |
| `vars/redhat.yml` | Fedora/RedHat mapping for Xorg config directory and platform label | When RedHat-family paths diverge |
| `vars/void.yml` | Void Linux mapping for Xorg config directory and platform label | When Void-specific paths diverge |
| `vars/gentoo.yml` | Gentoo mapping for Xorg config directory and platform label | When Gentoo-specific paths diverge |

## Examples

### Use repo dotfiles copied to the target host

```yaml
# In host_vars/workstation/xorg.yml:
xorg_source_dir: "/home/textyre/bootstrap/dotfiles"
```

Use this when the repository is already synced to the managed host and the role should read from that checkout.

### Deploy an alternate monitor profile

```yaml
# In host_vars/workstation/xorg.yml:
xorg_system_files:
  - src: "etc/X11/xorg.conf.d/00-keyboard.conf"
    dest: "/etc/X11/xorg.conf.d/00-keyboard.conf"
    owner: root
    group: root
    mode: "0644"
  - src: "etc/X11/xorg.conf.d/20-monitor-office.conf"
    dest: "/etc/X11/xorg.conf.d/20-monitor-office.conf"
    owner: root
    group: root
    mode: "0644"
```

Use this when a host needs a different monitor file name or profile while keeping the same deployment mechanism.

### Disable the role on a headless host

```yaml
# In host_vars/server/xorg.yml:
xorg_enabled: false
```

Use this on systems without Xorg where the role should be skipped cleanly.

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RedHat | Void Linux | Gentoo |
|--------|------------|-----------------|-----------------|------------|--------|
| OS family fact | `Archlinux` | `Debian` | `RedHat` | `Void` | `Gentoo` |
| Config directory | `/etc/X11/xorg.conf.d` | `/etc/X11/xorg.conf.d` | `/etc/X11/xorg.conf.d` | `/etc/X11/xorg.conf.d` | `/etc/X11/xorg.conf.d` |
| Files deployed by default | `00-keyboard.conf`, `10-monitor.conf` | `00-keyboard.conf`, `10-monitor.conf` | `00-keyboard.conf`, `10-monitor.conf` | `00-keyboard.conf`, `10-monitor.conf` | `00-keyboard.conf`, `10-monitor.conf` |
| Service managed by role | none | none | none | none | none |

## Logs

This role does not create dedicated log files and does not configure log rotation.

### Log files

| File | Path | Contents | Rotation |
|------|------|----------|----------|
| Ansible task output | playbook stdout/stderr | File copy results, assert failures, execution report | Controlled by your shell/CI system |
| System journal | `journalctl -b` | Xorg or display manager startup errors after the next login/boot | system journal rotation |
| Xorg runtime log | `/var/log/Xorg.0.log` or display-manager-owned log path | Xorg parsing errors, monitor detection, driver selection | distro/display-manager dependent |

### Reading the logs

- Xorg syntax or parsing problem: `grep -E 'EE|WW' /var/log/Xorg.0.log`
- Boot/session issue after deploying config: `journalctl -b | grep -Ei 'xorg|display|lightdm|sddm|gdm'`

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at source directory check | `ls -ld <xorg_source_dir>` on the managed host | Point `xorg_source_dir` to an existing dotfiles checkout or sync dotfiles first |
| Role fails with "OS family is not supported" | `ansible -m setup <host> -a 'filter=ansible_os_family'` | Run only on Archlinux, Debian, RedHat, Void, or Gentoo families |
| Xorg ignores the deployed files | `ls -l /etc/X11/xorg.conf.d/` and `grep -E 'InputClass|Monitor' /etc/X11/xorg.conf.d/*.conf` | Confirm filenames and paths in `xorg_system_files`; keep them under `/etc/X11/xorg.conf.d/` |
| Black screen or wrong resolution after reboot | `grep -E 'EE|WW' /var/log/Xorg.0.log` | Revert the broken monitor file, validate the modeline, and deploy a corrected `10-monitor.conf` |
| Keyboard layout does not switch | `grep Xkb /etc/X11/xorg.conf.d/00-keyboard.conf` | Check `Option "XkbLayout"` and `Option "XkbOptions"` in the source file, then rerun the role |

## Testing

Both mandatory scenarios are present. Use the fast scenario for quick config validation and Vagrant for cross-platform confidence.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Default (fast localhost) | `molecule test` | After changing copy logic, verify logic, or README-linked examples | Converge, idempotence, verify, negative path for missing `xorg_source_dir` |
| Docker (isolated Arch) | `molecule test -s docker` | After changing file deployment behavior in a clean systemd container | Isolated config deployment, permissions, file content assertions |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS dispatch, paths, or supported platform logic | Arch + Ubuntu VMs, prepare/bootstrap, shared converge/verify flow |

### Success criteria

- All steps in the selected scenario complete without `failed` tasks
- Idempotence reports `changed=0` on the second run
- Verify assertions pass for directory mode, file modes, required X11 content, and file count
- Negative test confirms the role rejects a missing `xorg_source_dir`

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Config directories | `/etc/X11/xorg.conf.d` exists as `root:root 0755` | TEST-008 |
| Config files | `00-keyboard.conf` and `10-monitor.conf` exist with `0644` | TEST-008 |
| Content | `XkbLayout`, `Monitor`, `Device`, `Screen`, `Modeline` are present | TEST-008 |
| Idempotence | Second converge makes no changes | TEST-008 |
| Validation failure | Missing source directory is rejected with a clear message | TEST-014 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `Role should have rejected missing xorg_source_dir` | Validation stopped working | Check `tasks/configure.yml` assert and the negative block in `molecule/shared/converge.yml` |
| `Expected 2 files ... found 1` | Fixture dotfiles incomplete | Rebuild the fixture in `prepare.yml` and rerun the scenario |
| `missing Monitor/Device/Screen directives` | Test fixture or source file lost required Xorg sections | Compare fixture content with expected monitor structure and restore missing stanza |
| `OS family ... is not supported` in Vagrant | Platform box reports unexpected `ansible_os_family` or dispatch files missing | Verify `vars/*.yml` and `tasks/*.yml` exist for every supported family |
| Vagrant `Python not found` or bootstrap failure | Guest not prepared before gather_facts-sensitive tasks | Check `molecule/vagrant/prepare.yml` and rerun `molecule test -s vagrant` |

## Tags

| Tag | What it runs | Use case |
|-----|--------------|----------|
| `xorg` | Entire role, including deploy, verify, and reporting | Full configuration apply |
| `display` | Directory and file deployment tasks | Re-deploy config files without focusing on reporting |
| `report` | Execution report tasks only | Re-render the final execution report table |

Example: `ansible-playbook playbooks/workstation.yml --tags xorg`

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | Public role variables and supported OS list | No, override via inventory unless support policy changes |
| `vars/*.yml` | Per-OS internal mappings | Only when platform-specific paths diverge |
| `tasks/main.yml` | Main orchestration flow | Yes, when adding/removing phases |
| `tasks/configure.yml` | Shared deployment logic | Yes, when changing how files are copied |
| `tasks/verify.yml` | Post-deploy self-checks and verify reporting | Yes, when changing verification behavior |
| `tasks/archlinux.yml` etc. | OS-specific dispatch entrypoints | Only when one family needs custom behavior |
| `meta/main.yml` | Galaxy metadata and supported platforms | Rarely |
| `molecule/shared/` | Shared converge and verify playbooks | Yes, when expanding test coverage |
| `molecule/default/`, `molecule/docker/`, `molecule/vagrant/` | Scenario definitions | Yes, when changing how tests run |
