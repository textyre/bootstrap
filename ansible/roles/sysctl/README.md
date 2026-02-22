# Ansible Role: sysctl

Configures Linux kernel parameters via `/etc/sysctl.d/99-ansible.conf` for three goals: kernel exploit hardening, network attack surface reduction, and workstation performance tuning.

Parameters are applied distribution-agnostically: `sysctl -e --system` loads all drop-in files and silently ignores parameters unsupported by the current kernel (e.g. `kernel.unprivileged_userns_clone` exists only in Arch `linux-hardened`).

## What this role actually does

### Kernel hardening

| Parameter | Effect |
|---|---|
| `kernel.randomize_va_space = 2` | Full ASLR — stack, heap, mmap, VDSO randomized. Attacker cannot predict addresses for ROP chains. KSPP, DISA STIG |
| `kernel.kptr_restrict = 2` | Hide kernel addresses from `/proc/kallsyms`, `/proc/modules`. Prevents leaking pointers for exploit development |
| `kernel.dmesg_restrict = 1` | Block unprivileged dmesg access. Kernel logs often contain pointers and sensitive boot-time data |
| `kernel.yama.ptrace_scope = 1` | ptrace restricted to child processes. `gdb ./app` works; `strace -p <pid>` on an unrelated process does not |
| `kernel.perf_event_paranoid = 3` | Block perf counters for unprivileged users. Mitigates Spectre side-channel via performance counters (DISA STIG V-258076) |
| `kernel.unprivileged_bpf_disabled = 1` | Block `bpf()` without `CAP_BPF`. Closes LPE class via eBPF programs (CVE-2021-3490, CVE-2022-23222) |
| `dev.tty.ldisc_autoload = 0` | Block TTY line discipline autoload. Closes CVE-2017-2636 (privilege escalation via TIOCSETD ioctl) |
| `vm.unprivileged_userfaultfd = 0` | Restrict `userfaultfd()` to `CAP_SYS_PTRACE`. Reduces exploitability of use-after-free via heap spray |
| `vm.mmap_min_addr = 65536` | Prohibit mapping below 64K. Blocks null pointer dereference exploitation in the kernel |

### Network hardening

| Parameter | Effect |
|---|---|
| `net.core.bpf_jit_harden = 2` | BPF JIT constant blinding for all users. Protects against JIT spray attacks via eBPF |
| `net.ipv4.conf.*.rp_filter = 1` | Reverse path filtering on **all** interfaces (wildcard applies to Docker/VPN created after boot). Prevents IP spoofing (CVE-2019-14899) |
| `net.ipv4.tcp_syncookies = 1` | SYN cookie protection against SYN flood DDoS |
| `net.ipv4.tcp_rfc1337 = 1` | Protect TIME_WAIT sockets against RST attacks (TIME_WAIT Assassination, RFC 1337) |
| `net.ipv4.conf.*.accept_redirects = 0` | Block ICMP redirects. Prevents traffic hijacking via MITM router injection |
| `net.ipv4.conf.*.send_redirects = 0` | Do not send ICMP redirects |
| `net.ipv4.conf.*.accept_source_route = 0` | Block IPv4 source routing (forced routing through MITM) |
| `net.ipv4.conf.all.log_martians = 1` | Log packets with impossible source/dest addresses (reconnaissance detection) |
| `net.ipv4.icmp_echo_ignore_broadcasts = 1` | Ignore broadcast ICMP echo (Smurf DDoS mitigation) |
| `net.ipv4.tcp_timestamps = 0` | Hide uptime from fingerprinting. CIS 3.3.10. **Requires `tcp_tw_reuse = 0`** |
| `net.ipv4.conf.all.arp_filter = 1` | ARP: do not respond through the wrong interface |
| `net.ipv4.conf.all.arp_ignore = 2` | ARP: respond only if target IP belongs to this interface |
| `net.ipv4.conf.all.drop_gratuitous_arp = 1` | Drop gratuitous ARP — primary vector for ARP cache poisoning and LAN MITM |
| `net.ipv6.conf.all.accept_redirects = 0` | Block ICMPv6 redirects |
| `net.ipv6.conf.all.accept_source_route = 0` | Block IPv6 source routing |
| `net.ipv6.conf.all.accept_ra = 0` | Reject IPv6 Router Advertisements. Rogue RA lets any host in the network become the default gateway (RFC 6104/6105) |

