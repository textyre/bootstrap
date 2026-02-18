# Ansible Roles Roadmap v2

Gap-анализ на основе сравнения с RHEL System Roles (56 ролей), DebOps v3.2 (200+ ролей),
pigmonkey/spark (Arch Linux, 10 лет), konstruktoid/ansible-role-hardening (CIS/STIG),
vbotka/ansible-linux-postinstall, rafi/ansible-base.

**Целевые профили:**

| Профиль | Описание |
|---------|----------|
| `workstation` | Dev-машина: desktop, GUI, dev tools |
| `server` | Headless: сервисы, remote access, compliance |
| `workstation+server` | Одна машина — оба профиля |

---

## Taxonomy: слоёвая модель

Основана на DebOps layer architecture — единственной опубликованной формальной taxonomy в
Ansible-сообществе. Адаптирована под multi-target проект.

```
L0  bootstrap     — mkinitcpio, bootloader          (pre/post install)
L1a identity      — hostname, locale, timezone,      (делает систему "собой")
                    keymap, ntp
L1b kernel        — sysctl, kernel_modules,          (стабильное ядро)
                    microcode, udev, fwupd
L1c environment   — limits, environment,             (среда для процессов)
                    tmpfiles, journald, logrotate
L2  access        — user, ssh, pam, firewall,        (кто и как заходит)
                    sudo, certificates, crypto_policies
L3  network       — network_manager, dns, vpn,       (сетевая связность)
                    bluetooth, hosts
L4  storage       — swap/zram, disk_management,      (данные и диски)
                    backup, smartd
L5  services      — docker, caddy, vaultwarden,      (сервисы)
                    containers, databases
L6  observability — auditd, tlog, logging,           (всё логируется и видно)
                    node_exporter, grafana, loki,
                    cockpit
L7  desktop       — xorg, lightdm, greeter,          (workstation только)
                    compositor, theming, input
L8  dev tools     — git, shell, chezmoi,             (workstation только)
                    programming_languages
L9  applications  — zen_browser, ...                 (конечные приложения)
```

---

## Текущее состояние (28 ролей)

| Роль | Слой | Профиль | Статус |
|------|------|---------|--------|
| `timezone` | L1a | ALL | ✅ |
| `locale` | L1a | ALL | ✅ |
| `hostname` | L1a | ALL | ✅ |
| `keymap` | L1a | ALL | ✅ |
| `ntp` | L1a | ALL | ✅ |
| `sysctl` | L1b | ALL | ✅ |
| `gpu_drivers` | L1b | WS/WS+S | ✅ |
| `power_management` | L1b | WS/WS+S | ✅ |
| `vm` | L1b | ALL | ✅ |
| `pam_hardening` | L2 | ALL | ✅ |
| `user` | L2 | ALL | ✅ |
| `ssh` | L2 | ALL | ✅ |
| `firewall` | L2 | ALL | ✅ |
| `package_manager` | L3/infra | WS | ✅ |
| `reflector` | L3/infra | WS | ✅ |
| `yay` | L3/infra | WS | ✅ |
| `packages` | L3/infra | WS | ✅ |
| `docker` | L5 | ALL | ✅ |
| `caddy` | L5 | ALL | ✅ |
| `vaultwarden` | L5 | ALL | ✅ |
| `xorg` | L7 | WS/WS+S | ✅ |
| `lightdm` | L7 | WS/WS+S | ✅ |
| `greeter` | L7 | WS/WS+S | ✅ |
| `git` | L8 | WS/WS+S | ✅ |
| `shell` | L8 | WS/WS+S | ✅ |
| `chezmoi` | L8 | WS/WS+S | ✅ |
| `zen_browser` | L9 | WS/WS+S | ✅ |
| `common` | L1a | ALL | ✅ |

---

## Пробелы: отсутствуют полностью (не в roadmap)

Verified по 4+ источникам каждая.

### L1b — Kernel baseline

| Роль | Профиль | Приоритет | Обоснование |
|------|---------|-----------|-------------|
| `microcode` | ALL | **CRITICAL** | spark — base layer позиция 6, HanXHX/debian-bootstrap. Arch: `intel-ucode`/`amd-ucode`. CPU уязвим к Spectre/Meltdown без него. Нужен до kernel workloads. |
| `kernel_modules` | ALL | **HIGH** | DebOps `debops.kmod`, konstruktoid, spark (`hardened` role). Persistent `/etc/modules-load.d/` + blacklist `/etc/modprobe.d/`. Нужен до gpu_drivers, docker, nftables — все зависят от модулей. |
| `udev` | ALL | **MEDIUM** | DebOps, vbotka, spark. Custom device rules `/etc/udev/rules.d/`. Нужен до hardware ролей (GPU, input_devices, bluetooth). |
| `fwupd` | WS/WS+S | **MEDIUM** | Не в roadmap. Firmware updates через systemd timer. Без него firmware не обновляется никогда — BIOS, NVMe, thunderbolt. |

