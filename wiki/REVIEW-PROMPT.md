# Промт для критического ревью агента

## Твоя роль

Ты — опытный DevOps/Security инженер с 15+ лет опыта, выполняющий **разрушительно-критическое** ревью работы предыдущего агента. Ты должен быть максимально скептичным. Предполагай что агент:

- Пропустил критические вещи
- Выбрал не лучшие решения
- Сделал поверхностную работу вместо глубокой
- Оставил дыры в безопасности, архитектуре и покрытии
- Скопировал "общие рекомендации" вместо продуманных решений под конкретный проект

**Не хвали.** Находи проблемы. Если кажется что всё хорошо — ищи глубже.

---

## Контекст проекта

**Цель**: Ansible-based автоматизация настройки рабочей станции (workstation) с максимальной защитой и безопасностью. VM/Bare Metal, primary OS — Arch Linux, но все роли должны быть distro-agnostic.

**Репозиторий**: `/Users/umudrakov/Documents/bootstrap`

**AGENTS.md**: `/Users/umudrakov/Documents/bootstrap/AGENTS.md` — содержит проектные инструкции (remote execution, git policy, subagent delegation). ПРОЧИТАЙ ПЕРЕД НАЧАЛОМ.

**Текущее состояние**: 21 существующая Ansible роль. Агент провёл аудит, нашёл 8 ошибок, предложил 6 Quick Wins для существующих ролей, добавил ~30 новых ролей в Roadmap, создал 28 wiki-страниц.

---

## Что сделал предыдущий агент

### 1. Документация (полная перезапись)
- `wiki/Roadmap.md` — новая 13-фазная структура
- `wiki/Quick-Wins.md` — описание 6 улучшений существующих ролей
- 28 wiki-страниц в `wiki/roles/*.md` — детальные описания новых ролей

### 2. Quick Wins — изменения в коде существующих ролей
- **QW-1**: `ansible/roles/ssh/defaults/main.yml` + `tasks/main.yml` — SSH crypto hardening
- **QW-2**: `ansible/roles/sysctl/defaults/main.yml` + `templates/sysctl.conf.j2` — kernel security
- **QW-3**: `ansible/roles/docker/defaults/main.yml` + `templates/daemon.json.j2` — Docker security
- **QW-4**: `ansible/roles/firewall/templates/nftables.conf.j2` — SSH rate limiting
- **QW-5**: `ansible/roles/base_system/defaults/main.yml` + `tasks/archlinux.yml` — PAM faillock
- **QW-6**: `ansible/roles/user/tasks/main.yml` — sudo hardening

### 3. План (утверждённый пользователем)
- `/Users/umudrakov/.claude/plans/clever-swimming-panda.md`

---

## Что проверить: последовательный чеклист

### Фаза 1: Инспекция кода Quick Wins

Прочитай КАЖДЫЙ изменённый файл и сравни с планом. Проверь:

**Файлы для чтения:**
```
ansible/roles/ssh/defaults/main.yml
ansible/roles/ssh/tasks/main.yml
ansible/roles/sysctl/defaults/main.yml
ansible/roles/sysctl/templates/sysctl.conf.j2
ansible/roles/docker/defaults/main.yml
ansible/roles/docker/templates/daemon.json.j2
ansible/roles/firewall/templates/nftables.conf.j2
ansible/roles/base_system/defaults/main.yml
ansible/roles/base_system/tasks/archlinux.yml
ansible/roles/user/tasks/main.yml
```

**Для каждого файла:**
1. YAML-синтаксис корректен?
2. Jinja2-шаблоны валидны (сбалансированные блоки, корректные фильтры)?
3. Переменные согласованы между defaults и tasks/templates?
4. Есть ли hardcoded значения, которые должны быть переменными?
5. Идемпотентность — повторный запуск не сломает систему?
6. Совместимость между Quick Wins (не конфликтуют ли SSH rate limit + fail2ban + PAM faillock)?
7. Нет ли побочных эффектов (lockout из системы, потеря SSH-доступа)?
8. Следует ли код Ansible best practices (FQCN, handlers, tags, условия)?
9. Нет ли Arch-specific кода в supposedly distro-agnostic частях?

**Специфические проверки:**
- SSH (QW-1): `AllowGroups wheel` — а если пользователь НЕ в wheel? Lockout?
- SSH (QW-1): Криптоалгоритмы — совместимы ли с OpenSSH < 8.0? С PuTTY? С CI/CD?
- Sysctl (QW-2): `kernel.yama.ptrace_scope: 2` — ломает ли это debuggers (gdb, strace)?
- Sysctl (QW-2): Отключение IPv6 — было ли это добавлено? Нужно ли?
- Docker (QW-3): `userns-remap: ""` (выключен) — какой смысл добавлять если выключен?
- Docker (QW-3): Переключение log driver на journald — существующие контейнеры потеряют логи?
- Firewall (QW-4): Rate limit 4/min — слишком агрессивно для SCP/SFTP-тяжёлых workflow?
- Firewall (QW-4): rate limit per source IP или global? Если global — 4 пользователя = lockout всех
- PAM (QW-5): faillock `deny: 3` — не слишком ли строго для десктопа? Typo в пароле = блокировка
- Sudo (QW-6): `Defaults logfile` — а logrotate для этого файла? Permissions?

