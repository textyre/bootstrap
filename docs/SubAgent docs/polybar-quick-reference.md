# Polybar Quick Reference (Краткая справка)

## Файловая структура

```
dotfiles/dot_config/polybar/
├── config.ini.tmpl                          [Main config, 274 lines, chezmoi template]
├── executable_launch.sh                     [Launcher, 39 lines, env vars, multi-monitor]
└── scripts/
    ├── executable_workspaces.sh.tmpl        [Workspace indicator, 133 lines, tail mode]
    ├── executable_add-workspace.sh          [Create new workspace + rofi menu]
    ├── executable_close-workspace.sh        [Delete workspace, move windows to ws1]
    ├── executable_change-workspace-icon.sh  [Change icon rofi menu]
    └── executable_workspace-menu.sh         [Right-click context menu]

dotfiles/dot_config/rofi/
├── themes/icon-select.rasi.tmpl             [Rofi grid for icon selection, 2x5]
└── themes/context-menu.rasi.tmpl            [Rofi dropdown menu, 2 items]

dotfiles/.chezmoidata/
├── layout.toml                              [Bar sizes, gaps, spacing parameters]
├── themes.toml                              [Color palettes: dracula, monochrome]
└── fonts.toml                               [JetBrainsMono Nerd Font references]
```

## 4 Bars (бара) — структура

| Bar | Модули | Ширина | X-offset | Назначение |
|-----|--------|--------|----------|-----------|
| **workspaces** | workspaces | динамическая | gaps_outer | Workspace indicator (левый остров) |
| **workspace-add** | workspace-add-btn | 40px | ws_width + 4 | "+" button (левый остров) |
| **clock** | date | 220px | 50%:-110 | День, дата, время (центр) |
| **system** | network, volume, cpu, memory, controlcenter, powermenu, tray | 440px | 100%:-448 | System info (правый остров) |

## 9 Модулей (modules)

### Встроенные (internal/*)
- **date** — день, дата, время (обновляется каждую сек)
- **network** — IP адрес или "disconnected"
- **volume** — % громкости (PulseAudio)
- **cpu** — % CPU usage
- **memory** — % RAM usage
- **tray** — системная tray (пуста)

### Пользовательские (custom/*)
- **workspaces** — скрипт в tail mode, слушает i3 события
- **workspace-add-btn** — текст "+" + левый клик
- **sep** — пустой offset (spacing)
- **controlcenter** — иконка ⚙️
- **powermenu** — иконка ⏻

## Динамические workspace иконки

**Базовые (всегда):**
- WS 1: 🌐 (Web browser)
- WS 2: 󰀫 (Code)
- WS 3: 󰀛 (Terminal)

**Динамические (4-10):**
- Создаются через add-workspace.sh (rofi меню выбора)
- Хранятся в `~/.config/polybar/workspace-icons.conf`
- Меняются через change-workspace-icon.sh (динамически, no restart)
- Удаляются через close-workspace.sh

**Все доступные иконки в меню:**
```
● (Circle default)
 Terminal
 Code
 Browser
 Files
 Chat
 Music
 Video
 Gaming
 Settings
 Notes
```

## Цвета (#AARRGGBB format в Polybar)

**Dracula (Catppuccin Mocha):**
```
bg=#11111b, fg=#cdd6f4, accent=#cba6f7 (фиолет)
success=#a6e3a1, warning=#f9e2af, urgent=#f38ba8
```

**Monochrome:**
```
bg=#0a0a0a, fg=#c0c0c0, accent=#d4d4d4 (серый)
```

## Nerd Font иконки (используемые)

| Иконка | Unicode | Модуль |
|--------|---------|--------|
| 🗓 | U+F073 | date |
| 📶 | U+F1EB | network |
| 🔊 | U+F028 | volume |
| 🔇 | U+F6A9 | mute |
| ⚙️ | U+F2DB | cpu |
| 💾 | U+F538 | memory |
| ⚙️ | U+F013 | controlcenter |
| ⏻ | U+F011 | powermenu |

## Wichtige Konstanten (в launch.sh)

```bash
GAPS_OUTER=8        # ✓ Синхронизирован с layout.toml
EDGE_PADDING=12     # ❌ Захардкожен (должен быть в layout.toml)
GAP=22              # ❌ Дублирован (см. sep_gap в layout.toml)
ICON_WIDTH=16       # ❌ Связан с font.icon_size неявно
MIN_WS=3            # ✓ Логично
```

**Расчёт ширины workspace бара:**
```
WS_BAR_WIDTH = 2*EDGE_PADDING + WS_COUNT*ICON_WIDTH + (WS_COUNT-1)*GAP
WS_ADD_OFFSET = GAPS_OUTER + WS_BAR_WIDTH + 4
```

## Интеграция с i3

**В i3 config:**
```bash
# Line 187
exec_always --no-startup-id ~/.config/polybar/launch.sh

# Line 189-191 (Other autostart items)
exec_always --no-startup-id ~/.local/bin/launch-picom
exec_always --no-startup-id sh -c 'pkill -x dunst; exec dunst'
```

## Зависимости (external commands)

**Обязательные:**
- `i3-msg` — IPC с i3 WM
- `jq` — JSON parsing для i3-msg output
- `xrandr` — обнаружение мониторов (graceful fallback)

**Для модулей:**
- `pamixer` — volume control

**Для скриптов:**
- `rofi` — меню выбора иконок

**Опциональные:**
- `gsimplecal` — calendar (клик на date)
- `pavucontrol` — GUI volume (клик на volume)
- `notify-send` — notifications (max workspaces warning)

## Workflow: добавление воркспейса

