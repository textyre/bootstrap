# Тестирование Ansible-ролей с Molecule

> **Источник:** [VK Tech Talks — Тестирование Ansible-ролей / Кирилл Борисов](https://www.youtube.com/watch?v=T4VVdkO9sCo)
> **Канал:** VK Team | **Дата:** 2023-04-03 | **Длительность:** ~39 мин

---

## Обзор

Кирилл Борисов (старший инженер-программист VK, 11+ лет в DevOps) рассказывает о выстраивании процесса CI/CD для Ansible-ролей с помощью фреймворка **Molecule**. Доклад покрывает весь путь — от проблем локальной разработки до автоматизированного тестирования в GitLab CI.

---

## Проблемы, которые решает Molecule

1. **Медленная локальная разработка** — поднятие VM для проверки роли занимало ~40 минут, без возможности снапшотов, Docker или Vagrant.
2. **Командная разработка** — каждый член команды вносит изменения в роли; баги обнаруживаются слишком поздно (на продакшене), а не на этапе MR/PR.

## Почему Molecule

Альтернативы: Kitchen (Test Kitchen), ServerSpec, InSpec — все написаны на Ruby. Molecule написана на Python, как и Ansible + Testinfra, что позволяет не тянуть дополнительный стек в команду.

## Преимущества Molecule

- **Управляемые сценарии** — несколько сценариев для одной роли (standalone, cluster и т.д.)
- **Множество драйверов** — Docker, Vagrant (VirtualBox, libvirt, Parallels, VMware), облачные провайдеры (AWS, Azure, GCP), delegated
- **Тестирование идемпотентности** — автоматическая проверка, что повторный прогон не вносит изменений
- **Автоматизация** — встраивается в любой CI/CD (GitLab CI, GitHub Actions и др.)
- **Быстрая отладка** — `molecule login` даёт shell в инстанс

---

## Структура проекта

```
role/
  molecule/
    default/        # сценарий по умолчанию
      molecule.yml
      converge.yml
      verify.yml
      prepare.yml
      tests/
    cluster/        # дополнительный сценарий
      molecule.yml
      ...
```

### Инициализация

```bash
pip install molecule
molecule init role <role_name>       # новая роль + molecule
molecule init scenario cluster       # добавить сценарий в существующую роль
```

---

## Стадии `molecule test`

| # | Стадия | Описание |
|---|--------|----------|
| 1 | **dependency** | Скачивание зависимостей из Ansible Galaxy (`requirements.yml`) |
| 2 | **lint** | Yamllint (YAML-синтаксис), ansible-lint (лучшие практики Ansible), flake8 (Python-тесты) |
| 3 | **destroy** | Уничтожение старого окружения (чистый старт). Можно добавить cleanup-задачи (деregistрация из Consul и т.п.) |
| 4 | **create** | Создание инстансов (контейнеры, VM) согласно `molecule.yml` |
| 5 | **prepare** | Подготовка окружения — установка пакетов, создание пользователей, имитация продакшена |
| 6 | **converge** | Прокатка роли на целевые хосты. Первая проверка, что роль запускается |
| 7 | **idempotence** | Повторный прогон converge — проверка, что нет `changed` |
| 8 | **side_effect** | Опциональная фаза для создания тестовых данных (пользователи FreeIPA, данные в Elasticsearch и т.д.) |
| 9 | **verify** | Запуск тестов (Testinfra / `ansible.builtin.assert`) |
| 10 | **destroy** | Финальная очистка |

---

## molecule.yml — ключевые секции

### Драйвер и платформы (Docker)

```yaml
driver:
  name: docker
platforms:
  - name: instance
    image: geerlingguy/docker-centos7-ansible
    groups:
      - mygroup
```

> Образы **Jeff Geerling** (geerlingguy) — специально пересобранные с systemd для тестирования.

### Provisioner

```yaml
provisioner:
  name: ansible
  options:
    vvv: true           # расширенный debug-вывод
  inventory:
    links:
      group_vars: ../group_vars
  env:
    ANSIBLE_CONFIG: ../../ansible.cfg
```

### Тестовая последовательность

```yaml
scenario:
  test_sequence:
    - destroy
    - create
    - prepare
    - converge
    - idempotence      # можно закомментировать (но не стоит!)
    - verify
    - destroy
```

---

## Тестирование: Testinfra vs Assert

### Testinfra (рекомендуется)

Тесты пишутся на Python (pytest). Возможности:

- Проверка сервисов: запущен, enabled
- Проверка пакетов: установлен
- Проверка пользователей, групп, файлов, директорий
- Проверка сокетов и портов
- Проверка вывода команд

```python
def test_chrony_running(host):
    svc = host.service("chronyd")
    assert svc.is_running
    assert svc.is_enabled

def test_freeipa_user(host):
    cmd = host.run("ipa user-find testuser")
    assert "testuser" in cmd.stdout
```

### Ansible Assert (для проверки на продакшене)

Используется `assert` модуль + handlers для проверки состояния после прокатки:

```yaml
handlers:
  - name: check_hadoop
    command: hadoop checknative
    register: result
  - name: verify_hadoop
    assert:
      that:
        - "'Native library' in result.stdout"
```

---

## CI/CD — GitLab CI пример

```yaml
stages:
  - test

molecule:
  stage: test
  script:
    - pip install python-docker molecule
    - molecule test
```

Время полного прогона: **~2 минуты** (вместо 40 минут на VM).

---

## Итоги

| До Molecule | После Molecule |
|-------------|----------------|
| 40 минут на создание VM | 2 минуты полный цикл |
| Ручная проверка | Автоматизированные тесты |
| Нет воспроизводимости | Единое окружение для всей команды |
| Баги на продакшене | Баги на этапе MR/PR |

---

## Q&A — ключевые моменты

- **Сложные роли в Docker** — да, можно комбинировать несколько инстансов (FreeIPA + зависимый сервис) в одном сценарии
- **Podman вместо Docker** — теоретически возможно, но без privileged будет сложно (systemd, интеграции)
- **Версии Ansible** — обязательно пинить в requirements / Dockerfile, иначе обновление линтера ломает CI
- **Windows** — WSL2 работает, нативная Windows — не рекомендуется
- **Динамический инвентарь** — не поддерживается в Molecule, хосты задаются явно
- **Тестирование апгрейда** — на фазе `prepare` ставится предыдущая версия, `converge` апгрейдит
- **Интеграционные тесты** — можно писать на pytest прямо в Testinfra
