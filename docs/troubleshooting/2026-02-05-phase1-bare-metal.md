# Troubleshooting History — 2026-02-05

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre

## Решено

### Lint и синтаксис

- [x] **FQCN: `ansible.builtin.pacman` → `community.general.pacman`** — 13 нарушений в `gpu_drivers/tasks/install-archlinux.yml` (11) и `power_management/tasks/install-archlinux.yml` (2). Исправлено, ansible-lint production profile чист.
- [x] **YAML-синтаксис валиден** — все 31 файл проверен через `yaml.safe_load()` и `yamllint`. Остались только line-length warnings (36 шт, non-blocking).

## Не решено

### Критичные

- [ ] **gpu_drivers: regex GPU-детекции перевёрнут** — В `lspci -nn` вывод идёт `VGA compatible controller: NVIDIA Corporation ...`, т.е. класс ПЕРЕД вендором. Текущие regex `NVIDIA.*(?:VGA|Display)` требуют NVIDIA перед VGA — **никогда не сматчат реальный вывод lspci**. Затронуты: `roles/gpu_drivers/tasks/main.yml:17,22,27` и `roles/gpu_drivers/molecule/default/verify.yml:18-20`. **Fix**: заменить на `(?:VGA|Display).*NVIDIA`, `(?:VGA|Display).*(?:AMD|ATI)`, `(?:VGA|Display).*Intel Corporation`.

- [ ] **power_management: `_power_management_is_laptop` может быть строкой "False"** — `set_fact` через `>-` + `{{ }}` в `tasks/main.yml:14-21`. Без `ANSIBLE_JINJA2_NATIVE=true` (дефолт с Ansible 2.12, но не гарантирован если переопределён) результат — строка `"False"`, а не bool. Строка `"False"` является truthy в Jinja2 (непустая строка). **Результат**: на десктопе TLP ставится и включается как на ноутбуке. Min ansible_version=2.15, значит native types скорее всего работает, но **один `| bool` фильтр убрал бы риск полностью**. Fix: `when: _power_management_is_laptop | bool` во всех условиях, или убрать `>-` в пользу inline `{{ }}`.

- [ ] **power_management: `HibernateMode=hibernate` — невалидное значение** — В `defaults/main.yml:37` стоит `power_management_hibernate_mode: hibernate`. Директива `HibernateMode=` в `sleep.conf(5)` принимает: `platform`, `shutdown`, `reboot`, `suspend`, `test_resume`. Значение `hibernate` — это действие пользователя, а не mode. **Fix**: заменить дефолт на `platform`.

- [ ] **power_management: `cpupower frequency-set` ломает idempotence** — В `tasks/main.yml:71` стоит `changed_when: true` + `failed_when: false`. Каждый прогон сообщает changed. Molecule тест включает `idempotence` шаг → **тест гарантированно провалится на десктопе**. Fix: проверять текущий governor через `cpupower frequency-info -p`, сравнивать с целевым, и запускать `frequency-set` только при несовпадении.

### Требуют core fix в конфигах

- [ ] **gpu_drivers: `pciutils` не в зависимостях** — `lspci` вызывается в `tasks/main.yml:7`, но `pciutils` нигде не устанавливается. На минимальном Arch (без `base-devel`) `lspci` может отсутствовать. `failed_when: false` замаскирует ошибку — GPU просто не обнаружится, драйвера не установятся, **без предупреждения**. Fix: добавить `community.general.pacman: name=pciutils state=present` перед lspci, или dependency от `base_system`.

- [ ] **gpu_drivers: multilib repo не проверяется** — Установка `lib32-*` пакетов (`gpu_drivers_multilib: true`) требует включённого `[multilib]` repo в `/etc/pacman.conf`. Роль не проверяет и не включает его. `pacman` тихо упадёт с ошибкой "target not found". Fix: проверить наличие multilib в pacman.conf или добавить pre-task для включения.

- [ ] **sysctl: `kernel.unprivileged_userns_clone` может не существовать** — Этот sysctl ключ — патч Arch/Debian, не upstream Linux. На ядрах без этого патча `sysctl --system` выдаст warning (не ошибку). Мелочь, но засоряет лог. Fix: обернуть в `{% if %}` с проверкой или вынести в `sysctl_custom_params`.

- [ ] **sysctl: molecule verify хардкодит значения** — `verify.yml:26` проверяет `!= 10`, `verify.yml:32` — `!= 524288`, `verify.yml:38` — `!= 4096`. Если пользователь переопределит defaults через group_vars, verify тест провалится. Fix: использовать `{{ sysctl_vm_swappiness }}` вместо литералов.

- [ ] **gpu_drivers: `xf86-video-nouveau` возможно удалён из Arch repos** — Пакет `xf86-video-nouveau` помечен как устаревший в пользу встроенного modesetting DDX. Может быть удалён в текущих Arch repos. **Требует проверки на VM**: `pacman -Ss xf86-video-nouveau`.

### Низкий приоритет

- [ ] **Полное тестирование не выполнено** — VM не была запущена. Ни molecule tests, ни `--check` dry-run, ни реальный прогон не выполнялись. Все проверки — только локальный lint. Требуется: `ansible-playbook playbooks/workstation.yml --tags sysctl,gpu,power --check --diff` на VM.

