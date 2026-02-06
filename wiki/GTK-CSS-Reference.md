# GTK CSS: Справочник

**Источники:**
- [GTK4 CSS Overview](https://docs.gtk.org/gtk4/css-overview.html)
- [GTK4 CSS Properties](https://docs.gtk.org/gtk4/css-properties.html)
- [GTK3 CSS Overview](https://docs.gtk.org/gtk3/css-overview.html)
- [GTK3 CSS Properties](https://docs.gtk.org/gtk3/css-properties.html)
- [Eww: Working with GTK](https://elkowar.github.io/eww/working_with_gtk.html)

**Контекст:** Ewwii использует GTK для рендеринга виджетов. Стилизация через подмножество CSS, специфичное для GTK.

---

## GTK CSS vs Web CSS

### Что ЕСТЬ

- Селекторы (элемент, класс, id, pseudo-classes, комбинаторы)
- Box model (margin, padding, border)
- Цвета (rgb, rgba, hex, named, currentColor, transparent)
- Фоны (color, image, gradient, size, position, repeat)
- Шрифты (family, size, weight, style, stretch)
- Тени (box-shadow, text-shadow)
- Скругления (border-radius)
- Переходы (transition)
- Анимации (@keyframes)
- Outline
- Opacity, filter
- Transform (2D/3D)
- Единицы: px, pt, em, ex, rem, %, in, cm, mm

### Чего НЕТ

- **Нет** flexbox, grid
- **Нет** float, position (absolute/relative/fixed)
- **Нет** width/height в CSS (используйте свойства виджетов)
- **Нет** display, overflow
- **Нет** z-index
- **Нет** attribute selectors (`[attr=value]`)
- **Нет** `::before`, `::after` псевдоэлементов

### Альтернативы

| Web CSS | GTK альтернатива |
|---------|-----------------|
| `display: flex` | `box(orientation:)` + `spacing` |
| `justify-content` | `halign`, `valign`, `space_evenly` |
| `flex-grow` | `hexpand`, `vexpand` |
| `width`, `height` | `min-width`, `min-height` в CSS или `width`, `height` как свойства виджета |
| `position: absolute` | `overlay` виджет |
| `gap` | `spacing` свойство виджета или `border-spacing` в CSS |

---

## Селекторы

### Базовые

| Селектор | Описание |
|----------|----------|
| `*` | Все узлы |
| `element` | По имени CSS-узла (напр. `button`, `label`, `box`) |
| `.class` | По классу (назначается через `class` свойство виджета) |
| `#id` | По widget_name |

### Комбинаторы

| Синтаксис | Описание |
|-----------|----------|
| `A B` | B потомок A (любой глубины) |
| `A > B` | B прямой ребёнок A |
| `A ~ B` | B следующий sibling после A |
| `A + B` | B непосредственно за A |

### Pseudo-классы

| Pseudo-класс | Описание |
|-------------|----------|
| `:hover` | Курсор над элементом |
| `:active` | Элемент нажат |
| `:focus` | Элемент в фокусе |
| `:focus-within` | Фокус внутри (GTK: на всех предках) |
| `:focus-visible` | Фокус видим (GTK: на элементе + предках) |
| `:disabled` | Неактивный |
| `:checked` | Отмечен (чекбокс, тоггл) |
| `:selected` | Выбран |
| `:indeterminate` | Неопределённое состояние |
| `:backdrop` | Окно неактивно |
| `:first-child` | Первый ребёнок |
| `:last-child` | Последний ребёнок |
| `:nth-child(n)` | n-й ребёнок |
| `:only-child` | Единственный ребёнок |
| `:not(sel)` | Отрицание |
| `:dir(ltr)` / `:dir(rtl)` | Направление текста |
| `:drop(active)` | Цель drag-and-drop |

### Специфичность

Работает как в CSS3: inline > id > class > element. Более конкретные селекторы побеждают.

---

## Свойства

### Цвет и прозрачность

| Свойство | Значения |
|----------|---------|
| `color` | Цвет текста и иконок |
| `opacity` | 0-1 |
| `filter` | `blur()`, `brightness()`, `contrast()`, `saturate()` и др. |

### Шрифты

| Свойство | Значения |
|----------|---------|
| `font-family` | `"Name"`, `serif`, `sans-serif`, `monospace` |
| `font-size` | px, pt, em, %, `smaller`/`larger`, `xx-small`..`xx-large` |
| `font-weight` | `normal`, `bold`, `100`-`900` |
| `font-style` | `normal`, `italic`, `oblique` |
| `font-stretch` | `condensed`..`expanded` |
| `font-variant` | `normal`, `small-caps` |
| `font-kerning` | `auto`, `normal`, `none` |
| `letter-spacing` | Length |
| `line-height` | Length, число, % (GTK4 >= 4.6) |
| `font` | Shorthand |

### Текст

| Свойство | Значения |
|----------|---------|
| `text-decoration-line` | `none`, `underline`, `overline`, `line-through` |
| `text-decoration-color` | Цвет |
| `text-decoration-style` | `solid`, `double`, `wavy` |
| `text-decoration` | Shorthand |
| `text-shadow` | `h-offset v-offset blur color` |
| `text-transform` | `capitalize`, `uppercase`, `lowercase`, `none` (GTK4) |
| `caret-color` | Цвет курсора ввода |

### Box Model

```
┌─── margin ───────────────────────────┐
│ ┌─── border ───────────────────────┐ │
│ │ ┌─── padding ─────────────────┐  │ │
│ │ │                             │  │ │
│ │ │         content             │  │ │
│ │ │                             │  │ │
│ │ └─────────────────────────────┘  │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

| Свойство | Значения | Shorthand |
|----------|---------|-----------|
| `margin-top/right/bottom/left` | Length | `margin` (1-4 значения) |
| `padding-top/right/bottom/left` | Length | `padding` (1-4 значения) |
| `min-width`, `min-height` | Length | — |

Shorthand: 4 значения = top right bottom left, 2 = vertical horizontal, 1 = all.

### Границы (Border)

| Свойство | Значения |
|----------|---------|
| `border-width` | Length (1-4 значения) |
| `border-style` | `solid`, `dashed`, `dotted`, `double`, `groove`, `ridge`, `inset`, `outset` |
| `border-color` | Цвет (1-4 значения) |
| `border-radius` | Length (1-4 значения) |
| `border` | Shorthand: `width style color` |
| `border-spacing` | Length — **зазор в GtkBox, GtkGrid, GtkCenterBox** (GTK4) |

> `border-spacing` в GTK4 — аналог `spacing` свойства виджета, но через CSS. Устанавливает расстояние между дочерними элементами GtkBox/GtkGrid/GtkCenterLayout.

### Border Image

| Свойство | Описание |
|----------|----------|
| `border-image-source` | Изображение для границы |
| `border-image-repeat` | `repeat`, `stretch`, `round` |
| `border-image-slice` | Разделение на 9 частей |
| `border-image-width` | Ширина областей |
| `border-image` | Shorthand |

### Outline

| Свойство | Значения |
|----------|---------|
| `outline-style` | Как border-style (`auto` не поддерживается) |
| `outline-width` | Length |
| `outline-color` | Цвет (`invert` не поддерживается) |
| `outline-offset` | Length |
| `outline` | Shorthand |

### Фон (Background)

| Свойство | Значения |
|----------|---------|
| `background-color` | Цвет |
| `background-image` | `url()`, `linear-gradient()`, `radial-gradient()`, `none` |
| `background-size` | Length, `cover`, `contain` |
| `background-position` | Координаты |
| `background-repeat` | `repeat`, `no-repeat`, `repeat-x`, `repeat-y` |
| `background-origin` | `padding-box`, `border-box`, `content-box` |
| `background-clip` | `padding-box`, `border-box`, `content-box` |
| `background` | Shorthand |
| `box-shadow` | `h v blur spread color` (множественные через запятую) |

### Трансформации

| Свойство | Значения |
|----------|---------|
| `transform` | `rotate()`, `scale()`, `translate()`, `skew()`, `matrix()` и 3D-варианты |
| `transform-origin` | Координаты |

### Переходы (Transition)

| Свойство | Значения |
|----------|---------|
| `transition-property` | Имена свойств, `all`, `none` |
| `transition-duration` | Время (`200ms`, `0.5s`) |
| `transition-timing-function` | `ease`, `linear`, `ease-in`, `ease-out`, `cubic-bezier()`, `steps()` |
| `transition-delay` | Время |
| `transition` | Shorthand |

### Анимации

| Свойство | Значения |
|----------|---------|
| `animation-name` | Имя из `@keyframes` |
| `animation-duration` | Время |
| `animation-timing-function` | Как transition |
| `animation-iteration-count` | Число, `infinite` |
| `animation-direction` | `normal`, `reverse`, `alternate`, `alternate-reverse` |
| `animation-play-state` | `running`, `paused` |
| `animation-delay` | Время |
| `animation-fill-mode` | `none`, `forwards`, `backwards`, `both` |
| `animation` | Shorthand |

```css
@keyframes fade-in {
    from { opacity: 0; }
    to   { opacity: 1; }
}
.widget { animation: fade-in 300ms ease-in; }
```

---

## GTK-специфичные свойства

### Иконки

| Свойство | Описание |
|----------|----------|
| `-gtk-icon-source` | `builtin`, URL, `none` |
| `-gtk-icon-size` | Размер иконки |
| `-gtk-icon-style` | `requested`, `regular`, `symbolic` |
| `-gtk-icon-transform` | Трансформация иконки |
| `-gtk-icon-palette` | Палитра для перекраски symbolic-иконок |
| `-gtk-icon-shadow` | Тень иконки |
| `-gtk-icon-filter` | Фильтр иконки (GTK4) |

### Другое

| Свойство | Описание |
|----------|----------|
| `-gtk-dpi` | DPI для конвертации единиц |
| `-gtk-secondary-caret-color` | Курсор для двунаправленного текста |
| `-gtk-key-bindings` | Горячие клавиши (через `@binding-set`) |

---

## Цвета в GTK

### Форматы

```css
color: red;                         /* именованный */
color: #ff0000;                     /* hex */
color: #f00;                        /* hex сокращённый */
color: rgb(255, 0, 0);              /* rgb */
color: rgba(255, 0, 0, 0.5);       /* rgba с прозрачностью */
color: currentColor;                /* текущий color */
color: transparent;                 /* полностью прозрачный */
```

### GTK-специфичные расширения (GTK3)

```css
@define-color accent_color #e07a5f;  /* определить символический цвет */
color: @accent_color;                /* использовать */

color: lighter(@bg);                 /* осветлить */
color: darker(@bg);                  /* затемнить */
color: shade(@bg, 1.3);             /* shade (>1 светлее, <1 темнее) */
color: alpha(@fg, 0.5);             /* установить прозрачность */
color: mix(@fg, @bg, 0.3);          /* смешать */
```

> **Внимание:** `alpha()` в GTK CSS — расширение GTK, может не поддерживаться в ewwii. Используйте `rgba()` с пре-вычисленными значениями.

---

## Глобальные ключевые слова

Все свойства поддерживают:

| Ключевое слово | Описание |
|----------------|----------|
| `inherit` | Наследовать от родителя |
| `initial` | Сбросить на значение по умолчанию |
| `unset` | `inherit` для наследуемых, `initial` для остальных |

---

## Media Queries (GTK4 >= 4.20)

```css
@media (prefers-color-scheme: dark) { ... }
@media (prefers-contrast: more) { ... }
@media (prefers-reduced-motion: reduce) { ... }
```

---

## Отладка

### GTK Inspector

```bash
ewwii inspector      # или eww inspector для eww
```

Позволяет:
- Выбрать элемент и увидеть применённые стили
- Посмотреть CSS-узлы (дерево виджетов)
- Диагностировать почему стили не применяются
- Интерактивно менять свойства

### GTK_DEBUG

```bash
GTK_DEBUG=interactive ewwii
```

---

## Частые проблемы

### 1. Стили не применяются

- Проверьте специфичность — inline `style` побеждает CSS-классы
- Используйте `ewwii inspector` для просмотра CSS-узлов
- Убедитесь что селектор соответствует имени CSS-узла, а не виджета

### 2. Размеры не работают

- GTK не поддерживает `width`/`height` в CSS
- Используйте `min-width`/`min-height` или свойства виджета

### 3. Лишнее пространство

- `GtkBox` по умолчанию может распределять пространство равномерно (`space_evenly`)
- `hexpand`/`vexpand` "заразны" — ребёнок с `hexpand: true` заставляет родителя расширяться
- `GtkButton` имеет внутренний padding по дефолту — используйте `padding: 0` в CSS
- `border-spacing` / `spacing` добавляют зазоры между ВСЕМИ детьми

### 4. Выравнивание

- `halign`/`valign` работают **внутри выделенного пространства**, а не абсолютно
- Если контейнер шире нужного — `halign: center` центрирует в лишнем пространстве, а не уменьшает контейнер

---

## Полезные ссылки

- [GTK4 CSS Overview](https://docs.gtk.org/gtk4/css-overview.html)
- [GTK4 CSS Properties](https://docs.gtk.org/gtk4/css-properties.html)
- [GTK3 CSS Overview](https://docs.gtk.org/gtk3/css-overview.html)
- [GTK3 CSS Properties](https://docs.gtk.org/gtk3/css-properties.html)
- [Eww: Working with GTK](https://elkowar.github.io/eww/working_with_gtk.html)
- [Pango Markup](https://docs.gtk.org/Pango/pango_markup.html)

---

Назад к [[Home]] | См. также: [[Ewwii-Reference]], [[Rhai-Reference]]
