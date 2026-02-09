# Troubleshooting History — 2026-02-09

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre

## Решено

### YAML / Синтаксис

- [x] **Docker Compose network name без кавычек** — `name: {{ var }}` невалидный YAML без кавычек. Исправлено на `name: "{{ var }}"` в обоих compose-шаблонах. Ошибка допущена при написании шаблона, не была замечена до review.

- [x] **Отсутствие `listen:` в handlers vaultwarden** — handlers caddy имели `listen:`, а vaultwarden нет. Обнаружено reader-агентом при верификации. Работает по совпадению имён, но нарушает best practice и ломает cross-role notify.

- [x] **`changed_when` отсутствует на command-хэндлерах** — ansible-lint `no-changed-when` на всех 4 хэндлерах (restart caddy, reload caddy, restart vaultwarden, reload caddy). Добавлено `changed_when: true`.

- [x] **Дефис в galaxy_tags** — `reverse-proxy` невалидный тег (только lowercase/digits). Исправлено на `reverseproxy`.

### Инфраструктура / Деплой

- [x] **Playbook не запускается с `--tags`** — Ansible валидирует ВСЕ роли в плейбуке даже при `--tags caddy,vaultwarden`. Отсутствующие роли (`gpu_drivers`, `sysctl`, `power_management`, `zen_browser`) блокируют запуск. Remote-executor обошёл созданием временного плейбука `caddy-vaultwarden.yml`. Правильное решение: убедиться что все роли существуют на VM.

- [x] **`sudo` не работает через SSH** — `sudo: a terminal is required to read the password`. Обход через `ansible localhost -m ... --become` (Ansible использует vault password для become). Это ожидаемое поведение при BatchMode SSH.

- [x] **ansible .venv не активируется** — первые попытки запуска без `source .venv/bin/activate` → `ansible-playbook: command not found`.

- [x] **Отсутствие `python-requests`** — модуль `community.docker.docker_compose_v2` требует `python-requests`. Обнаружено только при деплое. Не проверено заранее.

- [x] **Отсутствие `cronie`** — cron job для бэкапа требует `cronie` пакет + сервис. Не включён в зависимости роли.

- [x] **Права директории ansible 0707** — world-writable, Ansible игнорирует ansible.cfg. Исправлено на 0755.

### TLS / Сертификаты

- [x] **`SEC_ERROR_UNKNOWN_ISSUER` в браузере** — Caddy `tls internal` генерирует CA, но не добавляет его в системное хранилище. Не было предусмотрено в роли изначально. Добавлены таски: `docker cp` CA → trust store → `update-ca-trust`.

- [x] **Права CA файла 0600** — `docker cp` копирует с правами контейнера (root:root 0600). Браузер не может прочитать. Добавлен таск `ansible.builtin.file` с `mode: 0644`.

- [x] **Zen Browser не использует системный CA store** — Firefox/Zen имеет собственное хранилище NSS. Системный CA не подхватывается. Решение: `policies.json` с `ImportEnterpriseRoots: true` в `/usr/lib/zen-browser/distribution/`.

## Не решено

### Требуют core fix в конфигах

- [ ] **policies.json для Zen Browser не автоматизирован в роли** — добавлен вручную через ad-hoc команду. Нужно либо добавить в роль caddy (когда `tls internal`), либо в роль zen_browser. Вопрос: куда это принадлежит архитектурно?

- [ ] **Временный плейбук на remote** — remote-executor создал `/home/textyre/bootstrap/ansible/playbooks/caddy-vaultwarden.yml`. Нужно удалить.

- [ ] **vault_vaultwarden_admin_token не создан** — vault.yml с зашифрованным токеном не был создан. Admin panel работает, но без токена (доступ без пароля). Нужно сгенерировать токен и зашифровать через `ansible-vault encrypt_string`.

- [ ] **Зависимости не декларированы в роли** — `python-requests` и `cronie` нужны для работы, но не установлены автоматически. Добавить в пре-таски роли или в роль `packages`.

### Низкий приоритет

- [ ] **`caddy_open_firewall_port` переменная-призрак** — была определена в defaults, но ни один таск не использовал. Удалена, но порты добавлены вручную в `firewall_allow_tcp_ports` в system.yml. Нет автоматической связи между ролями caddy и firewall.

- [ ] **Reader-агент создал документ на диске** — `docs/SubAgent docs/ansible-role-verification-2026-02-09.md` был создан агентом без запроса. Удалён, но субагенты не должны создавать файлы самостоятельно.

