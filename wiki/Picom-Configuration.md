# Picom Configuration

Конфигурация композитора picom (upstream v12+, yshui/picom).

## Обзор

Picom установлен из pacman (официальный upstream, не picom-ftlabs-git). Версия v12+ поддерживает:
- Per-window `rules:` (единый блок вместо множества exclude-списков)
- Анимации с пресетами и кастомными скриптами
- Триггеры: `open`, `close`, `show`, `hide`, `geometry`

## Файлы

| Файл | Назначение |
|------|-----------|
| `dotfiles/dot_config/picom.conf.tmpl` | Шаблон конфигурации picom |
| `dotfiles/.chezmoidata/picom.toml` | SSOT: тени, opacity, blur, анимации |
| `dotfiles/dot_local/bin/executable_launch-picom` | Скрипт запуска (kill-wait-start) |

## Архитектура конфига

```
picom.conf.tmpl
├── Backend: glx (не xrender — медленнее для анимаций)
├── Global defaults: corner-radius, shadows
├── Blur: dual_kawase
├── Animations: appear/disappear (глобальные)
└── Rules: (unified per-window settings, порядок важен!)
    ├── Default opacity (active/inactive) — без match, ко ВСЕМ
    ├── Dock: no shadow, no blur, opacity = 1, custom appear 0.3s
    ├── Desktop: no effects, opacity = 1
    ├── _GTK_FRAME_EXTENTS@: opacity = 1 (CSD-тени)
    ├── DnD: no animations, opacity = 1
    ├── Polybar: opacity = 1
    ├── Firefox/Brave: full opacity
    ├── Alacritty: per-focus opacity
    ├── Tooltip: no animations
    ├── popup_menu: opacity = 0.95 (контекстные меню)
    └── Thunar: opacity = 1 (ПОСЛЕ popup_menu!)
```

## Анимации

### Доступные пресеты

| Пресет | Описание | VM совместимость |
|--------|---------|-----------------|
| `slide-in` / `slide-out` | Скольжение с направлением | Артефакты тени |
| `fly-in` / `fly-out` | Влёт/вылет с замедлением | Артефакты тени |
| `appear` / `disappear` | Scale + fade | Только тень анимируется |

### Кастомные анимации

```
animations = ({
  triggers = ["open", "show"];
  duration = 0.5;
  opacity = {
    curve = "linear";
    duration = 0.5;
    start = 0;
    end = 1;
  };
})
```

Поддерживаемые output-переменные: `opacity`, `scale-x`, `scale-y`, `offset-x`, `offset-y`, `shadow-opacity`, `crop-x`, `crop-y`, `crop-width`, `crop-height`.

### Важно: duration в СЕКУНДАХ

```
duration = 0.2;   # 200ms - ПРАВИЛЬНО
duration = 200;   # 200 СЕКУНД - НЕПРАВИЛЬНО!
```

### Backend: glx vs xrender

| Backend | Анимации | Рекомендация |
|---------|---------|-------------|
| `glx` | Нормальная скорость при заданном duration | **Использовать всегда** |
| `xrender` | Визуально «долгие» при том же duration (0.3s) | Не использовать для анимаций |

## Известные баги и ограничения

### BUG #1393: open-анимация не работает с !focused opacity

