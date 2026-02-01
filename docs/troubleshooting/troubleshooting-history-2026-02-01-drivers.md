# Troubleshooting History — 2026-02-01 (Session 2: Drivers Role)

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre

## Решено

### Категория: VirtualBox Guest Additions / 3D Acceleration

- [x] **GA downgrade 7.2.6 → 7.1.16 через ISO** — версия Guest Additions на VM (7.2.6 из pacman) не соответствовала хосту (7.1.16). Скачан ISO `VBoxGuestAdditions_7.1.16.iso`, запущен `VBoxLinuxAdditions.run` с `sudo`. Kernel modules собраны для 6.18.7-arch1-1. Downgrade успешен, но systemd unit не был создан (ISO installer не создаёт).

- [x] **3D acceleration: root cause найден, unfixable** — `glxinfo | grep Accelerated` → `no`. Причина: kernel-модуль `vmwgfx` проверяет `hypervisor_is_type(X86_HYPER_VMWARE)` в `vmw_driver.c`, но VirtualBox представляется как KVM через CPUID. Попытка CPUID override через `VBoxManage modifyvm --cpuid-set` не работает — VBox не позволяет переопределять hypervisor leaf (0x40000000). **Это ограничение ядра Linux, не исправить без патча ядра.** GA downgrade не помогла — проблема не в версии.

- [x] **ISO GA деинсталлированы** — во время тестирования molecule `pacman` не мог установить `virtualbox-guest-utils` из-за конфликтов файлов в `/usr/bin/` от ISO-установки. Решение: `sudo /opt/VBoxGuestAdditions-7.1.16/uninstall.sh`. После этого pacman-пакет 7.2.6 установлен успешно.

### Категория: Ansible / Drivers Role

- [x] **Multi-hypervisor drivers role создана** — роль `drivers` расширена для поддержки VirtualBox, VMware и Hyper-V. Автодетект гипервизора через `ansible_facts['virtualization_type']` + `['virtualization_role']`. Dispatch через `_drivers_hypervisor_map` словарь (как `base_system` для OS). Файлы: `main.yml` (оркестратор), `virtualbox.yml`, `vmware.yml`, `hyperv.yml`.

- [x] **VBox version check** — `VBoxControl --version` (guest) vs `VBoxControl guestproperty get /VirtualBox/HostInfo/VBoxVer` (host). Warning при несовпадении, не failure. Отключается через `drivers_vbox_version_check: false`. Все VBoxControl команды с `failed_when: false`.

- [x] **packages.yml обновлён** — добавлены `packages_vmware_guest` (open-vm-tools, open-vm-tools-desktop) и `packages_hyperv_guest` (hyperv).

- [x] **handlers, meta, molecule** — добавлены restart handlers для всех трёх гипервизоров, обновлены meta/galaxy_tags, создана molecule конфигурация (delegated driver, converge + verify).

- [x] **Taskfile.yml** — добавлен `test-drivers` task, включён в общую `test` sequence.

- [x] **workstation.yml tags** — расширены с `[drivers, vbox]` на `[drivers, vbox, vmware, hyperv]`.

### Категория: Lint

- [x] **ansible-lint: 8 var-naming[no-role-prefix]** — переменные `packages_virtualbox_guest`, `packages_vmware_guest`, `packages_hyperv_guest` в `defaults/main.yml` и `_verify_*` переменные в `verify.yml` не имели role prefix. Решение: `# noqa: var-naming[no-role-prefix]` для packages-переменных в defaults, переименование `_verify_*` → `drivers_verify_*` в verify.yml.

- [x] **ansible-lint: yaml[line-length]** — строка 46 в `virtualbox.yml` (regex_search) превышала лимит. Решение: вынесено в `vars:` блок + multiline `>-`. Итог: `Passed: 0 failure(s), 0 warning(s)` (production profile).

### Категория: Molecule тесты

