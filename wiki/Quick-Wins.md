# Quick Wins — улучшения существующих ролей

Изменения без создания новых ролей, значительно усиливающие безопасность системы. Каждый Quick Win — небольшое дополнение к существующей роли с высоким security impact.

---

## QW-1: SSH — криптография и DoS защита

**Роль:** `ssh`

### Проблема

Дефолтная конфигурация SSH допускает:
- Слабые алгоритмы шифрования (legacy ciphers для совместимости)
- Отсутствие ограничений на подключения (DoS через exhaustion атаки)
- Любые пользователи могут подключаться по SSH

### Что добавить

**1. Ограничение доступа по группам**
```yaml
# defaults/main.yml
ssh_allow_groups: ["wheel", "ssh-users"]  # Только указанные группы
```

**Конфигурация sshd:**
```
AllowGroups wheel ssh-users
```

**2. DoS защита — ограничение одновременных подключений**
```yaml
# defaults/main.yml
ssh_max_startups: "4:50:10"  # 4 неаутентифицированных подключения, затем 50% reject, макс 10
ssh_max_sessions: 10          # Максимум сессий на одно подключение
```

**Конфигурация sshd:**
```
MaxStartups 4:50:10
MaxSessions 10
```

**3. Ограничение криптографических алгоритмов**
```yaml
# defaults/main.yml
ssh_ciphers:
  - "chacha20-poly1305@openssh.com"
  - "aes256-gcm@openssh.com"
  - "aes128-gcm@openssh.com"

ssh_kex_algorithms:
  - "curve25519-sha256"
  - "curve25519-sha256@libssh.org"
  - "diffie-hellman-group-exchange-sha256"

ssh_macs:
  - "hmac-sha2-512-etm@openssh.com"
  - "hmac-sha2-256-etm@openssh.com"
  - "umac-128-etm@openssh.com"

ssh_host_key_algorithms:
  - "ssh-ed25519"
  - "rsa-sha2-512"
  - "rsa-sha2-256"
```

**Конфигурация sshd:**
```
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
```

### Файлы

- `ansible/roles/ssh/defaults/main.yml` — добавить переменные
- `ansible/roles/ssh/templates/sshd_config.j2` — добавить директивы

### Проверка

```bash
# Проверка конфигурации sshd
sshd -T | grep -E "(ciphers|kexalgorithms|macs|allowgroups|maxstartups)"

# Тест подключения с указанием алгоритмов
ssh -v user@host 2>&1 | grep "kex:"

# Проверка ограничения групп
ssh user@host  # Если user не в wheel — доступ запрещён
```

### Impact

- **Защита от криптоанализа**: только современные алгоритмы (ChaCha20, AES-GCM, Ed25519)
- **DoS защита**: ограничение одновременных подключений предотвращает exhaustion атаки
- **Least privilege**: только доверенные группы могут подключаться по SSH

---

## QW-2: Sysctl — параметры безопасности ядра

**Роль:** `sysctl`

### Проблема

Дефолтные kernel параметры оптимизированы для совместимости, но небезопасны:
- Нет ASLR (Address Space Layout Randomization) для kernel
- Информация о kernel доступна всем пользователям
- Нет защиты от IP spoofing и SYN flood
- Dmesg доступен non-root пользователям (information leak)

### Что добавить

**Секция Security в defaults/main.yml:**

