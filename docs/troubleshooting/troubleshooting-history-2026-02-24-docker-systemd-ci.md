# Troubleshooting History — Docker / systemd CI

Дата: 2026-02-24

## Решено

| Ошибка | Причина | Решение |
|--------|---------|---------|
| Dockerfile build падает на зеркалах или именах пакетов | Образ собирается из rolling/base репозитория, где mirrors/package names могут дрейфовать | Контракт образа должен проверять обязательные пакеты, а сборка должна использовать надежные зеркала |
| Локальный Molecule run берет устаревший fallback image | CI задает env image, а локальный fallback в `molecule.yml` остался старым | Обновлять fallback image вместе с CI env var, чтобы локальный и CI пути совпадали |
| Ubuntu Docker scenario не запускается при отсутствии `MOLECULE_UBUNTU_IMAGE` | Reusable workflow не передает image env, а scenario ожидает его | Задавать `MOLECULE_UBUNTU_IMAGE` в reusable workflow и иметь корректный fallback в molecule file |
| Docker scenario покрывает только Arch и пропускает Ubuntu-specific ошибки | В molecule matrix нет Ubuntu/systemd платформы | Добавлять Ubuntu platform для кроссплатформенных ролей, а role-specific prepare держать отдельно |
| `EBUSY`/`EXDEV` при изменении `/etc/hostname` или `/etc/hosts` | Docker bind-монтирует эти файлы, а systemd/Ansible используют atomic rename через границу mount point | В privileged Molecule prepare размонтировать test-only bind mount перед converge |
| `hostname` command not found | Минимальный контейнер не содержит пакет с legacy hostname binary | Проверять hostname через `hostnamectl status --static` или другой уже гарантированный интерфейс |
| Docker test проходит, но не проверяет реальное изменение | Prepare заранее приводит систему в ожидаемое состояние, поэтому converge становится no-op | В тестовом сценарии стартовать с отличающегося состояния и проверять фактическую коррекцию |
| Python HTTPS request падает с `CERTIFICATE_VERIFY_FAILED` | Минимальный Ubuntu/systemd контейнер не содержит или не обновил CA bundle | В prepare установить `ca-certificates` и обновить bundle до converge |
| Сервис в Docker не может выйти в сеть из-за systemd sandboxing | Unit-файл включает ограничения, которые в контейнере блокируют нужный namespace/network path | Делать test-only drop-in в Molecule prepare, не менять роль ради контейнера |
| Сервис с TLS/NTS молча не синхронизируется | В контейнере нет доверенных CA, handshake падает без очевидного crash | Для TLS-сервисов в Docker prepare проверять и устанавливать `ca-certificates` |
| Лог-файл пустой после exception path | `/dev/log` отсутствует в контейнере, syslog call падает раньше записи в file log | В exception handler сначала писать file log, потом пытаться отправить syslog |
| Docker containers на VM не имеют интернета | Host firewall/nftables блокирует bridge forwarding | Исправлять host test environment: разрешить forwarding для docker/bridge интерфейсов |
| Docker prepare ставит prerequisite только для Arch | `prepare.yml` устанавливает `pciutils` через `community.general.pacman`, а Ubuntu-ветка только делает `apt update`; converge случайно компенсирует отсутствие пакета | В Docker prepare добавлять OS-specific prerequisite tasks для каждой платформы, например `ansible.builtin.apt: name=pciutils` для Debian/Ubuntu |
| Docker/CI не имеет PCI GPU-устройств | `lspci` в контейнере или headless CI VM не возвращает записи VGA/Display/3D, поэтому ветка аппаратной auto-detect не отражает bare-metal | Не считать Docker проверкой аппаратной детекции; использовать зафиксированный stdout или VM/bare-metal scenario для проверки поведения детектора |
| NVIDIA proprietary/open-kernel packages не тестируются в Docker | DKMS требует совпадающие kernel headers и modules tree, а контейнер использует host kernel | Для Docker выбирать non-DKMS path или config-only scenario; DKMS install проверять только в подходящей VM/bare-metal среде |
| DKMS post-install hook может завершиться с ошибкой, а package task выглядит успешным | Package manager может вернуть success даже при сломанной сборке module build в post-install hook | Не полагаться только на package install rc для kernel module packages; проверять module build/load в среде с реальным kernel |
| Перегенерация initramfs не тестируется в Docker | `mkinitcpio -P`, `dracut --force`, `update-initramfs -u` требуют реального kernel/modules tree и могут падать или генерировать бесполезный image | В Docker не запускать rebuild path; проверять templates/configs отдельно, rebuild переносить в VM/bare-metal validation |
| Initramfs handler случайно срабатывает в Docker | Изменение NVIDIA drop-in или config-only сценарий может вызвать `mkinitcpio -P`, `dracut --force` или `update-initramfs -u` внутри контейнера без реального kernel/modules tree | Не давать Docker-сценарию запускать rebuild; отделять проверку templates/configs от rebuild validation в VM/bare-metal |
| `vainfo`, `vulkaninfo` и driver runtime commands невалидны в generic Docker CI | VA-API/Vulkan runtime требует GPU, загруженные kernel modules и пользовательскую display session | Runtime GPU checks держать вне generic Docker verify; Docker проверяет package/config/idempotence smoke |
| Принудительный Intel/Mesa path проверяет только CI-safe subset | Pure Mesa packages install cleanly без DKMS/kernel modules, но NVIDIA/AMD hardware behavior не покрывается | В test description явно писать scope: package installation, config rendering, idempotence; не заявлять hardware driver coverage |
