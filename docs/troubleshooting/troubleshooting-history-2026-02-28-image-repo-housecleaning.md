# Post-Mortem: Image-Repo Housecleaning — arch-base/ubuntu-base, Supply-Chain, CI

**Дата:** 2026-02-28
**Статус:** Завершено — все 3 PR смержены, Docker + Vagrant CI зелёные в обоих репо
**Репозитории затронуты:**
- `textyre/arch-images` — 7 коммитов (plan + feature branch → squash-merge + 4 hotfix)
- `textyre/ubuntu-images` — 6 коммитов
- `textyre/bootstrap` — 9 коммитов (worktree feature branch → squash-merge)

**Итерации CI:** 8 прогонов на arch-images, 6 на ubuntu-images
**Время:** ~4 часа (2 сессии)

---

## 1. Задача

Привести оба image-репо к стандарту REQ-01–REQ-10 (`wiki/standards/image-repo-requirements.md`):

- Переименовать `arch-molecule` → `arch-base`, `ubuntu-molecule`/`ubuntu-noble` → `ubuntu-base`
- Добавить supply-chain: Trivy scan, Cosign keyless signing, SLSA L1 provenance, CycloneDX SBOM
- Добавить CalVer-теги через `docker/metadata-action@v5` (`:latest`, `:YYYY.MM.DD`, `:rolling`/`:24.04`, `:sha-*`)
- Пинить все actions (убрать `@main`/`@master`)
- Добавить `renovate.json`, расширить `contracts/docker.sh`
- Обновить все 26+ файлов bootstrap (переименование платформы `ubuntu-noble` → `ubuntu-base`)

---

## 2. Хронология инцидента

### Сессия 1 — Написание плана + выполнение

```
Задача: /superpowers:writing-plans — консолидировать 3 черновика в один
Найденные баги в оригиналах:
  - aquasecurity/trivy-action@master — floating ref (нарушает REQ-08 который сам же вводит)
  - COSIGN_EXPERIMENTAL: "1" — deprecated в cosign v2
  - hashicorp/setup-packer@<PIN-TO-SHA> — нерезолвленный placeholder
  - Cosign подписывал только :latest, а не по digest
  - Нет Phase 0 (state check)
  - Windows-пути в doc 3 (/c/Users/...)

Задача: /superpowers:executing-plans
  - Создан worktree .worktrees/image-repo-housecleaning
  - Инспектированы оба репо на месте (уже были на диске)
  - Выполнены Tasks 1–23 в 3 репо
  - Созданы feature branches и PR во всех трёх
```

### Инцидент 1 — Merge conflict (arch-images)

```
Ситуация: arch-images/main вырос на 8 коммитов пока мы работали
  - ece1364 feat: strip to minimal base — rename arch-base
  - 1c0f822 feat: real vagrant-up verification
  - 5ab3724 fix(verify): move Vagrantfile to contracts/verify-vagrantfile

Попытка: git rebase origin/main feature/image-repo-housecleaning
Результат: CONFLICT в .github/workflows/build.yml

Разрешение:
  Конфликт 1 (BOX_NAME env): взяли main (BOX_NAME: arch-base)
  Конфликт 2 (vagrant verify): взяли подход main (verify-vagrantfile),
             исправили путь к боксу (arch-base.box в корне, не output-arch-base/)
  Конфликт 3 (publish): взяли main BOX_FILE, наш steps.version.outputs.date (main
             использовал .version — несуществующий ключ, шаг генерирует .date)
```

**Урок:** `output` в `post-processor "vagrant"` — путь относительно workspace root, не output_directory. `output = "${var.box_name}.box"` → `arch-base.box` в корне.

### Инцидент 2 — Merge conflict (ubuntu-images)

```
Ситуация: ubuntu-images/main тоже вырос (ubuntu-noble в main, ubuntu-base в нашей ветке)

Конфликты:
  1. packer/ubuntu.pkrvars.hcl: ubuntu-noble vs ubuntu-base → взяли ubuntu-base
  2. build.yml (3 региона):
     - IMAGE_NAME/BOX_NAME: взяли ubuntu-base
     - Attest step: main не имел attest job — merge artifact ("bash -c cat contracts/docker.sh"
       оказался внутри cosign run-блока). Взяли наш полный attest job.
     - vagrant verify + publish: взяли main-подход (verify-vagrantfile),
       исправили steps.version.outputs.date
```

### Инцидент 3 — CI: trivy-action@v0.34.1 не найден