```yaml
# defaults/main.yml
sysctl_security_params:
  # === ASLR (Address Space Layout Randomization) ===
  kernel.randomize_va_space: 2              # Полная рандомизация адресного пространства

  # === Kernel hardening ===
  kernel.kptr_restrict: 2                   # Скрыть kernel pointers от non-root (dmesg, /proc)
  kernel.dmesg_restrict: 1                  # Ограничить dmesg для root only
  kernel.perf_event_paranoid: 3             # Запретить perf для non-root (side-channel атаки)
  kernel.unprivileged_bpf_disabled: 1       # Запретить BPF для non-root
  kernel.yama.ptrace_scope: 2               # Запретить ptrace (отладка процессов)

  # === Network security ===
  # SYN cookies — защита от SYN flood
  net.ipv4.tcp_syncookies: 1

  # Reverse path filtering — защита от IP spoofing
  net.ipv4.conf.all.rp_filter: 1
  net.ipv4.conf.default.rp_filter: 1

  # ICMP redirects — запретить (MITM атаки)
  net.ipv4.conf.all.accept_redirects: 0
  net.ipv4.conf.default.accept_redirects: 0
  net.ipv6.conf.all.accept_redirects: 0
  net.ipv6.conf.default.accept_redirects: 0

  # Secure redirects — запретить (routing атаки)
  net.ipv4.conf.all.secure_redirects: 0
  net.ipv4.conf.default.secure_redirects: 0

  # Source routing — запретить (IP spoofing)
  net.ipv4.conf.all.accept_source_route: 0
  net.ipv4.conf.default.accept_source_route: 0
  net.ipv6.conf.all.accept_source_route: 0
  net.ipv6.conf.default.accept_source_route: 0

  # ICMP echo — игнорировать broadcasts (smurf атаки)
  net.ipv4.icmp_echo_ignore_broadcasts: 1

  # Игнорировать bogus ICMP errors
  net.ipv4.icmp_ignore_bogus_error_responses: 1

  # TCP timestamps — отключить (fingerprinting)
  net.ipv4.tcp_timestamps: 0

  # Log martian packets (spoofed/invalid source IP)
  net.ipv4.conf.all.log_martians: 1
  net.ipv4.conf.default.log_martians: 1

  # === IPv6 (если не используется) ===
  net.ipv6.conf.all.disable_ipv6: 1
  net.ipv6.conf.default.disable_ipv6: 1
  net.ipv6.conf.lo.disable_ipv6: 1

  # === Filesystem security ===
  fs.protected_hardlinks: 1    # Защита от hardlink exploits
  fs.protected_symlinks: 1     # Защита от symlink exploits
  fs.suid_dumpable: 0          # Запретить core dumps для suid процессов
```

### Файлы

- `ansible/roles/sysctl/defaults/main.yml` — добавить `sysctl_security_params`
- `ansible/roles/sysctl/templates/99-security.conf.j2` — новый шаблон для security параметров
- Результат: `/etc/sysctl.d/99-security.conf`

### Проверка

```bash
# Применить изменения
sysctl --system

# Проверка конкретного параметра
sysctl kernel.randomize_va_space
sysctl net.ipv4.tcp_syncookies

# Проверка всех security параметров
sysctl -a | grep -E "(randomize_va_space|kptr_restrict|tcp_syncookies|rp_filter)"

# Проверка dmesg restrict
dmesg  # Если non-root — должно быть "dmesg: read kernel buffer failed: Operation not permitted"
```

### Impact

- **ASLR**: Защита от memory corruption exploits
- **Kernel information leak**: Ограничение доступа к kernel pointers и dmesg
- **Network attacks**: Защита от SYN flood, IP spoofing, ICMP redirects
- **Filesystem security**: Защита от symlink/hardlink exploits

---

## QW-3: Docker — безопасность daemon

**Роль:** `docker`

### Проблема

Дефолтная конфигурация Docker небезопасна:
- Контейнеры используют root namespace (UID 0 в контейнере = UID 0 на хосте)
- Inter-container communication (ICC) разрешён по умолчанию (контейнеры могут обращаться друг к другу)
- Нет ограничений на capabilities и syscalls
- Логирование через json-file без ротации (переполнение диска)

### Что добавить

**Расширенные настройки в defaults/main.yml:**