```
Пользователь щелкает "+" кнопку
    ↓
add-workspace.sh запускается
    ↓
Rofi меню: выбрать иконку из 10 вариантов
    ↓
Сохранить иконку в ~/.config/polybar/workspace-icons.conf
    ↓
Переключиться на новый WS (i3-msg)
    ↓
Перезапустить polybar (launch.sh) — пересчёт ширины
    ↓
Новый WS с иконкой видим в workspace bar
```

## Workflow: смена иконки

```
Правый клик на WS 4+
    ↓
workspace-menu.sh показывает меню: "Сменить" / "Закрыть"
    ↓
Пользователь выбирает "Сменить"
    ↓
change-workspace-icon.sh → rofi меню
    ↓
Новая иконка сохраняется в конфиг
    ↓
workspaces.sh перезагружает иконки (tail mode, IPC)
    ↓
Иконка обновляется БЕЗ перезагрузки polybar ✓
```

## Workflow: закрытие воркспейса

```
Правый клик на WS 4+ → выбрать "Закрыть"
    ↓
close-workspace.sh:
  1. Перемещает все окна в WS 1 (i3-msg)
  2. Удаляет иконку из конфига
  3. Перезапускает polybar
    ↓
WS удален из памяти i3, workspace bar пересчитан
```

## Chezmoi темплейтирование

**Переменные в шаблонах:**

```go
{{ $t := index .themes .theme_name }}    // Текущая тема (dracula/monochrome)

// Цвета
{{ $t.bg }}                               // Background (#0a0a0a или #11111b)
{{ $t.fg }}                               // Foreground (#c0c0c0 или #cdd6f4)
{{ $t.accent }}                           // Accent (#d4d4d4 или #cba6f7)

// Layout
{{ .layout.bar_height }}                  // 32
{{ .layout.bar_offset_y }}                // 6
{{ .layout.bar_width_workspaces }}        // 100 (baseline)
{{ .layout.sep_gap }}                     // 22
{{ .layout.corner_radius }}               // 10

// Шрифты
{{ .font.mono }}                          // JetBrainsMono Nerd Font Mono
{{ .font.icon }}                          // JetBrainsMono Nerd Font Mono
{{ .font.icon_size }}                     // 16
```

## Polybar Markup (format strings)

| Тег | Назначение | Пример |
|-----|-----------|--------|
| `%{T2}text%{T-}` | Переключить шрифт | Использовать font-1 (иконки) |
| `%{Fcolor}text%{F-}` | Цвет текста | `%{F#cdd6f4}` |
| `%{O22}` | Offset (spacing) | Пробел в 22px |
| `%{A1:cmd:}text%{A}` | Left-click | `%{A1:i3-msg workspace 1:}ws1%{A}` |
| `%{A3:cmd:}text%{A}` | Right-click | Context-menu |
| `%{u-}%{+u}text%{-u}` | Underline | Для focused workspace |

## Типичные ошибки

| Ошибка | Результат | Решение |
|--------|-----------|---------|
| Цвет в формате #RRGGBBAA | Неправильный цвет в polybar | Использовать #AARRGGBB (альфа первый) |
| DISPLAY не экспортирован | Бары не видны в SSH | `export DISPLAY=:0; launch.sh` |
| Nerd Font не установлен | Иконки = пробелы | `fc-list \| grep Nerd` и установить |
| Локаль POSIX | Unicode символы не рендерятся | `locale; LANG=en_US.UTF-8` |
| launch.sh не .tmpl | Constants не подставляются | Конвертировать в .tmpl или читать из config |

## Требуемые системные параметры

```bash
locale          # ДОЛЖНА быть en_US.UTF-8 (или другая UTF-8)
fc-list         # ДОЛЖНА содержать JetBrainsMono Nerd Font
i3 --version    # Требуется i3 WM
xrandr          # Для multi-monitor (graceful fallback если нет)
```

## Известные проблемы

### Критичные
- [ ] Динамическая ширина workspace bar не полностью верифицирована на практике
- [ ] При добавлении WS весь polybar перезагружается (видимый флаш)

### Технический долг
- [ ] EDGE_PADDING=12 захардкожен в 3 местах (launch.sh, workspaces.sh.tmpl, docs)
- [ ] GAP дублирован: sep_gap в layout.toml и GAP в launch.sh
- [ ] ICON_WIDTH не связан явно с font.icon_size
- [ ] Нет условного рендеринга для разных WM (только i3)

### Визуально не тестировано
- [ ] Dracula тема (тестировалась только Monochrome)
- [ ] Multi-monitor конфигурация (практическое использование)

## Миграция на другую систему

### Что скопировать 1:1
- Все .tmpl файлы (chezmoi темплейтирование)
- Структуру скриптов
- Nerd Font иконки (Unicode codepoints)
- Цветовые палитры

### Что может потребовать изменений
- **Если другой WM (Hyprland, Sway):** переписать скрипты (вместо i3-msg)
- **Если другой шрифт:** обновить иконки (может быть другой Unicode)
- **Если другой terminal:** обновить alacritty → ваш терминал
- **Если другая система управления:** переписать Ansible part

## Checklist для верификации после развёртывания

- [ ] `locale` показывает UTF-8 (не POSIX)
- [ ] `fc-list | grep JetBrainsMono` возвращает шрифты
- [ ] 3 бара видны вверху экрана (слева, центр, справа)
- [ ] Рабочие пространства переключаются при клике
- [ ] "+" кнопка добавляет WS (+ rofi меню)
- [ ] Right-click на WS 4+ показывает контекстное меню
- [ ] Иконки отображаются корректно (не как пробелы)
- [ ] Network модуль показывает IP
- [ ] Volume, CPU, Memory обновляются
- [ ] Control Center открывается (⚙️ клик)
- [ ] Power Menu открывается (⏻ клик)
- [ ] Calendar работает (клик на дату)