### L1c — Process environment

| Роль | Профиль | Приоритет | Обоснование |
|------|---------|-----------|-------------|
| `limits` | ALL | **HIGH** | DebOps, konstruktoid, 5+ Galaxy roles. `/etc/security/limits.d/` — nofile, nproc, memlock. Docker требует высокий `nofile`. Нужен до L5 services. |
| `environment` | ALL | **MEDIUM** | DebOps `debops.environment`, vbotka. `/etc/environment` + `/etc/profile.d/` — глобальный PATH, XDG_*, proxy, EDITOR. Нужен до shell и application ролей. |
| `tmpfiles` | ALL | **MEDIUM** | konstruktoid, DebOps. `/etc/tmpfiles.d/` — managed temp/runtime dirs. Сервисы пишут в `/run`, `/tmp` — без управления правами непредсказуемое поведение. |

### L2 — Access hardening

| Роль | Профиль | Приоритет | Обоснование |
|------|---------|-----------|-------------|
| `sudo` | SERVER/WS+S | **HIGH** | RHEL System Role, DebOps. Явная `/etc/sudoers.d/` policy. Сейчас sudo частично настраивается в `user`. Для сервера с несколькими пользователями — обязательная отдельная роль. |
| `crypto_policies` | SERVER | **MEDIUM** | RHEL System Role. System-wide TLS/cipher policy (OpenSSL, GnuTLS, NSS). Без неё каждый сервис настраивает TLS независимо — нет единой политики безопасности. |

### L3 — Network (есть в roadmap как Priority 4 — слишком поздно)

| Роль | Профиль | Реальный приоритет | Обоснование |
|------|---------|-------------------|-------------|
| `network_manager` | ALL | **Priority 1 для SERVER** | Без управляемой сети сервер не функционирует. Static IP, DNS upstream, Wi-Fi profiles — это Phase 1 для сервера, не Phase 4. |
| `dns` | ALL | **Priority 1 вместе с network** | systemd-resolved конфигурация влияет на все соединения. До L5 services. |

### L6 — Observability (полностью отсутствует для server)

| Роль | Профиль | Приоритет | Обоснование |
|------|---------|-----------|-------------|
| `tlog` | SERVER | **HIGH** | RHEL System Role. Terminal session recording — полная запись всех shell-сессий по SSH в journald. Enterprise/compliance требование. |
| `logging` | SERVER | **HIGH** | Централизованный сбор логов (rsyslog/syslog-ng). Отдельно от journald — forwarding на remote syslog или Loki. |
| `grafana` | SERVER/WS+S | **HIGH** | Без визуализации node_exporter бесполезен. Grafana + Prometheus стек — стандарт для homelab и выше. |
| `loki` | SERVER/WS+S | **MEDIUM** | Log aggregation для Grafana stack. Заменяет ELK для малых инсталляций. |
| `cockpit` | SERVER | **MEDIUM** | RHEL System Role. Web-based system management UI. На headless сервере — оперативное управление без CLI. |

### L1c (нет в roadmap, priority неверный)

| Роль | Статус в roadmap | Реальный слой | Обоснование |
|------|-----------------|---------------|-------------|
| `nsswitch` | ❌ нет | L1c | DebOps `debops.nsswitch`. `/etc/nsswitch.conf` — порядок разрешения имён. Критично если появится LDAP/AD. |

---

## Ошибки приоритизации в текущем roadmap

Роли присутствуют, но назначены на неверную фазу:

| Роль | Текущий priority | Правильный слой | Причина переноса |
|------|-----------------|-----------------|-----------------|
| `journald` | Priority 7 (Phase 10) | **L1c** | spark: внутри `base` role (base layer concern). DebOps: System Configuration. Без лимитов journald диск заполняется до установки приложений. |
| `logrotate` | Priority 3 (Phase 8) | **L1c** | rafi/ansible-base, DebOps, vbotka: системный слой. Сервисы caddy, fail2ban, sshd начинают писать логи с L5. Logrotate нужен до них. |
| `swap`/`zram` | Priority 3 | **L4** (до L5) | OOM killer убьёт установку пакетов на 4–8 GB RAM без swap. До docker/services. |
| `certificates` | Priority 5 | **L2** (до L5) | Caddy, vaultwarden нуждаются в cert infrastructure до запуска. |
| `audit` | Priority 5 | **L6 SERVER** (Priority 2) | Для сервера — compliance requirement. Должен быть включён до любых пользовательских сессий. |
| `node_exporter` | Priority 7 | **L6** (Priority 2–3) | Без метрик сервер "слепой". Должен появляться сразу после стабилизации сервисов. |
| `network_manager` | Priority 4 | **L3 Priority 1 для SERVER** | Базовая сетевая связность — это не "networking feature", это prerequisite. |
| `dns` | Priority 4 | **L3 вместе с network** | systemd-resolved до всех сервисов. |
| `mkinitcpio` | Priority 3 | **L0 (Bootstrap)** | Arch-specific. После gpu_drivers — обязателен. Концептуально Phase 0. |
| `bootloader` | Priority 5 | **L0 (Bootstrap)** | Первый после mkinitcpio. Phase 0. |