```yaml
# defaults/main.yml

# === User namespace remapping ===
docker_userns_remap: "default"  # Изолировать UID/GID контейнеров от хоста
# "default" — автоматическое создание dockremap user/group
# "username:groupname" — кастомный mapping

# === Inter-container communication ===
docker_icc: false  # Запретить прямое общение между контейнерами (требует явные links/networks)

# === Live restore ===
docker_live_restore: true  # Контейнеры продолжают работать при перезапуске daemon

# === Security options ===
docker_no_new_privileges: true  # Запретить privilege escalation в контейнерах (default для всех)
docker_seccomp_profile: "default"  # Seccomp профиль (whitelist syscalls)
docker_apparmor_profile: "docker-default"  # AppArmor профиль (если используется)

# === Logging driver ===
docker_log_driver: "journald"  # Централизованное логирование через journald (вместо json-file)
docker_log_opts:
  tag: "{{.Name}}/{{.ID}}"  # Тег для идентификации контейнера в journald

# === Daemon security ===
docker_iptables: true         # Управление iptables (для network isolation)
docker_ip_forward: true       # IP forwarding (требуется для контейнерных сетей)
docker_ip_masq: true          # NAT для исходящих подключений
docker_userland_proxy: false  # Отключить userland proxy (использовать hairpin NAT)
```

### Конфигурация daemon.json

**Файл:** `/etc/docker/daemon.json`

```json
{
  "userns-remap": "default",
  "icc": false,
  "live-restore": true,
  "no-new-privileges": true,
  "log-driver": "journald",
  "log-opts": {
    "tag": "{{.Name}}/{{.ID}}"
  },
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "userland-proxy": false,
  "seccomp-profile": "/etc/docker/seccomp.json",
  "storage-driver": "overlay2"
}
```

### Файлы

- `ansible/roles/docker/defaults/main.yml` — добавить переменные
- `ansible/roles/docker/templates/daemon.json.j2` — обновить шаблон
- `ansible/roles/docker/handlers/main.yml` — рестарт docker daemon

### User namespace remapping

При включении `userns-remap: default`:
1. Docker создаёт пользователя `dockremap` и группу `dockremap`
2. Файл `/etc/subuid` и `/etc/subgid` содержит mapping:
   ```
   dockremap:100000:65536
   ```
3. UID 0 в контейнере → UID 100000 на хосте
4. Если контейнер escape — атакующий получает UID 100000, а не root

**Ограничения:**
- Volumes с host paths могут не работать (permission issues)
- Несовместимо с некоторыми privileged контейнерами

### Проверка

```bash
# Проверка конфигурации daemon
cat /etc/docker/daemon.json

# Рестарт daemon
systemctl restart docker

# Проверка userns-remap
docker info | grep "Security Options"
# Должно быть: userns

# Проверка логирования
journalctl -u docker -f

# Проверка ICC (должен быть запрещён)
docker network inspect bridge | grep "com.docker.network.bridge.enable_icc"
# false

# Проверка no-new-privileges
docker run --rm alpine cat /proc/self/status | grep NoNewPrivs
# NoNewPrivs: 1
```

### Impact

- **Userns-remap**: Container escape не даёт root на хосте
- **ICC disabled**: Контейнеры изолированы друг от друга (требуют явные networks)
- **No-new-privileges**: Защита от suid exploits в контейнерах
- **Journald logging**: Централизованное логирование, ротация через journald

---

## QW-4: Firewall — SSH rate limiting

**Роль:** `firewall`

### Проблема

SSH bruteforce атаки — постоянная угроза для публичных серверов. Fail2ban помогает, но работает реактивно (банит после попыток). Rate limiting на уровне firewall блокирует атаку проактивно.

### Что добавить

**Переменная в defaults/main.yml:**

```yaml
# defaults/main.yml
firewall_ssh_rate_limit_enabled: true
firewall_ssh_rate_limit: 4         # Максимум 4 подключения в минуту с одного IP
firewall_ssh_rate_limit_burst: 2   # Burst (допустимый всплеск)
```

### Правило nftables

**Файл:** `ansible/roles/firewall/templates/nftables.conf.j2`

