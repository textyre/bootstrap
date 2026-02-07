# Troubleshooting History — 2026-02-07 — Picom Forks Analysis & Config Tuning

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre

---

## Решено

### Исследование: выбор форка picom

- [x] **Глубокий анализ всех форков picom** — проанализированы 10+ форков/проектов (yshui, FT-Labs, jonaburg, pijulius, dccsillag, ibhagwan, sdhand, compfy, fdev31, r0-zero, yaocccc, Arian8j2). Проверены GitHub, AUR, Arch repos, Repology, changelogs. Подтверждено: **upstream yshui/picom v13 — единственный правильный выбор** для нашего стека (Arch + i3wm + VirtualBox VM)

- [x] **Установлено: все animation-форки устарели** — jonaburg удалён из AUR (авг 2023), FT-Labs orphaned в AUR, compfy archived (автор сам рекомендует picom v12), dccsillag — PR #772 отклонён. Единственный живой нишевый форк — pijulius (spring-based физика), но отстаёт от upstream на ~2 года фич

- [x] **Генеалогия фич восстановлена** — rounded corners (sdhand → ibhagwan → upstream), dual kawase blur (tryone144 → upstream), анимации (community inspired → yshui реализовал по-своему preset-based в v12). Все ключевые фичи из форков давно merged в upstream

- [x] **Версии в пакетных менеджерах верифицированы:**
  - Arch official: `extra/picom` **12.5-3** (build 2025-05-29)
  - AUR: `picom-git` (359 голосов, HEAD upstream)
  - GitHub: **v13** (2026-02-07 — свежий релиз сегодня!)
  - Fedora 42+: 12.5, Ubuntu 25.04+: 12.5, Debian sid: 12.5

### Исследование: picom v13 changelog

