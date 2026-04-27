# TODO

## TODO

## ОЖИДАЕТ

### `BOOT-006`
Поднять VPN в исполняющем VM-контуре и подтвердить, что стандартный workflow получает рабочий маршрут до GitHub Releases без обходов в роли `yay`.

## В РАБОТЕ

Пока пусто.

## РЕВЬЮ

Пока пусто.

## ЗАВЕРШЕНО

### `BOOT-003`
Агент настроил shell и окружение `Codex` так, что прямые команды `VBoxManage` работают в его контуре так же, как в пользовательском терминале.

### `BOOT-004`
Создана новая VM `arch-base` на основе snapshot `Before installation`, и на ней создан snapshot `base`, соответствующий baseline package inventory из `docs/default-packages.md`.

### `BOOT-005`
Первые 3 роли (`reflector`, `package_manager`, `packages`) успешно прогнаны на `arch-base` от snapshot `base`, повторный прогон дал `changed=0`, после чего создан новый snapshot `after-packages`.

### `BOOT-007`
Следующий блокер на `nody-greeter` снят в рамках выполнения `BOOT-005`; отдельного незавершенного follow-up по этой ошибке больше нет.

### `BOOT-008`
Подтверждено, что snapshot `base` соответствует чистому post-install baseline из `docs/default-packages.md`, а snapshot `after-packages` содержит пакетное состояние после первых 3 ролей; оба snapshot существуют и готовы к дальнейшему использованию.

### `BOOT-009`
Проведен ресерч по open-source/self-hosted инструментам для SBOM/SCA/Supply Chain для snapshot-состояний `base` и `after-packages`, а также отдельный UX-ресерч по canvas/grouped/rich-content инструментам:
- [2026-04-25-supply-chain-sbom-tooling-research.md](D:/projects/bootstrap/docs/research/2026-04-25-supply-chain-sbom-tooling-research.md)
- [2026-04-25-canvas-ux-tooling-research.md](D:/projects/bootstrap/docs/research/2026-04-25-canvas-ux-tooling-research.md)

### `BOOT-010`
Проведен ресерч по готовым практическим реализациям и референсам для SBOM/Supply Chain контура: ролям, playbooks, self-hosted сервисам, automation-репозиториям и walkthrough-материалам:
- [2026-04-26-supply-chain-reference-implementations-research.md](D:/projects/bootstrap/docs/research/2026-04-26-supply-chain-reference-implementations-research.md)

### `BOOT-011`
На основе артефактов `BOOT-009` и `BOOT-010` предыдущая artifact-first концепция переосмыслена под новые инварианты `in-VM only` и DB-backed history: предложены ровно 3 архитектурных варианта локального `supply-chain` контура внутри VM с collection, persistence, compare, analysis, visualization, review/sign-off, immutable capture identity, measured scope policy, canonical source of truth, Mermaid-схемами, сравнением trade-offs и рекомендованным вариантом `Embedded History DB` для первой реализации:
- [2026-04-26-supply-chain-architecture-options.md](D:/projects/bootstrap/docs/plans/2026-04-26-supply-chain-architecture-options.md)

### `BOOT-012`
Secure bootstrap model доведена до рабочей и безопасной реализации: runtime vault/sudo secret переведен на GPG-encrypted project-local secret в `.local/bootstrap/vault-pass.gpg`, plaintext `.local/bootstrap/vault-pass` / `.local/bootstrap/sudo-password` больше не являются обязательной основой, remote bootstrap/task runs форвардят секрет эпизодически через `ssh-run.sh --bootstrap-secrets`, `bootstrap_run_sudo` больше не ломает stdin/heredoc write-path, а fresh disposable VM от snapshot `Before installation` проходит standard bootstrap prepare path и доходит до реального старта Ansible без ручных правок внутри guest.

### `BOOT-013`
CI починен строго последовательно по GitHub Actions jobs без ослабления security: подтвержденно стали зелеными `YAML Lint & Syntax`, `Ansible Lint`, `packages (test-docker)`, `package_manager (test-docker)`, `docker (test-docker)`, `vaultwarden (test-docker)`, `ssh (test-docker)`, `teleport (test-docker)`, `ssh (test-vagrant/arch)` и `ssh (test-vagrant/ubuntu)`.