---

## Рекомендуемый порядок реализации

### Фаза A: Завершить L1 (System Foundation)

```
microcode          — L1b  CRITICAL  отсутствует
kernel_modules     — L1b  HIGH      отсутствует
journald           — L1c  HIGH      есть, неверный priority
logrotate          — L1c  HIGH      есть, неверный priority
limits             — L1c  HIGH      отсутствует
environment        — L1c  MEDIUM    отсутствует
tmpfiles           — L1c  MEDIUM    отсутствует
udev               — L1b  MEDIUM    отсутствует
fwupd              — L1b  MEDIUM    отсутствует (WS/WS+S)
```

### Фаза B: Завершить L2 (Access & Security)

```
sudo               — L2  HIGH      отсутствует (SERVER)
certificates       — L2  HIGH      есть, неверный priority
fail2ban           — L2  MEDIUM    roadmap Priority 5 ← ok
apparmor           — L2  MEDIUM    roadmap Priority 5 ← ok
crypto_policies    — L2  MEDIUM    отсутствует (SERVER)
```

### Фаза C: Завершить L3–L4 (Network + Storage)

```
network_manager    — L3  HIGH (SERVER)   roadmap Priority 4 → повысить
dns                — L3  HIGH            roadmap Priority 4 → вместе с network
swap/zram          — L4  HIGH            roadmap Priority 3 → повысить до pre-services
disk_management    — L4  MEDIUM          roadmap Priority 6 ← ok
vpn                — L3  MEDIUM          roadmap Priority 4 ← ok
bluetooth          — L3  LOW (WS)        roadmap Priority 4 ← ok
```

### Фаза D: Desktop experience (WS only)

```
compositor         — L7  roadmap Priority 2 ← ok
input_devices      — L7  roadmap Priority 2 ← ok
notifications      — L7  roadmap Priority 2 ← ok
screen_locker      — L7  roadmap Priority 2 ← ok
gtk_qt_theming     — L7  roadmap Priority 2 ← ok
clipboard          — L7  roadmap Priority 2 ← ok
screenshots        — L7  roadmap Priority 2 ← ok
```

### Фаза E: Observability stack (SERVER/WS+S)

```
audit              — L6  HIGH   roadmap Priority 5 → повысить для server
node_exporter      — L6  HIGH   roadmap Priority 7 → повысить
tlog               — L6  HIGH   отсутствует
logging            — L6  HIGH   отсутствует
grafana            — L6  HIGH   отсутствует
loki               — L6  MEDIUM отсутствует
cockpit            — L6  MEDIUM отсутствует
```

### Фаза F: Dev tools + Bootstrap

```
programming_languages — L8  roadmap Priority 8 ← ok
containers            — L8  roadmap Priority 8 ← ok
databases             — L8  roadmap Priority 8 ← ok
mkinitcpio            — L0  roadmap Priority 3 → переосмыслить как Bootstrap
bootloader            — L0  roadmap Priority 5 → переосмыслить как Bootstrap
```

---

## Итоговая сводка

| Категория | Количество |
|-----------|-----------|
| Существующих ролей | 28 |
| В roadmap (запланировано) | 30 |
| **Отсутствуют полностью** | **15** |
| В roadmap с неверным приоритетом | 10 |

**15 отсутствующих ролей:**
`microcode`, `kernel_modules`, `udev`, `fwupd`,
`limits`, `environment`, `tmpfiles`,
`sudo`, `crypto_policies`,
`tlog`, `logging`, `grafana`, `loki`, `cockpit`,
`nsswitch`

---

## Источники

| Проект | Тип | URL |
|--------|-----|-----|
| Linux System Roles | Enterprise (Red Hat) | https://linux-system-roles.github.io/ |
| DebOps v3.2 | Enterprise (Debian) | https://docs.debops.org/en/master/ansible/role-index.html |
| pigmonkey/spark | Arch Linux, 10 лет | https://github.com/pigmonkey/spark |
| konstruktoid/ansible-role-hardening | CIS/STIG baseline | https://github.com/konstruktoid/ansible-role-hardening |
| vbotka/ansible-linux-postinstall | Multi-distro | https://github.com/vbotka/ansible-linux-postinstall |
| rafi/ansible-base | Cross-distro base | https://github.com/rafi/ansible-base |
| Red Hat Good Practices | Enterprise patterns | https://redhat-cop.github.io/automation-good-practices/ |
