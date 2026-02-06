# Ewwii Migration — Runbook for Next Agent

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre
SSH: `ssh arch-127.0.0.1-2222`
Chezmoi source: `~/.local/share/chezmoi` → symlink → `~/bootstrap/dotfiles`

---

## STOP. READ THIS BEFORE DOING ANYTHING.

4 предыдущие сессии (и 1 частично успешная) сделали. Главные открытия:

1. **Ewwii 0.4.0 НЕ загружает внешние CSS файлы** (`eww.scss`, `eww.css` — полностью игнорируются). Стили применяются ТОЛЬКО через inline `style` property на виджетах в Rhai конфиге.
2. **Проверка файлов ≠ проверка визуала.** `grep 'font-size: 12px' eww.scss` ничего не значит.

**Правило #1:** После ЛЮБОГО изменения → `chezmoi apply --force` → перезапуск ewwii → **спроси пользователя "видишь разницу?"**. Никакой grep не заменяет глаза.

**Правило #2:** Стили — ТОЛЬКО через inline `style` property в ewwii.rhai.tmpl. Внешние CSS файлы бесполезны.

**Правило #3:** Делай одно изменение за раз. Применяй. Проверяй визуально. Следующее.

---

## 1. ТЕКУЩЕЕ СОСТОЯНИЕ (сессия 5, подтверждено визуально)

### Что РАБОТАЕТ (подтверждено пользователем):
- ✅ Single transparent dock window (2560px wide) — бар виден
- ✅ 3 воркспейса с иконками (🌍, 󰀫, 󰀛) — workspaces.sh показывает min_workspaces
- ✅ Фон и цвета островов видны — inline `style` с `background-color: rgba(...)` работает
- ✅ `cursor: "pointer"` — поддерживается как Rhai widget property
- ✅ Add-кнопка (+) работает
- ✅ Иконки clock/system — видны (U+F017, U+F1EB, U+F028, U+F2DB, U+F538, U+F013, U+F011)
- ✅ Границы островов — сплошной цвет `#404040` (monochrome) / `#65547e` (dracula)
- ✅ Капсульная форма островов — `border-radius: 48px`
- ✅ Отступы по бокам — `bar_pad_sides: 12px`
- ✅ Высота островов — `min-height: 18px`
- ✅ Компактные модули — `spacing: 4`, `sep width: 2`

### Что НЕ РАБОТАЕТ:
| # | Проблема | Статус | Детали |
|---|----------|--------|--------|
| 1 | **Иконки clock/system** | ✅ ПОЧИНЕНО (сессия 5) | Причина: Write tool уничтожил Unicode. Решение: иконки в fonts.toml через `\uXXXX`, шаблон ссылается на chezmoi переменные |
| 2 | **Размер шрифта** | ❌ Не проверено | font-size на bar-container может не наследоваться к child labels |
| 3 | **Границы островов** | ✅ ПОЧИНЕНО (сессия 5) | Заменены rgba → сплошной hex. dracula: `#65547e`, monochrome: `#404040` |
| 4 | **Отступы по бокам** | ✅ ПОЧИНЕНО (сессия 5) | `bar_pad_sides` 2→12. Работает с geometry width: 100% |
| 5 | **Ширина облаков** | ✅ ПОЧИНЕНО (сессия 5) | Причина: eventbox/box внутри островов расширяются. Решение: (1) three-section layout + (2) button вместо eventbox→box→labels. Button — leaf widget, сам определяет ширину. Clock и system — по одной кнопке внутри острова |
| 6 | **Высота островов** | ✅ ПОЧИНЕНО (сессия 5) | 34→18px, отступы top=6, bottom=0 |

---

## 2. КРИТИЧЕСКОЕ ОТКРЫТИЕ: EWWII 0.4.0 ИГНОРИРУЕТ ВНЕШНИЕ CSS

### Доказательство (сессия 4):
1. Поставили `* { background-color: red !important; font-size: 40px !important; }` в `eww.css`
2. Перезапустили ewwii (полный restart: kill + daemon + open)
3. **НУЛЕВОЙ визуальный эффект** — скриншоты до и после пиксель-в-пиксель идентичны

### Что РАБОТАЕТ:
- `style: "background-color: red; padding: 20px;"` на виджете → ✅ красный фон виден
- `css: ".bar-container { background-color: blue; }"` на виджете → ✅ синий фон виден

