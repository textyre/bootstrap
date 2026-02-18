# NTP Role Enhancement — chrony.conf Management

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend the existing `ntp` role to deploy a managed `chrony.conf` with NTS-enabled servers, full parametrization via variables, dumpdir for fast post-reboot sync, and detailed logging for Loki.

**Architecture:** Add a Jinja2 template for `/etc/chrony.conf`, 9 new variables in `defaults/main.yml` with sensible defaults (4 NTS servers from 3 providers, makestep, minsources, dumpdir, logging), one new template-deploy task inserted before service start, and 6 new Molecule assertions verifying the config is correctly rendered.

**Tech Stack:** Ansible 2.15+, chrony 4.x, Jinja2, Molecule (local Arch Linux)

---

## Files at a Glance

| File | Action |
|------|--------|
| `ansible/roles/ntp/defaults/main.yml` | Modify — add 9 variables |
| `ansible/roles/ntp/templates/chrony.conf.j2` | Create — new Jinja2 template |
| `ansible/roles/ntp/tasks/main.yml` | Modify — insert 1 task before service start |
| `ansible/roles/ntp/molecule/default/verify.yml` | Modify — add 6 assertions |

**No changes to:** `handlers/main.yml`, `vars/main.yml`, `meta/main.yml`, `tasks/disable_systemd.yml`

---

## Task 1: Add Molecule assertions (TDD — write tests first)

**Files:**
- Modify: `ansible/roles/ntp/molecule/default/verify.yml`

These assertions will FAIL until the template task is implemented. That's intentional — we verify the tests are catching the missing behavior before we fix it.

**Step 1: Add 6 assertions to verify.yml**

Open `ansible/roles/ntp/molecule/default/verify.yml`. Find the last task (`Show result`) and insert the following block **before** it:

```yaml
    - name: Verify chrony.conf is deployed by Ansible
      ansible.builtin.stat:
        path: /etc/chrony.conf
      register: _verify_chrony_conf

    - name: Assert chrony.conf exists and is a regular file
      ansible.builtin.assert:
        that:
          - _verify_chrony_conf.stat.exists
          - _verify_chrony_conf.stat.isreg
        fail_msg: "/etc/chrony.conf is missing"

    - name: Read chrony.conf content
      ansible.builtin.slurp:
        src: /etc/chrony.conf
      register: _verify_chrony_conf_content

    - name: Decode chrony.conf content
      ansible.builtin.set_fact:
        _verify_chrony_conf_text: "{{ _verify_chrony_conf_content.content | b64decode }}"

    - name: Assert NTS flag present in at least one server line
      ansible.builtin.assert:
        that:
          - "'nts' in _verify_chrony_conf_text"
        fail_msg: "No NTS servers found in /etc/chrony.conf"

    - name: Assert minsources directive present
      ansible.builtin.assert:
        that:
          - "'minsources' in _verify_chrony_conf_text"
        fail_msg: "minsources directive missing from /etc/chrony.conf"

    - name: Assert driftfile directive present
      ansible.builtin.assert:
        that:
          - "'driftfile' in _verify_chrony_conf_text"
        fail_msg: "driftfile directive missing from /etc/chrony.conf"

    - name: Assert dumpdir directive present
      ansible.builtin.assert:
        that:
          - "'dumpdir' in _verify_chrony_conf_text"
        fail_msg: "dumpdir directive missing from /etc/chrony.conf"

    - name: Assert log tracking directive present
      ansible.builtin.assert:
        that:
          - "'log measurements statistics tracking' in _verify_chrony_conf_text"
        fail_msg: "log tracking directive missing from /etc/chrony.conf"
```

**Step 2: Run Molecule verify to confirm tests fail**

Use the `/ansible` skill:
```
Run: molecule verify -s default
Working dir: ansible/roles/ntp/
```

Expected: FAIL on "Assert NTS flag present" — confirming we're testing the right thing.
The existing `/etc/chrony.conf` (from package) won't have `nts`, `minsources`, or `dumpdir`.

**Step 3: Commit the failing tests**

```bash
git add ansible/roles/ntp/molecule/default/verify.yml
git commit -m "test(ntp): add chrony.conf content assertions for NTS and parameters"
```

---

## Task 2: Add variables to defaults/main.yml

