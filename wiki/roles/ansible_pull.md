# Роль: ansible_pull

**Phase**: 10 | **Направление**: Autodeploy

## Цель

Настройка самообновляющейся конфигурации через `ansible-pull`: машина автоматически забирает изменения из git-репозитория и применяет playbook. Работает через systemd timer для регулярных обновлений без внешнего Ansible control node.

## Ключевые переменные (defaults)

```yaml
ansible_pull_enabled: true  # Включить ansible-pull

# Git-репозиторий с конфигурацией
ansible_pull_repo_url: "https://github.com/user/bootstrap.git"
ansible_pull_repo_branch: "master"
ansible_pull_repo_dest: "/opt/ansible-pull"  # Локальная копия репозитория

# Playbook для применения
ansible_pull_playbook: "site.yml"  # Основной playbook в репозитории

# Параметры запуска ansible-pull
ansible_pull_inventory: "localhost,"  # Inventory (localhost для локальной машины)
ansible_pull_extra_args: ""           # Дополнительные аргументы (--tags, --skip-tags, --check)
ansible_pull_verbosity: 0             # Уровень verbose: 0=normal, 1=-v, 2=-vv, 3=-vvv

# Systemd timer настройки
ansible_pull_timer_enabled: true               # Включить systemd timer
ansible_pull_timer_on_calendar: "*-*-* 03:00:00"  # Ежедневно в 03:00
ansible_pull_timer_persistent: true            # Запустить пропущенный запуск после перезагрузки
ansible_pull_timer_random_delay: 300           # Случайная задержка до 5 минут (избежать одновременного запуска на всех машинах)

# Аутентификация в git (если приватный репозиторий)
ansible_pull_git_ssh_key: ""          # Путь к SSH-ключу для git (например: /root/.ssh/id_ed25519)
ansible_pull_git_accept_hostkey: true # Автоматически принять SSH host key

# Логирование
ansible_pull_log_file: "/var/log/ansible-pull.log"
ansible_pull_log_max_size: "10M"  # Ротация логов

# Уведомления (опционально)
ansible_pull_notify_on_failure: false  # Отправить уведомление при ошибке (требует настроенный mail/webhook)
ansible_pull_notify_command: ""        # Команда для уведомлений (например: curl webhook)
```

## Что настраивает

**На всех дистрибутивах:**
- Установка `ansible` и `git`
- Systemd service `ansible-pull.service` (oneshot)
- Systemd timer `ansible-pull.timer` (расписание запусков)
- Первоначальный clone репозитория в `ansible_pull_repo_dest`
- SSH-ключ для git (если приватный репозиторий)
- Логирование в `ansible_pull_log_file`
- Включение и запуск timer

**На Arch Linux:**
- Пакеты: `ansible`, `git`
- Путь к сервису: `/etc/systemd/system/ansible-pull.service`

**На Debian/Ubuntu:**
- Пакеты: `ansible`, `git`
- Путь к сервису: `/etc/systemd/system/ansible-pull.service`

**На Fedora/RHEL:**
- Пакеты: `ansible`, `git`
- Путь к сервису: `/etc/systemd/system/ansible-pull.service`

## Зависимости

- `base_system` — systemd, git
- `user` — если используется SSH-ключ для git

## Примечания

### Как работает ansible-pull

1. **Timer запускается** по расписанию (например, ежедневно в 03:00)
2. **ansible-pull** выполняет:
   ```bash
   git pull origin master  # Обновление локальной копии
   ansible-playbook -i localhost, site.yml  # Применение playbook
   ```
3. **Логирование** результата в `/var/log/ansible-pull.log`
4. **Уведомление** (если настроено) при ошибке

### Пример systemd service

`/etc/systemd/system/ansible-pull.service`:

```ini
[Unit]
Description=Ansible Pull — self-updating configuration
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/ansible-pull
ExecStartPre=/usr/bin/git pull origin master
ExecStart=/usr/bin/ansible-pull \
  -U https://github.com/user/bootstrap.git \
  -d /opt/ansible-pull \
  -i localhost, \
  site.yml
StandardOutput=append:/var/log/ansible-pull.log
StandardError=append:/var/log/ansible-pull.log
```

### Пример systemd timer

`/etc/systemd/system/ansible-pull.timer`:

```ini
[Unit]
Description=Ansible Pull timer — daily at 3:00 AM

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
RandomizedDelaySec=300
Unit=ansible-pull.service

[Install]
WantedBy=timers.target
```

### Аутентификация в приватный git

Если репозиторий приватный, создайте deploy SSH-ключ:

1. На машине:
   ```bash
   ssh-keygen -t ed25519 -f /root/.ssh/ansible-pull -N ""
   ```

2. Добавьте `/root/.ssh/ansible-pull.pub` в GitHub/GitLab (Deploy Keys, read-only)

3. В переменных:
   ```yaml
   ansible_pull_git_ssh_key: "/root/.ssh/ansible-pull"
   ansible_pull_repo_url: "git@github.com:user/bootstrap.git"
   ```

### Проверка работы

```bash
# Статус timer
systemctl status ansible-pull.timer

# Следующий запуск
systemctl list-timers ansible-pull.timer

# Ручной запуск
systemctl start ansible-pull.service

# Логи последнего запуска
journalctl -u ansible-pull.service -n 100

# Лог-файл
tail -f /var/log/ansible-pull.log
```

### RandomizedDelaySec

Добавляет случайную задержку перед запуском (до 5 минут). Полезно, если ansible-pull запускается на множестве машин одновременно — избегает перегрузки git-сервера и network.

### Безопасность

- **Используйте read-only deploy keys** для git (не полный SSH-доступ)
- **Ограничьте доступ к логам** (`chmod 600 /var/log/ansible-pull.log`)
- **Проверяйте playbook** перед push в master (тестируйте на staging-ветке)
- **Не храните секреты в git** — используйте Ansible Vault или внешнее хранилище (HashiCorp Vault, AWS Secrets Manager)

### Идемпотентность

ansible-pull выполняет playbook каждый раз. Убедитесь, что все задачи идемпотентны (повторный запуск не меняет состояние).

## Tags

- `ansible`
- `autodeploy`
- `self-updating`
- `systemd`

---

Назад к [[Roadmap]]