### Вывод:
- Внешние файлы `eww.scss` / `eww.css` — **бесполезны** в ewwii 0.4.0
- Стили нужно задавать через `style` property (inline CSS) или `css` property (class-based CSS) на виджетах
- Бинарник содержит `gtk_css_provider_load_from_data` (inline CSS), НО НЕ загружает файлы
- Help text ewwii упоминает `eww.(s)css` — это **ложь**, файлы не загружаются

### Также НЕ поддерживается:
- CSS `alpha()` функция — вызывает `Error: Only 1 argument allowed, but 2 were passed`
- Используй pre-computed `rgba(r, g, b, a)` значения в `themes.toml`

---

## 3. НЕРЕШЁННЫЕ ПРОБЛЕМЫ — ГИПОТЕЗЫ

### 3.1 Иконки clock/system не видны

**Факты:**
- WS иконки из `workspaces.sh` (🌍, 󰀫, 󰀛) — ВИДНЫ
- Иконки в Rhai шаблоне (, , , , , , ) — НЕ ВИДНЫ
- Nerd Font установлен: JetBrainsMono Nerd Font Mono ✅
- Unicode в rendered файле цел (подтверждено hexdump)

**Гипотезы:**
1. **Write tool повредил Unicode** при перезаписи ewwii.rhai.tmpl — нужно проверить rendered файл на VM
2. **font-family не наследуется** через inline style на parent → нужно добавить font-family на каждый icon label
3. **Rhai string concatenation** (`"font-size: " + icon_size + "px;"`) может не работать с int — нужно `icon_size.to_string()`
4. **Chezmoi template порезал Unicode** при обработке .tmpl → нужно проверить raw bytes

**Как проверить:**
```bash
# 1. Проверить codepoints в rendered файле
python3 -c "
import re
with open('/home/textyre/.config/ewwii/ewwii.rhai', 'r') as f:
    content = f.read()
for m in re.finditer(r'text:\s*\"([^\"]+)\"', content):
    text = m.group(1)
    if len(text) <= 3 and not text.isascii():
        codepoints = ' '.join(f'U+{ord(c):04X}' for c in text)
        print(f'text=\"{text}\"  codepoints: {codepoints}')
"

# 2. Тест рендеринга в терминале
echo -e "Clock: \uf017  Network: \uf1eb  Volume: \uf028"
```

### 3.2 Font-size не наследуется

**Факты:**
- `style: "font-size: 14px;"` установлен на bar-container
- Визуально шрифт не изменился

**Гипотезы:**
1. Inline `style` на parent НЕ наследуется к child widgets в ewwii
2. Нужно ставить font-size на КАЖДЫЙ label виджет

**Как исправить:**
- Добавить `style: "font-size: 14px;"` на каждый label (date, time, value)
- Или использовать `css` property на root для глобальных стилей

### 3.3 Отступы по бокам не изменились

**Факты:**
- bar-container style включает `padding: 2px 2px 4px 2px`
- Geometry width: 100%
- Визуально боковые отступы не изменились

**Гипотезы:**
1. padding может не работать по бокам на 100% width dock window
2. Старые значения были не от CSS (а от i3 gaps_outer)

---

## 4. ЛОВУШКИ CHEZMOI (уже решены, но могут повториться)

### 4.1 SCP -r создаёт вложенные копии
**Решение:** Копируй ФАЙЛЫ, не директории. См. секцию Deploy.

### 4.2 Chezmoi мержит ВСЕ .toml в .chezmoidata/
**Проверка:** `ls ~/bootstrap/dotfiles/.chezmoidata/` — должны быть ТОЛЬКО fonts.toml, layout.toml, themes.toml

### 4.3 Root-level .chezmoidata.toml
**Проверка:** `ls ~/bootstrap/dotfiles/.chezmoidata.toml 2>/dev/null` — не должен существовать

---

## 5. DEPLOYMENT ПРОЦЕДУРА

