# Role: docker

Роль настраивает уже установленный Docker Engine: daemon config и состояние сервиса. Установкой пакета Docker владеет общий package layer.

## Поток

1. Проверка поддерживаемой ОС, storage driver и daemon-переменных.
2. Валидация и развёртывание `/etc/docker/daemon.json`.
3. Немедленный restart только после реального изменения daemon config, затем обеспечение запущенного и включённого сервиса.
4. Формирование итогового отчёта.

## Важные свойства

- `docker_userns_remap: default` отделяет UID контейнеров от UID хоста, но влияет на writable bind mounts.
- Remapping нужно включать до создания постоянных images/containers: он использует
  отдельное представление Docker data root и требует корректных диапазонов `dockremap`
  в `/etc/subuid` и `/etc/subgid`.
- `docker_icc` разрешает связь контейнеров внутри одной Docker-сети; изоляция сервисов достигается отдельными user-defined сетями.
- На systemd используется logging driver `journald`; на других init systems используется `local`.
- Роль не добавляет пользователей в root-equivalent группу `docker`; административные команды выполняются через `sudo` и остаются под действием sudo policy.

## Тесты

Docker и Vagrant выполняют полный pipeline роли и проверяют повторный запуск без изменений на Arch/Ubuntu. Docker запускает systemd и Docker service в privileged-контейнере, Vagrant проверяет тот же контракт внутри полноценной VM. Функции самого Docker Engine тесты роли не проверяют. Запуски выполняются только через remote VM или CI.

Подробный контракт переменных и troubleshooting находятся в [README роли](../../ansible/roles/docker/README.md).

---

Back to [[Home]]