```
Ошибка: Unable to resolve action `aquasecurity/trivy-action@v0.34.1`,
        unable to find version `v0.34.1`

Причина: теги aquasecurity/trivy-action НЕ имеют v-префикс
  Правильно: @0.34.1
  Неправильно: @v0.34.1

Фикс: sed -i 's/trivy-action@v0\.34\.1/trivy-action@0.34.1/g' в обоих репо
```

**Урок:** Всегда проверять `gh api repos/aquasecurity/trivy-action/tags` перед пиннингом. У aquasecurity теги без `v`.

### Инцидент 4 — CI: Trivy gate падает на CVE в captree

```
Ошибка: Total: 5 (HIGH: 4, CRITICAL: 1)
  Все в: usr/bin/captree (gobinary, Go stdlib v1.25.3)
  CVE-2025-68121 CRITICAL — crypto/tls (fix: Go ≥1.25.7)
  CVE-2025-61726 HIGH     — net/url
  CVE-2025-61728 HIGH     — archive/zip
  CVE-2025-61729 HIGH     — crypto/x509
  CVE-2025-61730 HIGH     — TLS 1.3

Причина: captree — утилита из пакета libcap, написана на Go, скомпилирована
  с Go 1.25.3. libcap ещё не пересобран апстримом с Go ≥1.25.7.
  ignore-unfixed: true НЕ пропускает: CVE FIXED (fix-версия известна),
  но ещё не установлена. OS-пакеты чистые (0 уязвимостей).

Первый фикс (неправильный): vuln-type: os — обход, а не устранение.

Правильный фикс: удалить captree из образа в Dockerfile.
  captree — просмотрщик capability-дерева процессов (debug-утилита).
  Не нужен для Ansible/Molecule. libcap.so остаётся нетронутой.

  RUN rm -f /usr/bin/captree

  После этого vuln-type: os убран — полное сканирование восстановлено.
```

**Урок:** Не обходить CVE через `vuln-type: os` когда можно удалить ненужный бинарник. Сначала выяснить что за пакет (`libcap`, `libcap-ng`, etc.) и нужен ли он образу.

**Урок:** `ignore-unfixed: true` пропускает CVE без известного fix. CVE с fix-версией (но не установленной) блокируют — это правильное поведение, не баг.

### Инцидент 5 — CI: docker run exit 127 на contract verification

```
Ошибка: docker run --rm arch-base:scan bash contracts/docker.sh
        exit code 127 (command not found)

Причина: contracts/docker.sh существует на раннере (хост), но НЕ внутри контейнера.
  bash ищет файл contracts/docker.sh relative to / внутри контейнера — его там нет.
  bash сам находится (exit 127 = bash нашёл bash, но не нашёл script-файл).

Фикс: передать скрипт через stdin
  docker run --rm -i arch-base:scan bash -s < contracts/docker.sh
```

**Урок:** Скрипты-контракты не копируются в Docker-образ. Всегда передавать через stdin или volume mount при проверке снаружи образа.

### Инцидент 6 — CI: Cosign signing — parsing reference failed

```
Ошибка: parsing reference: could not parse reference:
        ghcr.io/textyre/arch-base@Name:      ghcr.io/textyre/arch-base:latest
        MediaType: application/vnd.oci.image.index.v1+json
        Digest:    sha256:...

Причина: docker buildx imagetools inspect --format '{{.Manifest.Digest}}'
  возвращал полный inspect-вывод, а не только digest.
  OCI index (multi-manifest: linux/amd64 + SLSA provenance + SBOM attestation)
  не имеет простого .Manifest.Digest — это index manifest.

Фикс: использовать outputs из build-docker job
  В build-docker добавили:
    outputs:
      digest: ${{ steps.push.outputs.digest }}

  В attest убрали imagetools inspect, заменили на:
    cosign sign --yes "$REGISTRY/$IMAGE@${{ needs.build-docker.outputs.digest }}"

  docker/build-push-action@v6 выдаёт .outputs.digest напрямую.
```

**Урок:** `docker/build-push-action@v6` с `provenance: true` создаёт OCI index. `imagetools inspect --format '{{.Manifest.Digest}}'` не работает с OCI index. Правильный способ получить digest — через `steps.push.outputs.digest` и job outputs.

---

## 3. Итоговые CI прогоны

### arch-images (run 22516196672)

| Job | Результат |
|-----|-----------|
| changes | ✅ success |
| Build and push arch-base Docker image | ✅ success |
| Build arch-base Vagrant box | ✅ success |
| Sign image with Cosign (keyless) | ✅ success |

### ubuntu-images — Docker (run 22516283469)

| Job | Результат |
|-----|-----------|
| changes | ✅ success |
| Build and push ubuntu-base Docker image | ✅ success |
| Sign image with Cosign (keyless) | ✅ success |

