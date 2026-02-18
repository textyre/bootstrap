# timezone: cron restart handler — implementation plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a cron restart handler to the timezone role so that crond is restarted when the timezone actually changes, with transparent skip-logging if cron is not installed.

**Architecture:** Two handler tasks bound via `listen: restart cron` — first gathers `service_facts`, second restarts cron only `when: cron service in facts`. Handler is triggered by `notify: restart cron` on the "Set timezone" task. Cron service name mapped per `os_family` in `vars/main.yml`.

**Tech Stack:** Ansible, `ansible.builtin.service_facts`, `ansible.builtin.service`

**Design doc:** `docs/plans/2026-02-18-timezone-cron-handler-design.md`

---

### Task 1: Create `vars/main.yml` with cron service name mapping

**Files:**
- Create: `ansible/roles/timezone/vars/main.yml`

**Step 1: Create the file**

```yaml
---
# === Таймзона — внутренние переменные ===
# Имя cron-сервиса по os_family
# Используется в handlers/main.yml для перезапуска cron после смены таймзоны
_tz_cron_service:
  Archlinux: crond
  Debian: cron
  Ubuntu: cron
  RedHat: crond
  Void: crond
  Gentoo: crond
```

**Step 2: Verify YAML syntax is valid** (визуальная проверка отступов).

**Step 3: Show git command**

```bash
git add ansible/roles/timezone/vars/main.yml
git commit -m "feat(timezone): add vars/main.yml with cron service name mapping"
```

---

### Task 2: Create `handlers/main.yml`

**Files:**
- Create: `ansible/roles/timezone/handlers/main.yml`

**Step 1: Create the file**

```yaml
---
# === Таймзона — handlers ===

# Перезапуск cron после смены таймзоны
# Два шага через listen: service_facts → restart (только если cron установлен)
# Логи: skipped если не установлен, changed если перезапущен

- name: Gather service facts for cron restart
  ansible.builtin.service_facts:
  listen: restart cron

- name: Restart cron if present
  ansible.builtin.service:
    name: "{{ _tz_cron_service[ansible_facts['os_family']] | default('crond') }}"
    state: restarted
  when: (_tz_cron_service[ansible_facts['os_family']] | default('crond')) in ansible_facts.services
  listen: restart cron
```

**Step 2: Show git command**

```bash
git add ansible/roles/timezone/handlers/main.yml
git commit -m "feat(timezone): add cron restart handler with service_facts guard"
```

---

### Task 3: Add `notify: restart cron` to tasks/main.yml

**Files:**
- Modify: `ansible/roles/timezone/tasks/main.yml`

**Step 1: Read the file**

Confirm current "Set timezone" task looks like:

```yaml
- name: Set timezone
  community.general.timezone:
    name: "{{ timezone_name }}"
  tags: ['timezone']
```

**Step 2: Add notify**

```yaml
- name: Set timezone
  community.general.timezone:
    name: "{{ timezone_name }}"
  notify: restart cron
  tags: ['timezone']
```

**Step 3: Show git command**

```bash
git add ansible/roles/timezone/tasks/main.yml
git commit -m "feat(timezone): notify cron restart on timezone change"
```

---

### Task 4: Update README.md

**Files:**
- Modify: `ansible/roles/timezone/README.md`

**Step 1: Add cron handler to "What this role does" checklist**

Find the line:
```
- [x] Проверяет корректность применённой таймзоны
```

Add after it:
```
- [x] Перезапускает cron при фактической смене таймзоны (skipped если не установлен)
```

**Step 2: Show git command**

```bash
git add ansible/roles/timezone/README.md
git commit -m "docs(timezone): document cron restart handler in README"
```

---

### Task 5: Sync to VM and validate

**Step 1: Sync role to remote VM**

```bash
bash scripts/ssh-scp-to.sh -r ansible/roles/timezone/ /home/textyre/bootstrap/ansible/roles/timezone/
```

**Step 2: Run ansible-lint**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && source ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg ansible-lint ansible/roles/timezone/"
```

Expected: 0 violations.

**Step 3: Run molecule test**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap && task test-timezone"
```

Expected: syntax → converge → verify all pass.

**Step 4: Run molecule converge second time — verify idempotency**

```bash
bash scripts/ssh-run.sh "cd /home/textyre/bootstrap/ansible/roles/timezone && source /home/textyre/bootstrap/ansible/.venv/bin/activate && ANSIBLE_CONFIG=/home/textyre/bootstrap/ansible/ansible.cfg MOLECULE_PROJECT_DIRECTORY=/home/textyre/bootstrap/ansible molecule converge"
```

Expected: second run `changed=0`.
