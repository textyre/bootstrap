# sysctl

Configures Linux kernel parameters for exploit hardening, network attack surface reduction, and workstation performance tuning.

## Execution flow

1. **Assert OS support** -- fails immediately if `ansible_facts['os_family']` is not in the supported list (Archlinux, Debian, RedHat, Void, Gentoo)
2. **Install packages** (`tasks/packages.yml`) -- installs `procps-ng` (Arch/Void/Gentoo) or `procps` (Debian/RedHat) via `ansible.builtin.package`
3. **Manage services** (`tasks/services.yml`) -- disables `apport.service` on Debian/Ubuntu if `sysctl_fs_suid_dumpable != 2` (apport overwrites this value after boot). Logs outcome if service not found.
4. **Deploy configuration** (`tasks/deploy.yml`) -- creates `/etc/sysctl.d/` directory, deploys `/etc/sysctl.d/99-z-ansible.conf` from template. **Triggers handler:** if config changed, `sysctl -e -p` reloads parameters before verification.
5. **Verify parameters** (`tasks/verify.yml`) -- reads 14 key security parameters via `sysctl -n`, reports OK / MISMATCH / NOT SUPPORTED / ERROR for each
6. **Report** (`tasks/report.yml`) -- writes structured execution report via `common/report_phase` + `report_render`

### Handlers

| Handler | Triggered by | What it does |
|---------|-------------|-------------|
| `reload sysctl` | Config file change (step 4) | Runs `sysctl -e -p /etc/sysctl.d/99-z-ansible.conf`. Skipped in Docker (kernel params read-only). |

## Variables

### Configurable (`defaults/main.yml`)

Override these via inventory (`group_vars/` or `host_vars/`), never edit `defaults/main.yml` directly.

#### Feature toggles

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `sysctl_security_enabled` | `true` | safe | Master switch for all security parameters |
| `sysctl_security_kernel_hardening` | `true` | safe | Kernel: ASLR, kptr_restrict, eBPF, ptrace, mmap_min_addr |
| `sysctl_security_network_hardening` | `true` | safe | Network: ARP, ICMP, TCP, rp_filter, IPv6 |
| `sysctl_security_filesystem_hardening` | `true` | safe | FS: hardlink/symlink/FIFO/SUID protection |
| `sysctl_security_ipv6_disable` | `false` | careful | Fully disable IPv6. Breaks DNS fallback, Docker networking, Happy Eyeballs |

#### Performance

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `sysctl_vm_swappiness` | `10` | safe | Swap aggressiveness. Security: `1`, Performance: `10-60` |
| `sysctl_vm_vfs_cache_pressure` | `50` | safe | Cache eviction pressure |
| `sysctl_vm_dirty_ratio` | `10` | safe | Dirty page flush threshold (%). For media servers: `20-40` |
| `sysctl_vm_dirty_background_ratio` | `5` | safe | Background flush start (%) |
| `sysctl_fs_inotify_max_user_watches` | `524288` | safe | inotify watch limit (for IDEs, file watchers) |
| `sysctl_fs_inotify_max_user_instances` | `1024` | safe | Max inotify instances per user |
| `sysctl_fs_file_max` | `2097152` | safe | System open file descriptor limit |
| `sysctl_net_core_somaxconn` | `4096` | safe | TCP connection backlog (for dev servers and Docker) |
| `sysctl_net_ipv4_tcp_fastopen` | `3` | safe | TCP Fast Open (0=off, 1=client, 2=server, 3=both) |
| `sysctl_net_ipv4_tcp_tw_reuse` | `0` | careful | TIME_WAIT socket reuse. **Must be 0 when `tcp_timestamps=0`** |