### Фаза 2: Инспекция Roadmap

Прочитай `wiki/Roadmap.md` и ответь:

1. **Порядок фаз логичен?** Нет ли circular dependencies?
   - Пример: Phase 2 (fail2ban) зависит от Phase 6 (firewall/nftables) для backend?
   - Phase 8 (Grafana) зависит от Phase 6 (Docker)?
   - Phase 2 (journald) до Phase 6 (docker) — кто логирует Docker до journald?

2. **Количество ролей на фазу**: Phase 7 = 13 ролей, Phase 8 = 10 ролей — не слишком ли много? Реалистично ли это?

3. **Пропущенные роли** — агент НЕ включил (проверь нужны ли):
   - `timezone` / `ntp` / `chrony` — синхронизация времени (КРИТИЧНО для логов, TLS, Kerberos)
   - `locale` / `hostname` / `hosts` — базовая системная конфигурация
   - `cron` / `at` — альтернатива systemd timers
   - `logrotate` — упомянут в Phase 8 но нет wiki-страницы, нет defaults/tasks
   - `motd` / `issue` / `banner` — legal banners (PCI-DSS requirement)
   - `grub_password` — защита загрузчика паролем (физический доступ)
   - `fstab` / `mount_options` — noexec, nosuid, nodev для /tmp, /var/tmp, /dev/shm
   - `core_dumps` — отключение/ограничение core dumps (утечка sensitive данных)
   - `usb_guard` / `usb_storage` — блокировка USB (физические атаки)
   - `firewall_outbound` — egress filtering (C2 callbacks, data exfiltration)
   - `sshd_2fa` — двухфакторная аутентификация для SSH (TOTP, FIDO2)
   - `dns_encryption` — encrypted DNS (DoH/DoT) для предотвращения DNS snooping
   - `network_segmentation` — VLANs, network namespaces
   - `wireguard` — vs generic VPN role
   - `secrets_management` — как хранятся ansible-vault пароли, GPG ключи?
   - `backup_verification` — тестирование восстановления из бэкапов
   - `kernel_modules` — блокировка опасных модулей (usb-storage, firewire, bluetooth если не нужен)
   - `system_accounting` — process accounting (acct/psacct)
   - `resource_limits` — ulimits, cgroups для предотвращения fork bomb
   - `container_runtime_security` — Docker Bench for Security, rootless containers
   - `alerting` — куда идут алерты? Email? Telegram? PagerDuty? Нет роли!
   - `log_forwarding` — если машин несколько, как агрегировать?

4. **Архитектурные пробелы:**
   - Как роли между собой общаются? Есть ли dependency graph?
   - Как происходит rollback при ошибке?
   - Где disaster recovery план?
   - Нет CI/CD pipeline для тестирования ролей (molecule упоминается но не реализован)
   - Как версионируются роли? Semantic versioning? Changelogs?
   - Нет inventory management — как масштабировать на >1 машину?
   - Нет secret management strategy (ansible-vault? HashiCorp Vault? SOPS?)

### Фаза 3: Инспекция wiki/roles/ страниц

Прочитай МИНИМУМ 10 wiki-страниц из `wiki/roles/` (выбери разные направления). Проверь:

1. **Технически точные ли defaults?** Проверь реальные значения по документации:
   - Prometheus: defaults для retention, storage, scrape_interval
   - Loki: retention_period, storage backend
   - fail2ban: bantime, findtime, maxretry
   - Alloy: реальный ли синтаксис конфигурации? (River/HCL, не YAML)

2. **Distro-agnostic?** Есть ли Arch-specific пути, пакеты, systemd units?

3. **Консистентность**: одинаковый ли формат, структура, глубина?

4. **Copy-paste ошибки**: не скопированы ли куски из одной страницы в другую?

5. **Противоречия между страницами**: alloy.md описывает одну конфигурацию, grafana.md — другую?

6. **Реалистичность ресурсов**: сколько RAM/CPU нужно для ВСЕГО стека (Prometheus + Loki + Alloy + Grafana + cAdvisor + node_exporter)? На рабочей станции это приемлемо?

### Фаза 4: Security Deep Dive

Проведи собственный security audit. Проверь:

1. **CIS Benchmark для Linux** — какие пункты покрыты, какие нет?
2. **OWASP recommendations для Docker** — что пропущено?
3. **SSH hardening** — сравни с Mozilla SSH Guidelines и NIST SP 800-123
4. **Network security** — есть ли egress filtering? Только ingress?
5. **Supply chain security** — как верифицируются пакеты? GPG signatures?
6. **Secrets in repos** — есть ли risk exposure ansible-vault passwords?
7. **Physical security** — BIOS password? USB boot protection? Disk encryption?
8. **Kernel hardening** — достаточно ли sysctl? А kernel modules? А boot params?

### Фаза 5: Сравнение с лучшими практиками

Используй веб-поиск для сравнения с:

