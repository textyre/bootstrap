# Роль: git

## Цель

Настроить Git developer toolchain для существующих пользователей: установить Git/Git LFS и привести глобальный `~/.gitconfig` к желаемому состоянию.

Роль не создает пользователей, не создает SSH/GPG ключи, не клонирует репозитории, не управляет GitHub/GitLab аккаунтами и не владеет dotfiles вне своего Git-конфига.

## Pipeline

1. `validate` — проверяет наличие distro mapping для обнаруженной OS family.
2. `load vars` — загружает `vars/distro/<os_family>/main.yml`.
3. `configure` — устанавливает пакеты и настраивает каждого пользователя.
4. `verify` — проверяет, что `git` и `git-lfs` запускаются.
5. `report` — финальный отчет через `common`.

`tasks/main.yml` — только оркестратор.

## Что настраивает

- пакеты Git и Git LFS;
- `user.name` и `user.email`, если они заданы;
- базовые настройки `init.defaultBranch`, `core.editor`, `pull.rebase`, `push.autoSetupRemote`, `core.autocrlf`;
- optional signing config для `ssh` или `gpg`;
- aliases;
- credential helper;
- optional global hooks path;
- optional extra Git config;
- optional `safe.directory`;
- Git LFS global filters через декларативные `git_config` entries.

## Ключевые переменные

| Переменная | Default | Смысл |
|------------|---------|-------|
| `git_owner` | project `target_user` | Основной пользователь, чей `~/.gitconfig` управляется ролью. |
| `git_additional_users` | `[]` | Дополнительные пользователи с таким же контрактом. |
| `git_default_branch` | `main` | `init.defaultBranch`. |
| `git_editor` | `vim` | `core.editor`. |
| `git_pull_rebase` | `true` | `pull.rebase`. |
| `git_push_autosetup_remote` | `true` | `push.autoSetupRemote`. |
| `git_core_autocrlf` | `input` | `core.autocrlf`. |
| `git_manage_aliases` | `true` | Управлять aliases. |
| `git_manage_credential` | `true` | Управлять credential helper. |
| `git_manage_hooks` | `false` | Создать hooks dir и записать `core.hooksPath`. |
| `git_safe_directories` | `[]` | Пути для `safe.directory`. |

User dict:

```yaml
git_owner:
  name: textyre
  user_name: "textyre"
  user_email: "textyre@example.com"
  signing_method: none
  signing_key: ""
  credential_helper: ""
```

Поддерживаемые значения `signing_method`: `none`, `ssh`, `gpg`. `none` отключает автоматическую подпись коммитов. `ssh` и `gpg` включают автоматическую подпись; для `ssh` в `signing_key` указывается путь к публичному ключу, для `gpg` — ID ключа.

## Пакеты

| OS family | Git | Git LFS |
|-----------|-----|---------|
| Archlinux | `git` | `git-lfs` |
| Debian/Ubuntu | `git` | `git-lfs` |
| RedHat/Fedora | `git` | `git-lfs` |
| Void | `git` | `git-lfs` |
| Gentoo | `dev-vcs/git` | `dev-vcs/git-lfs` |

## Тесты

- Docker: Arch/Ubuntu syntax, install, converge и idempotence.
- Vagrant: Arch/Ubuntu VM syntax, converge и idempotence.
Role-level verify проверяет запуск `git` и `git-lfs`. Molecule проверяет, что роль разбирается, сходится в Docker и реальной VM и проходит idempotence; функциональность Git и role-level verify не дублируются.

## Зависимости

- `community.general.git_config` из `community.general`.
- Пользователи должны существовать до запуска роли. Обычно это контракт роли `user`.