#### Security: Kernel

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `sysctl_kernel_randomize_va_space` | `2` | internal | ASLR level (2=full). Do not lower below 2 |
| `sysctl_kernel_kptr_restrict` | `2` | internal | Kernel pointer restriction (2=always hidden) |
| `sysctl_kernel_dmesg_restrict` | `1` | internal | Block unprivileged dmesg |
| `sysctl_kernel_yama_ptrace_scope` | `1` (profile-aware) | careful | ptrace scope. 0=gaming (Wine/Proton), 1=dev (gdb ./app), 2=security (root only). Auto-set by `workstation_profiles` |
| `sysctl_kernel_perf_event_paranoid` | `3` | internal | perf event access (3=kernel-only). Spectre mitigation |
| `sysctl_kernel_unprivileged_bpf_disabled` | `1` | internal | Block unprivileged bpf(). CVE-2021-3490, CVE-2022-23222 |
| `sysctl_kernel_tty_ldisc_autoload` | `0` | internal | Block TTY line discipline autoload. CVE-2017-2636 |
| `sysctl_vm_unprivileged_userfaultfd` | `0` | internal | Restrict userfaultfd() to CAP_SYS_PTRACE |
| `sysctl_vm_mmap_min_addr` | `65536` | internal | Minimum mmap address. Blocks null deref exploitation |
| `sysctl_kernel_unprivileged_userns_clone` | `1` | careful | Arch linux-hardened kernel only. Ignored on other kernels |

#### Security: Network

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `sysctl_net_core_bpf_jit_harden` | `2` | internal | BPF JIT hardening (2=all users) |
| `sysctl_net_ipv4_rp_filter` | `1` | careful | Reverse path filter. Applied to `conf.all` + `conf.default` (not wildcard). Docker hosts may need `rp_filter=2` on bridge interfaces |
| `sysctl_net_ipv4_tcp_syncookies` | `1` | internal | SYN cookies. Do not disable |
| `sysctl_net_ipv4_tcp_rfc1337` | `1` | internal | TIME_WAIT assassination protection |
| `sysctl_net_ipv4_accept_redirects` | `0` | internal | Block ICMP redirects |
| `sysctl_net_ipv4_send_redirects` | `0` | internal | Do not send ICMP redirects |
| `sysctl_net_ipv4_accept_source_route` | `0` | internal | Block IPv4 source routing |
| `sysctl_net_ipv4_log_martians` | `1` | safe | Log martian packets |
| `sysctl_net_ipv4_icmp_echo_ignore_broadcasts` | `1` | internal | Ignore broadcast ICMP echo (Smurf mitigation) |
| `sysctl_net_ipv4_icmp_ignore_bogus_error_responses` | `1` | internal | Ignore bogus ICMP errors |
| `sysctl_net_ipv4_tcp_timestamps` | `0` | careful | Disable TCP timestamps (uptime fingerprinting). Requires `tcp_tw_reuse=0` |
| `sysctl_net_ipv4_arp_filter` | `1` | careful | ARP interface filter |
| `sysctl_net_ipv4_arp_ignore` | `1` | careful | ARP reply scope. 1=safe for Docker/VM. 2=strict, breaks Docker bridge |
| `sysctl_net_ipv4_drop_gratuitous_arp` | `0` | careful | Drop gratuitous ARP. 1 breaks keepalived/VRRP HA |
| `sysctl_net_ipv6_accept_redirects` | `0` | internal | Block ICMPv6 redirects |
| `sysctl_net_ipv6_accept_source_route` | `0` | internal | Block IPv6 source routing |
| `sysctl_net_ipv6_accept_ra` | `1` | careful | Router Advertisements. 0 breaks SLAAC IPv6. Use 0 only with DHCPv6 stateful/static IPv6 |

#### Security: Filesystem

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `sysctl_fs_protected_hardlinks` | `1` | internal | Hardlink protection |
| `sysctl_fs_protected_symlinks` | `1` | internal | Symlink protection in sticky dirs |
| `sysctl_fs_protected_fifos` | `2` | internal | FIFO write protection in sticky dirs |
| `sysctl_fs_protected_regular` | `2` | internal | Regular file write protection in sticky dirs |
| `sysctl_fs_suid_dumpable` | `0` | internal | Prohibit SUID core dumps. CIS 1.6.4, DISA STIG V-230462 |

