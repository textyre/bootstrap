# sysctl

Configures a workstation kernel policy through Linux sysctl parameters.

This role is not a generic "write any sysctl file" helper. It owns one
specific baseline: a Linux workstation should be harder than distro defaults
against common local kernel-abuse and network-misrouting classes, while still
remaining usable for development, desktop, gaming, VM, Docker-host, and normal
IPv6 networks.

The role therefore chooses compatibility-aware defaults instead of maximum
hardening everywhere. Examples:

- `ptrace_scope=1`, not `2` or `3`, so normal `gdb ./app` still works.
- `arp_ignore=1`, not `2`, because stricter ARP behavior breaks Docker bridges,
  Kubernetes VIPs, and multi-IP VM setups.
- `drop_gratuitous_arp=0`, because `1` breaks keepalived/VRRP and legitimate
  IP-move announcements.
- `accept_ra=1`, because many workstation networks use SLAAC IPv6.
- `tcp_timestamps=0` is paired with `tcp_tw_reuse=0` because reuse depends on
  timestamps for safe connection distinction.

## Runtime Model

| Environment | What the role can guarantee | Why |
|-------------|-----------------------------|-----|
| Bare metal | Persistent sysctl policy applied by the distro sysctl loader on boot/reload | The OS owns the running kernel and `/proc/sys`, but this role does not force live apply |
| VM guest | Persistent guest sysctl policy applied by the guest distro sysctl loader on boot/reload | A VM has its own guest kernel; the role does not affect the host or hypervisor |
| Docker container | Template/render/idempotence behavior only; not host kernel hardening | A container shares the host kernel, and many sysctls are read-only, not namespaced, or blocked by the runtime |

Docker is useful as a fast Molecule convergence/idempotence target. It is not a
full security target for this role. A successful Docker run means the persistent
policy renders cleanly and idempotently, not that the host kernel is hardened.

## Policy Rationale

| Policy area | User-facing purpose | Default posture | Rationale / source family |
|-------------|---------------------|-----------------|---------------------------|
| Kernel information exposure | Do not give ordinary users kernel pointers, dmesg contents, or broad perf/BPF introspection by default | Restrict by default, relax per profile only | Linux kernel sysctl docs, Yama LSM docs, KSPP-style hardening |
| Debugging / ptrace | Keep normal development usable while blocking broad process attach | `ptrace_scope=1` | `0` is friendlier for Wine/Proton and attach debugging; `2`/`3` are stronger but break common dev workflows |
| Filesystem race protections | Reduce `/tmp` and sticky-directory attack classes | Enable protected hardlinks/symlinks/FIFOs/regular files | Linux fs sysctl docs and `proc_sys_fs(5)` document these protections |
| SUID crash dumps | Avoid writing memory from privileged programs into core dump files | `fs.suid_dumpable=0` | Security baseline prefers no SUID core dumps; Ubuntu apport conflicts with this and is handled explicitly |
| Network routing trust | Do not accept redirects or source routes from the network | Disable redirects/source route | Linux IP sysctl docs and CIS-style workstation hardening |
| Spoofing / ARP | Add anti-spoofing controls without breaking common VM/Docker networks | Moderate defaults, not maximum strictness | `rp_filter=1`, `arp_ignore=1`, `drop_gratuitous_arp=0` are compatibility-aware |
| IPv6 | Keep normal workstation IPv6 working | Do not disable IPv6; accept RA | Disabling IPv6 or RA breaks SLAAC, DNS fallback, and common office/home networks |
| Workstation capacity | Avoid low distro defaults that hurt IDEs, file watchers, and local dev servers | Raise inotify/file/backlog limits | Practical workstation baseline, not security hardening |

The role comments, template, and documentation use these source families:

- Linux kernel sysctl docs: <https://docs.kernel.org/admin-guide/sysctl/>
- Yama LSM ptrace scope: <https://docs.kernel.org/admin-guide/LSM/Yama.html>
- Linux fs sysctl/man pages: <https://docs.kernel.org/admin-guide/sysctl/fs.html>, <https://man7.org/linux/man-pages/man5/proc_sys_fs.5.html>
- CIS/STIG/KSPP-aligned hardening controls where noted in comments.

## Execution flow

`tasks/main.yml` is only the role orchestrator. Business logic lives in phase files.