```bash
# 1. Копирование (с локальной Windows машины)
scp -o BatchMode=yes -o ConnectTimeout=10 \
  dotfiles/.chezmoidata/layout.toml \
  dotfiles/.chezmoidata/fonts.toml \
  dotfiles/.chezmoidata/themes.toml \
  arch-127.0.0.1-2222:/home/textyre/bootstrap/dotfiles/.chezmoidata/

scp -o BatchMode=yes -o ConnectTimeout=10 \
  dotfiles/dot_config/ewwii/ewwii.rhai.tmpl \
  dotfiles/dot_config/ewwii/executable_launch.sh \
  arch-127.0.0.1-2222:/home/textyre/bootstrap/dotfiles/dot_config/ewwii/

scp -o BatchMode=yes -o ConnectTimeout=10 \
  dotfiles/dot_config/ewwii/scripts/executable_workspaces.sh \
  arch-127.0.0.1-2222:/home/textyre/bootstrap/dotfiles/dot_config/ewwii/scripts/

# 2. Apply
ssh arch-127.0.0.1-2222 "chezmoi apply --force ~/.config/ewwii/"

# 3. Перезапуск
ssh arch-127.0.0.1-2222 "pkill -f eww; sleep 1; DISPLAY=:0 ~/.config/ewwii/launch.sh &"

# 4. ВИЗУАЛЬНАЯ ПРОВЕРКА
```

---

## 6. ФАЙЛЫ ПРОЕКТА — КАРТА

```
dotfiles/
├── .chezmoidata/
│   ├── layout.toml          # bar_height, bar_pad_top/bottom/sides, sep_gap...
│   ├── fonts.toml            # bar_size (14), icon_size (18), font family
│   └── themes.toml           # цвета + island_bg/island_border (rgba)
├── dot_config/
│   ├── ewwii/
│   │   ├── ewwii.rhai.tmpl   # ГЛАВНЫЙ: виджеты + inline styles
│   │   ├── eww.scss.tmpl     # БЕСПОЛЕЗЕН: ewwii не загружает внешние CSS
│   │   ├── executable_launch.sh  # запуск daemon + open bar
│   │   └── scripts/
│   │       └── executable_workspaces.sh.tmpl  # JSON генератор для i3 WS
│   └── i3/
│       └── config.tmpl       # i3 config
```

### Ключевые переменные

| Переменная | Определена в | Используется в | Текущее значение |
|-----------|-------------|---------------|-----------------|
| `.layout.bar_height` | layout.toml | ewwii.rhai.tmpl (geometry, min-height) | 18 |
| `.layout.bar_pad_top` | layout.toml | ewwii.rhai.tmpl (geometry, padding) | 6 |
| `.layout.bar_pad_bottom` | layout.toml | ewwii.rhai.tmpl (geometry, padding) | 0 |
| `.layout.bar_pad_sides` | layout.toml | ewwii.rhai.tmpl (padding) | 12 |
| `.layout.bar_padding` | layout.toml | ewwii.rhai.tmpl (clock/system island padding) | 2 |
| `.layout.bar_radius` | layout.toml | ewwii.rhai.tmpl (border-radius) | 48 |
| `.layout.bar_border` | layout.toml | ewwii.rhai.tmpl (border-width) | 1 |
| `.layout.sep_gap` | layout.toml | ewwii.rhai.tmpl (sep() width) | 4 |
| `.layout.edge_padding` | layout.toml | ewwii.rhai.tmpl (ws island padding) | 12 |
| `.font.bar_size` | fonts.toml | ewwii.rhai.tmpl (font-size) | 14 |
| `.font.icon_size` | fonts.toml | ewwii.rhai.tmpl (icon font-size) | 18 |
| `$t.island_bg` | themes.toml | ewwii.rhai.tmpl (island background) | rgba(10,10,10,0.87) / rgba(17,17,27,0.87) |
| `$t.island_border` | themes.toml | ewwii.rhai.tmpl (island border) | #404040 (mono) / #65547e (dracula) |
| `.font.icon_*` | fonts.toml | ewwii.rhai.tmpl (icon text) | TOML `\uXXXX` escaped Nerd Font codepoints |

---

## 7. ДОКУМЕНТАЦИЯ

### Ewwii (форк eww)
1. **Styling widgets** — https://ewwii-sh.github.io/docs/theming_and_ui/styling_widgets
2. **Working with GTK** — https://ewwii-sh.github.io/docs/theming_and_ui/working_with_gtk
3. **Config fundamentals** — https://ewwii-sh.github.io/docs/config_and_syntax/config_fundamentals

### Eww (оригинальный)
4. **Widgets** — https://elkowar.github.io/eww/widgets.html
5. **Configuration** — https://elkowar.github.io/eww/configuration.html

### GTK CSS reference (GTK3)
6. **GTK CSS properties** — https://docs.gtk.org/gtk3/css-properties.html

---

## 8. ИСТОРИЯ СЕССИЙ

### Сессия 1 (2026-02-05): Начальная миграция
- 4 отдельных dock windows → стакаются вертикально (i3 dock behavior)