### Filesystem hardening

| Parameter | Effect |
|---|---|
| `fs.protected_hardlinks = 1` | Block hardlinks to files without read/write/ownership. TOCTOU mitigation |
| `fs.protected_symlinks = 1` | Block following symlinks in world-writable sticky directories. Prevents `/tmp` race conditions |
| `fs.protected_fifos = 2` | Block writes to FIFOs in sticky directories without ownership. TOCTOU mitigation |
| `fs.protected_regular = 2` | Block writes to regular files in sticky directories without ownership |
| `fs.suid_dumpable = 0` | Prohibit core dumps of SUID binaries. Passwords and keys can appear in setuid process dumps. CIS 1.6.4, DISA STIG V-230462 |

### Performance

| Parameter | Purpose |
|---|---|
| `vm.swappiness = 10` | Minimize swap usage. Security: `1`, Performance: `10–60` |
| `vm.vfs_cache_pressure = 50` | Reduce inode/dentry cache eviction aggressiveness |
| `vm.dirty_ratio = 10` | Force flush when dirty pages reach 10% of RAM. For media servers (Plex/Jellyfin) with large libraries, raise to `20–40` to reduce write-stall pauses during transcoding |
| `vm.dirty_background_ratio = 5` | Start background flush at 5% dirty pages. Raise to `10–15` alongside `dirty_ratio` for media workloads |
| `fs.inotify.max_user_watches = 524288` | For IDEs (VSCode, JetBrains) and file watchers |
| `fs.inotify.max_user_instances = 1024` | Max inotify instances per user |
| `fs.file-max = 2097152` | System-wide open file descriptor limit. Note: applications (Plex, Jellyfin) also need per-process `LimitNOFILE` raised in their systemd unit — `fs.file-max` alone is not enough |
| `net.core.somaxconn = 4096` | TCP connection backlog (for dev servers and Docker) |
| `net.ipv4.tcp_fastopen = 3` | TCP Fast Open on client and server. Reduces latency on repeated connections |

## Requirements

- Ansible 2.9 or higher
- `become: true`
- `gather_facts: true`
- Supported OS families: `Archlinux`, `Debian`

## Role Variables

### Feature toggles

| Variable | Default | Description |
|---|---|---|
| `sysctl_security_enabled` | `true` | Master switch for all security parameters |
| `sysctl_security_kernel_hardening` | `true` | Kernel: ASLR, kptr_restrict, eBPF, ptrace, mmap_min_addr |
| `sysctl_security_network_hardening` | `true` | Network: ARP, ICMP, TCP, rp_filter, IPv6 |
| `sysctl_security_filesystem_hardening` | `true` | FS: hardlink/symlink/FIFO/SUID protection |
| `sysctl_security_ipv6_disable` | `false` | Fully disable IPv6 (caution: breaks DNS, Docker, Happy Eyeballs) |

### Performance

| Variable | Default | Description |
|---|---|---|
| `sysctl_vm_swappiness` | `10` | Swap aggressiveness |
| `sysctl_vm_vfs_cache_pressure` | `50` | Cache eviction pressure |
| `sysctl_vm_dirty_ratio` | `10` | Dirty page flush threshold (%) |
| `sysctl_vm_dirty_background_ratio` | `5` | Background flush start (%) |
| `sysctl_fs_inotify_max_user_watches` | `524288` | inotify watch limit |
| `sysctl_fs_inotify_max_user_instances` | `1024` | inotify instance limit |
| `sysctl_fs_file_max` | `2097152` | System open file descriptor limit |
| `sysctl_net_core_somaxconn` | `4096` | TCP connection backlog |
| `sysctl_net_ipv4_tcp_fastopen` | `3` | TCP Fast Open (0=off, 1=client, 2=server, 3=both) |
| `sysctl_net_ipv4_tcp_tw_reuse` | `0` | TIME_WAIT socket reuse — **must be 0 when tcp_timestamps=0** |

### Security: Kernel