#### Custom parameters

| Variable | Default | Safety | Description |
|----------|---------|--------|-------------|
| `sysctl_custom_params` | `[]` | safe | Additional parameters: `[{name: "kernel.param", value: "1"}]` |

### Internal mappings (`vars/`)

These files contain cross-platform mappings. Do not override via inventory -- edit the files directly only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/main.yml` | `_sysctl_supported_os` bridge, `_sysctl_procps_package` per-OS package name | Adding support for a new distro |

## Examples

### Default hardened workstation

```yaml
# In your playbook:
- name: Harden kernel parameters
  hosts: all
  become: true
  gather_facts: true
  roles:
    - role: sysctl
```

### Developer workstation (via inventory)

```yaml
# In group_vars/all/sysctl.yml or host_vars/<hostname>/sysctl.yml:
sysctl_kernel_yama_ptrace_scope: 1       # allow gdb ./app (default for developer profile)
sysctl_net_ipv4_arp_ignore: 1            # less strict ARP in VM environments
sysctl_security_ipv6_disable: false      # keep IPv6 (default)
```

### Maximum security (server)

```yaml
# In group_vars/servers/sysctl.yml:
sysctl_vm_swappiness: 1                  # minimize sensitive data in swap
sysctl_kernel_yama_ptrace_scope: 2       # root-only ptrace
sysctl_security_ipv6_disable: true       # if no IPv6 connectivity
```

### Docker host with custom bridge settings

```yaml
# In host_vars/docker-host/sysctl.yml:
sysctl_custom_params:
  - { name: "net.ipv4.conf.docker0.rp_filter", value: "2" }
  - { name: "net.bridge.bridge-nf-call-iptables", value: "1" }
