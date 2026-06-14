# locale

Generates system locales and configures process locale defaults through `/etc/locale.conf`.

## Execution flow

1. **Validate** (`tasks/validate/main.yml`) — runs preflight validation from `tasks/validate/preflight.yml`, loads `vars/<os_family>/main.yml`, and records the validation phase.
2. **Generate locales** (`tasks/generate/main.yml`) — dispatches to `tasks/generate/<os_family>.yml` and records the generation phase.
3. **Verify generated locales** (`tasks/verify/main.yml`) — runs verification from `tasks/verify/glibc.yml` and records the verification phase.
4. **Configure system locale** (`tasks/configure/main.yml`) — deploys `/etc/locale.conf` through `tasks/configure/glibc.yml` and records the configuration phase.
5. **Report** (`tasks/report/main.yml`) — renders the accumulated `_locale_phases` execution report.

### Handlers

This role has no handlers. Void Linux reconfiguration runs inline after `/etc/default/libc-locales` changes so verification observes the new locale archive without flushing unrelated play handlers.

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory, not by editing `defaults/main.yml`.

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `locale_enabled` | `true` | safe | Set `false` to skip the role. |
| `locale_list` | `["en_US.UTF-8", "ru_RU.UTF-8"]` | careful | Locales to generate. Must include `locale_default` and every `LC_*` override value. |
| `locale_default` | `"en_US.UTF-8"` | careful | Value written as `LANG` in `/etc/locale.conf`. |
| `locale_lc_overrides` | `{}` | careful | Optional `LC_*` values written after `LANG`. Each value must also be in `locale_list`. |
| `_locale_supported_os` | five project OS families | internal | ROLE-003 support list. Do not override from inventory. |

### Internal mappings (`vars/`)

| File | What it contains | When to edit |
|------|------------------|--------------|
| `vars/archlinux/main.yml` | Config path and Arch generation task | Changing Arch locale behavior |
| `vars/debian/main.yml` | Config path and Debian generation task | Changing Ubuntu/Debian locale behavior |
| `vars/redhat/main.yml` | Config path and RedHat generation task | Changing Fedora/RedHat locale behavior |
| `vars/void/main.yml` | Config path and Void generation task | Changing Void locale behavior |
| `vars/gentoo/main.yml` | Config path and Gentoo generation task | Changing Gentoo locale behavior |

## Examples

### Configure English default with Russian date/time

```yaml
# inventory/group_vars/all/system.yml
locale_list:
  - "en_US.UTF-8"
  - "ru_RU.UTF-8"
locale_default: "en_US.UTF-8"
locale_lc_overrides:
  LC_TIME: "ru_RU.UTF-8"
  LC_MONETARY: "ru_RU.UTF-8"
```

### Disable locale management on one host

```yaml
# inventory/host_vars/<hostname>.yml
locale_enabled: false
```

## Cross-platform details

| Aspect | Arch Linux | Ubuntu/Debian | Fedora/RedHat | Void Linux | Gentoo |
|--------|------------|---------------|---------------|------------|--------|
| Config path | `/etc/locale.conf` | `/etc/locale.conf` | `/etc/locale.conf` | `/etc/locale.conf` | `/etc/locale.conf` |
| Generation method | `/etc/locale.gen` + `locale-gen` | `community.general.locale_gen` | `glibc-langpack-*` packages | `/etc/default/libc-locales` + `xbps-reconfigure` | `/etc/locale.gen` + `locale-gen` |
| Verification | `locale -a` | `locale -a` | `locale -a` | `locale -a` | `locale -a` |

## Logs

This role does not create log files. Locale generation errors surface in the Ansible task output. For system-level locale behavior, inspect `/etc/locale.conf` and run `locale` with the environment values sourced from that file.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails during Validate | Read the assert `fail_msg` | Ensure `locale_list` is non-empty and contains `locale_default` plus all override values. |
| Requested locale is missing after Generate | Run `locale -a` | Check the OS task file under `tasks/generate/` and confirm the locale name matches distro syntax. |
| `/etc/locale.conf` was not updated | Check whether Verify failed before Configure | Fix locale generation first; configure intentionally runs only after verify passes. |
| Ubuntu rejects a locale in Molecule | Check `/usr/share/i18n/SUPPORTED` in prepare output | Add the locale entry to scenario prepare data or use a supported locale name. |
| Void locale remains unavailable | Run `xbps-reconfigure -f glibc-locales` manually for diagnosis | Fix `/etc/default/libc-locales` content or package state; the role runs reconfigure only after file changes. |

## Testing

Project rules require VM execution through the host-side workflow for real runs. From the role directory, the defined scenarios are:

| Scenario | Command | What it tests |
|----------|---------|---------------|
| `default` | `molecule test -s default` | Local delegated smoke path and idempotence spelling. |
| `docker` | `molecule test -s docker` | Arch and Ubuntu container feedback. |
| `vagrant` | `molecule test -s vagrant` | Arch and Ubuntu VM integration. |
| `validation` | `molecule test -s validation` | Fail-fast validation for invalid public inputs. |

### Success criteria

- `syntax`, `converge`, `idempotence`, and `verify` complete.
- Second converge reports zero changes.
- Verify confirms config file content, permissions, generated locales, and functional `locale` output.

## Tags

| Tag | What it runs | Use case |
|-----|--------------|----------|
| `locale` | All role tasks | Full locale apply. |
| `report` | Report phase/render tasks | Execution report output. |

Example:

```bash
task workstation -- --tags locale
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | Public role inputs and supported OS list | No, override public values via inventory |
| `vars/<os_family>/main.yml` | Config path and generation task per OS family | Only when changing platform behavior |
| `tasks/main.yml` | Role flow router | When adding/removing phases |
| `tasks/validate/` | Validate phase tasks | When validate phase flow or public API checks change |
| `tasks/generate/` | OS-specific locale generation | When changing distro generation behavior |
| `tasks/verify/` | In-role generation verification | When changing verification logic |
| `tasks/configure/` | `/etc/locale.conf` deployment | When changing config deployment |
| `tasks/report/` | Report phase tasks and row helper | When report wiring changes |
| `templates/locale.conf.j2` | Rendered locale config | When changing file content |
| `molecule/` | Scenario definitions and verification | When changing test coverage |

## License

MIT