| Variable | Default | Description |
|---|---|---|
| `sysctl_kernel_randomize_va_space` | `2` | ASLR level (2=full) |
| `sysctl_kernel_kptr_restrict` | `2` | Kernel pointer restriction (2=always hidden) |
| `sysctl_kernel_dmesg_restrict` | `1` | Block unprivileged dmesg |
| `sysctl_kernel_yama_ptrace_scope` | `1` | ptrace scope (1=child only, 2=root only) |
| `sysctl_kernel_perf_event_paranoid` | `3` | perf event access (3=kernel-only) |
| `sysctl_kernel_unprivileged_bpf_disabled` | `1` | Block unprivileged bpf() |
| `sysctl_kernel_tty_ldisc_autoload` | `0` | Block TTY line discipline autoload |
| `sysctl_vm_unprivileged_userfaultfd` | `0` | Restrict userfaultfd() |
| `sysctl_vm_mmap_min_addr` | `65536` | Minimum mmap address |
| `sysctl_kernel_unprivileged_userns_clone` | `1` | Arch linux-hardened kernel only — ignored on other kernels |

### Security: Network

| Variable | Default | Description |
|---|---|---|
| `sysctl_net_core_bpf_jit_harden` | `2` | BPF JIT hardening (2=all users) |
| `sysctl_net_ipv4_rp_filter` | `1` | Reverse path filter (applied as wildcard `*.rp_filter`) |
| `sysctl_net_ipv4_tcp_syncookies` | `1` | SYN cookies |
| `sysctl_net_ipv4_tcp_rfc1337` | `1` | TIME_WAIT assassination protection |
| `sysctl_net_ipv4_accept_redirects` | `0` | Block ICMP redirects |
| `sysctl_net_ipv4_send_redirects` | `0` | Do not send ICMP redirects |
| `sysctl_net_ipv4_accept_source_route` | `0` | Block IPv4 source routing |
| `sysctl_net_ipv4_log_martians` | `1` | Log martian packets |
| `sysctl_net_ipv4_icmp_echo_ignore_broadcasts` | `1` | Ignore broadcast ICMP echo |
| `sysctl_net_ipv4_icmp_ignore_bogus_error_responses` | `1` | Ignore bogus ICMP errors |
| `sysctl_net_ipv4_tcp_timestamps` | `0` | Disable TCP timestamps |
| `sysctl_net_ipv4_arp_filter` | `1` | ARP interface filter |
| `sysctl_net_ipv4_arp_ignore` | `1` | ARP reply scope (1=safe for Docker/VM; 2=strict, bare-metal only) |
| `sysctl_net_ipv4_drop_gratuitous_arp` | `0` | Drop gratuitous ARP (1 breaks keepalived/VRRP HA) |
| `sysctl_net_ipv6_accept_redirects` | `0` | Block ICMPv6 redirects |
| `sysctl_net_ipv6_accept_source_route` | `0` | Block IPv6 source routing |
| `sysctl_net_ipv6_accept_ra` | `1` | Router Advertisements (0 breaks SLAAC IPv6; use 0 only with DHCPv6 stateful/static IPv6) |

### Security: Filesystem

| Variable | Default | Description |
|---|---|---|
| `sysctl_fs_protected_hardlinks` | `1` | Hardlink protection |
| `sysctl_fs_protected_symlinks` | `1` | Symlink protection in sticky dirs |
| `sysctl_fs_protected_fifos` | `2` | FIFO write protection in sticky dirs |
| `sysctl_fs_protected_regular` | `2` | Regular file write protection in sticky dirs |
| `sysctl_fs_suid_dumpable` | `0` | Prohibit SUID core dumps |

### Custom parameters

| Variable | Default | Description |
|---|---|---|
| `sysctl_custom_params` | `[]` | Additional parameters: `[{name: "kernel.param", value: "1"}]` |

## Tags

| Tag | Purpose |
|---|---|
| `sysctl` | All tasks |
| `sysctl`, `packages` | Package installation only |
| `sysctl`, `configure` | Deploy drop-in config only |
| `sysctl`, `verify` | Post-apply parameter verification only |

## Example Playbook

```yaml
- name: Harden kernel parameters
  hosts: all
  become: true
  gather_facts: true

  roles:
    - role: sysctl
```

Override for a development workstation:

```yaml
- role: sysctl
  vars:
    sysctl_kernel_yama_ptrace_scope: 1       # allow gdb ./app (default)
    sysctl_net_ipv4_arp_ignore: 1            # less strict ARP in VM environments
    sysctl_security_ipv6_disable: false      # keep IPv6 (default)
```

