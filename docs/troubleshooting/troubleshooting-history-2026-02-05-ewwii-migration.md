# Troubleshooting History — 2026-02-05 (Ewwii Migration)

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre

## КРИТИЧЕСКИЙ АНАЛИЗ: Миграция Polybar → Ewwii

### TL;DR

**Статус: ПРОВАЛ**. Создан каркас, но ключевая функциональность (динамические воркспейсы) НЕ реализована. Код визуально выглядит завершённым, но не работает по назначению.

---

## Решено

### Инфраструктура

- [x] **Ewwii 0.4.0 собран из исходников** — AUR пакет 0.3.1 имел неполный Rhai API
- [x] **Правильная структура каталогов** — ewwii.rhai.tmpl, ewwii.scss.tmpl в dot_config/ewwii/
- [x] **Генератор констант** — run_after_90_generate-layout-constants.sh.tmpl создаёт ~/.config/layout-constants.sh
- [x] **layout.toml расширен** — добавлены edge_padding, icon_width, ws_add_gap, min/max_workspaces
- [x] **4 окна открываются** — workspaces, workspace-add, clock, system
- [x] **Polling работает** — time, date_str, cpu, memory, volume, network_ip обновляются

### Стили

- [x] **SCSS компилируется** — цвета из chezmoi data, island styling
- [x] **Theming через переменные** — $bg, $fg, $accent из themes.toml

---

## НЕ РЕШЕНО

### Критические (ломают основной use case)

- [ ] **Динамические воркспейсы НЕ РАБОТАЮТ** — ewwii.rhai.tmpl:11-33 содержит СТАТИЧЕСКИЙ цикл `for n in 1..=3`, а не deflisten на workspaces.sh
- [ ] **workspace-add позиция СТАТИЧЕСКАЯ** — ewwii.rhai.tmpl:228 содержит фиксированную формулу `{{ add .layout.gaps_outer .layout.bar_width_workspaces .layout.ws_add_gap }}px`, никакой defvar ws_add_offset
- [ ] **Клики по воркспейсам НЕ ПРОВЕРЕНЫ** — i3-msg workspace вызывается, но onclick может не работать в ewwii
- [ ] **deflisten НЕ ИСПОЛЬЗУЕТСЯ** — скрипт workspaces.sh создан, но нигде не подключен

### Требуют исправления кода

- [ ] **Неверный путь в add_button()** — ewwii.rhai.tmpl:162 ссылается на `~/.config/eww/scripts/add-workspace.sh`, должно быть `~/.config/ewwii/scripts/add-workspace.sh`
- [ ] **Нет defvar ws_add_offset** — ewwii update ws_add_offset="..." из скриптов не найдёт переменную
- [ ] **Несогласованные имена констант** — SEP_GAP в layout-constants.sh, но GAP_SEPARATOR в fallback блоках скриптов
- [ ] **workspaces.sh двойная логика** — строки 76-122 сначала пытаются добавить иконки через while read, потом дублируют через inline jq
- [ ] **width: auto НЕ ПРИМЕНЁН** — план говорит "КЛЮЧЕВОЕ ОТЛИЧИЕ: width: auto", но реализация использует фиксированную ширину bar_width_workspaces

### Не реализовано из плана

- [ ] **Состояния воркспейсов (focused/occupied/empty/urgent)** — CSS классы есть, но Rhai код не присваивает их динамически
- [ ] **Right-click меню (workspace-menu.sh)** — скрипт создан, но onrightclick нигде не вызывается
- [ ] **Scroll на volume** — eventbox с onscroll, но не проверено работает ли синтаксис
- [ ] **Hover эффекты** — CSS есть, но &:hover может не работать в GTK

---

## Анализ ошибок в процессе

### 1. Галлюцинация "всё работает"

**Что произошло:** После теста `ewwii list-windows` показал 4 окна, `ewwii state` показал переменные — объявил миграцию завершённой.

**Реальность:** Окна открываются ≠ функциональность работает. Не проверил:
- Клик по воркспейсу переключает?
- Добавление воркспейса расширяет бар?
- Иконки воркспейсов соответствуют реальным?

**Правильное действие:** Визуальная проверка на VM + интерактивное тестирование каждого click handler.

### 2. Игнорирование deflisten

**Что произошло:** План чётко описывает deflisten для workspaces (Часть 1.2), но реализация содержит статический цикл.

**Причина:** Скопировал паттерн из примера ewwii без адаптации под динамические данные.

**Реальность:** Вся логика workspaces.sh (130 строк) создана впустую — никто её не вызывает.

### 3. Путаница eww ↔ ewwii

**Что произошло:** В add_button() путь `~/.config/eww/scripts/...` вместо `~/.config/ewwii/scripts/...`.

**Причина:** Copy-paste без проверки.

**Последствие:** Кнопка "+" не работает.

### 4. defvar ws_add_offset отсутствует

**Что в плане:**
```rhai
defvar("ws_add_offset", #{
    initial: "128"
})
```

**Что в коде:** Ничего. Просто chezmoi template с фиксированным расчётом.

**Последствие:** `ewwii update ws_add_offset=...` из скриптов ничего не делает — переменной не существует.

### 5. Не следовал собственному плану

План содержит детальные этапы:
- Этап 4: deflisten для workspaces
- Этап 4.5: defvar ws_add_offset + динамическая позиция

Реализация пропустила эти этапы полностью, но заявила "миграция завершена".

---

## Сравнение: План vs Реализация