**Files:**
- Modify: `ansible/roles/ntp/defaults/main.yml`

**Step 1: Replace the file content**

Current content:
```yaml
---
# === NTP — синхронизация времени ===
# chrony как универсальный NTP-демон (все дистро, все init-системы)

ntp_enabled: true
```

New content (preserve the existing `ntp_enabled`, add 9 new variables):
```yaml
---
# === NTP — синхронизация времени ===
# chrony как универсальный NTP-демон (все дистро, все init-системы)

ntp_enabled: true

# NTP-серверы — список объектов {host, nts, iburst}
# Три независимых провайдера с поддержкой NTS (RFC 8915)
ntp_servers:
  - { host: "time.cloudflare.com",  nts: true, iburst: true }
  - { host: "time.nist.gov",        nts: true, iburst: true }
  - { host: "ptbtime1.ptb.de",      nts: true, iburst: true }
  - { host: "ptbtime2.ptb.de",      nts: true, iburst: true }

# Коррекция часов при запуске chrony
# Прыжок если расхождение > threshold сек, только в первые limit обновлений
ntp_makestep_threshold: 1.0
ntp_makestep_limit: 3

# Минимум согласующихся источников для обновления системных часов
# Защищает от одиночного испорченного сервера
ntp_minsources: 2

# Пути к файлам chrony
ntp_driftfile: "/var/lib/chrony/drift"
ntp_dumpdir: "/var/lib/chrony"     # история измерений — ускоряет старт после перезагрузки

# Каталог для лог-файлов chrony (читается Promtail/Loki)
ntp_logdir: "/var/log/chrony"

# Синхронизация аппаратных часов (RTC) с системными
ntp_rtcsync: true

# Логировать изменения часов > N секунд в syslog
ntp_logchange: 0.5

# Детальное логирование замеров для Loki
# Пишет measurements.log, statistics.log, tracking.log в ntp_logdir
ntp_log_tracking: true
```

**Step 2: Verify YAML is valid**

```bash
python3 -c "import yaml; yaml.safe_load(open('ansible/roles/ntp/defaults/main.yml'))"
```

Expected: no output (no errors).

**Step 3: Commit**

```bash
git add ansible/roles/ntp/defaults/main.yml
git commit -m "feat(ntp): add chrony.conf variables — NTS servers, makestep, minsources, dumpdir, logging"
```

---

## Task 3: Create the Jinja2 template

**Files:**
- Create: `ansible/roles/ntp/templates/chrony.conf.j2`

**Step 1: Create the templates directory and file**

```
Create: ansible/roles/ntp/templates/chrony.conf.j2
```

Full content:
```jinja2
# Managed by Ansible — do not edit manually
# Role: ntp | Template: chrony.conf.j2

{% for server in ntp_servers %}
server {{ server.host }}{% if server.iburst | default(true) %} iburst{% endif %}{% if server.nts | default(false) %} nts{% endif %}

{% endfor %}
# Clock stability
driftfile {{ ntp_driftfile }}
{% if ntp_dumpdir %}
dumpdir {{ ntp_dumpdir }}
{% endif %}
makestep {{ ntp_makestep_threshold }} {{ ntp_makestep_limit }}
minsources {{ ntp_minsources }}

{% if ntp_rtcsync %}
# Sync hardware RTC to system clock
rtcsync
{% endif %}

# Leap seconds from system timezone database
leapsectz right/UTC

# Logging
logdir {{ ntp_logdir }}
logchange {{ ntp_logchange }}
{% if ntp_log_tracking %}
log measurements statistics tracking
{% endif %}
```

**Expected rendered output with defaults:**
```
server time.cloudflare.com iburst nts
server time.nist.gov iburst nts
server ptbtime1.ptb.de iburst nts
server ptbtime2.ptb.de iburst nts

driftfile /var/lib/chrony/drift
dumpdir /var/lib/chrony
makestep 1.0 3
minsources 2

rtcsync

leapsectz right/UTC

logdir /var/log/chrony
logchange 0.5
log measurements statistics tracking
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp/templates/chrony.conf.j2
git commit -m "feat(ntp): add chrony.conf.j2 template with NTS servers and full parametrization"
```

---

## Task 4: Add deploy-template task to tasks/main.yml

**Files:**
- Modify: `ansible/roles/ntp/tasks/main.yml` — insert after disable block, before service start