1. **Validate** (`tasks/validate/main.yml`) -- fails before mutation on unsupported OS/init.
2. **Load vars** (`tasks/load/main.yml`) -- loads distro-family package mapping from `vars/<os_family>/main.yml`.
3. **Detect** (`tasks/detect/main.yml`) -- gathers Debian service facts when apport conflict handling is relevant.
4. **Install** (`tasks/install/main.yml`) -- installs `procps-ng` (Arch/Void/RedHat) or `procps` (Debian/Gentoo) via `ansible.builtin.package`.
5. **Service** (`tasks/service/main.yml`) -- disables `apport.service` on Debian/Ubuntu only when present and when it would override `fs.suid_dumpable` hardening.
6. **Configure** (`tasks/configure/main.yml`) -- renders `/etc/sysctl.d/99-z-ansible.conf` from the policy template. The distro sysctl loader applies it on boot/reload; the role does not force live apply.
7. **Report** (`tasks/main.yml`) -- renders the structured execution report accumulated during each phase.

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
| `sysctl_kernel_unprivileged_userns_clone` | `1` | careful | Arch linux-hardened kernel only. Standard kernels may report it as unsupported when the distro sysctl loader runs |

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

`sysctl_custom_params` is an escape hatch for environment-specific parameters
that the role does not own directly, for example Docker bridge overrides on a
Docker host. The semantic safety and structure of custom parameters belong to
the inventory owner. If a custom parameter becomes common baseline policy, move
it into `defaults/main.yml` and the internal parameter groups instead of keeping
it as custom data forever.

### Internal mappings (`vars/`)

These files contain cross-platform mappings. Do not override via inventory -- edit the files directly only when adding new platform support.

| File | What it contains | When to edit |
|------|-----------------|-------------|
| `vars/main.yml` | Supported platforms, internal config path, and parameter groups used by the template | Changing managed parameter structure |
| `vars/<os_family>/main.yml` | `_sysctl_procps_package` for each supported distro family | Adding or changing package mapping |

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

## Default Decisions

### Kernel policy

| Parameter | Default | Why this default exists | When to change |
|---|---:|---|---|
| `kernel.randomize_va_space` | `2` | Full ASLR is the baseline: userspace memory layout randomization should be on unless there is a legacy debugging reason. | Only for broken legacy software or controlled debugging. |
| `kernel.kptr_restrict` | `2` | Kernel pointers are useful to exploit chains and rarely useful to normal users. `2` hides them even from users that would otherwise pass credential checks. | Lower only on dedicated kernel debugging hosts. |
| `kernel.dmesg_restrict` | `1` | Kernel logs can expose addresses, device state, and failure details. Normal users do not need raw dmesg on a workstation baseline. | Lower for local debugging workflows that intentionally allow unprivileged dmesg. |
| `kernel.yama.ptrace_scope` | `1` | This is the workstation compromise: `gdb ./app` works, but attaching to unrelated processes is restricted. | `0` for gaming/Wine/Proton or attach-heavy dev; `2` for security profile. |
| `kernel.perf_event_paranoid` | `3` | Perf counters are useful for profiling but also expose side-channel surface. The baseline prefers safety over unprivileged profiling. | Lower on performance engineering hosts. |
| `kernel.unprivileged_bpf_disabled` | `1` | Unprivileged BPF has had repeated privilege-escalation exposure. Workstations do not need unprivileged BPF by default. | Change only for workloads that explicitly require unprivileged BPF. |
| `dev.tty.ldisc_autoload` | `0` | Automatic TTY line discipline loading is unnecessary on normal workstations and has been an exploit path. | Rare; only for specialized TTY/serial environments. |
| `vm.unprivileged_userfaultfd` | `0` | Userfaultfd can help exploit reliability; normal users do not need unrestricted access by default. | Change for runtimes or debuggers that explicitly require it. |
| `vm.mmap_min_addr` | `65536` | Blocks low-address mappings used in null-pointer-dereference exploitation patterns. `65536` is the common hardened floor. | Lower only for very old software requiring low mappings. |
| `kernel.unprivileged_userns_clone` | `1` | Kept permissive because desktop/container tooling may depend on user namespaces. It is optional because it exists mainly on Arch linux-hardened. | Set `0` only if user namespaces are intentionally disallowed. |