**Добавить в chain input (перед правилом accept SSH):**

```nftables
# SSH rate limiting
table inet filter {
    set ssh_ratelimit {
        type ipv4_addr
        flags dynamic
        timeout 1m
    }

    chain input {
        # ... существующие правила ...

        # SSH rate limiting (4 подключения/мин)
        tcp dport 22 ct state new \
            add @ssh_ratelimit { ip saddr limit rate over 4/minute burst 2 packets } \
            counter drop comment "SSH rate limit exceeded"

        # Accept SSH (если rate limit не превышен)
        tcp dport 22 ct state new counter accept comment "SSH"

        # ... остальные правила ...
    }
}
```

### Альтернатива: iptables

Если используется iptables (вместо nftables):

```bash
# Создать chain для SSH rate limiting
iptables -N SSH_RATELIMIT

# Rate limiting: макс 4 подключения/мин
iptables -A SSH_RATELIMIT -m recent --name SSH --set
iptables -A SSH_RATELIMIT -m recent --name SSH --update --seconds 60 --hitcount 5 -j DROP
iptables -A SSH_RATELIMIT -j ACCEPT

# Применить к SSH
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -j SSH_RATELIMIT
```

### Файлы

- `ansible/roles/firewall/defaults/main.yml` — добавить переменные
- `ansible/roles/firewall/templates/nftables.conf.j2` — обновить шаблон

### Проверка

```bash
# Применить правила
nft -f /etc/nftables.conf

# Проверка правила
nft list ruleset | grep -A5 "ssh"

# Тест rate limiting (с другой машины)
for i in {1..10}; do ssh user@host & done
# Первые 4 подключения проходят, остальные блокируются

# Логи (если включено логирование)
journalctl -k | grep "SSH rate limit"
```

### Impact

- **Proactive защита**: Блокирует bruteforce до попыток аутентификации
- **DoS защита**: Ограничивает exhaustion атаки на SSH
- **Дополнение к fail2ban**: Firewall + fail2ban = двойная защита

---

## QW-5: Base System — PAM faillock hardening

**Роль:** `base_system`

### Проблема

Дефолтная PAM конфигурация не блокирует аккаунты после неудачных попыток входа. Bruteforce атаки на локальный login (консоль, display manager) не ограничены.

### Что добавить

**Переменная в defaults/main.yml:**

```yaml
# defaults/main.yml
pam_faillock_enabled: true
pam_faillock_deny: 3               # Блокировка после 3 неудачных попыток
pam_faillock_unlock_time: 900      # Разблокировка через 15 минут (секунды)
pam_faillock_fail_interval: 900    # Окно для подсчёта неудачных попыток (15 минут)
pam_faillock_audit: true           # Логирование в audit log
pam_faillock_silent: true          # Не показывать пользователю количество попыток
pam_faillock_root_unlock_time: -1  # Root: -1 = бессрочная блокировка (требует admin)
```

### Конфигурация PAM

**Файл:** `/etc/security/faillock.conf` (для pam_faillock)

```ini
# Deny after 3 failed attempts
deny = 3

# Unlock time: 900 seconds (15 minutes)
unlock_time = 900

# Fail interval: count attempts within 15 minutes
fail_interval = 900

# Audit logging
audit

# Silent mode (don't reveal attempt count to attacker)
silent

# Root account: require admin unlock (no auto-unlock)
root_unlock_time = -1
```

**Интеграция в PAM (Arch/Debian/Fedora):**

Добавить в `/etc/pam.d/system-auth` (Arch/Fedora) или `/etc/pam.d/common-auth` (Debian):

```pam
# Before pam_unix.so
auth       required   pam_faillock.so preauth
auth       required   pam_unix.so
auth       required   pam_faillock.so authfail

# Account section
account    required   pam_faillock.so
```

### Задача Ansible