- [ ] **yamllint line-length warnings (36 шт)** — В основном длинные Jinja2 выражения и molecule vars_files paths. Не блокирующие, но могут раздражать в CI. Fix: разбить длинные строки или настроить `.yamllint` правило.

- [ ] **power_management: TLP config минимален** — `tlp.conf.j2` содержит только 7 параметров. Реальный TLP config имеет ~100+ опций. Текущий конфиг перезаписывает `/etc/tlp.conf` целиком, потеряв все дефолты TLP. Fix: рассмотреть `lineinfile` вместо `template`, или включить полный дефолтный конфиг TLP как базу.

- [ ] **gpu_drivers: Debian install — заглушка** — `install-debian.yml` содержит только debug msg. Пользователь на Debian не получит ни драйверов, ни предупреждения (кроме debug msg). Допустимо на текущем этапе (приоритет Arch), но стоит добавить `ansible.builtin.fail` с понятным сообщением.

- [ ] **power_management: verify не проверяет governor на десктопе** — На десктопе verify проверяет только cpupower pkg и sleep.conf, но не проверяет что governor реально установлен в `schedutil`. Fix: добавить `cpupower frequency-info -p | grep schedutil`.

- [ ] **Нет `validate:` на template задачах** — `sysctl.conf.j2` можно валидировать через `validate: sysctl -p %s` перед деплоем. Предотвратит деплой невалидного конфига.

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `roles/sysctl/defaults/main.yml` | Создан — дефолтные kernel параметры |
| `roles/sysctl/tasks/main.yml` | Создан — deploy template + OS dispatch |
| `roles/sysctl/tasks/archlinux.yml` | Создан — debug placeholder |
| `roles/sysctl/tasks/debian.yml` | Создан — apt install procps |
| `roles/sysctl/handlers/main.yml` | Создан — sysctl --system |
| `roles/sysctl/templates/sysctl.conf.j2` | Создан — vm/fs/net/kernel params |
| `roles/sysctl/meta/main.yml` | Создан — galaxy metadata |
| `roles/sysctl/molecule/default/molecule.yml` | Создан — delegated driver |
| `roles/sysctl/molecule/default/converge.yml` | Создан — assert Arch + run role |
| `roles/sysctl/molecule/default/verify.yml` | Создан — file + live value checks |
| `roles/power_management/defaults/main.yml` | Создан — device type, TLP, governor, sleep |
| `roles/power_management/tasks/main.yml` | Создан — DMI detect, TLP, cpupower, sleep |
| `roles/power_management/tasks/install-archlinux.yml` | Создан — pacman tlp/cpupower |
| `roles/power_management/tasks/install-debian.yml` | Создан — apt tlp/linux-tools |
| `roles/power_management/handlers/main.yml` | Создан — restart tlp |
| `roles/power_management/templates/tlp.conf.j2` | Создан — CPU/disk/wifi/PCIe |
| `roles/power_management/templates/sleep.conf.j2` | Создан — systemd sleep modes |
| `roles/power_management/meta/main.yml` | Создан — galaxy metadata |
| `roles/power_management/molecule/default/molecule.yml` | Создан — delegated driver |
| `roles/power_management/molecule/default/converge.yml` | Создан — assert Arch + run role |
| `roles/power_management/molecule/default/verify.yml` | Создан — pkg + config + service checks |
| `roles/gpu_drivers/defaults/main.yml` | Создан — vendor packages, preferences |
| `roles/gpu_drivers/tasks/main.yml` | Создан — lspci detect, env config |
| `roles/gpu_drivers/tasks/install-archlinux.yml` | Создан — nvidia/amd/intel/vulkan pkgs |
| `roles/gpu_drivers/tasks/install-debian.yml` | Создан — debug placeholder |
| `roles/gpu_drivers/handlers/main.yml` | Создан — пустой (нет сервисов) |
| `roles/gpu_drivers/templates/gpu-environment.conf.j2` | Создан — LIBVA_DRIVER_NAME |
| `roles/gpu_drivers/meta/main.yml` | Создан — galaxy metadata |
| `roles/gpu_drivers/molecule/default/molecule.yml` | Создан — delegated driver |
| `roles/gpu_drivers/molecule/default/converge.yml` | Создан — assert Arch + run role |
| `roles/gpu_drivers/molecule/default/verify.yml` | Создан — per-vendor pkg + env checks |
| `playbooks/workstation.yml` | Добавлен Phase 1.5: Hardware & Kernel (3 роли) |
| `inventory/group_vars/all/system.yml` | Добавлены секции gpu_drivers, sysctl, power_management |
| `docs/roadmap/ansible-roles.md` | 14→17 ролей, Приоритет 1 ✅ |

## Итог

**Создано**: 31 новый файл (3 роли), обновлено 3 файла интеграции.
**Lint**: ansible-lint production — 0 ошибок. yamllint — 36 line-length warnings.
**Тестирование на VM**: НЕ ВЫПОЛНЕНО (VM не запущена).

**Критичных багов найдено: 4** — regex GPU-детекции перевёрнут (gpu_drivers не будет работать), `_is_laptop` потенциально string truthiness баг, невалидный HibernateMode, cpupower ломает idempotence.

**Core fixes needed: 5** — pciutils dependency, multilib repo check, sysctl ключ может не существовать, hardcoded verify values, xf86-video-nouveau deprecated.

**Роли НЕ ГОТОВЫ к production** до исправления критичных багов и прогона на реальной VM.