### Network policy

| Parameter | Default | Why this default exists | When to change |
|---|---:|---|---|
| `net.core.bpf_jit_harden` | `2` | Applies BPF JIT hardening to all users, not only unprivileged users. | Lower only if BPF performance is a measured bottleneck. |
| `net.ipv4.conf.all.rp_filter` / `default` | `1` | Drops packets whose source does not match the reverse route, reducing simple spoofing exposure. | Use custom per-interface params for Docker/VPN/asymmetric routing. |
| `net.ipv4.tcp_syncookies` | `1` | Keeps SYN flood mitigation enabled. | Normally do not disable. |
| `net.ipv4.tcp_rfc1337` | `1` | Protects TIME_WAIT sockets from reset-based assassination behavior described by RFC 1337. | Normally do not disable. |
| `net.ipv4.conf.*.accept_redirects` | `0` | Workstations should not let the network rewrite their route choice through ICMP redirects. | Rare; only on trusted legacy networks requiring redirects. |
| `net.ipv4.conf.*.send_redirects` | `0` | A workstation is not a router and should not emit redirects. | Enable only on intentional router hosts owned by a network role. |
| `net.ipv4.conf.*.accept_source_route` | `0` | Source route lets the sender influence packet path and is not appropriate for a workstation baseline. | Normally do not enable. |
| `net.ipv4.conf.*.log_martians` | `1` | Logs impossible/spoofed-looking packets so network anomalies are visible. | Disable if logs are too noisy in a known noisy environment. |
| `net.ipv4.icmp_echo_ignore_broadcasts` | `1` | Avoids participating in broadcast-ping amplification patterns. | Normally do not disable. |
| `net.ipv4.icmp_ignore_bogus_error_responses` | `1` | Drops bogus ICMP errors that add noise and can confuse diagnostics. | Normally do not disable. |
| `net.ipv4.tcp_timestamps` | `0` | Privacy choice: avoids exposing TCP timestamp behavior. Because timestamps are off, `tcp_tw_reuse` must remain `0`. | Set `1` only when performance/reuse behavior is more important than this privacy posture. |
| `net.ipv4.tcp_tw_reuse` | `0` | Compatible with `tcp_timestamps=0`; avoids unsafe reuse assumptions. | Enable only together with timestamps and a measured need. |
| `net.ipv4.conf.all.arp_filter` | `1` | Avoids answering ARP through the wrong interface on multi-interface hosts. | Disable if a specific multi-homing setup requires weaker ARP behavior. |
| `net.ipv4.conf.all.arp_ignore` | `1` | Compatibility-aware ARP hardening. `2` is stricter but breaks Docker bridges, Kubernetes VIPs, and multi-IP VMs. | Use `2` only on simple bare-metal hosts without those patterns. |
| `net.ipv4.conf.all.drop_gratuitous_arp` | `0` | Keeps legitimate IP movement working. `1` can break keepalived/VRRP and WireGuard/IP-change announcements. | Set `1` only where gratuitous ARP is forbidden and HA/IP-move is absent. |
| `net.ipv6.conf.*.accept_redirects` | `0` | IPv6 redirects are not trusted in the baseline. | Rare; only on trusted networks requiring redirects. |
| `net.ipv6.conf.*.accept_source_route` | `0` | IPv6 source routing is not appropriate for a workstation baseline. | Normally do not enable. |
| `net.ipv6.conf.*.accept_ra` | `1` | Keeps SLAAC IPv6 working on normal workstation networks. | Set `0` only with static IPv6 or DHCPv6 stateful design. |

### Filesystem policy

| Parameter | Default | Why this default exists | When to change |
|---|---:|---|---|
| `fs.protected_hardlinks` | `1` | Blocks hardlink tricks across privilege boundaries. | Normally do not disable. |
| `fs.protected_symlinks` | `1` | Blocks symlink-following attacks in world-writable sticky directories. | Normally do not disable. |
| `fs.protected_fifos` | `2` | Strict FIFO protection in sticky directories; reduces race/spoofing patterns. | Lower only for legacy software broken by strict sticky-dir protection. |
| `fs.protected_regular` | `2` | Strict regular-file protection in sticky directories. | Lower only for legacy software broken by strict sticky-dir protection. |
| `fs.suid_dumpable` | `0` | SUID program memory should not be written to core dumps. This is why Ubuntu apport is treated as a conflict when it forces `2`. | Set `2` only if crash reporting is explicitly more important than this hardening control. |