```yaml
# ansible/roles/base_system/tasks/pam.yml
- name: Configure PAM faillock
  template:
    src: faillock.conf.j2
    dest: /etc/security/faillock.conf
    owner: root
    group: root
    mode: 0644
  when: pam_faillock_enabled | bool

- name: Enable faillock in PAM system-auth (Arch/Fedora)
  lineinfile:
    path: /etc/pam.d/system-auth
    line: "{{ item }}"
    insertbefore: "^auth.*pam_unix.so"
  loop:
    - "auth       required   pam_faillock.so preauth"
    - "auth       required   pam_faillock.so authfail"
  when:
    - pam_faillock_enabled | bool
    - ansible_os_family in ['Archlinux', 'RedHat']

- name: Enable faillock in PAM common-auth (Debian)
  lineinfile:
    path: /etc/pam.d/common-auth
    line: "{{ item }}"
    insertbefore: "^auth.*pam_unix.so"
  loop:
    - "auth       required   pam_faillock.so preauth"
    - "auth       required   pam_faillock.so authfail"
  when:
    - pam_faillock_enabled | bool
    - ansible_os_family == 'Debian'
```

### Файлы

- `ansible/roles/base_system/defaults/main.yml` — добавить переменные
- `ansible/roles/base_system/templates/faillock.conf.j2` — шаблон конфигурации
- `ansible/roles/base_system/tasks/pam.yml` — новая задача для PAM

### Проверка

```bash
# Тест: 3 неудачных попытки
su - testuser
# Ввести неправильный пароль 3 раза

# Проверка блокировки
faillock --user testuser
# Output: количество failed attempts

# Разблокировка вручную (admin)
faillock --user testuser --reset

# Логи
journalctl -t pam_faillock

# Автоматическая разблокировка (через 15 минут)
# Ждать или проверить:
faillock --user testuser  # Счётчик обнуляется через unlock_time
```

### Impact

- **Bruteforce protection**: Блокировка после 3 неудачных попыток
- **Audit logging**: Все попытки логируются для анализа
- **Silent mode**: Атакующий не знает, сколько попыток осталось
- **Root protection**: Root аккаунт требует admin разблокировки (не авто)

---

## QW-6: User — sudo timeout и audit

**Роль:** `user`

### Проблема

Дефолтные настройки sudo небезопасны:
- `timestamp_timeout=15` минут — долгий кеш sudo (риск если пользователь отошёл от машины)
- Нет логирования команд sudo
- Нет изоляции TTY (возможна инъекция команд через TIOCSTI ioctl)

### Что добавить

**Переменная в defaults/main.yml:**

```yaml
# defaults/main.yml
sudo_hardening_enabled: true
sudo_timestamp_timeout: 5       # Кеш sudo: 5 минут (вместо 15)
sudo_use_pty: true              # Принудительный PTY (защита от TIOCSTI injection)
sudo_logfile: "/var/log/sudo.log"  # Отдельный лог для sudo команд
sudo_log_input: false           # Логировать stdin (опасно, может содержать пароли)
sudo_log_output: false          # Логировать stdout (для audit, но много данных)
sudo_passwd_timeout: 0          # Таймаут ввода пароля (0 = бесконечно, рекомендуется 5 минут)
sudo_authenticate_always: false # Запрашивать пароль для каждой команды (без кеша)
```

### Конфигурация sudoers

**Файл:** `/etc/sudoers.d/hardening`

```sudoers
# Sudo hardening settings

# Кеш sudo: 5 минут (default: 15)
Defaults timestamp_timeout=5

# Принудительный PTY (защита от TTY injection)
Defaults use_pty

# Логирование команд в отдельный файл
Defaults logfile="/var/log/sudo.log"

# Логирование в syslog (дополнительно)
Defaults syslog=authpriv

# Сохранять переменные окружения (опционально)
Defaults env_keep += "EDITOR VISUAL"

# Требовать пароль для sudo -i (full root shell)
Defaults rootpw

# Показывать количество неудачных попыток
Defaults badpass_message="Incorrect password, %p attempts remaining"

# Лимит попыток ввода пароля
Defaults passwd_tries=3
```