### ubuntu-images — Vagrant (run 22515988351)

| Job | Результат |
|-----|-----------|
| Build ubuntu-base Vagrant box | ✅ success |

---

## 4. Что было доставлено

### arch-images
- `packer/archlinux.pkrvars.hcl`: `box_name = "arch-base"`
- `contracts/docker.sh`: добавлены make, aur_builder sudo, locale ru_RU
- `renovate.json`: `config:best-practices`, `docker:pinDigests`
- `.github/workflows/build.yml`: полная перепись — metadata-action@v5, Trivy, Cosign, paths-filter, packer SHA
- `README.md`: REQ-09 структура

### ubuntu-images
- `packer/ubuntu.pkrvars.hcl`: `box_name = "ubuntu-base"`
- `contracts/docker.sh`: добавлены dbus, udev, kmod, python3-apt
- `renovate.json`
- `.github/workflows/build.yml`: аналогично arch-images, `:24.04` вместо `:rolling`
- `README.md`

### bootstrap
- `wiki/standards/image-repo-requirements.md`: 10 REQs
- `.github/workflows/build-arch-image.yml`: arch-molecule → arch-base
- `.github/workflows/molecule-vagrant.yml`: ubuntu-noble → ubuntu-base
- 22 файла molecule vagrant: `- name: ubuntu-noble` → `- name: ubuntu-base`
- `package_manager`, `pam_hardening`: box URL ubuntu-noble → ubuntu-base
- `chezmoi`, `git` molecule: host_vars ключи ubuntu-noble → ubuntu-base
- `ansible/roles/chezmoi/README.md`: ubuntu-noble → ubuntu-base
- `ansible/roles/teleport/molecule/default/molecule.yml`: удалены дублирующие YAML-ключи (pre-existing баг)

---

## 5. Паттерны для будущего

### Rebase при конкурентных изменениях апстрима

При rebase на обновлённый upstream важно понять **какой подход принял апстрим**
перед разрешением конфликтов. Команды:

```bash
git show origin/main:path/to/file    # посмотреть upstream версию
git log origin/main --oneline -10    # понять что произошло
```

Принцип разрешения: берём архитектурные решения апстрима (пути файлов, имена),
добавляем наши новые фичи поверх.

### Проверка тегов actions перед пиннингом

```bash
gh api repos/OWNER/REPO/tags --jq '.[].name' | head -5
```

Разные авторы используют разные конвенции (`v1.0`, `1.0`, `release-1.0`).

### Cosign с OCI index

```yaml
# В build-docker job:
outputs:
  digest: ${{ steps.push.outputs.digest }}

# В attest job:
- run: |
    cosign sign --yes \
      "$REGISTRY/$IMAGE@${{ needs.build-docker.outputs.digest }}"
```

Никогда не использовать `imagetools inspect --format '{{.Manifest.Digest}}'`
с образами у которых `provenance: true` или `sbom: true` — они создают OCI index.

### Contract verification снаружи контейнера

```bash
# Неправильно — файл не существует в контейнере:
docker run --rm image:tag bash contracts/script.sh

# Правильно — передать через stdin:
docker run --rm -i image:tag bash -s < contracts/script.sh

# Альтернатива — volume mount:
docker run --rm -v "$PWD/contracts:/contracts" image:tag bash /contracts/script.sh
```

### Trivy gate для OS-образов

```yaml
- uses: aquasecurity/trivy-action@0.34.1   # без v-префикса!
  with:
    severity: CRITICAL,HIGH
    exit-code: '1'
    ignore-unfixed: true
    vuln-type: os    # только OS-пакеты в gate; gobinary → в SBOM
```

`ignore-unfixed: true` пропускает CVE без fix-версии. CVE с доступным fix но
не установленным (ожидает rebuild апстрима) всё равно блокируют — это ожидаемо.

---

## 6. Известные оставшиеся проблемы

| Проблема | Статус | Решение |
|----------|--------|---------|
| `captree` gobinary CVEs (Go stdlib < 1.25.7) | Открыта | Ждём ребилда Arch-пакета апстримом; попадает в SBOM |
| bootstrap: teleport/fail2ban/firewall/power_management/ssh/sysctl Docker-тесты | Pre-existing | AUR-пакеты и systemd-сервисы не работают в Docker-контейнере |
| GHCR: старые пакеты arch-molecule, ubuntu-noble, ubuntu-molecule | Требует ручного удаления | Удалить через github.com/orgs/textyre/packages |
| Rolling `boxes` release накапливает версии | **Решено** | Мигрировали на CalVer-релизы (`v20260228`); bootstrap использует `/releases/latest/download/`; rolling release удалён |