- [x] **converge.yml отсутствовал packages.yml** — `vars_files` содержал только `vault.yml`. `packages_virtualbox_guest` брался из defaults (пустой список), установка пакетов пропускалась, `vboxservice` не существовал. Решение: добавлен `packages.yml` в `vars_files` в converge.yml и verify.yml.

- [x] **Nested drivers/drivers/ после SCP** — `scp -r` создал вложенную директорию. Решение: `cp -a drivers/* . && rm -rf drivers` на VM.

- [x] **Molecule test passed** — `Molecule executed 1 scenario (1 successful)`. Syntax OK, Converge: 11 ok / 2 changed / 0 failed (VBox detected, packages installed, service enabled, version mismatch WARNING). Verify: 5 ok / 0 failed (vboxservice active, VMware/Hyper-V skipped).

### Категория: Инфра / Vault

- [x] **Vault password найден на VM** — искался на Windows хосте (нет `~/.vault-pass`, нет `pass`). Пароль находится на VM: `~/.vault-pass`.

## Не решено

### Известные ограничения

- [ ] **VBox 3D acceleration не работает** — `vmwgfx` kernel module проверяет `hypervisor_is_type(X86_HYPER_VMWARE)`, VBox возвращает KVM через CPUID. Unfixable без патча ядра. Renderer: `SVGA3D` (Mesa software). Это не баг конфигурации — это upstream kernel limitation.

- [ ] **VBox GA version mismatch** — после деинсталляции ISO GA и установки через pacman: guest 7.2.6 vs host 7.1.16. Роль корректно предупреждает об этом. Для fix: обновить VirtualBox на хосте до 7.2.6 или установить GA 7.1.16 через ISO (но тогда pacman не управляет пакетом).

### Из предыдущей сессии (не затронуты)

- [ ] **picom визуальные настройки** — бисекция отложена
- [ ] **hosts.ini cleanup** — удалить после проверки YAML inventory

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `ansible/inventory/group_vars/all/packages.yml` | Добавлены `packages_vmware_guest`, `packages_hyperv_guest` |
| `ansible/roles/drivers/defaults/main.yml` | Полная перезапись: hypervisor map, supported list, noqa comments |
| `ansible/roles/drivers/tasks/main.yml` | Полная перезапись: оркестратор с автодетектом и dispatch |
| `ansible/roles/drivers/tasks/virtualbox.yml` | Создан: установка пакетов, vboxservice, version check |
| `ansible/roles/drivers/tasks/vmware.yml` | Создан: установка open-vm-tools, vmtoolsd |
| `ansible/roles/drivers/tasks/hyperv.yml` | Создан: установка hyperv, hv_*_daemon services |
| `ansible/roles/drivers/handlers/main.yml` | Создан: restart handlers для всех гипервизоров |
| `ansible/roles/drivers/meta/main.yml` | Обновлён: description, galaxy_tags |
| `ansible/roles/drivers/molecule/default/molecule.yml` | Создан: delegated driver config |
| `ansible/roles/drivers/molecule/default/converge.yml` | Создан: converge playbook с vars_files |
| `ansible/roles/drivers/molecule/default/verify.yml` | Создан: verify с проверками сервисов по гипервизору |
| `ansible/playbooks/workstation.yml` | Tags расширены: `[drivers, vbox, vmware, hyperv]` |
| `Taskfile.yml` | Добавлен `test-drivers` task + в test sequence |
| VM: ISO GA 7.1.16 | Деинсталлированы (`uninstall.sh`) |
| VM: pacman `virtualbox-guest-utils` | Установлен 7.2.6 через molecule converge |

## Итог

Роль `drivers` расширена для multi-hypervisor поддержки (VirtualBox, VMware, Hyper-V) с автодетектом и version checking. Molecule тест проходит (1 scenario, 1 successful). ansible-lint чист (production profile). VM сейчас использует pacman-пакет `virtualbox-guest-utils` 7.2.6 (version mismatch с хостом 7.1.16 — роль предупреждает). 3D acceleration остаётся сломанным из-за kernel-level ограничения vmwgfx.