```

## What this role actually does

### Kernel hardening

| Parameter | Effect |
|---|---|
| `kernel.randomize_va_space = 2` | Full ASLR -- stack, heap, mmap, VDSO randomized. KSPP, DISA STIG |
| `kernel.kptr_restrict = 2` | Hide kernel addresses from `/proc/kallsyms`, `/proc/modules` |
| `kernel.dmesg_restrict = 1` | Block unprivileged dmesg access |
| `kernel.yama.ptrace_scope = 1` | ptrace restricted to child processes. `gdb ./app` works; `strace -p <pid>` on unrelated process does not |
| `kernel.perf_event_paranoid = 3` | Block perf counters for unprivileged users. Spectre mitigation (DISA STIG V-258076) |
| `kernel.unprivileged_bpf_disabled = 1` | Block `bpf()` without `CAP_BPF`. CVE-2021-3490, CVE-2022-23222 |
| `dev.tty.ldisc_autoload = 0` | Block TTY line discipline autoload. CVE-2017-2636 |
| `vm.unprivileged_userfaultfd = 0` | Restrict `userfaultfd()` to `CAP_SYS_PTRACE`. Heap spray mitigation |
| `vm.mmap_min_addr = 65536` | Prohibit mapping below 64K. Blocks null pointer dereference exploitation |

### Network hardening

| Parameter | Effect |
|---|---|
| `net.core.bpf_jit_harden = 2` | BPF JIT constant blinding for all users. JIT spray protection |
| `net.ipv4.conf.all.rp_filter = 1` | Reverse path filtering on all + default interfaces. Prevents IP spoofing (CVE-2019-14899) |
| `net.ipv4.tcp_syncookies = 1` | SYN cookie protection against SYN flood DDoS |
| `net.ipv4.tcp_rfc1337 = 1` | Protect TIME_WAIT sockets against RST attacks (RFC 1337) |
| `net.ipv4.conf.*.accept_redirects = 0` | Block ICMP redirects. Prevents traffic hijacking via MITM |
| `net.ipv4.conf.*.send_redirects = 0` | Do not send ICMP redirects |
| `net.ipv4.conf.*.accept_source_route = 0` | Block IPv4 source routing |
| `net.ipv4.conf.all.log_martians = 1` | Log packets with impossible addresses (reconnaissance detection) |
| `net.ipv4.icmp_echo_ignore_broadcasts = 1` | Ignore broadcast ICMP echo (Smurf DDoS mitigation) |
| `net.ipv4.tcp_timestamps = 0` | Hide uptime from fingerprinting. CIS 3.3.10. **Requires `tcp_tw_reuse = 0`** |
| `net.ipv4.conf.all.arp_filter = 1` | ARP: do not respond through the wrong interface |
| `net.ipv4.conf.all.arp_ignore = 1` | ARP: respond only if target IP belongs to receiving interface. Value `2` is stricter but breaks Docker/K8s/multi-IP VMs |
| `net.ipv4.conf.all.drop_gratuitous_arp = 0` | Do not drop gratuitous ARP (default). Value `1` blocks ARP cache poisoning but breaks keepalived/VRRP HA |
| `net.ipv6.conf.all.accept_redirects = 0` | Block ICMPv6 redirects |
| `net.ipv6.conf.all.accept_source_route = 0` | Block IPv6 source routing |
| `net.ipv6.conf.all.accept_ra = 1` | Accept IPv6 Router Advertisements (kernel default). Required for SLAAC. Set `0` only with DHCPv6 stateful or static IPv6 |

### Filesystem hardening

| Parameter | Effect |
|---|---|
| `fs.protected_hardlinks = 1` | Block hardlinks to files without read/write/ownership. TOCTOU mitigation |
| `fs.protected_symlinks = 1` | Block following symlinks in world-writable sticky directories |
| `fs.protected_fifos = 2` | Block writes to FIFOs in sticky directories without ownership |
| `fs.protected_regular = 2` | Block writes to regular files in sticky directories without ownership |
| `fs.suid_dumpable = 0` | Prohibit core dumps of SUID binaries. CIS 1.6.4, DISA STIG V-230462 |

### Performance

| Parameter | Purpose |
|---|---|
| `vm.swappiness = 10` | Minimize swap usage |
| `vm.vfs_cache_pressure = 50` | Reduce inode/dentry cache eviction |
| `vm.dirty_ratio = 10` | Force flush when dirty pages reach 10% of RAM |
| `vm.dirty_background_ratio = 5` | Start background flush at 5% dirty pages |
| `fs.inotify.max_user_watches = 524288` | For IDEs (VSCode, JetBrains) and file watchers |
| `fs.inotify.max_user_instances = 1024` | Max inotify instances per user |
| `fs.file-max = 2097152` | System-wide open file descriptor limit |
| `net.core.somaxconn = 4096` | TCP connection backlog |
| `net.ipv4.tcp_fastopen = 3` | TCP Fast Open on client and server |

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| Package | `procps-ng` | `procps` | `procps-ng` | `procps-ng` | `procps` |
| Config path | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` |
| Apport service | n/a | disabled if `suid_dumpable != 2` | n/a | n/a | n/a |
| `kernel.unprivileged_userns_clone` | linux-hardened only | absent | absent | absent | absent |
| Boot loader | `systemd-sysctl.service` | `systemd-sysctl.service` | `systemd-sysctl.service` | `sysctl` service (runit) | `sysctl` service (openrc) |

## Logs

### Log files

This role does not create its own log files. Kernel messages and sysctl behavior are logged through system logging.

| Source | How to read | Contents |
|--------|------------|----------|
| syslog / journald | `journalctl -k` | Kernel messages including martian packet logs (`log_martians=1`) |
| Ansible output | `ansible-playbook` stdout | Role execution report (install, configure, verify phases) |
| Verify output | Role verify task debug messages | OK / MISMATCH / NOT SUPPORTED / ERROR per parameter |