### Сессия 2 (2026-02-05 вечер): Попытка исправления
- Root cause: i3 dock stacking. Оценка: 4/10

### Между сессиями 2-3: Single dock window решение
- Один прозрачный dock + island boxes внутри → горизонтальный бар

### Сессия 3 (2026-02-06): "7 визуальных проблем"
- 5 раундов дебага chezmoi data, 0 визуальных фиксов. Оценка: 2/10

### Сессия 4 (2026-02-06): **Корневая причина найдена**
- **Открытие:** ewwii 0.4.0 НЕ загружает внешние CSS файлы
- **Доказательство:** `* { background-color: red !important; }` в eww.css → нулевой эффект
- **Открытие:** inline `style` property РАБОТАЕТ (тест: red background → виден)
- **Открытие:** CSS `alpha()` НЕ поддерживается → используем pre-computed rgba()
- Переписан ewwii.rhai.tmpl с inline styles на всех виджетах
- Добавлены island_bg/island_border в themes.toml
- Workspaces скрипт показывает 3 WS минимум
- **Результат:** острова выше, фон видим, 3 WS с иконками
- **Осталось:** иконки clock/system, font-size, границы, отступы по бокам
- Оценка: 6/10

### Сессия 5 (2026-02-06): **Визуальная доводка + иконки починены**
- **Границы:** rgba → сплошной hex (`#404040` mono, `#65547e` dracula)
- **Капсулы:** border-radius 14→48px — полное скругление
- **Отступы:** sides 2→12, top 2→6, bottom 4→0
- **Высота:** 34→18px (min-height островов)
- **Компактность:** убран spacer в clock, spacing 6→4, sep 4→2
- **Иконки:** ПОЧИНЕНЫ. Причина: Write tool уничтожил Unicode при перезаписи. Решение: иконки определены в fonts.toml через TOML `\uXXXX` escape, шаблон использует chezmoi переменные `{{ .font.icon_clock }}` и т.д.
- **Ширина островов:** ПОЧИНЕНА. Причина: ewwii box layout выделяет прямым детям больше натуральной ширины. `halign`, `hexpand: false` на самих островах НЕ помогают. `centerbox` не поддерживается.
  - **Решение (двойное):**
    1. Three-section layout — bar-left (без hexpand), bar-center/bar-right (hexpand: true, halign: fill). Острова внутри с halign center/end
    2. **Button вместо eventbox→box→labels** — button это leaf widget, сам определяет ширину по контенту. Clock и system переписаны как одна кнопка с конкатенированным текстом
  - **Не работали:** `hexpand: false` на островах, `halign` на островах, spacer+box, eventbox hexpand: false, кнопки внутри box (box всё равно расширяется), centerbox (не поддерживается)
  - **Ключевое открытие:** в ewwii leaf widgets (button, label) определяют ширину по контенту, а container widgets (box, eventbox) расширяются до allocation
- **Открытие:** TOML `\uXXXX` escape безопасен от Unicode corruption при редактировании
- **Результат:** все иконки видны, острова компактные капсулы, границы чёткие, ширина по контенту
- Оценка: 9/10

---

## 9. ЧЕКЛИСТ ДЛЯ СЛЕДУЮЩЕГО АГЕНТА

### Перед началом работы
- [x] Ewwii 0.4.0 НЕ загружает внешние CSS — только inline `style`/`css` properties
- [x] CSS `alpha()` не поддерживается — используем rgba() из themes.toml
- [x] Nerd Font установлен на VM
- [x] `cursor: "pointer"` — поддерживается как widget property

### Решённые задачи (сессия 5)
- [x] Иконки clock/system: Unicode потерян Write tool → решение: `\uXXXX` в fonts.toml + chezmoi переменные
- [x] Границы: rgba → сплошной hex (`#404040` / `#65547e`), хорошо видны
- [x] Отступы по бокам: `bar_pad_sides` 2→12, работает
- [x] Высота: 34→18px, компактнее
- [x] Ширина островов: three-section layout (bar-left без hexpand, bar-center/right с hexpand+fill, острова с halign center/end)

### Нерешённые задачи
- [ ] Font-size: добавить font-size на каждый text label (наследование не работает)

### На каждое изменение
- [ ] SCP файлы на VM (НЕ директории)
- [ ] `chezmoi apply --force`
- [ ] `pkill -f eww; sleep 1; DISPLAY=:0 ~/.config/ewwii/launch.sh`
- [ ] Визуальная проверка (спросить пользователя)