## Самокритика: что можно было сделать лучше

### Не продумано заранее

1. **TLS trust chain** — самая грубая ошибка. Настроил Caddy с `tls internal`, но не подумал что браузер не будет доверять сертификату. Потребовалось 3 итерации: (1) добавить CA в систему, (2) исправить права файла, (3) настроить Firefox/Zen для использования системного CA. Всё это должно было быть в роли с самого начала.

2. **`/etc/hosts`** — пользователь справедливо указал что не автоматизировано. Добавлено post-factum.

3. **Проверка зависимостей** — `python-requests`, `cronie`, `sqlite3` нужны для работы ролей, но нигде не проверяются и не устанавливаются.

### Процессные проблемы

4. **Нет dry-run перед деплоем** — `--check` не удалось запустить из-за проблемы с `--tags` и отсутствующими ролями. Деплой пошёл "вслепую" через обходной плейбук.

5. **Слишком много ad-hoc команд** — `/etc/hosts`, CA trust, permissions, policies.json — всё сделано вручную через ansible ad-hoc вместо автоматизации в ролях. Нарушает принцип infrastructure-as-code.

6. **Не проверил browser-совместимость** — знал что это Zen Browser (форк Firefox), но не учёл что Firefox не использует системный CA store. Стандартная проблема Linux, должен был предусмотреть.

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/roles/caddy/defaults/main.yml` | Создан. Убрана неиспользуемая `caddy_open_firewall_port` |
| `ansible/roles/caddy/tasks/main.yml` | Создан. Добавлены таски CA trust + chmod |
| `ansible/roles/caddy/templates/Caddyfile.j2` | Создан |
| `ansible/roles/caddy/templates/docker-compose.yml.j2` | Создан. Исправлены кавычки в network name |
| `ansible/roles/caddy/handlers/main.yml` | Создан. Добавлен `changed_when: true` |
| `ansible/roles/caddy/meta/main.yml` | Создан. Исправлен `reverse-proxy` → `reverseproxy` |
| `ansible/roles/caddy/molecule/default/*` | Созданы (molecule.yml, converge.yml, verify.yml) |
| `ansible/roles/vaultwarden/defaults/main.yml` | Создан |
| `ansible/roles/vaultwarden/tasks/main.yml` | Создан. Добавлен таск `/etc/hosts` |
| `ansible/roles/vaultwarden/templates/docker-compose.yml.j2` | Создан. Исправлены кавычки в network name |
| `ansible/roles/vaultwarden/templates/vault.caddy.j2` | Создан |
| `ansible/roles/vaultwarden/templates/vaultwarden-backup.sh.j2` | Создан |
| `ansible/roles/vaultwarden/handlers/main.yml` | Создан. Добавлены `listen:` + `changed_when: true` |
| `ansible/roles/vaultwarden/meta/main.yml` | Создан |
| `ansible/roles/vaultwarden/molecule/default/*` | Созданы (molecule.yml, converge.yml, verify.yml) |
| `ansible/playbooks/workstation.yml` | Добавлены роли caddy + vaultwarden в Phase 5 |
| `ansible/inventory/group_vars/all/system.yml` | Добавлены секции caddy, vaultwarden, firewall ports |

## Ручные действия на VM (не автоматизированы в ролях)

| Действие | Как сделано | Нужно автоматизировать |
|----------|-------------|----------------------|
| `/etc/hosts` запись | ansible ad-hoc → lineinfile | Добавлено в роль vaultwarden |
| CA в системный trust store | ansible ad-hoc → docker cp + update-ca-trust | Добавлено в роль caddy |
| Права CA файла 0644 | ansible ad-hoc → file mode | Добавлено в роль caddy |
| Zen Browser policies.json | ansible ad-hoc → copy | НЕ добавлено в роль |
| Установка cronie | remote-executor через pacman | НЕ добавлено в роль |
| Установка python-requests | remote-executor через pip | НЕ добавлено в роль |
| Временный плейбук | remote-executor создал | Нужно удалить |

## Итог

Caddy + Vaultwarden задеплоены и работают. HTTPS с внутренним CA, бэкап по cron, rate limiting настроен. Основные проблемы: TLS trust chain не продуман (3 итерации), зависимости не декларированы, часть настроек сделана вручную. Требуется доработка: policies.json в роль, vault admin token, очистка временных файлов на VM.