### Reading the logs

- Martian packet detection: `journalctl -k --grep="martian"` -- look for spoofed packets
- Sysctl load errors at boot: `journalctl -u systemd-sysctl` -- check for parameter rejection
- Role verify results: run with `--tags sysctl,verify` and check debug output

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in supported list | Check `ansible_facts['os_family']` -- must be Archlinux, Debian, RedHat, Void, or Gentoo |
| Verify shows MISMATCH for a parameter | Another sysctl.d file overrides our value after boot | Check `sysctl --system` output -- files are loaded alphabetically. Our `99-z-ansible.conf` should sort last. Remove conflicting files or rename them |
| `kernel.unprivileged_userns_clone` shows NOT SUPPORTED | Parameter exists only in Arch `linux-hardened` kernel | Expected on standard kernels. The `-e` flag silently skips it. No action needed |
| Docker containers cannot route traffic after role apply | `rp_filter=1` (strict) blocks Docker bridge | Add to `sysctl_custom_params`: `{name: "net.ipv4.conf.docker0.rp_filter", value: "2"}` |
| `gdb --pid` or `strace -p` fails with EPERM | `ptrace_scope=1` restricts to child processes only | For debugging: temporarily `echo 0 > /proc/sys/kernel/yama/ptrace_scope`. Or set `sysctl_kernel_yama_ptrace_scope: 0` for gaming profile |
| IPv6 connectivity lost after role apply | `sysctl_security_ipv6_disable: true` or `accept_ra: 0` | Set `sysctl_security_ipv6_disable: false` and `sysctl_net_ipv6_accept_ra: 1` (defaults) |
| apport keeps resetting `fs.suid_dumpable` to 2 | apport.service starts after systemd-sysctl | Role should disable apport automatically. Check `systemctl is-enabled apport` |
| Handler skipped in Docker | Sysctl params are read-only in containers | Expected behavior. Config file is still deployed; params apply on real boot |

## Testing

Both scenarios are required for every role (TEST-002). Run Docker for fast feedback, Vagrant for full validation.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Docker (fast) | `molecule test -s docker` | After changing variables, templates, or task logic | Config deployment, idempotence, file assertions (kernel params read-only in Docker) |
| Vagrant (cross-platform) | `molecule test -s vagrant` | After changing OS-specific logic or security params | Real sysctl values, boot persistence, Arch + Ubuntu matrix |

### Success criteria

- All steps complete: `syntax -> create -> prepare -> converge -> idempotence -> verify -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Verify step: all assertions pass with `success_msg` output
- Final line: no `failed` tasks

### What the tests verify

| Category | Examples | Test requirement |
|----------|----------|-----------------|
| Packages | procps-ng/procps installed via `package_facts` | TEST-008 |
| Config files | `/etc/sysctl.d/99-z-ansible.conf` exists, correct content, mode 0644, owned by root | TEST-008 |
| Services | apport disabled on Debian (when applicable) | TEST-008 |
| Runtime values | Live `sysctl -n` for 14 security + all performance params (Vagrant only) | TEST-008 |
| Permissions | Config file mode 0644, owner root:root | TEST-008 |
| Boot persistence | Reboot VM, re-verify all values survive systemd-sysctl reload (Vagrant only) | TEST-008 |
| Cross-platform | `kernel.unprivileged_userns_clone` checked on Arch only; procps-ng vs procps | TEST-013 |

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `procps-ng package not found` | Stale package cache in container | Rebuild: `molecule destroy && molecule test -s docker` |
| Idempotence failure on config deploy | Template produces different output on second run | Check for dynamic expressions in template (timestamps, random values) |
| `Assertion failed` on live value check | Parameter not applied (Docker) or another file overrides | Docker: expected (live checks skipped). Vagrant: check sysctl.d file ordering |
| Vagrant: `Python not found` on Arch | prepare.yml didn't run or bootstrap failed | Check `prepare.yml` imports `prepare-vagrant.yml`. Run full `molecule test -s vagrant` |
| `apport.service not found` assertion fails | Running on Arch where apport doesn't exist | Assertion is guarded by `os_family == Debian`. If failing, check `gather_facts: true` |

## Tags

| Tag | What it runs | Use case |
|-----|-------------|----------|
| `sysctl` | Entire role | Full apply |
| `sysctl`, `packages` | Package installation only | Ensure procps is installed |
| `sysctl`, `configure` | Deploy drop-in config only | Re-deploy config without verify |
| `sysctl`, `verify` | Post-apply verification only | Check live values without deploying |
| `sysctl`, `services` | Service management only | Disable apport |
| `sysctl`, `report` | Execution report only | Re-generate execution report |

```bash
# Full apply
ansible-playbook playbook.yml --tags sysctl