- [x] **v13 release notes изучены** — багфикс: краш при отрицательном blur-opacity (#1493). v13-rc1 (2025-12-09): разделение geometry-триггера на `size`/`position`, per-window `shadow-color`, `blur-opacity` с animation variables, custom шейдеры для desktop background, `urgent` window matching

- [x] **v12 → v13 progression понятна** — v12 (2024-09-27) дал нативные анимации + unified rules; v12.1-v12.5 — багфиксы; v13-rc1 — major features (shadow-color, blur-opacity, shaders); v13 — стабилизация

### Конфигурация: rules uncommented

- [x] **Window rules раскомментированы в `picom.conf.tmpl`** — ранее были закомментированы для изоляции тестирования анимаций. Восстановлены: opacity per-app, dock/desktop без тени и blur, Thunar без анимаций, tooltip/popup_menu/dnd правила, fullscreen без corner-radius

- [x] **Dock opacity явно установлена** — `opacity = 1` для dock, desktop, Thunar, Polybar, dnd, _GTK_FRAME_EXTENTS — предотвращает применение `!focused` opacity к UI-элементам

- [x] **Thunar правило вынесено после popup_menu** — порядок правил важен (последнее значение побеждает); popup_menu задаёт `opacity = 0.95`, а Thunar перезаписывает на `opacity = 1` + отключает анимации/тени/blur

---

## Не решено

### Критичные

- [ ] **BUG #1393: `!focused` opacity подавляет open/show анимацию** — upstream баг picom. Когда в `rules:` есть правило `match = "!focused"; opacity = X;`, оно подавляет `open`/`show` анимацию на focused окнах. Close/hide работает. Workaround: закомментировать `!focused` правило (теряем unfocused dimming) или принять что open-анимация не сработает. **Нет fix upstream.** Root cause: анимация open выставляет окно как focused, но rule engine уже применил !focused opacity, конфликт подавляет триггер

- [ ] **VM (software rendering): appear/disappear анимируют только тень** — в VirtualBox без GPU-ускорения scale-based пресеты (`appear`, `disappear`) не рендерят анимацию самого окна, только тени. Slide-based (`slide-in`, `slide-out`) работают, но BUG #1393 мешает при наличии opacity rules. **Ограничение среды, не picom.**

### Требуют core fix в конфигах

- [ ] **Обновление до v13** — сейчас в Arch official repos picom 12.5-3. v13 вышел сегодня (2026-02-07). Для получения v13 нужно: (a) ждать обновления `extra/picom` или (b) перейти на `picom-git` из AUR. v13 даёт per-window `shadow-color`, `blur-opacity`, custom shaders, `urgent` matching

- [ ] **Решить конфликт animations + !focused opacity** — текущий конфиг имеет закомментированные rules из-за BUG #1393. Варианты:
  1. Убрать `!focused` opacity → теряем dimming неактивных окон
  2. Убрать анимации → теряем visual candy
  3. Оставить обе → open-анимация не работает, close работает
  4. Ждать fix upstream (issue #1393 открыт)

### Низкий приоритет

- [ ] **Исследовать v13 `blur-opacity` для ewwii bar** — v13 добавляет per-window blur-opacity с анимацией. Можно использовать для плавного появления blur на dock при hover/focus. Требует `picom-git` или ожидания v13 в repos

- [ ] **Физические анимации (bounce/spring)** — upstream picom не поддерживает physics-based анимации (stiffness/dampening/mass). Единственный живой форк с ними — pijulius, но он отстаёт от upstream. Принятое решение: остаёмся на upstream preset-based анимациях

- [ ] **Документ `docs/picom-v12-v13-research.md` содержит неточности** — строка 178: `duration = 300` написано как миллисекунды, но duration в picom v12+ в **СЕКУНДАХ** (0.3 = 300ms). Также отсутствуют пресеты `fly-in`/`fly-out`, не упомянут v13

---

## Сводная таблица форков

| Форк | Stars | Arch пакет | Статус | Вердикт |
|------|:-----:|-----------|--------|---------|
| **yshui/picom** (upstream) | ~4700 | `extra/picom` 12.5 | v13 released | **Использовать** |
| FT-Labs/picom | ~262 | `picom-ftlabs-git` (orphaned) | Последний коммит ~дек 2023 | Устаревает |
| jonaburg/picom | ~980 | УДАЛЁН из AUR | Заброшен | Мёртв |
| pijulius/picom | ~425 | `picom-pijulius-next-git` (1 голос) | Dev branch | Нишевый |
| dccsillag/picom | ~159 | Нет пакета | PR #772 отклонён | Историч. |
| ibhagwan/picom | ~761 | Нет | Фичи в upstream | Историч. |
| sdhand/picom | ~134 | Нет | Фичи в upstream | Историч. |
| allusive-dev/compfy | Мало | `compfy` (5 голосов) | ARCHIVED фев 2024 | Мёртв |

## Генеалогия фич

```
tryone144/compton ──(dual kawase blur)──► ibhagwan ──► upstream (merged)
sdhand/picom ──(rounded corners)──► ibhagwan ──► upstream (merged)
dccsillag (spring anims) ──► pijulius (desktop switch, inner border)
                          └──► PR #772 (отклонён, yshui сделал по-своему)
jonaburg (Blackcapcoder anims, 40us deltas) ──► заброшен
FT-Labs (10+ anims, physics) ──► orphaned
yshui v12 (preset-based анимации, triggers, suppressions) ──► v13 (shadow-color, blur-opacity, shaders)
```

---

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `dotfiles/dot_config/picom.conf.tmpl` | Раскомментированы window rules; добавлены `opacity = 1` для dock/desktop/Thunar/Polybar; Thunar вынесен после popup_menu; corner-radius = 0 для tooltip/popup |

---

## Итог

**Picom upstream v13 (yshui/picom) — безальтернативный выбор.** Все animation-форки мертвы или устарели. Ключевые фичи из форков (blur, rounded corners) давно в upstream. Физические анимации (единственное преимущество форков) не стоят потери unified rules, blur-opacity, custom shaders и стабильности.

Текущий конфиг работает на upstream v12.5. Open-анимация ограничена BUG #1393 (конфликт с !focused opacity). Close-анимация (`disappear`) работает. При обновлении Arch repos до v13 — исследовать blur-opacity и shadow-color для улучшения рендера.
