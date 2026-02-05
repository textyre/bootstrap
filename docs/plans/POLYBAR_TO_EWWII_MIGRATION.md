# План миграции с Polybar на Ewwii

**Дата:** 2026-02-05
**Проект:** bootstrap (dotfiles)
**Источник:** [Ewwii](https://github.com/Ewwii-sh/ewwii)

---

## Часть 1: Что такое Ewwii

**Ewwii** (Elkowar's Wacky Widgets Improved Interface) — переработка оригинального eww с ключевыми отличиями:

| Характеристика | eww (оригинал) | ewwii |
|----------------|----------------|-------|
| **Язык конфигурации** | Yuck (Lisp-подобный) | **Rhai** (Rust-подобный скриптинг) |
| **GTK версия** | GTK3 | **GTK4** |
| **Hot reload** | Частичный | Полный |
| **Расширяемость** | Ограниченная | Плагины + модули Rhai |
| **X11/Wayland** | Да | Да |

### Структура конфигурации Ewwii

```
~/.config/ewwii/
├── ewwii.rhai          # Главный конфиг (виджеты, окна, переменные)
├── ewwii.scss          # Стили (CSS/SCSS)
└── scripts/            # Вспомогательные скрипты
    ├── getvol
    ├── workspaces.sh
    └── ...
```

---

## Часть 2: Текущая функциональность Polybar (что сохранить)

### 2.1 Архитектура — "Три плавающих острова"

```
[ЛЕВЫЙ ОСТРОВ]           [ЦЕНТРАЛЬНЫЙ ОСТРОВ]     [ПРАВЫЙ ОСТРОВ]
┌──────────────────┐     ┌─────────────────┐      ┌──────────────────────────┐
│ 🌐 󰀫 󰀛 [+]      │     │  Wed Feb 05 14:23│      │ 192.168.1.5  🔊75%      │
│ workspaces       │     │  clock/date     │      │ CPU 12%  MEM 45%  ⚙ ⏻   │
└──────────────────┘     └─────────────────┘      └──────────────────────────┘
```

**Характеристики островов:**
- `override-redirect = true` (не управляются WM)
- Прозрачный фон с полупрозрачными островами (#dd11111b)
- Border radius 14px, border 1px
- Высота 32px, offset-y 6px
- Multi-monitor: 4 бара на монитор

### 2.2 Модули (9 штук)

| Модуль | Тип | Функциональность | Интерактивность |
|--------|-----|------------------|-----------------|
| **workspaces** | custom/script | Иконки WS 1-10, tail mode, i3 events | Left-click: switch, Right-click: menu (WS 4+) |
| **workspace-add-btn** | custom/text | Кнопка "+" | Left-click: rofi меню выбора иконки |
| **date** | internal/date | День + дата + время | Left-click: gsimplecal |
| **network** | internal/network | IP адрес или "disconnected" | Left-click: nmtui в терминале |
| **volume** | internal/pulseaudio | Громкость % или "muted" | Click: pavucontrol, Scroll: ±5% |
| **cpu** | internal/cpu | CPU % | — |
| **memory** | internal/memory | RAM % | — |
| **controlcenter** | custom/text | Иконка ⚙️ | Left-click: rofi control center |
| **powermenu** | custom/text | Иконка ⏻ | Left-click: rofi power menu |

### 2.3 Динамические воркспейсы

**Фиксированные (WS 1-3):**
- WS 1: 🌐 (браузер)
- WS 2: 󰀫 (код)
- WS 3: 󰀛 (терминал)

**Динамические (WS 4-10):**
- Создаются по кнопке "+"
- Иконка выбирается из rofi меню (10 вариантов)
- Сохраняются в `~/.config/polybar/workspace-icons.conf`
- Можно изменить иконку (right-click → "Сменить иконку")
- Можно удалить (right-click → "Закрыть") — окна перемещаются в WS 1

**Визуальные состояния:**
- Focused: accent color + underline
- Occupied: foreground
- Empty: foreground-dim
- Urgent: red

### 2.4 Цветовые схемы

**Dracula (Catppuccin Mocha):**
```scss
$bg: #11111b;
$fg: #cdd6f4;
$accent: #cba6f7;
$success: #a6e3a1;
$warning: #f9e2af;
$info: #89b4fa;
$urgent: #f38ba8;
```

**Monochrome:**
```scss
$bg: #0a0a0a;
$fg: #c0c0c0;
$accent: #d4d4d4;
// Все остальные — оттенки серого
$urgent: #b04040; // единственный цветной
```

### 2.5 Скрипты (7 штук)

| Скрипт | Назначение |
|--------|------------|
| `launch.sh` | Запуск polybar, расчёт ширины WS бара |
| `workspaces.sh.tmpl` | Рендер воркспейсов (tail mode) |
| `add-workspace.sh` | Создание нового WS через rofi |
| `close-workspace.sh` | Удаление WS, перемещение окон |
| `change-workspace-icon.sh` | Смена иконки WS |
| `workspace-menu.sh` | Контекстное меню WS |

### 2.6 Зависимости

**Обязательные:**
- i3-msg (IPC с i3 WM)
- jq (JSON parsing)
- rofi (меню)

**Для модулей:**
- pamixer (volume scroll)
- PulseAudio/PipeWire (volume module)

**Опциональные (click handlers):**
- gsimplecal (календарь)
- pavucontrol (volume GUI)
- alacritty (терминал для nmtui)

### 2.7 Chezmoi интеграция

Все `.tmpl` файлы используют переменные:
- `{{ $t.bg }}`, `{{ $t.fg }}`, `{{ $t.accent }}` — цвета
- `{{ .layout.bar_height }}`, `{{ .layout.gaps_outer }}` — размеры
- `{{ .font.mono }}`, `{{ .font.icon_size }}` — шрифты

---

## Часть 3: Архитектура Ewwii-решения

### 3.1 Структура файлов

```
dotfiles/dot_config/ewwii/
├── ewwii.rhai.tmpl              # Главный конфиг (chezmoi template)
├── ewwii.scss.tmpl              # Стили (chezmoi template)
├── scripts/
│   ├── executable_workspaces.sh.tmpl    # Вывод JSON воркспейсов
│   ├── executable_add-workspace.sh      # Создание WS (rofi)
│   ├── executable_close-workspace.sh    # Удаление WS
│   ├── executable_change-icon.sh        # Смена иконки
│   ├── executable_workspace-menu.sh     # Контекстное меню
│   ├── executable_getvol.sh             # Получение громкости
│   └── executable_getnetwork.sh         # Получение IP
└── workspace-icons.conf         # Хранилище иконок WS 4-10
```

### 3.2 Маппинг Polybar → Ewwii

| Polybar | Ewwii эквивалент |
|---------|------------------|
| `[bar/name]` | `defwindow("name", ...)` |
| `modules-left` | `box({ halign: "start" }, [...])` |
| `modules-center` | `box({ halign: "center" }, [...])` |
| `modules-right` | `box({ halign: "end" }, [...])` |
| `internal/date` | `poll("time", { interval: "1s", cmd: "date ..." })` |
| `internal/pulseaudio` | `listen("volume", { cmd: "pactl subscribe" })` + `poll()` |
| `internal/cpu` | `poll("cpu", { interval: "2s", cmd: "..." })` |
| `internal/memory` | `poll("memory", { interval: "3s", cmd: "..." })` |
| `internal/network` | `poll("network", { interval: "3s", cmd: "..." })` |
| `custom/script tail=true` | `listen("var", { cmd: "script" })` |
| `click-left` | `onclick: "command"` |
| `scroll-up/down` | `onscroll: "command {}"` |
| `format-foreground` | CSS: `.class { color: ... }` |
| `format-background` | CSS: `.class { background-color: ... }` |

### 3.3 Ключевое преимущество Ewwii для островов

```rhai
// Динамический размер по контенту — автоматически!
defwindow("workspaces", #{
    geometry: #{
        width: "auto",    // <-- КЛЮЧЕВОЕ ОТЛИЧИЕ
        height: "32px",
        anchor: "top left",
    },
    // ...
}, workspaces_widget())
```

**В Polybar** ширина задаётся статически или через env var (WS_BAR_WIDTH).
**В Ewwii** ширина `"auto"` растягивается по контенту автоматически.

---

## Часть 4: План миграции (пошаговый)

### Фаза 0: Подготовка

- [ ] **0.1** Установить ewwii на VM
  ```bash
  # Через Nix
  nix profile install github:Ewwii-sh/ewwii
  # Или сборка из исходников
  git clone https://github.com/Ewwii-sh/ewwii
  cd ewwii && cargo build --release
  ```

- [ ] **0.2** Проверить зависимости ewwii
  - GTK4 (libgtk-4)
  - layer-shell (для Wayland) или X11 протокол

- [ ] **0.3** Создать директорию конфигурации
  ```bash
  mkdir -p ~/.config/ewwii/scripts
  ```

### Фаза 1: Базовый скелет (MVP)

- [ ] **1.1** Создать `ewwii.rhai.tmpl` с минимальной структурой
  - Один бар (clock) для проверки работоспособности
  - Базовая геометрия и anchor

- [ ] **1.2** Создать `ewwii.scss.tmpl` с базовыми стилями
  - Цвета из chezmoi (dracula/monochrome)
  - Шрифт JetBrainsMono Nerd Font

- [ ] **1.3** Создать `launch.sh` для ewwii
  ```bash
  ewwii daemon &
  ewwii open workspaces
  ewwii open clock
  ewwii open system
  ```

- [ ] **1.4** Интегрировать в i3 config
  ```bash
  exec_always --no-startup-id ~/.config/ewwii/launch.sh
  ```

### Фаза 2: Статические модули

- [ ] **2.1** Clock/Date виджет
  ```rhai
  poll("time", #{
      interval: "1s",
      cmd: "date '+%a %b %d    %H:%M'",
      initial: ""
  })
  ```

- [ ] **2.2** CPU виджет
  ```rhai
  poll("cpu", #{
      interval: "2s",
      cmd: "top -bn1 | grep 'Cpu(s)' | awk '{print int($2)}'",
      initial: "0"
  })
  ```

- [ ] **2.3** Memory виджет
  ```rhai
  poll("memory", #{
      interval: "3s",
      cmd: "free | awk '/Mem:/ {printf \"%.0f\", $3/$2*100}'",
      initial: "0"
  })
  ```

- [ ] **2.4** Network виджет
  ```rhai
  poll("network", #{
      interval: "3s",
      cmd: "scripts/getnetwork.sh",
      initial: "disconnected"
  })
  ```

- [ ] **2.5** Volume виджет
  ```rhai
  poll("volume", #{
      interval: "0.5s",  // или listen с pactl subscribe
      cmd: "pamixer --get-volume",
      initial: "0"
  })
  ```

### Фаза 3: Динамические воркспейсы

- [ ] **3.1** Портировать `workspaces.sh.tmpl` → `workspaces.sh`
  - Вывод JSON структуры воркспейсов
  - Subscribe на i3 events

- [ ] **3.2** Создать виджет workspaces в Rhai
  ```rhai
  listen("workspaces_json", #{
      cmd: "scripts/workspaces.sh",
      initial: "[]"
  })

  fn workspaces_widget(ws_json) {
      let ws_list = parse_json(ws_json);
      let buttons = [];
      for ws in ws_list {
          buttons.push(workspace_button(ws));
      }
      return box(#{ class: "workspaces", orientation: "h" }, buttons);
  }
  ```

- [ ] **3.3** Реализовать состояния воркспейсов
  - CSS классы: `.ws-focused`, `.ws-occupied`, `.ws-empty`, `.ws-urgent`

- [ ] **3.4** Портировать кнопку "+"
  ```rhai
  button(#{
      class: "ws-add",
      onclick: "scripts/add-workspace.sh",
      label: "+"
  })
  ```

- [ ] **3.5** Портировать контекстное меню (right-click)
  - Через `onrightclick` в ewwii (если поддерживается)
  - Или через отдельный обработчик

### Фаза 4: Интерактивность

- [ ] **4.1** Click handlers для всех модулей
  ```rhai
  button(#{
      onclick: "gsimplecal",
      label: time
  })
  ```

- [ ] **4.2** Scroll handlers для volume
  ```rhai
  eventbox(#{
      onscroll: "pamixer -{} 5",  // {} заменяется на u/d
  }, [...])
  ```

- [ ] **4.3** Портировать rofi скрипты
  - `add-workspace.sh` — без изменений
  - `close-workspace.sh` — без изменений
  - `change-icon.sh` — без изменений
  - `workspace-menu.sh` — без изменений

### Фаза 5: Три острова (финальная геометрия)

- [ ] **5.1** Workspaces island (левый)
  ```rhai
  defwindow("workspaces", #{
      monitor: 0,
      windowtype: "dock",
      geometry: #{
          x: "{{ .layout.gaps_outer }}px",
          y: "{{ .layout.bar_offset_y }}px",
          width: "auto",  // КЛЮЧЕВОЕ: адаптивная ширина
          height: "{{ .layout.bar_height }}px",
          anchor: "top left",
      },
      exclusive: false,
  }, workspaces_bar())
  ```

- [ ] **5.2** Clock island (центр)
  ```rhai
  defwindow("clock", #{
      geometry: #{
          x: "50%",
          y: "{{ .layout.bar_offset_y }}px",
          width: "{{ .layout.bar_width_clock }}px",
          height: "{{ .layout.bar_height }}px",
          anchor: "top center",
      },
  }, clock_bar())
  ```

- [ ] **5.3** System island (правый)
  ```rhai
  defwindow("system", #{
      geometry: #{
          x: "-{{ .layout.gaps_outer }}px",
          y: "{{ .layout.bar_offset_y }}px",
          width: "{{ .layout.bar_width_system }}px",
          height: "{{ .layout.bar_height }}px",
          anchor: "top right",
      },
  }, system_bar())
  ```

### Фаза 6: Стилизация

- [ ] **6.1** Перенести все цвета в SCSS переменные
  ```scss
  $bg: {{ $t.bg }};
  $fg: {{ $t.fg }};
  $accent: {{ $t.accent }};
  // ...
  ```

- [ ] **6.2** Стили островов
  ```scss
  .bar {
      background-color: rgba($bg, 0.87);  // #dd prefix в polybar
      border: 1px solid rgba($accent, 0.4);
      border-radius: {{ .layout.bar_radius }}px;
      padding: {{ .layout.bar_padding }}px;
  }
  ```

- [ ] **6.3** Стили модулей (workspaces, volume slider, etc.)

- [ ] **6.4** Стили hover/active состояний

### Фаза 7: Multi-monitor

- [ ] **7.1** Детект мониторов
  ```bash
  # В launch.sh
  for m in $(xrandr --query | grep " connected" | cut -d" " -f1); do
      MONITOR=$m ewwii open workspaces
      MONITOR=$m ewwii open clock
      MONITOR=$m ewwii open system
  done
  ```

- [ ] **7.2** Передача monitor в defwindow
  ```rhai
  defwindow("workspaces", #{
      monitor: env("MONITOR") || 0,
      // ...
  }, ...)
  ```

### Фаза 8: Финализация

- [ ] **8.1** Удалить старую конфигурацию polybar
  ```bash
  rm -rf dotfiles/dot_config/polybar
  ```

- [ ] **8.2** Обновить i3 config — убрать exec polybar

- [ ] **8.3** Обновить chezmoi .chezmoiignore если нужно

- [ ] **8.4** Протестировать theme switching
  - chezmoi apply должен перегенерировать ewwii.rhai и ewwii.scss
  - ewwii reload должен применить новые стили

- [ ] **8.5** Документировать изменения в README

---

## Часть 5: Риски и митигация

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| **Ewwii нестабилен** (60 stars, активная разработка) | Средняя | Сохранить polybar конфиг как fallback |
| **Rhai синтаксис незнакомый** | Низкая | Примеры в репозитории ewwii |
| **GTK4 отсутствует на VM** | Низкая | Установить gtk4 пакет |
| **Hot reload ломается** | Средняя | Использовать `ewwii kill && ewwii daemon` |
| **Wayland-only фичи** | Низкая | Проект заявляет поддержку X11 |
| **Документация неполная** | Высокая | Ориентироваться на примеры и исходный код |

---

## Часть 6: Критерии успеха

### Must Have (обязательно)
- [ ] Три острова отображаются корректно
- [ ] Воркспейсы 1-10 работают (switch, create, delete)
- [ ] Динамическая ширина WS острова при добавлении/удалении
- [ ] Все click handlers работают
- [ ] Volume scroll работает
- [ ] Theme switching через chezmoi работает

### Should Have (желательно)
- [ ] Hot reload при изменении конфига
- [ ] Нет visible flicker при операциях с WS
- [ ] Multi-monitor поддержка

### Nice to Have (бонус)
- [ ] Анимации переходов (если ewwii поддерживает)
- [ ] Более гранулярный контроль hover состояний
- [ ] Уведомления при ошибках скриптов

---

## Часть 7: Оценка трудозатрат

| Фаза | Оценка | Комментарий |
|------|--------|-------------|
| 0. Подготовка | 1-2 часа | Установка, зависимости |
| 1. MVP | 2-3 часа | Один бар, базовые стили |
| 2. Статические модули | 2-3 часа | 5 модулей |
| 3. Динамические WS | 4-6 часов | Самая сложная часть |
| 4. Интерактивность | 2-3 часа | Click/scroll handlers |
| 5. Три острова | 2-3 часа | Геометрия, позиционирование |
| 6. Стилизация | 2-4 часа | CSS, состояния |
| 7. Multi-monitor | 1-2 часа | Если нужно |
| 8. Финализация | 1-2 часа | Cleanup, docs |

**Итого:** 17-28 часов (2-4 дня работы)

---

## Приложение A: Пример ewwii.rhai (скелет)

```rhai
// ============================================
// Ewwii Configuration — Migrated from Polybar
// ============================================

// --- Variables (polls and listeners) ---

poll("time", #{
    interval: "1s",
    cmd: "date '+%a %b %d    %H:%M'",
    initial: ""
});

poll("cpu", #{
    interval: "2s",
    cmd: "scripts/getcpu.sh",
    initial: "0"
});

poll("memory", #{
    interval: "3s",
    cmd: "scripts/getmem.sh",
    initial: "0"
});

poll("network", #{
    interval: "3s",
    cmd: "scripts/getnetwork.sh",
    initial: "disconnected"
});

poll("volume", #{
    interval: "0.5s",
    cmd: "pamixer --get-volume 2>/dev/null || echo 0",
    initial: "0"
});

listen("workspaces_json", #{
    cmd: "scripts/workspaces.sh",
    initial: "[]"
});

// --- Widget Functions ---

fn workspaces_bar() {
    return box(#{ class: "bar workspaces-bar", orientation: "h" }, [
        workspaces_widget(workspaces_json),
        workspace_add_button(),
    ]);
}

fn clock_bar() {
    return box(#{ class: "bar clock-bar" }, [
        button(#{
            class: "clock",
            onclick: "gsimplecal",
            label: " " + time,
        }),
    ]);
}

fn system_bar() {
    return box(#{ class: "bar system-bar", orientation: "h", space_evenly: false }, [
        network_widget(),
        volume_widget(),
        cpu_widget(),
        memory_widget(),
        controlcenter_button(),
        powermenu_button(),
    ]);
}

// --- Helper Widgets ---

fn workspaces_widget(ws_json) {
    // Parse JSON and create buttons dynamically
    // Implementation depends on ewwii JSON support
    return box(#{ class: "workspaces" }, [
        label(#{ text: "WS" }) // placeholder
    ]);
}

fn workspace_add_button() {
    return button(#{
        class: "ws-add",
        onclick: "~/.config/ewwii/scripts/add-workspace.sh",
        label: "+",
    });
}

fn network_widget() {
    return button(#{
        class: if network == "disconnected" { "network disconnected" } else { "network connected" },
        onclick: "alacritty -e nmtui",
        label: " " + network,
    });
}

fn volume_widget() {
    let icon = if volume == "muted" { "󰖁" } else { "" };
    return eventbox(#{
        onscroll: "pamixer -{} 5",
    }, [
        button(#{
            class: "volume",
            onclick: "pavucontrol",
            label: icon + " " + volume + "%",
        }),
    ]);
}

fn cpu_widget() {
    return label(#{ class: "cpu", text: " " + cpu + "%" });
}

fn memory_widget() {
    return label(#{ class: "memory", text: "󰍛 " + memory + "%" });
}

fn controlcenter_button() {
    return button(#{
        class: "controlcenter",
        onclick: "~/.config/rofi/scripts/controlcenter.sh",
        label: "",
    });
}

fn powermenu_button() {
    return button(#{
        class: "powermenu",
        onclick: "~/.config/rofi/scripts/powermenu.sh",
        label: "",
    });
}

// --- Window Definitions ---

enter([
    defwindow("workspaces", #{
        monitor: 0,
        windowtype: "dock",
        geometry: #{
            x: "8px",
            y: "6px",
            width: "auto",
            height: "32px",
            anchor: "top left",
        },
        exclusive: false,
    }, workspaces_bar()),

    defwindow("clock", #{
        monitor: 0,
        windowtype: "dock",
        geometry: #{
            x: "50%",
            y: "6px",
            width: "220px",
            height: "32px",
            anchor: "top center",
        },
        exclusive: false,
    }, clock_bar()),

    defwindow("system", #{
        monitor: 0,
        windowtype: "dock",
        geometry: #{
            x: "-8px",
            y: "6px",
            width: "440px",
            height: "32px",
            anchor: "top right",
        },
        exclusive: false,
    }, system_bar()),
]);
```

---

## Приложение B: Пример ewwii.scss (скелет)

```scss
// ============================================
// Ewwii Styles — Migrated from Polybar
// ============================================

// --- Theme Variables (chezmoi templates) ---
// {{ $t := index .themes .theme_name }}

$bg: {{ $t.bg }};
$fg: {{ $t.fg }};
$fg-dim: {{ $t.fg_dim }};
$accent: {{ $t.accent }};
$success: {{ $t.success }};
$warning: {{ $t.warning }};
$info: {{ $t.info }};
$urgent: {{ $t.urgent }};

$bar-height: {{ .layout.bar_height }}px;
$bar-radius: {{ .layout.bar_radius }}px;
$bar-padding: {{ .layout.bar_padding }}px;

// --- Reset ---
* {
    all: unset;
    font-family: "JetBrainsMono Nerd Font Mono";
    font-size: {{ .font.bar_size }}px;
}

// --- Bar Base ---
.bar {
    background-color: rgba($bg, 0.87);
    border: 1px solid rgba($accent, 0.4);
    border-radius: $bar-radius;
    padding: $bar-padding;
    color: $fg;
}

// --- Workspaces ---
.workspaces {
    button {
        padding: 0 8px;
        color: $fg-dim;

        &:hover {
            color: $accent;
        }

        &.focused {
            color: $accent;
            border-bottom: 2px solid $accent;
        }

        &.occupied {
            color: $fg;
        }

        &.urgent {
            color: $urgent;
        }
    }
}

.ws-add {
    color: $accent;
    padding: 0 8px;

    &:hover {
        color: lighten($accent, 10%);
    }
}

// --- Clock ---
.clock {
    color: $fg;
}

// --- Network ---
.network {
    &.connected {
        color: $success;
    }

    &.disconnected {
        color: $urgent;
    }
}

// --- Volume ---
.volume {
    color: $fg;
}

// --- System Monitors ---
.cpu {
    color: $info;
}

.memory {
    color: $warning;
}

// --- Control Buttons ---
.controlcenter {
    color: $accent;

    &:hover {
        color: lighten($accent, 10%);
    }
}

.powermenu {
    color: $urgent;

    &:hover {
        color: lighten($urgent, 10%);
    }
}
```

---

**Документ создан:** 2026-02-05
**Автор:** Claude (миграция с Polybar на Ewwii)