Override for maximum security (server):

```yaml
- role: sysctl
  vars:
    sysctl_vm_swappiness: 1                  # minimize sensitive data in swap
    sysctl_kernel_yama_ptrace_scope: 2       # root-only ptrace
    sysctl_security_ipv6_disable: true       # if no IPv6 connectivity
```

Run specific tasks:

```bash
# Deploy config and verify only
ansible-playbook playbook.yml --tags sysctl,configure,verify

# Verify current values without deploying
ansible-playbook playbook.yml --tags sysctl,verify
```

## Files deployed

- `/etc/sysctl.d/99-ansible.conf` — drop-in kernel parameter configuration, loaded automatically at boot by `systemd-sysctl.service` and on-demand via `sysctl --system`

## Compliance

| Standard | Coverage |
|---|---|
| **KSPP** (Kernel Self Protection Project) | ASLR, kptr_restrict, dmesg_restrict, ptrace_scope, perf_event_paranoid, unprivileged_bpf_disabled, tty_ldisc_autoload, mmap_min_addr, syncookies, protected_hardlinks/symlinks/fifos/regular, suid_dumpable |
| **CIS Linux Benchmark** | tcp_timestamps (3.3.10), suid_dumpable (1.6.4), rp_filter, ICMP controls |
| **DISA STIG** | perf_event_paranoid (V-258076), suid_dumpable (V-230462), randomize_va_space |

## Notes

**`tcp_timestamps` and `tcp_tw_reuse` are linked.** `tcp_tw_reuse = 1` is unsafe when `tcp_timestamps = 0` — the kernel uses timestamps to distinguish new connections from duplicate packets from old TIME_WAIT sockets. Both are set conservatively here: `tcp_timestamps = 0`, `tcp_tw_reuse = 0`.

**`kernel.unprivileged_userns_clone`** exists only in the Arch `linux-hardened` kernel. On standard upstream kernels (Arch and Debian), it is absent. The `-e` flag in the handler ensures it is silently skipped.

**`arp_ignore` default is `1`** (reply only if target IP belongs to receiving interface). Value `2` is stricter but breaks Docker bridge networking, Kubernetes VIPs, and multi-IP VMs. Kicksecure rolled back from `2` to `1` ([PR #290](https://github.com/Kicksecure/security-misc/pull/290)). Use `2` only on bare-metal single-NIC servers without Docker.

**`drop_gratuitous_arp` default is `0`**. Value `1` blocks ARP cache poisoning but breaks `keepalived`/VRRP HA failover — backup servers cannot announce virtual IP takeover. Enable only on non-HA workstations: `sysctl_net_ipv4_drop_gratuitous_arp: 1`.

**`rp_filter` uses `conf.all` + `conf.default`** (not wildcard `*`). The wildcard would override Docker bridge interfaces (`docker0`, `br-*`) which require `rp_filter=2` (loose) or `0` to route container traffic correctly. For Docker hosts, add to `sysctl_custom_params`:
```yaml
sysctl_custom_params:
  - { name: "net.ipv4.conf.docker0.rp_filter", value: "2" }
```

**`accept_ra` default is `1`** (accept Router Advertisements, kernel default). Setting `0` disables SLAAC — IPv6 connectivity is lost on networks without DHCPv6 stateful, which is the majority of home/office/cloud networks. Disable only on servers with static IPv6 or DHCPv6 stateful: `sysctl_net_ipv6_accept_ra: 0`.

**Gaming: `tcp_timestamps = 0` and port exhaustion.** Disabling timestamps has negligible effect on game latency. However, the paired `tcp_tw_reuse = 0` means TIME_WAIT sockets are not recycled. Under heavy connection workloads (game launchers, CDN patch downloads making 1000+ short TCP connections/min), ephemeral port exhaustion can occur. Override to `sysctl_net_ipv4_tcp_tw_reuse: 1` only if `tcp_timestamps` is also re-enabled.

**Post-apply verification** reads live values via `sysctl -n` and reports `OK`, `MISMATCH`, `NOT SUPPORTED` (kernel version too old), or `ERROR` for each checked parameter. Parameters unsupported by the current kernel are skipped without error.

## License

MIT

## Author

Part of the bootstrap infrastructure automation project.