**Issue:** [yshui/picom#1393](https://github.com/yshui/picom/issues/1393)

Когда в `rules:` есть правило `{ match = "!focused"; opacity = ...; }`, оно подавляет `open`/`show` анимацию на окнах, получающих фокус. Закрытие (`close`/`hide`) работает нормально.

**Причина:** При открытии окно получает фокус, что триггерит пересчёт opacity из-за `!focused` правила. Этот пересчёт подавляет анимацию.

**Статус:** Не исправлен (upstream, сентябрь 2025).

**Workaround:** Убрать глобальный `!focused` opacity rule. Но тогда теряется затемнение неактивных окон. Компромисс: оставить `!focused` для UX, принять что open-анимация не работает.

### VM (software rendering): scale-анимации не рендерятся

В VM с software rendering (VMware SVGA3D, VirtualBox) пресеты `appear`/`disappear` анимируют **только тень**, а не само окно. Это ограничение software renderer — scale-based эффекты не поддерживаются.

**Что работает:**
- `disappear` (close) — тень анимируется, окно мгновенно исчезает (визуально приемлемо)
- Dock `appear` (open) — работает (dock не матчится `!focused`, обходит баг #1393)
- Кастомная opacity-анимация — синтаксис парсится, но визуально эффект не заметен в VM

**Что НЕ работает:**
- `appear` (open) на обычных окнах — подавляется багом #1393
- Scale-анимации — только тень, не окно
- `slide-in` / `fly-in` — создают движущийся теневой артефакт

### rules: переопределяет old-style опции

Когда в конфиге есть блок `rules:`, следующие глобальные опции **игнорируются** с предупреждениями:
- `active-opacity`
- `inactive-opacity`
- `opacity-rule`
- `rounded-corners-exclude`
- `shadow-exclude`
- `wintypes:`

Вся логика opacity, shadow exclusion и window types должна быть внутри `rules:`.

## Синтаксис rules

### Default (без match — применяется ко всем)

```
rules: (
  { opacity = 0.92; },
  { match = "!focused"; opacity = 0.85; },
  ...
)
```

### Per-window animations

```
# Отключить анимации
{ match = "class_g = 'Thunar'"; animations = (); }

# Кастомная анимация
{
  match = "window_type = 'dock'";
  animations = ({
    triggers = ["open", "show"];
    preset = "appear";
    duration = 0.3;
  });
}
```

### Match syntax

```
match = "class_g = 'Alacritty'"          # по классу
match = "class_g = 'Alacritty' && focused"  # класс + состояние
match = "window_type = 'dock'"           # по типу окна
match = "fullscreen"                     # fullscreen окна
match = "!focused"                       # без фокуса
match = "_GTK_FRAME_EXTENTS@"            # по X property
match = "class_g = 'firefox' || class_g = 'Brave-browser'"  # OR
```

## Порядок применения rules и opacity

Rules в picom v12+ применяются **последовательно сверху вниз**. Если окно матчится нескольким правилам, свойства из более поздних правил перезаписывают более ранние.

### Приоритет правил

```
rules: (
  { opacity = 0.92; },                            # 1. Нет match → ко ВСЕМ окнам
  { match = "!focused"; opacity = 0.85; },         # 2. Перезаписывает opacity для unfocused
  { match = "window_type = 'popup_menu'";          # 3. popup_menu получает 0.95
    opacity = 0.95; },
  { match = "class_g = 'Thunar'"; opacity = 1; },  # 4. ПОСЛЕ popup_menu — перезаписывает
)
```

### Opacity leak через default rule

Правило без `match` считается default и применяется ко **всем** окнам, включая dock, desktop, DnD и CSD-тени (`_GTK_FRAME_EXTENTS@`). Чтобы opacity не «протекал» на служебные окна, нужно явно прописать `opacity = 1`:

| Окно | Почему нужен explicit `opacity = 1` |
|------|-------------------------------------|
| Dock (ewwii bar) | Бар не должен быть полупрозрачным |
| Desktop | Рабочий стол — фоновое окно |
| `_GTK_FRAME_EXTENTS@` | CSD-тени GTK-приложений |
| DnD | Drag-and-drop overlay |
| Polybar | Если используется параллельно |

### Thunar vs popup_menu

Контекстные меню Thunar — X11 окна с `window_type = 'popup_menu'` **И** `class_g = 'Thunar'`. Если правило Thunar стоит **до** popup_menu, то popup_menu перезапишет его opacity. Правило Thunar должно быть **после** popup_menu в списке rules.

## Синхронизация picom и GTK CSS (rounded corners)

Скруглённые углы на контекстных меню GTK3-приложений (Thunar, Xfce) требуют синхронизации **двух уровней**: picom обрезает пиксели на уровне композитора (`corner-radius`), GTK CSS рисует скруглённый фон на уровне приложения (`border-radius`).

### Двухуровневая архитектура

```
X11 window (window_type = popup_menu)
├── picom corner-radius: 10px       ← compositor clipping
└── GTK3 drawing:
    ├── .csd.popup decoration       ← border-radius: 10px
    ├── menu                        ← margin: 4px; padding: 6px; border-radius: 10px
    └── menuitem                    ← border-radius: 6px; padding: 7px 6px
```

### Что происходит без синхронизации

| Конфигурация | Результат |
|-------------|-----------|
| Только picom `corner-radius` | Чёрные углы (picom обрезает, GTK рисует квадратное) |
| Только GTK CSS `border-radius` | Визуально квадратные (GTK скруглил, но X11 окно прямоугольное) |
| **Оба синхронизированы** | Корректные скруглённые углы |

### Рецепт (на основе [adw-gtk3 #100](https://github.com/lassekongo83/adw-gtk3/issues/100))

**GTK3** (`~/.config/gtk-3.0/gtk.css`):

```css
.csd.popup decoration { border-radius: 10px; box-shadow: 0 2px 8px rgba(0,0,0,0.3); }
.csd menu             { border-radius: 10px; }
menu                  { margin: 4px; padding: 6px; }
menuitem              { border-radius: 6px; padding: 7px 6px; }
separator             { margin: 4px 8px; }
```

**GTK4** (`~/.config/gtk-4.0/gtk.css`) — аналогичный подход через `popover.menu > contents`.

**Picom** — глобальный `corner-radius` с тем же значением (10px). Не отключать для `popup_menu`.

Подробнее о GTK CSS: [[GTK-CSS-Reference]]

## Итоги отладки анимаций (2026-02-07)

Проведено систематическое A/B тестирование конфигурации (~13 деплоев): последовательно включались и выключались rules, shadows, blur, менялся backend и пресеты.

### Хронология экспериментов

| # | Конфигурация | Результат |
|---|-------------|-----------|
| 1 | Все эффекты + rules + animations 0.2s | Open не работает, close работает |
| 2 | Duration увеличен до 1.0s | Open всё равно не работает |
| 3 | Пресет `fly-in` вместо `appear` | Не помогло |
| 4 | Убран `!focused` opacity rule | Open **заработал** на dock |
| 5 | Per-window animations (window_type = 'normal', 5s) | Анимируется только тень |
| 6-7 | Custom opacity animation / возврат к baseline | Синтаксис парсится, визуально не заметно |
| 8-10 | Animations only / xrender / glx 0.2s | xrender заметно медленнее |
| 11-12 | Rules + corners / rules закомментированы | Animations работают |
| 13 | **Финальная конфигурация** | Стабильный конфиг |

### Финальная конфигурация

- Backend: `glx`
- Анимации: `appear`/`disappear` 0.2s (глобальные)
- Rules: unified block с explicit `opacity = 1` для служебных окон
- Ограничения VM (software rendering + [BUG #1393](https://github.com/yshui/picom/issues/1393)) задокументированы выше и не требуют действий до перехода на bare metal

## Миграция с picom-ftlabs-git

### Что изменилось

| ftlabs | upstream v12+ |
|--------|--------------|
| `animation-stiffness-in-tag` | `animations = ({ preset = "..."; })` |
| `animation-dampening` | `duration = 0.2;` (секунды) |
| `animation-for-open-window = "zoom"` | `preset = "appear"` |
| `animation-for-unmap-window` | `triggers = ["close"]` |
| Множественные exclude-списки | Единый `rules:` блок |
| `round-borders` | Не поддерживается (i3 patch handles it) |

### Пакеты

- **Было:** `picom-ftlabs-git` (AUR) + `picom` в conflicts
- **Стало:** `picom` (pacman, packages_wm)

## Troubleshooting

### Picom не стартует

```bash
# Проверить процесс
pgrep -a picom

# Запустить с диагностикой
DISPLAY=:0 picom --diagnostics

# Запустить в foreground с debug
DISPLAY=:0 picom --config ~/.config/picom.conf --log-level=debug
```

### Экран зависает после изменения конфига

```bash
# Через SSH:
ssh <host> "pkill picom"
# Затем переключиться на TTY: Ctrl+Alt+F2
```

### Проверить рендеренный конфиг

```bash
cat ~/.config/picom.conf
```

---

Назад к [[Home]]
