# SSH: Windows → controller → target

SSH plugin обеспечивает доступ Windows OpenStrap к обеим VM. Контейнер Control Plane использует обычный SSH client и статический Ansible inventory для target.

## Соединения

| Откуда | Куда | Адрес |
|---|---|---|
| Windows | `bootstrap-target` / `textyre` | `127.0.0.1:2251` |
| Windows | `ansible-control` / `openstrap` | `127.0.0.1:2252` |
| Control Plane container | `bootstrap-target` / `textyre` | `172.28.51.10:22` |

Общая приватная сеть `bootstrap` соединяет обе VM. Blueprint передаёт актуальные target references в environment workstation Docker exec; адрес и порт читаются статическим inventory внутри готового image.

## Identity

Source snapshot `arch-base/base` разрешает существующий публичный SSH ключ пользователя `textyre`. `openstrap.config.mjs` задаёт соответствующую локальную identity в `ssh({ identities: { "bootstrap-target": ... } })`. Не копируйте новый ключ в source VM и не меняйте её состояние для теста.

`ansible/inventory/openstrap.yml` читает host, port, user и содержимое private key из `BOOTSTRAP_TARGET_*` environment. Native `ansible_private_key` и `[connection] ssh_agent = auto` добавляют OpenSSH private key в память агента на время запуска. Private key не сохраняется в файлах проекта или контейнере. Системный пакет `openssh-client` предоставляет SSH client и agent.

## Host key trust

`StrictHostKeyChecking=accept-new` сохраняет новый public host key при первом SSH-соединении и отклоняет изменившийся. Это доверие при первом контакте в общей приватной сети, а не независимая attestation source. OpenSSH создаёт обычный `/root/.ssh/known_hosts`; named volume `bootstrap-control-plane-home:/root` сохраняет его при пересоздании контейнера.

Не отключайте host key checking и не удаляйте known_hosts для маскировки ошибки. Сначала подтвердите identity и причину изменения, особенно при пересоздании target по тому же адресу.

## Диагностика

```powershell
Set-Location D:/projects/bootstrap
openstrap connect bootstrap-target --local --run "id -un"
openstrap connect ansible-control --local --run "cat /etc/os-release"
```

Для Ansible операций используйте Docker exec с нужным runtime environment; Tasks доступны отдельно для разработки. Arbitrary `connect --run` сам по себе blueprint secrets не получает.

Если SSH не работает, проверьте правильный target, running state, recorded port, локальную identity и known_hosts. Не назначайте protected `arch` default host и не устанавливайте пакеты/sshd вручную на source.

## Файлы и секреты

OpenStrap загружает готовый image из GHCR. В `/opt/bootstrap/ansible` уже находятся статический inventory, роли, playbooks, group vars и зашифрованный Vault. Локальные private keys, Vault password files, `.local` и host runtime config в image не входят.

Target connection values и пароль Vault предоставляются только workstation step environment. Docker exec передаёт разрешённые имена переменных; значения не входят в container configuration, image build или pull/start команды. Environment-only `ansible/vault-pass.sh` включается в образ при сборке. Пароли и private keys не выводятся в diagnostics, CLI arguments или history.

[Windows Setup](Windows-Setup.md) · [Bootstrap Secrets](../docs/bootstrap-secrets.md) · [Test VM Workflow](standards/test-vm-workflow.md).
