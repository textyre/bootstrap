# SSH Setup: Windows → Arch Linux

Полное руководство по настройке SSH для синхронизации проекта с Windows на Arch Linux VM/сервер.

## Требования

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

## Быстрая настройка

### 1. Настройка конфигурации

Откройте `windows\config\config.ps1`:

```powershell
$Global:SERVER_USER = "your_username"
$Global:SERVER_HOST = "192.168.1.100"  # или 127.0.0.1 для VM
$Global:SERVER_PORT = 22               # или 2222 для NAT forwarding
$Global:REMOTE_PATH = "/home/your_username/bootstrap"
```

### 2. Настройка SSH ключа (один раз)

```powershell
cd windows
.\ssh\setup_ssh_key.ps1
```

Скрипт выполнит 3 шага:
1. Сгенерирует уникальный SSH ключ Ed25519
2. Скопирует его на сервер (потребуется пароль ОДИН раз)
3. Обновит SSH конфигурацию

### 3. Синхронизация файлов

```powershell
.\sync\sync_to_server.ps1
```

## Структура Windows утилит

```
windows/
├── config/
│   ├── config.ps1              # Общая конфигурация (НАСТРОЙТЕ ЗДЕСЬ)
│   └── show-config.ps1         # Просмотр текущей конфигурации
├── ssh/
│   ├── setup_ssh_key.ps1       # Полная настройка SSH
│   ├── setup_ssh_key.bat       # Обертка для двойного клика
│   ├── test-connection.ps1     # Проверка подключения
│   └── modules/
│       ├── ssh-keygen.ps1      # Генерация ключа
│       ├── ssh-copy-id.ps1     # Копирование ключа
│       └── ssh-config.ps1      # Обновление SSH config
└── sync/
    ├── sync_to_server.ps1      # Синхронизация (rsync/scp)
    └── sync_to_server.bat      # Обертка для двойного клика
```

## Настройка VirtualBox NAT (для VM)

Если используете VirtualBox с NAT, нужно пробросить порт:

### Через GUI

`Settings` → `Network` → `Adapter 1 (NAT)` → `Advanced` → `Port Forwarding`

Добавить правило:
- Name: `guestssh`
- Protocol: `TCP`
- Host IP: `127.0.0.1`
- Host Port: `2222`
- Guest Port: `22`

### Через CLI

```powershell
VBoxManage modifyvm "VM-name" --natpf1 "guestssh,tcp,,2222,,22"
VBoxManage showvminfo "VM-name" --details
```

## SSH на Arch Linux (гостевая система)

```bash
# Установить и запустить SSH
sudo pacman -Syu openssh
sudo systemctl enable --now sshd
sudo systemctl status sshd

# Проверить что слушает порт 22
ss -tlnp | grep ssh

# Проверить firewall (если включен)
sudo nft list ruleset
```

## Уникальные SSH ключи

Скрипты создают отдельный ключ для каждого сервера:

```
id_rsa_<host>_<port>
```

Например: `id_rsa_127.0.0.1_2222`

**Преимущества:**
- Изоляция: компрометация одного ключа не влияет на другие
- Управление: легко отозвать доступ к конкретному серверу
- Безопасность: современный алгоритм Ed25519

## SSH Config

Автоматически создается запись в `~/.ssh/config`:

```
Host arch-127.0.0.1-2222
    HostName 127.0.0.1
    Port 2222
    User textyre
    IdentityFile C:\Users\user\.ssh\id_rsa_127.0.0.1_2222
    IdentitiesOnly yes
```

Подключение:
```bash
ssh arch-127.0.0.1-2222
```

## Синхронизация (sync_to_server.ps1)

### Режимы работы

1. **rsync** (предпочтительный) — инкрементальная синхронизация
2. **scp** (fallback) — полное копирование если rsync недоступен

### Функции

- Автоматическое создание удаленной директории
- Исключение ненужных файлов (`.git/`, `.venv/`, `node_modules/`, и др.)
- Конвертация line endings (CRLF → LF для `.sh`)
- Установка прав выполнения на `.sh` файлы
- Поддержка SSH ключей

### Исключенные файлы

```
.git/
.github/
.venv/
windows/
.claude/
.vscode/
.idea/
__pycache__/
.molecule/
.cache/
*.pyc
*.pyo
```

### Опции

```powershell
# Принудительно использовать scp вместо rsync
.\sync_to_server.ps1 -ForceScp

# Пропустить установку прав на .sh файлы
.\sync_to_server.ps1 -SkipPermissions
```

## Утилиты

### Просмотр конфигурации

```powershell
.\config\show-config.ps1
```

Показывает:
- Параметры подключения
- Статус SSH ключа
- Результат проверки подключения
- Настроенные SSH хосты

### Проверка подключения

```powershell
.\ssh\test-connection.ps1
```

## Решение проблем

### Скрипт запрашивает пароль каждый раз

```powershell
# Запустите настройку SSH ключа заново
.\ssh\setup_ssh_key.ps1
```

### "Permission denied" при подключении

1. Проверьте параметры в `config\config.ps1`
2. Проверьте SSH сервер на Arch: `sudo systemctl status sshd`
3. Проверьте права на `~/.ssh/authorized_keys` (должны быть 600)

### "Connection refused"

```bash
# На Arch Linux проверьте SSH сервер
sudo systemctl status sshd
sudo systemctl start sshd
```

### Rsync недоступен

```powershell
# Установите rsync через winget
winget install rsync
```

## Примеры использования

### Первоначальная настройка

```powershell
# 1. Настройте config.ps1
notepad .\config\config.ps1

# 2. Посмотрите конфигурацию
.\config\show-config.ps1

# 3. Настройте SSH ключ
.\ssh\setup_ssh_key.ps1

# 4. Проверьте подключение
.\ssh\test-connection.ps1

# 5. Синхронизируйте файлы
.\sync\sync_to_server.ps1
```

### Ежедневное использование

```powershell
# Просто синхронизируйте
.\sync\sync_to_server.ps1

# Или двойной клик на
sync\sync_to_server.bat
```

## Ручное копирование ключа

Если автоматическое копирование не сработало:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p 2222 youruser@127.0.0.1 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
```

Или на госте:

```bash
mkdir -p ~/.ssh
cat /tmp/id_ed25519.pub >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

## Отладка SSH

```powershell
# SSH с подробным логированием
ssh -vvv -i C:\Users\<You>\.ssh\id_ed25519 -p 2222 youruser@127.0.0.1
```

На Arch:

```bash
# Проверить права
ls -la ~/.ssh
cat ~/.ssh/authorized_keys

# Исправить права
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

---

Назад к [[Home]]
