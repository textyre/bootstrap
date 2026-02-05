# Polybar Configuration — Architecture

Полный анализ конфигурации Polybar "три плавающих острова".

## Executive Summary

Polybar реализует 3-bar floating island design с динамическими воркспейсами, real-time system monitoring, и hot-reloadable icons.

**Статус:** ~90% готов для миграции, с идентифицированным техническим долгом.

### Key Statistics

| Category | Count | Status |
|----------|-------|--------|
| Config files | 1 main + 7 scripts | All present |
| Bars defined | 4 (workspaces, add, clock, system) | Fully functional |
| Modules | 9 total (6 internal, 3 custom) | All working |
| Color schemes | 2 (dracula, monochrome) | Both defined |
| Nerd Font icons | 16+ glyphs | Properly encoded |

## Архитектура: "Три плавающих острова"

```
[ЛЕВЫЙ ОСТРОВ]           [ЦЕНТР]         [ПРАВЫЙ ОСТРОВ]
Workspaces              Clock           System Info
+ Add button            Date/Time       Network, Volume, CPU,
                                        Memory, Controls
```

**Характеристики:**
- Каждый бар — отдельный процесс polybar
- `override-redirect = true` — не управляются WM
- Прозрачный фон с полупрозрачными островами
- Border radius 14px, border 1px
- Высота 32px, offset-y 6px
- Multi-monitor: 4 бара на монитор

## Структура файлов

```
dotfiles/dot_config/polybar/
├── config.ini.tmpl              [Main config, 274 lines, chezmoi template]
├── executable_launch.sh         [Launcher, 39 lines, env vars, multi-monitor]
└── scripts/
    ├── executable_workspaces.sh.tmpl    [Workspace indicator, 133 lines, tail mode]
    ├── executable_add-workspace.sh      [Create workspace + rofi menu]
    ├── executable_close-workspace.sh    [Delete workspace]
    ├── executable_change-workspace-icon.sh  [Change icon]
    └── executable_workspace-menu.sh     [Right-click menu]

dotfiles/dot_config/rofi/themes/
├── icon-select.rasi.tmpl        [Icon grid, 2x5]
└── context-menu.rasi.tmpl       [Context dropdown]

dotfiles/.chezmoidata/
├── layout.toml                  [Bar sizes, gaps, spacing]
├── themes.toml                  [Colors: dracula, monochrome]
└── fonts.toml                   [JetBrainsMono Nerd Font]
```

## 9 Модулей

### Встроенные (internal/*)
- **date** — день, дата, время (1 sec update)
- **network** — IP или "disconnected" (3 sec)
- **volume** — % громкости (PulseAudio)
- **cpu** — % CPU usage (2 sec)
- **memory** — % RAM usage (3 sec)
- **tray** — системная tray (пуста)

### Пользовательские (custom/*)
- **workspaces** — tail mode, i3 events
- **workspace-add-btn** — кнопка "+"
- **sep** — spacing offset
- **controlcenter** — иконка ⚙️
- **powermenu** — иконка ⏻

## Динамические воркспейсы

**Фиксированные (WS 1-3):**
- WS 1: 🌐 (Web browser)
- WS 2: 󰀫 (Code)
- WS 3: 󰀛 (Terminal)

**Динамические (WS 4-10):**
- Создаются через "+" кнопку
- Иконка выбирается из rofi меню (10 вариантов)
- Хранятся в `~/.config/polybar/workspace-icons.conf`
- Можно изменить иконку (right-click)
- Можно удалить (right-click) — окна перемещаются в WS 1

**Визуальные состояния:**
- Focused: accent color + underline
- Occupied: foreground
- Empty: foreground-dim
- Urgent: red

## Цветовые схемы

### Dracula (Catppuccin Mocha)
```scss
$bg: #11111b;
$fg: #cdd6f4;
$accent: #cba6f7;  // фиолетовый
$success: #a6e3a1;
$warning: #f9e2af;
$info: #89b4fa;
$urgent: #f38ba8;
```

### Monochrome
```scss
$bg: #0a0a0a;
$fg: #c0c0c0;
$accent: #d4d4d4;  // серый
$urgent: #b04040;  // единственный цветной
```

## Workflow: Управление воркспейсами

### Добавление
```
Клик "+" → rofi меню → выбор иконки → 
сохранить в конфиг → i3-msg workspace N → 
launch.sh (перезапуск для пересчета ширины)
```

### Смена иконки
```
Right-click → меню "Сменить" → rofi → 
обновить конфиг → workspaces.sh перезагружает 
иконки автоматически (tail mode, NO RESTART)
```

### Удаление
```
Right-click → "Закрыть" → переместить окна в WS 1 → 
удалить из конфига → launch.sh (перезапуск)
```

## Динамическая ширина

Workspace bar width рассчитывается в `launch.sh`:

```bash
WS_BAR_WIDTH = 2*EDGE_PADDING + WS_COUNT*ICON_WIDTH + (WS_COUNT-1)*GAP

# Пример (3 workspaces): 2*12 + 3*16 + 2*22 = 116px
# Пример (10 workspaces): 2*12 + 10*16 + 9*22 = 382px
```

Экспортируется как env var для polybar.

## Chezmoi интеграция

Все `.tmpl` файлы используют переменные:

```go
{{ $t := index .themes .theme_name }}  // Текущая тема
{{ $t.bg }}, {{ $t.fg }}, {{ $t.accent }}  // Цвета
{{ .layout.bar_height }}, {{ .layout.gaps_outer }}  // Размеры
{{ .font.mono }}, {{ .font.icon_size }}  // Шрифты
```

## Зависимости

**Обязательные:**
- i3-msg (IPC с i3 WM)
- jq (JSON parsing)
- rofi (меню)

**Для модулей:**
- pamixer (volume scroll)
- PulseAudio/PipeWire

**Опциональные:**
- gsimplecal (календарь)
- pavucontrol (volume GUI)
- alacritty (терминал)

## Технический долг

### Критичные
- ⚠️ Динамическая ширина не полностью верифицирована
- 🔴 Полный polybar restart вместо hot reload (visible flicker)

### Архитектурные
- ❌ EDGE_PADDING=12 захардкожен в 3 местах
- ❌ GAP=22 дублирован (sep_gap vs launch.sh)
- ❌ ICON_WIDTH=16 не связан явно с font.icon_size

### Требуют верификации
- [ ] Dracula тема (только monochrome тестировалась)
- [ ] Multi-monitor (single monitor подтвержден)
- [ ] Все 10 workspace иконок

## Миграция

**Что копировать 1:1:**
- Все `.tmpl` файлы
- Скрипты (bash portable)
- Nerd Font иконки (Unicode codepoints)
- Цветовые палитры

**Что адаптировать:**
- i3-msg → target WM IPC (Hyprland, Sway)
- Shell paths если не /bin/bash
- Terminal команду (alacritty → ваш терминал)

## References

Полная документация в `docs/SubAgent docs/`:
- `POLYBAR_FULL_ANALYSIS_SUMMARY.md` — Executive summary
- `polybar-detailed-analysis.md` — Technical specs
- `polybar-quick-reference.md` — Quick lookup
- `polybar-architecture-diagram.md` — Diagrams

---

Назад к [[Home]]