### Задача Ansible

```yaml
# ansible/roles/user/tasks/sudo.yml
- name: Create sudo hardening config
  template:
    src: sudoers_hardening.j2
    dest: /etc/sudoers.d/hardening
    owner: root
    group: root
    mode: 0440
    validate: 'visudo -cf %s'
  when: sudo_hardening_enabled | bool

- name: Create sudo log file
  file:
    path: "{{ sudo_logfile }}"
    state: touch
    owner: root
    group: root
    mode: 0600
  when: sudo_hardening_enabled | bool

- name: Configure logrotate for sudo log
  template:
    src: sudo_logrotate.j2
    dest: /etc/logrotate.d/sudo
    owner: root
    group: root
    mode: 0644
  when: sudo_hardening_enabled | bool
```

### Logrotate для sudo

**Файл:** `/etc/logrotate.d/sudo`

```
/var/log/sudo.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0600 root root
}
```

### Файлы

- `ansible/roles/user/defaults/main.yml` — добавить переменные
- `ansible/roles/user/templates/sudoers_hardening.j2` — шаблон sudoers
- `ansible/roles/user/templates/sudo_logrotate.j2` — шаблон logrotate
- `ansible/roles/user/tasks/sudo.yml` — новая задача для sudo hardening

### Проверка

```bash
# Проверка синтаксиса sudoers
visudo -c

# Проверка конкретного файла
visudo -cf /etc/sudoers.d/hardening

# Тест кеша (должен запрашивать пароль через 5 минут)
sudo ls
# Ждать 5 минут
sudo ls  # Должен запросить пароль снова

# Проверка логирования
sudo cat /var/log/sudo.log

# Пример лога:
# Feb 16 10:30:15 hostname user : TTY=pts/0 ; PWD=/home/user ; USER=root ; COMMAND=/usr/bin/ls
```

### use_pty защита

`use_pty` защищает от атаки через TIOCSTI ioctl:

**Атака (без use_pty):**
```c
// Злоумышленник может инъектировать команды в parent TTY
ioctl(0, TIOCSTI, "rm -rf /\n");
```

**Защита (с use_pty):**
Sudo создаёт отдельный PTY, изолированный от parent shell. Инъекция не работает.

### Impact

- **Short timeout**: Кеш sudo 5 минут вместо 15 (меньше окно для атаки)
- **PTY isolation**: Защита от TTY injection атак
- **Audit logging**: Все sudo команды логируются для forensics
- **Visibility**: Администратор видит все privileged операции

---

## Итоги Quick Wins

| QW | Роль | Изменение | Security Impact |
|----|------|-----------|-----------------|
| **QW-1** | `ssh` | Crypto restrictions, DoS protection, AllowGroups | Защита от crypto атак и bruteforce |
| **QW-2** | `sysctl` | ASLR, kptr_restrict, rp_filter, SYN cookies | Kernel hardening, network security |
| **QW-3** | `docker` | userns-remap, no-new-privileges, journald | Container isolation, audit |
| **QW-4** | `firewall` | SSH rate limiting (4/min) | Proactive bruteforce protection |
| **QW-5** | `base_system` | PAM faillock (deny=3, unlock=15min) | Local bruteforce protection |
| **QW-6** | `user` | Sudo timeout=5, use_pty, logfile | Sudo abuse protection, audit |

**Приоритет внедрения:** QW-1 → QW-2 → QW-4 → QW-5 → QW-6 → QW-3

**Время на внедрение:** ~1-2 дня для всех Quick Wins

**Рекомендации:**
- Тестируйте на staging перед production
- QW-3 (Docker userns-remap) может сломать существующие volumes — проверьте совместимость
- QW-2 (sysctl) может повлиять на производительность — мониторьте CPU/network

---

Назад к [[Roadmap]]