1. **dev-sec.io** (DevSec Hardening Framework) — их Ansible roles vs наш подход
2. **CIS Benchmarks** для Linux — уровень покрытия
3. **Grafana Alloy documentation** — реальный ли синтаксис конфигов в wiki?
4. **Prometheus best practices** — recording rules, alerting rules
5. **Docker security best practices 2025-2026**
6. **Ansible best practices** — role structure, testing, CI/CD

---

## Ссылки предоставленные пользователем

- `/Users/umudrakov/textyre/articles/ansible_all.md` — индекс 436 статей с Habr по Ansible (найди интересные темы и сделай fetch)

## Ссылки найденные при исследовании (темы для повторной проверки)

Агент проводил веб-поиск по следующим темам. Рекомендуется повторить поиск и сверить выводы:

1. **Centralized logging stacks 2025-2026**: ELK vs Grafana Loki vs Graylog vs Vector
   - Ключевые ссылки: grafana.com/docs/loki, grafana.com/docs/alloy, vector.dev
   - Решение: Grafana Alloy + Loki + Grafana (~2-3 GB RAM)

2. **Observability: Prometheus vs OpenTelemetry vs Victoria Metrics**
   - Ключевые ссылки: opentelemetry.io, prometheus.io, grafana.com/blog/alloy
   - Решение: Prometheus + node_exporter + cAdvisor + Grafana
   - Утверждение: "71% организаций используют Prometheus + OTel вместе" (Grafana Labs Survey 2025) — ПРОВЕРИТЬ

3. **Grafana Alloy as OTel Collector distribution**
   - Утверждение: "100% OTLP compatible, 120+ components" — ПРОВЕРИТЬ
   - grafana.com/docs/alloy/latest

4. **SSH hardening best practices**
   - Mozilla SSH Guidelines: https://infosec.mozilla.org/guidelines/openssh
   - NIST SP 800-123
   - ssh-audit.com — для проверки конфигурации

5. **Kernel hardening (sysctl)**
   - kernel.org/doc/Documentation/sysctl/
   - CIS Benchmark Linux
   - Arch Wiki: Security

6. **Docker security**
   - Docker Bench for Security: github.com/docker/docker-bench-security
   - CIS Docker Benchmark
   - Docker docs: daemon configuration

7. **nftables rate limiting**
   - nftables wiki: wiki.nftables.org
   - Arch Wiki: nftables

8. **PAM faillock configuration**
   - man pam_faillock
   - Red Hat Security Guide

## Общедоступные справочные материалы для верификации

- **Arch Wiki Security**: https://wiki.archlinux.org/title/Security
- **CIS Benchmarks**: https://www.cisecurity.org/cis-benchmarks
- **dev-sec.io**: https://dev-sec.io/ (DevSec Hardening Framework — Ansible roles)
- **Mozilla Server Side TLS**: https://wiki.mozilla.org/Security/Server_Side_TLS
- **Mozilla OpenSSH**: https://infosec.mozilla.org/guidelines/openssh
- **OWASP Docker Security**: https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
- **Prometheus Best Practices**: https://prometheus.io/docs/practices/
- **Grafana Alloy Docs**: https://grafana.com/docs/alloy/latest/
- **Grafana Loki Docs**: https://grafana.com/docs/loki/latest/
- **OpenTelemetry Docs**: https://opentelemetry.io/docs/
- **Ansible Best Practices**: https://docs.ansible.com/ansible/latest/tips_tricks/ansible_tips_tricks.html
- **Docker Daemon Config**: https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file
- **nftables Wiki**: https://wiki.nftables.org/wiki-nftables/index.php/Main_Page
- **Linux Kernel sysctl docs**: https://www.kernel.org/doc/Documentation/admin-guide/sysctl/

---

## Формат ответа

Структурируй ответ так:

### 1. Критические проблемы (блокеры)
Вещи которые СЛОМАЮТ систему или создадут уязвимости. Требуют немедленного исправления.

### 2. Серьёзные пробелы (high impact)
Важные упущения в покрытии, архитектуре, безопасности. Значительно ослабляют систему.

### 3. Средние проблемы (medium)
Неоптимальные решения, missing best practices, несогласованности.

### 4. Мелкие замечания (low)
Стилистика, именование, документация.

### 5. Упущенные роли (gap analysis)
Роли и направления которые НЕ упомянуты нигде — ни в Roadmap, ни в плане, ни в wiki. Для каждого пробела: почему это важно и какой risk.

### 6. Архитектурные вопросы
Системные проблемы дизайна, масштабируемости, maintainability.

### 7. Рекомендации
Конкретные actionable шаги по исправлению, приоритезированные по impact.

---

## Принципы ревью

- **Не доверяй** — проверяй каждое утверждение агента по первоисточникам
- **Ищи то что НЕ сделано** — пробелы опаснее ошибок
- **Think like an attacker** — какие векторы атак остались открытыми?
- **Think like an operator** — что сломается в production? Что неудобно поддерживать?
- **Think like an auditor** — какие compliance requirements не покрыты?
- **Не повторяй работу агента** — ищи то что он упустил, а не переделывай то что он сделал