The new task must go **after** "Disable conflicting time sync daemons" and **before** "Enable and start chronyd". This ensures:
1. Service starts with the correct config (not package default)
2. If config changes later, the handler restarts chronyd

**Step 1: Insert the task**

In `ansible/roles/ntp/tasks/main.yml`, find this block:

```yaml
# ======================================================================
# ---- Запуск chrony ----
# ======================================================================

- name: Enable and start chronyd
```

Insert the following **immediately before** that block (before the comment line):

```yaml
# ======================================================================
# ---- Конфигурация ----
# ======================================================================

- name: Deploy chrony configuration
  ansible.builtin.template:
    src: chrony.conf.j2
    dest: /etc/chrony.conf
    owner: root
    group: root
    mode: "0644"
  notify: restart ntp
  tags: ['ntp']

```

**Step 2: Verify YAML syntax**

Use the `/ansible` skill:
```
Run: ansible-playbook --syntax-check ansible/playbooks/workstation.yml
```

Expected: no errors.

**Step 3: Commit**

```bash
git add ansible/roles/ntp/tasks/main.yml
git commit -m "feat(ntp): deploy chrony.conf from template before service start"
```

---

## Task 5: Run full Molecule test suite

**Step 1: Run full Molecule sequence**

Use the `/ansible` skill:
```
Run: molecule test -s default
Working dir: ansible/roles/ntp/
```

This runs: syntax → converge → verify.

Expected result:
- `converge`: all tasks pass, "Deploy chrony configuration" shows `changed`
- `verify`: all existing assertions pass + all 6 new assertions pass

**Step 2: If verify fails on NTS assertions**

The remote VM's chrony may not have internet access during Molecule tests. If NTS assertions fail because `chronyc sources` shows no NTS sources (VM behind NAT without NTS connectivity), the assertions in `verify.yml` about `chronyc sources` checking NTS are separate from the config-content assertions. Our new assertions check `/etc/chrony.conf` file content — not live NTS status — so they should pass regardless.

If `chronyc tracking` fails (no internet = no sync = stratum 0 / unsynchronised), check if Molecule runs with network access. The existing verification was already there before our changes.

**Step 3: Commit (only if not already committed per task)**

All commits were done per task. Nothing to commit here.

---

## Task 6: Update meta/main.yml description

**Files:**
- Modify: `ansible/roles/ntp/meta/main.yml`

**Step 1: Update description field**

Change:
```yaml
  description: >-
    NTP time synchronization via chrony. Installs chrony, disables
    systemd-timesyncd, enables and verifies chronyd.
    Supports Arch Linux, Debian, Ubuntu, RedHat/EL, Alpine, Void Linux.
```

To:
```yaml
  description: >-
    NTP time synchronization via chrony. Installs chrony, deploys
    chrony.conf with NTS-enabled servers (Cloudflare, NIST, PTB),
    disables systemd-timesyncd, enables and verifies chronyd.
    Supports Arch Linux, Debian, Ubuntu, RedHat/EL, Alpine, Void Linux.
```

**Step 2: Commit**

```bash
git add ansible/roles/ntp/meta/main.yml
git commit -m "docs(ntp): update meta description to mention NTS and chrony.conf management"
```

---

## Verification Checklist

After all tasks complete, confirm:

- [ ] `ansible/roles/ntp/defaults/main.yml` has `ntp_servers`, `ntp_makestep_threshold`, `ntp_makestep_limit`, `ntp_minsources`, `ntp_driftfile`, `ntp_dumpdir`, `ntp_logdir`, `ntp_rtcsync`, `ntp_logchange`, `ntp_log_tracking`
- [ ] `ansible/roles/ntp/templates/chrony.conf.j2` exists
- [ ] `ansible/roles/ntp/tasks/main.yml` has "Deploy chrony configuration" task with `notify: restart ntp`
- [ ] `ansible/roles/ntp/molecule/default/verify.yml` has 6 new assertions using `slurp` + `b64decode`
- [ ] `molecule test` passes all assertions
- [ ] `/etc/chrony.conf` on the VM contains `nts`, `minsources 2`, `dumpdir`, `log measurements statistics tracking`
- [ ] `chronyc sources` on the VM shows NTS servers (indicated by `*` or `+` and `nts` in source info)
