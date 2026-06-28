# Troubleshooting History — Vagrant / KVM CI

Дата: 2026-02-25

## Решено

| Ошибка | Причина | Решение |
|--------|---------|---------|
| `No module named 'vagrant'` / `No module named 'python_vagrant'` | Molecule/Vagrant Ansible-модули выполнялись не тем Python, куда были установлены зависимости | Использовать одно Python-окружение через `actions/setup-python` и ставить Molecule, plugins и `python-vagrant` туда же |
| `couldn't resolve module/action 'vagrant'` | `ANSIBLE_LIBRARY` указывал на пакет plugin, а не на директорию `modules/` | Вычислять путь динамически из `molecule_plugins.vagrant.__file__` и добавлять поддиректорию `modules` |
| Vagrant box не найден или не поддерживает libvirt | Были выбраны box names, ориентированные на VirtualBox или отсутствующие в Vagrant Cloud | Для libvirt использовать совместимые образы, например `generic/arch` и `bento/ubuntu-24.04` |
| Vagrant scenario использует legacy публичный box вместо project base box | Роль тестируется на окружении, которое отличается от поддерживаемого bootstrap image contract | Использовать project-owned `arch-base.box`/`ubuntu-base.box` или явно документировать внешний box |
| `ModuleNotFoundError: molecule.command.idempotency` | В Molecule 25.x шаг называется `idempotence`, не `idempotency` | В `scenario.test_sequence` использовать `idempotence` |
| `python3: not found` на Arch VM | Минимальный Arch Vagrant box не содержит Python | В `prepare.yml`: `gather_facts: false`, затем `raw` bootstrap Python, затем отдельный `gather_facts` |
| Pacman падает на `PGP signature ... is unknown trust` | У Arch box устаревший `archlinux-keyring` | В prepare обновлять keyring перед установкой пакетов |
| Pacman скачивает пакет по старому URL и получает 404 | В Vagrant box устарела локальная база пакетов | Обновлять package database перед установкой пакетов в Vagrant/fresh VM сценариях |
| Pacman ловит partial-sync 404 даже после обновления БД | Box или prepare использует отдельное зеркало, которое не синхронизировано с master | В base box использовать надежный CDN mirror и в prepare делать forced DB refresh как defense-in-depth |
| Частичное обновление Arch ломает ABI библиотек | Обновлены package DB/часть пакетов, но система не приведена к консистентному состоянию | Для stale VM делать полный `pacman -Syu` до установки/проверок, затем перезапускать сервисы/VM при необходимости |
| `unknown url type: https` в Python/urllib | Stale Arch box получил частичное обновление: Python и OpenSSL оказались ABI-несовместимы | После keyring refresh выполнять полный `pacman -Syu` перед converge |
| Undefined variable в backup/rescue path | Переменная регистрировалась под одним именем, а использовалась под другим; happy path это не покрывал | Выравнивать имена `register`/use и проверять не только happy path, но и ветки восстановления |
| `risky-file-permissions` на `copy`/`file` | Задача создавала файл без явного `mode`, поэтому ansible-lint считал права небезопасными | Всегда задавать `mode` для `ansible.builtin.copy` и `ansible.builtin.file` |
| Ошибка прав доступа: wrong `mode:` in template or file task | Задача `template`/`file` создает артефакт с неверными permissions; verify или lint видит missing/wrong permissions | Для каждого `template`, `copy`, `file` задавать явные `owner`, `group`, `mode` и проверять ожидаемые permissions в verify только там, где permissions являются частью контракта |
| `Could not find the requested service Qemu-guest-agent` | Имя systemd unit было задано с неправильным регистром; unit names case-sensitive | Использовать фактическое имя unit: `qemu-guest-agent` |
| `qemu-guest-agent` установлен, но не стартует | В libvirt/KVM VM отсутствует virtio-serial channel `/dev/virtio-ports/org.qemu.guest_agent.0`, от которого зависит сервис | Перед управлением сервисом проверять наличие virtio channel и явно объяснять skip |
| Undefined variable в module/status check | `register` был записан под одним именем, а читался под другим (`_vm_*` vs `vm_*`) | Соблюдать единую naming convention для внутренних `register` переменных и проверять KVM path, а не только Docker path |
| Idempotence падает на persistent fact file | В fact-файл попало transient per-run состояние, которое менялось между первым и вторым converge | Писать в persistent facts только стабильные свойства системы; transient state держать в runtime переменных |
| Vagrant/libvirt exact cache hit всё равно даёт `No usable default provider` | Ruby native extensions из cache были собраны на другом runner и не переносимы между GitHub Actions instances | Переустанавливать `vagrant-libvirt` на каждом runner; cache использовать только для ускорения скачивания gem artifacts |
| Тег `molecule-notest` не пропускает задачу | В `provisioner.options.skip-tags` задан явный список, который заменил default skip-tags Molecule | Если задается `skip-tags`, явно добавлять туда `molecule-notest` |
| `become_user` падает до выполнения task с ACL/chmod ошибкой | При подключении не-root пользователь Ansible пытается дать временным файлам ACL для другого unprivileged user | Не запускать такие задачи в Molecule через корректные skip-tags или обеспечить ACL support в prepare |
| Сетевые операции падают в CI VM | CI VM не гарантирует доступность внешних сервисов, а `options.skip-tags` может не примениться одинаково во всех drivers | Для задач, которые не должны идти в Molecule, использовать тег `molecule-notest` непосредственно на задаче |
| Полное тестирование на VM не выполнено | Были только локальный lint/yamllint/static checks; Molecule, `--check --diff` и реальный VM run не выполнялись | Не считать роль готовой до прогона на VM через проектный workflow с converge/idempotence/verify evidence |
| Vagrant VM без GPU passthrough не проверяет physical GPU path | VM дает реальный init/kernel, но не предоставляет PCI GPU device без passthrough | Разделять VM smoke/idempotence и bare-metal/passthrough validation; не заявлять GPU runtime coverage без устройства |
| Vagrant package cache может быть устаревшим | Generic/base boxes могут иметь stale pacman keyring или outdated apt cache | В `prepare.yml` обновлять keyring/package cache перед установкой prerequisites |
| Multilib не тестируется в Vagrant/Docker image | `[multilib]` repo не включен в базовых образах, поэтому `lib32-*` packages недоступны | Для multilib scenario включать repo в prepare или явно фиксировать, что multilib out of scope |
| Ubuntu VM падает на недоступном package name | Пакеты вроде `intel-media-va-driver`, `vulkan-tools`, `mesa-vulkan-drivers` могут называться иначе или отсутствовать в конкретной версии Ubuntu repos | Проверять package availability на целевой Ubuntu VM до утверждения mapping и синхронно обновлять install/verify |
| Vagrant VM проверяет distro packages, но не hardware runtime | Даже с реальным kernel VM без GPU passthrough не предоставляет PCI GPU device, поэтому package install проходит, а `vainfo`/`vulkaninfo` runtime остается непроверенным | Разделять package/config/idempotence coverage и hardware runtime coverage; для runtime нужен bare-metal или passthrough |
