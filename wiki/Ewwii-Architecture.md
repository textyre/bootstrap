# Ewwii — Архитектура и требования

## Обзор

**Ewwii** (ElKowar's Wacky Widgets Improved Interface) — status bar на базе GTK4, заменяющий Polybar. Конфигурация пишется на Rhai (императивный язык, синтаксис близок к Rust), стилизация через GTK CSS/SCSS.

| Характеристика | eww | ewwii |
|----------------|-----|-------|
| Язык конфигурации | Yuck (Lisp) | **Rhai** (Rust-like) |
| GTK версия | GTK3 | **GTK4** |
| Hot reload | Частичный | Полный |
| Расширяемость | Ограниченная | Плагины + Rhai модули |

### Ключевое преимущество — автоматическая ширина

```rhai
defwindow("bar", #{
    geometry: #{
        width: "auto",  // Автоматический размер по контенту
        height: "32px",
    },
}, bar_widget())
```

В Polybar ширина задавалась статически через env var и пересчитывалась скриптом при каждом изменении числа воркспейсов. В ewwii ширина определяется автоматически по контенту виджетов.

---

## Архитектура: три плавающих острова

```
[ЛЕВЫЙ]              [ЦЕНТР]          [ПРАВЫЙ]
Workspaces           Clock/Date       System Info
```

Реализован как **single transparent dock window** с тремя island-контейнерами внутри. Каждый остров — визуально независимая капсула со своим фоном, рамкой и скруглением.

### Принципы layout

- Override-redirect, прозрачный фон окна
- Border radius 48px (полное скругление капсул)
- Three-section layout: bar-left (без hexpand), bar-center/bar-right (hexpand: true, halign: fill)
- Острова внутри секций с halign center/end соответственно
- Chezmoi templating для тем, layout-параметров и шрифтов

### Темы

Поддерживаются две цветовые схемы, переключаемые через chezmoi:

- **Dracula (Catppuccin Mocha)** — тёмно-фиолетовая палитра с цветными акцентами
- **Monochrome** — чёрно-белая палитра, единственный цветной элемент — urgent (тёмно-красный)

Тема применяется ко всем компонентам: ewwii bar, rofi-меню, рамки островов.

---

## Модули

### Системный мониторинг

| Модуль | Что показывает | Обновление | Интерактивность |
|--------|---------------|------------|-----------------|
| network | IP-адрес или статус disconnected | Поллинг 3s | Клик -> сетевые настройки |
| volume | Громкость в % или muted | Поллинг 0.5s | Скролл +/-5%, клик -> микшер |
| cpu | Загрузка CPU в % | Поллинг 2s | — |
| memory | Использование RAM в % | Поллинг 3s (`/proc/meminfo`) | — |
| date | День, дата, время | Поллинг 1s | Клик -> календарь |

### Управление

| Модуль | Назначение | Интерактивность |
|--------|-----------|-----------------|
| controlcenter | Иконка настроек | Клик -> rofi-скрипт центра управления |
| powermenu | Иконка питания | Клик -> rofi-скрипт выключения/перезагрузки |
| tray | Системный трей | Зарезервирован |

### Вспомогательные

| Модуль | Назначение |
|--------|-----------|
| workspaces | Отображение WS 1-10 (listen mode, i3 IPC через JSON) |

---

## Динамические воркспейсы

- WS 1-3 фиксированные (видны всегда, даже пустые)
- WS 4-10 создаются по требованию и появляются динамически
- Иконки через rofi-меню
- Контекстное меню для изменения/удаления WS 4+

Визуальные состояния воркспейсов:
- **Focused** — акцентный цвет
- **Occupied** — основной цвет текста
- **Empty** — приглушённый цвет
- **Urgent** — красный

Скрипт `workspaces.sh` подписан на i3 IPC и генерирует JSON с состоянием всех воркспейсов при каждом событии WM.

---

## Текущий статус реализации

### Реализовано

- Три острова отображаются (single dock window)
- Workspaces 1-10 работают (i3 IPC + JSON)
- Динамическая ширина WS острова (автоматическая по контенту)
- Click handlers на всех модулях + volume scroll
- Theme switching через chezmoi (dracula/monochrome)
- Hot reload конфига
- External SCSS (community standard, файл `ewwii.scss`)
- `GSK_RENDERER=cairo` для экономии RAM (~200MB -> нормальное потребление)
- `label(markup:)` с Pango для разных размеров иконок и текста
- Hover/active/transition эффекты через внешний SCSS
- Иконки через Nerd Font codepoints в fonts.toml (TOML `\uXXXX` escape)

### В работе / Планируется

- Multi-monitor поддержка (детект через xrandr, передача monitor в defwindow)
- Анимации переходов
- Гранулярный hover контроль

---

## Файловая структура

```
dotfiles/dot_config/ewwii/
├── ewwii.rhai.tmpl          # Виджеты, layout (без inline стилей)
├── ewwii.scss.tmpl          # Все CSS-стили
├── executable_launch.sh     # Запуск daemon + open bar
└── scripts/
    └── executable_workspaces.sh.tmpl  # JSON генератор для i3 WS
```

Chezmoi data файлы (`dotfiles/.chezmoidata/`):

| Файл | Содержимое |
|------|-----------|
| layout.toml | Размеры баров, отступы, радиусы, gaps (~16 параметров) |
| fonts.toml | Семейство шрифтов, размеры, Nerd Font codepoints |
| themes.toml | Цветовые палитры (22 цвета на тему), island_bg/island_border |

При `chezmoi apply` шаблоны рендерят итоговые конфиги с подставленными цветами, размерами и шрифтами. Тема выбирается в `chezmoi.toml` по имени.

---

## Ключевые правила

1. **CSS файл ДОЛЖЕН называться `ewwii.scss`, НЕ `eww.scss`.** Ewwii ищет файл с именем, совпадающим с именем бинарника. Все community-конфиги используют внешний SCSS — это стандартный подход.

2. **`space_evenly: false` обязателен на каждом box.** Без этого GTK распределяет пространство равномерно между детьми, вызывая лишние отступы.

3. **Leaf widgets (button, label) определяют ширину по контенту; container widgets (box, eventbox) расширяются до allocation.** Для компактных элементов использовать button или label, а не box-обёртки.

4. **`GSK_RENDERER=cairo`** — снижает RAM с ~200MB до нормы (отключает GPU-ускорение GTK4).

5. **`label(markup:)` с Pango** — для разных размеров иконок и текста в одном label. Атрибуты `<span>`: `size` (pt), `color`, `weight`, `font_family`.

6. **CSS `alpha()` не поддерживается** — использовать pre-computed `rgba()` значения (хранятся в themes.toml).

---

## Зависимости

**Обязательные:** ewwii, GTK4, i3 WM, jq, rofi, pamixer, Nerd Font, UTF-8 локаль

**Опциональные:** gsimplecal (календарь), pavucontrol (микшер), alacritty (терминал для nmtui)

---

Назад к [[Home]] | См. также: [[Ewwii-Reference]], [[Rhai-Reference]], [[GTK-CSS-Reference]]