### Workstation capacity policy

| Parameter | Default | Why this default exists | When to change |
|---|---:|---|---|
| `vm.swappiness` | `10` | Workstations should avoid eager swap use without disabling swap completely. | Use `1` for sensitive/security profile, higher values for memory-pressure workloads. |
| `vm.vfs_cache_pressure` | `50` | Keeps filesystem metadata cache longer, improving interactive desktop/dev workloads. | Raise if memory pressure matters more than cache retention. |
| `vm.dirty_ratio` | `10` | Avoids large bursts of dirty memory before forced writeback. | Raise for media/file-server workloads that prefer throughput over latency. |
| `vm.dirty_background_ratio` | `5` | Starts background writeback before the hard dirty limit. Validate requires it to be <= `dirty_ratio`. | Tune with `dirty_ratio`; do not set above it. |
| `fs.inotify.max_user_watches` | `524288` | IDEs, language servers, and file watchers need more than conservative distro defaults. | Raise for very large monorepos. |
| `fs.inotify.max_user_instances` | `1024` | Allows multiple watcher-heavy desktop/dev tools. | Raise if watcher tools hit instance limits. |
| `fs.file-max` | `2097152` | Avoids low global file descriptor ceilings on dev workstations. | Tune lower/higher only for known capacity policy. |
| `net.core.somaxconn` | `4096` | Gives local dev servers and containers a less restrictive listen backlog. | Tune per service in the owning service role if needed. |
| `net.ipv4.tcp_fastopen` | `3` | Enables client and server TCP Fast Open for lower connection setup latency where supported. | Disable if a network middlebox or app has compatibility issues. |

## Cross-platform details

