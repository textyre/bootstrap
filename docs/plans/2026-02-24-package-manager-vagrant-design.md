# Design: package_manager — Vagrant KVM сценарий

**Date:** 2026-02-24
**Status:** Approved

## Цель

Добавить molecule vagrant сценарий для роли `package_manager`, запускаемый на GitHub Actions
с KVM (доступен на `ubuntu-latest` с апреля 2024). Тестировать на Arch Linux и Ubuntu 24.04
параллельно без дублирования логики.

## Контекст

- Существующий docker сценарий тестирует только Arch Linux через кастомный `arch-systemd` образ
- Docker сценарий запускается в `ci-env` контейнере — не имеет доступа к `/dev/kvm`
- Vagrant сценарий даёт реальную VM: настоящий systemd, настоящий pacman, настоящие таймеры
- verify.yml уже содержит проверки для Arch (`os_family == Archlinux`) и Debian/Ubuntu

## Архитектура

Два новых файла:

```
ansible/roles/package_manager/molecule/vagrant/molecule.yml
.github/workflows/molecule-vagrant.yml
```

Переиспользуются без изменений:
- `molecule/shared/converge.yml`
- `molecule/shared/verify.yml`

## molecule/vagrant/molecule.yml

```yaml
---
driver:
  name: vagrant
  provider:
    name: libvirt

platforms:
  - name: arch-vm
    box: archlinux/archlinux
    memory: 2048
    cpus: 2
  - name: ubuntu-noble
    box: generic/ubuntu2404
    memory: 2048
    cpus: 2

provisioner:
  name: ansible
  config_options:
    defaults:
      callbacks_enabled: profile_tasks
  env:
    ANSIBLE_ROLES_PATH: "${MOLECULE_PROJECT_DIRECTORY}/../"
  playbooks:
    converge: ../shared/converge.yml
    verify: ../shared/verify.yml

verifier:
  name: ansible

scenario:
  test_sequence:
    - syntax
    - create
    - converge
    - idempotency
    - verify
    - destroy
```

### Выбор box

| Платформа | Box | Причина |
|-----------|-----|---------|
| Arch Linux | `archlinux/archlinux` | Официальный box команды Arch, поддерживает libvirt |
| Ubuntu 24.04 | `generic/ubuntu2404` | Provider-agnostic (в отличие от `ubuntu/noble64` который оптимизирован под VirtualBox) |

## .github/workflows/molecule-vagrant.yml

### Триггеры

- `workflow_dispatch` — ручной запуск с выбором роли (default: `package_manager`)
- `schedule: cron: '0 4 * * 1'` — еженедельно, понедельник 04:00 UTC

### Параллельность

GitHub Actions matrix по платформам:

```yaml
strategy:
  matrix:
    platform: [arch-vm, ubuntu-noble]
  fail-fast: false
```

Каждый job запускает: `molecule test -s vagrant --platform-name ${{ matrix.platform }}`

`fail-fast: false` — падение одной платформы не отменяет другую.

### Зависимости на раннере

Vagrant workflow **не использует** `ci-env` контейнер (нет доступа к `/dev/kvm` внутри контейнера).
Запускается напрямую на `ubuntu-latest`. Зависимости устанавливаются в шагах:

1. **KVM udev** — разрешить доступ к `/dev/kvm`
2. **libvirt + vagrant** — `libvirt-daemon-system`, `qemu-kvm`, `vagrant`, `vagrant-libvirt` plugin
3. **Python venv** — `ansible-core==2.20.1`, `molecule==25.12.0`, `molecule-plugins[vagrant]==25.8.12`
   (версии из `requirements.txt`, добавляется только vagrant driver)

## Что даёт vagrant vs docker для Arch

| Аспект | Docker (текущий) | Vagrant KVM |
|--------|-----------------|-------------|
| systemd | Имитация (cgroupns hack) | Настоящий PID 1 |
| paccache.timer | `systemctl is-enabled` работает | Реальный timer enable/start |
| pacman | Без базы данных (stripped image) | Полный pacman с keyring |
| makepkg | OK | OK |
| Скорость | ~2 мин | ~5-7 мин |

## Ограничения

- Void Linux — нет официального Vagrant box, не тестируется
- Fedora, Debian — можно добавить позже, расширив matrix в workflow и platforms в molecule.yml
