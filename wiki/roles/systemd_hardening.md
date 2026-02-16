# Роль: systemd_hardening

**Phase**: 6 | **Направление**: Services

## Цель

Применение sandboxing и изоляции для systemd-сервисов через директивы безопасности. Ограничивает доступ к файловой системе, блокирует опасные системные вызовы, отключает повышение привилегий и минимизирует attack surface критических сервисов.

## Ключевые переменные (defaults)

```yaml
systemd_hardening_enabled: true  # Включить hardening для сервисов

# Целевые сервисы для hardening (список unit-файлов)
systemd_hardening_services:
  - sshd
  - docker
  - caddy
  - nginx

# Директивы безопасности (применяются через drop-in файлы)
systemd_hardening_private_tmp: true          # PrivateTmp=yes — изолированный /tmp
systemd_hardening_protect_system: "strict"   # ProtectSystem=strict — read-only /usr, /boot, /efi
systemd_hardening_protect_home: true         # ProtectHome=yes — запрет доступа к /home
systemd_hardening_no_new_privileges: true    # NoNewPrivileges=yes — запрет suid/sgid
systemd_hardening_private_devices: false     # PrivateDevices=yes — изолированный /dev
systemd_hardening_protect_kernel_tunables: true  # ProtectKernelTunables=yes — read-only /proc/sys
systemd_hardening_protect_kernel_modules: true   # ProtectKernelModules=yes — запрет modprobe
systemd_hardening_protect_control_groups: true   # ProtectControlGroups=yes — read-only /sys/fs/cgroup
systemd_hardening_restrict_address_families: ["AF_INET", "AF_INET6", "AF_UNIX"]  # Ограничение сетевых семейств
systemd_hardening_restrict_namespaces: true      # RestrictNamespaces=yes — запрет unshare
systemd_hardening_lock_personality: true         # LockPersonality=yes — запрет personality()
systemd_hardening_memory_deny_write_execute: false  # MemoryDenyWriteExecute=yes — W^X защита (может ломать JIT)
systemd_hardening_restrict_realtime: true        # RestrictRealtime=yes — запрет realtime планировщика
systemd_hardening_restrict_suid_sgid: true       # RestrictSUIDSGID=yes — запрет suid/sgid файлов
systemd_hardening_system_call_filter: "@system-service"  # SystemCallFilter — whitelist syscall (default set)
systemd_hardening_system_call_architectures: "native"    # SystemCallArchitectures=native — запрет 32-bit на x86_64

# Дополнительные ограничения
systemd_hardening_read_write_paths: []      # ReadWritePaths — разрешить запись (исключения из ProtectSystem)
systemd_hardening_read_only_paths: []       # ReadOnlyPaths — принудительно read-only
systemd_hardening_inaccessible_paths: []    # InaccessiblePaths — полностью скрыть пути

# Капабилити (CAP_NET_BIND_SERVICE для sshd/caddy, остальные drop)
systemd_hardening_ambient_capabilities: []  # AmbientCapabilities — минимальный набор
systemd_hardening_capability_bounding_set: []  # CapabilityBoundingSet — ограничение капабилити
```

## Что настраивает

**На всех дистрибутивах:**
- Drop-in файлы в `/etc/systemd/system/<service>.service.d/hardening.conf`
- Применение директив безопасности к целевым сервисам
- Перезагрузка systemd (`systemctl daemon-reload`)
- Рестарт сервисов с новыми настройками

**На Arch Linux:**
- Пакет: `systemd` (уже установлен)
- Путь к drop-in: `/etc/systemd/system/`

**На Debian/Ubuntu:**
- Пакет: `systemd` (уже установлен)
- Путь к drop-in: `/etc/systemd/system/`

**На Fedora/RHEL:**
- Пакет: `systemd` (уже установлен)
- Путь к drop-in: `/etc/systemd/system/`

## Зависимости

- `base_system` — базовый systemd и утилиты

## Примечания

### Проверка hardening

```bash
# Анализ безопасности сервиса
systemd-analyze security sshd.service

# Проверка применённых директив
systemctl show sshd.service | grep -E "(PrivateTmp|ProtectSystem|NoNewPrivileges)"
```

### Совместимость

- `MemoryDenyWriteExecute=yes` — может ломать приложения с JIT (Node.js, Java, .NET)
- `ProtectHome=yes` — блокирует доступ к пользовательским данным (не подходит для desktop-сервисов)
- `PrivateDevices=yes` — блокирует доступ к устройствам (несовместимо с GPU/аудио)

### SystemCallFilter наборы

- `@system-service` — базовый набор для демонов
- `@basic-io` — файловые операции
- `@network-io` — сетевые операции
- Чёрный список: `~@privileged @resources`

## Tags

- `systemd`
- `hardening`
- `security`
- `sandboxing`

---

Назад к [[Roadmap]]