# Deploy config and verify only
ansible-playbook playbook.yml --tags sysctl,configure,verify

# Verify current values without deploying
ansible-playbook playbook.yml --tags sysctl,verify
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings with inline comments | No -- override via inventory |
| `vars/main.yml` | Internal bridge vars, OS-family package mappings | Only when adding distro support |
| `templates/sysctl.conf.j2` | Drop-in sysctl config template with KSPP/CIS/STIG references | When changing parameter structure |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/packages.yml` | Package installation | Rarely |
| `tasks/services.yml` | Apport disable + outcome logging | Rarely |
| `tasks/deploy.yml` | Config file deployment | When changing deploy logic |
| `tasks/verify.yml` | Post-deploy self-check (14 parameters) | When changing verification logic |
| `tasks/report.yml` | Structured execution report | When changing report format |
| `handlers/main.yml` | `reload sysctl` handler | Rarely |
| `meta/main.yml` | Galaxy metadata, platform list | When changing supported platforms |
| `molecule/` | Test scenarios (docker, vagrant, default) | When changing test coverage |

## Compliance

| Standard | Coverage |
|---|---|
| **KSPP** (Kernel Self Protection Project) | ASLR, kptr_restrict, dmesg_restrict, ptrace_scope, perf_event_paranoid, unprivileged_bpf_disabled, tty_ldisc_autoload, mmap_min_addr, syncookies, protected_hardlinks/symlinks/fifos/regular, suid_dumpable |
| **CIS Linux Benchmark** | tcp_timestamps (3.3.10), suid_dumpable (1.6.4), rp_filter, ICMP controls |
| **DISA STIG** | perf_event_paranoid (V-258076), suid_dumpable (V-230462), randomize_va_space |

## Notes

**`tcp_timestamps` and `tcp_tw_reuse` are linked.** `tcp_tw_reuse = 1` is unsafe when `tcp_timestamps = 0` -- the kernel uses timestamps to distinguish new connections from duplicate packets. Both are set conservatively: `tcp_timestamps = 0`, `tcp_tw_reuse = 0`.

**`kernel.unprivileged_userns_clone`** exists only in the Arch `linux-hardened` kernel. On standard upstream kernels, it is absent. The `-e` flag in the handler ensures it is silently skipped.

**`arp_ignore` default is `1`** (reply only if target IP belongs to receiving interface). Value `2` is stricter but breaks Docker bridge networking, Kubernetes VIPs, and multi-IP VMs. Kicksecure rolled back from `2` to `1` ([PR #290](https://github.com/Kicksecure/security-misc/pull/290)).

**`rp_filter` uses `conf.all` + `conf.default`** (not wildcard `*`). The wildcard would override Docker bridge interfaces which require `rp_filter=2` (loose) or `0`.

**Workstation profiles**: `sysctl_kernel_yama_ptrace_scope` is profile-aware. With `workstation_profiles: [gaming]` it defaults to `0` (Wine/Proton need this). With `[security]` it defaults to `2`. Otherwise `1`.

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