| Aspect | Arch Linux | Ubuntu / Debian | Fedora / RHEL | Void Linux | Gentoo |
|--------|-----------|-----------------|---------------|------------|--------|
| Package | `procps-ng` | `procps` | `procps-ng` | `procps-ng` | `procps` |
| Config path | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` | `/etc/sysctl.d/99-z-ansible.conf` |
| Apport service | n/a | disabled if `suid_dumpable != 2` | n/a | n/a | n/a |
| `kernel.unprivileged_userns_clone` | linux-hardened only | absent | absent | absent | absent |
| Boot persistence | distro sysctl loader | distro sysctl loader | distro sysctl loader | distro sysctl loader | distro sysctl loader |

## Logs

### Log files

This role does not create its own log files. Kernel messages and sysctl behavior are logged through system logging.

| Source | How to read | Contents |
|--------|------------|----------|
| syslog / journald | `journalctl -k` | Kernel messages including martian packet logs (`log_martians=1`) |
| Ansible output | Taskfile/Ansible stdout | Role execution report (validate, load, detect, install, service, configure phases) |

### Reading the logs

- Martian packet detection: `journalctl -k --grep="martian"` -- look for spoofed packets
- Sysctl load errors at boot: check the distro init logs for the sysctl loader and parameter rejection.

## Troubleshooting

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Role fails at "Assert supported operating system" | OS family not in supported list | Check `ansible_facts['os_family']` -- must be Archlinux, Debian, RedHat, Void, or Gentoo |
| Runtime value differs after reboot/reload | Another sysctl.d file overrides our value or the kernel does not support the parameter | Check `sysctl --system` output. Files are loaded alphabetically; move the conflicting setting to its owning role or adjust ordering deliberately |
| `kernel.unprivileged_userns_clone` is rejected by the distro sysctl loader | Parameter exists only in Arch `linux-hardened` kernel | Remove or override this parameter for hosts that do not support it |
| Containers on a Docker host cannot route traffic after role apply | Host `rp_filter=1` blocks Docker bridge traffic | Add to the Docker host inventory: `sysctl_custom_params: [{name: "net.ipv4.conf.docker0.rp_filter", value: "2"}]` |
| `gdb --pid` or `strace -p` fails with EPERM | `ptrace_scope=1` restricts to child processes only | Set `sysctl_kernel_yama_ptrace_scope: 0` through inventory for hosts that need attach-style debugging, then rerun the role |
| IPv6 connectivity lost after role apply | `sysctl_security_ipv6_disable: true` or `accept_ra: 0` | Set `sysctl_security_ipv6_disable: false` and `sysctl_net_ipv6_accept_ra: 1` (defaults) |
| apport keeps resetting `fs.suid_dumpable` to 2 | apport.service starts after the distro sysctl loader | Role should disable apport automatically. Check the service manager state for `apport` |
| Value did not change immediately after role run | The role renders persistent policy and does not force live apply | Reboot or run the distro sysctl loader through the owning operational workflow |

## Testing

Molecule scenarios prepare prerequisites, run the role, and check idempotence. There is no separate Molecule verify playbook because this role's contract is the persistent policy render; live kernel state is not forced during converge.

| Scenario | Command | When to use | What it tests |
|----------|---------|-------------|---------------|
| Role task | `task test-sysctl` | Standard project entrypoint for sysctl role checks | Molecule scenario sequence for the role |
| Docker (fast) | `task test-sysctl -- --scenario-name docker` | After changing variables, templates, or task logic | Syntax, convergence, idempotence of the persistent policy |
| Vagrant (cross-platform) | `task test-sysctl -- --scenario-name vagrant` | After changing OS-specific logic or security params | Syntax, convergence, idempotence on VM filesystems/package managers |

### Success criteria

- All steps complete: `syntax -> create -> prepare -> converge -> idempotence -> destroy`
- Idempotence step: `changed=0` (second run changes nothing)
- Final line: no `failed` tasks

### Common test failures

| Error | Cause | Fix |
|-------|-------|-----|
| `procps-ng package not found` | Stale package cache in container | Rebuild through the project task: `task test-sysctl -- --scenario-name docker` |
| Idempotence failure on config deploy | Template output differs on the second run | Check for dynamic expressions in the template |
| Vagrant: `Python not found` on Arch | prepare.yml didn't run or bootstrap failed | Check `prepare.yml` imports `prepare-vagrant.yml`. Run full `task test-sysctl -- --scenario-name vagrant` |

## Tags

The role exposes the top-level `sysctl` tag for full role execution. Internal phases are intentionally not treated as separate operator entrypoints.

```bash
# Full apply
task workstation -- --tags sysctl
```

## File map

| File | Purpose | Edit? |
|------|---------|-------|
| `defaults/main.yml` | All configurable settings with inline comments | No -- override via inventory |
| `vars/main.yml` | Internal config path and template parameter groups | When changing managed parameter structure |
| `vars/<os_family>/main.yml` | OS-family package mapping | Only when changing supported platform details |
| `templates/sysctl.conf.j2` | Persistent sysctl policy file with operator-facing rationale comments | When changing parameter structure or generated file comments |
| `tasks/main.yml` | Execution flow orchestrator | When adding/removing steps |
| `tasks/validate/main.yml` | Fail-fast platform validation | When changing role contract |
| `tasks/load/main.yml` | OS-specific var loading | Rarely |
| `tasks/detect/main.yml` | Runtime fact gathering for service conflicts | Rarely |
| `tasks/install/main.yml` | Package installation | Rarely |
| `tasks/service/main.yml` | Apport conflict management | Rarely |
| `tasks/configure/main.yml` | Persistent policy render | When changing configure logic |
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

**`kernel.unprivileged_userns_clone`** exists only in the Arch `linux-hardened` kernel. On standard upstream kernels, it is absent. Keep it only if the target kernel policy expects this optional parameter; otherwise override or remove it for those hosts.

**`arp_ignore` default is `1`** (reply only if target IP belongs to receiving interface). Value `2` is stricter but breaks Docker bridge networking, Kubernetes VIPs, and multi-IP VMs. Kicksecure rolled back from `2` to `1` ([PR #290](https://github.com/Kicksecure/security-misc/pull/290)).

**`rp_filter` uses `conf.all` + `conf.default`** (not wildcard `*`). The wildcard would override Docker bridge interfaces which require `rp_filter=2` (loose) or `0`.

**Workstation profiles**: `sysctl_kernel_yama_ptrace_scope` is profile-aware. With `workstation_profiles: [gaming]` it defaults to `0` (Wine/Proton need this). With `[security]` it defaults to `2`. Otherwise `1`.

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