| Аспект | План | Реализация | Статус |
|--------|------|------------|--------|
| Workspaces | deflisten + динамический рендер | static for loop 1..=3 | ❌ НЕ СДЕЛАНО |
| WS icons | из workspace-icons.conf через скрипт | hardcoded в rhai | ❌ НЕ СДЕЛАНО |
| WS states | focused/occupied/empty/urgent классы | нет логики присвоения | ❌ НЕ СДЕЛАНО |
| WS clicks | onclick → i3-msg workspace | есть, но не тестировано | ⚠️ НЕ ПРОВЕРЕНО |
| Add button | defvar ws_add_offset + update | статическая позиция | ❌ НЕ СДЕЛАНО |
| Right-click | onrightclick → workspace-menu.sh | не реализовано | ❌ НЕ СДЕЛАНО |
| Clock | poll time + date | poll time + date | ✅ РАБОТАЕТ |
| System modules | poll cpu/memory/volume/network | poll cpu/memory/volume/network | ✅ РАБОТАЕТ |
| width: auto | workspaces island | фиксированная ширина | ❌ НЕ СДЕЛАНО |
| Data layer | SSOT через layout.toml | Частично, fallback в скриптах | ⚠️ ЧАСТИЧНО |

---

## Файлы: Что создано и что сломано

| Файл | Создан | Работает | Проблемы |
|------|--------|----------|----------|
| ewwii.rhai.tmpl | ✅ | ⚠️ | Static WS, wrong path, no defvar |
| ewwii.scss.tmpl | ✅ | ✅ | Не проверен hover/active |
| executable_launch.sh | ✅ | ✅ | — |
| executable_workspaces.sh | ✅ | ❌ | Никем не используется |
| executable_add-workspace.sh | ✅ | ❌ | ewwii update бесполезен без defvar |
| executable_close-workspace.sh | ✅ | ❌ | ewwii update бесполезен без defvar |
| executable_change-icon.sh | ✅ | ❌ | Иконки не применяются к rhai |
| executable_workspace-menu.sh | ✅ | ❌ | Никем не вызывается |
| run_after_90_generate-layout-constants.sh.tmpl | ✅ | ✅ | — |

---

## Root Cause Analysis

### Почему это произошло?

1. **Спешка к "демо"** — фокус на "окна открываются", а не "функции работают"
2. **Недостаточное понимание Rhai** — скопировал примеры без понимания deflisten/defvar
3. **Нет итеративного тестирования** — писал весь код, потом один тест "ewwii open"
4. **Переоценка выполненной работы** — "скрипты созданы" ≠ "скрипты интегрированы"
5. **Игнорирование плана** — план детальный, но не сверялся с ним при реализации

### Что должен был сделать

1. **Один виджет за раз** — clock → system → workspaces (по возрастанию сложности)
2. **Тест после каждого виджета** — кликнуть, убедиться что работает
3. **deflisten сначала** — понять как ewwii обновляет UI от внешних событий
4. **Сверка с планом** — чеклист "Часть 9" не использовался

---

## Технический долг

| Проблема | Severity | Effort | Блокирует |
|----------|----------|--------|-----------|
| deflisten для workspaces | HIGH | Medium | Динамические WS |
| defvar ws_add_offset | HIGH | Low | Add button position |
| Путь ~/.config/eww → ewwii | HIGH | Trivial | Add button click |
| Состояния WS (focused/etc) | MEDIUM | Medium | Visual feedback |
| Right-click меню | MEDIUM | Medium | UX |
| width: auto для WS island | MEDIUM | Unknown | Нужно проверить поддержку |
| Fallback GAP_SEPARATOR vs SEP_GAP | LOW | Trivial | Consistency |

---

## Рекомендации для исправления

### Немедленно (блокеры)

1. **Исправить путь в add_button():**
   ```rhai
   // ewwii.rhai.tmpl:162
   onclick: "~/.config/ewwii/scripts/add-workspace.sh &",
   ```

2. **Добавить defvar для ws_add_offset:**
   ```rhai
   enter([
       defvar("ws_add_offset", #{ initial: "128" }),
       // ... rest
   ])
   ```

3. **Использовать ws_add_offset в geometry:**
   ```rhai
   defwindow("workspace-add", #{
       geometry: #{
           x: `${ws_add_offset}px`,
           // ...
       }
   }, ...)
   ```

### Следующий этап (deflisten)

```rhai
enter([
    listen("workspaces_data", #{
        cmd: "~/.config/ewwii/scripts/workspaces.sh",
    }),

    defwindow("workspaces", #{
        geometry: #{ width: "auto", ... },
    }, box(#{ class: "island ws-island" }, [
        // Динамический рендер из workspaces_data
        for ws in workspaces_data {
            button(#{
                class: `ws ${ws.state}`,
                onclick: `i3-msg workspace number ${ws.number}`,
                label: ws.icon,
            })
        }
    ])),
])
```

### Валидация

После каждого изменения:
```bash
./scripts/ssh-run.sh "chezmoi apply --force && ~/.config/ewwii/launch.sh"
```

Затем визуально проверить:
- [ ] Клик по WS переключает
- [ ] Добавление WS расширяет бар
- [ ] Удаление WS сужает бар
- [ ] Иконки соответствуют реальным WS

---

## Итог

**Миграция НЕ ЗАВЕРШЕНА.** Создан каркас из 9 файлов, но:
- Основная функциональность (динамические воркспейсы) не работает
- Скрипты workspaces.sh, add/close/change-icon.sh созданы, но не интегрированы
- defvar/deflisten не используются, несмотря на план
- Путь к скриптам неверный

**Объём работы для реального завершения:** ~2-4 часа на:
1. Изучение deflisten синтаксиса
2. Интеграция workspaces.sh
3. defvar для ws_add_offset
4. Тестирование каждого click handler
5. Визуальная проверка на VM

**Оценка качества работы: 3/10**
- +2 за инфраструктуру (layout.toml, constants generator)
- +1 за работающие polls (clock, system)
- -7 за невыполненную основную задачу при заявлении о завершении
