# Ewwii: Справочник API

**Источник:** [Официальная документация](https://ewwii-sh.github.io/docs/intro)
**Последний релиз:** 0.3.1 (Nov 2024)
**Дата:** 2026-02-06

---

## Обзор

Ewwii (ElKowar's Wacky Widgets Improved Interface) — форк eww на Rust. Конфигурация пишется на **Rhai** (императивный скриптовый язык, синтаксис близок к Rust/C). Стилизация через **GTK CSS/SCSS**.

### История версий

| Версия | Дата | Ключевые изменения |
|--------|------|-------------------|
| 0.3.1 | Nov 2024 | Фикс circular_progress, localsignal |
| **0.3.0** | Nov 2024 | **Миграция на GTK4.** localsignal, localbind, flowbox, плагины, icon-виджет. **УДАЛЕНЫ:** centerbox, icon_name, same_size |
| 0.2.0 | Sep 2024 | std::regex, state-команда, engine-override |
| 0.1.0 | Sep 2024 | Первый релиз |

### Breaking changes в v0.3.0 (GTK4)

- **`centerbox`** — гайд говорит "removed", но API перечисляет и GTK4 имеет нативный `GtkCenterBox`. Статус неясен, нужен тест
- **CSS-классы окон** — только корневой дочерний элемент наследует класс с именем окна (раньше автоматически на всём дереве)
- **`icon_name` удалён из image** — используйте новый виджет `icon`
- **`icon_size` удалён** — задавайте размер через CSS
- **EventBox переписан** на GTK4 контроллерах
- **RAM ~200MB** из-за GPU-ускорения GTK4. Митигация: `GSK_RENDERER=cairo ewwii open foo`

### Файлы конфигурации

| Файл | Назначение |
|------|-----------|
| `~/.config/ewwii/ewwii.rhai` | Виджеты, переменные, окна |
| `~/.config/ewwii/ewwii.scss` или `ewwii.css` | CSS-стили (GTK CSS) |

---

## Структура конфигурации

Корневой элемент — `enter([...])`. Допускается **несколько** `enter()` блоков (переменные из первого доступны во втором). Внутри объявляются переменные и окна:

```rhai
enter([
    poll("time", #{ interval: "1s", cmd: "date '+%H:%M'", initial: "" }),
    listen("volume", #{ cmd: "pactl subscribe", initial: "" }),
    defwindow("bar", #{ ... }, bar_widget(time, volume)),
])
```

### defwindow

| Свойство | Тип | Описание |
|----------|-----|----------|
| `monitor` | int | Индекс монитора |
| `windowtype` | string | `"normal"`, `"dock"`, `"toolbar"`, `"dialog"`, `"desktop"` |
| `stacking` | string | X11: `"fg"`, `"bg"`. Wayland: + `"overlay"`, `"bottom"` |
| `wm_ignore` | bool | Игнорировать WM |
| `namespace` | string | Идентификатор окна для WM-правил (Wayland) |
| `geometry` | map | `x`, `y`, `width`, `height` (px/%), `anchor`, `resizable` |
| `reserve` | map | `side` ("top"/"bottom"/"left"/"right"), `distance` (px/%) |
| `exclusive` | bool | Исключительная зона (другие окна не перекрывают) |
| `force_normal` | bool | Создать обычное окно на Wayland (v0.2.0+) |

---

## Виджеты

### Контейнеры (принимают `children`)

| Виджет | Описание |
|--------|----------|
| `box` | Основной контейнер. Горизонтальный/вертикальный layout |
| `centerbox` | Трёхсекционный: start/center/end. Гайд по миграции говорит "removed in v0.3.0", но API ewwii перечисляет его, и GTK4 нативно содержит `GtkCenterBox` (нового в GTK4). **Статус: требует теста** |
| `eventbox` | Контейнер с обработкой событий (клики, hover, scroll, клавиши) |
| `tooltip` | Контейнер с тултипом |
| `revealer` | Показ/скрытие содержимого с анимацией |
| `scroll` | Прокручиваемый контейнер |
| `overlay` | Наложение виджетов друг на друга |
| `stack` | Переключение между дочерними виджетами |
| `expander` | Раскрываемая секция |
| `flowbox` | Автоматический перенос элементов |

### Листовые виджеты (без children)

| Виджет | Описание |
|--------|----------|
| `label` | Текст. Поддерживает Pango markup |
| `button` | Кнопка с текстом |
| `image` | Изображение из файла |
| `icon` | Иконка (с поддержкой SVG fill) |
| `input` | Поле ввода |
| `scale` | Ползунок (слайдер) |
| `progress` | Прогресс-бар |
| `circular_progress` | Круговой прогресс |
| `graph` | График |
| `calendar` | Календарь |
| `checkbox` | Чекбокс |
| `combo_box_text` | Выпадающий список |
| `color_button` | Кнопка выбора цвета |
| `color_chooser` | Виджет выбора цвета |
| `transform` | CSS-трансформации |

---

## Свойства виджетов

### Общие (все виджеты)

| Свойство | Тип | Описание |
|----------|-----|----------|
| `class` | string | CSS-класс |
| `style` | string | Inline SCSS |
| `css` | string | Блок SCSS-кода |
| `halign` | string | `"fill"`, `"baseline"`, `"center"`, `"start"`, `"end"` |
| `valign` | string | Аналогично halign |
| `hexpand` | bool | Растягиваться по горизонтали |
| `vexpand` | bool | Растягиваться по вертикали |
| `width` | int | Ширина в пикселях |
| `height` | int | Высота в пикселях |
| `visible` | bool | Видимость |
| `tooltip` | string | Текст тултипа |
| `active` | bool | Активность взаимодействия |
| `widget_name` | string | Идентификатор виджета |
| `can_target` | bool | Принимает ли pointer events |
| `focusable` | bool | Может ли получить фокус |

### box

| Свойство | Тип | Описание |
|----------|-----|----------|
| `spacing` | int | Зазор между дочерними элементами (px) |
| `orientation` | string | `"horizontal"` / `"vertical"` |
| `space_evenly` | bool | Равномерное распределение пространства |

### label

| Свойство | Тип | Описание |
|----------|-----|----------|
| `text` | string | Текстовое содержимое |
| `markup` | string | Pango markup (поддерживает `<span>`, `<b>`, `<i>`) |
| `truncate` | bool | Обрезать текст |
| `truncate_left` | bool | Обрезать слева |
| `limit_width` | int | Максимальная ширина в символах |
| `show_truncated` | bool | Показывать многоточие |
| `wrap` | bool | Перенос строк |
| `wrap_mode` | string | Режим переноса |
| `lines` | int | Количество строк |
| `xalign` | float | Горизонтальное выравнивание текста (0.0-1.0) |
| `yalign` | float | Вертикальное выравнивание текста (0.0-1.0) |
| `justify` | string | Выравнивание текста |
| `gravity` | string | Направление текста |
| `unindent` | bool | Убрать отступы |

### button

| Свойство | Тип | Описание |
|----------|-----|----------|
| `onclick` | string | Команда по клику |
| `onmiddleclick` | string | Команда по среднему клику |
| `onrightclick` | string | Команда по правому клику |
| `timeout` | duration | Таймаут между кликами (default: debounce) |

### eventbox

| Свойство | Тип | Описание |
|----------|-----|----------|
| `onclick` | string | Команда по клику |
| `onmiddleclick` | string | Команда по среднему клику |
| `onrightclick` | string | Команда по правому клику |
| `onscroll` | string | Команда при скролле |
| `onhover` | string | Команда при наведении |
| `onhoverlost` | string | Команда при уходе курсора |
| `onkeypress` | string | Команда при нажатии клавиши |
| `onkeyrelease` | string | Команда при отпускании клавиши |
| `cursor` | string | Курсор (напр. `"pointer"`) |
| `ondropped` | string | Команда при drop |
| `dragvalue` | string | Значение для drag |
| `dragtype` | string | Тип для drag |
| `spacing` | int | Зазор между дочерними элементами |
| `orientation` | string | `"horizontal"` / `"vertical"` |
| `space_evenly` | bool | Равномерное распределение |
| `timeout` | duration | Таймаут |

### revealer

| Свойство | Тип | Описание |
|----------|-----|----------|
| `reveal` | bool | Показать/скрыть |
| `transition` | string | Тип анимации |
| `duration` | duration | Длительность (default: "500ms") |

### scale

| Свойство | Тип | Описание |
|----------|-----|----------|
| `value` | float | Текущее значение |
| `min` | float | Минимум |
| `max` | float | Максимум |
| `onchange` | string | Команда при изменении |
| `orientation` | string | Горизонтальный/вертикальный |
| `flipped` | bool | Инвертировать направление |
| `draw_value` | bool | Показывать числовое значение |
| `round_digits` | int | Округление |
| `marks` | string | Отметки на шкале |
| `timeout` | duration | Таймаут |

### image / icon

| Свойство | Тип | Описание |
|----------|-----|----------|
| `path` | string | Путь к файлу |
| `image_width` | int | Ширина |
| `image_height` | int | Высота |
| `preserve_aspect_ratio` | bool | Сохранять пропорции |
| `fill_svg` | string | Цвет заливки SVG |
| `icon` | string | Имя иконки (только у `icon`) |

---

## Переменные

### poll — периодический опрос

```rhai
poll("name", #{ interval: "2s", cmd: "command", initial: "default" })
```

Запускает команду каждые N секунд. Доступна только внутри `enter([])`.

### listen — непрерывное прослушивание

```rhai
listen("name", #{ cmd: "command --follow", initial: "default" })
```

Запускает команду один раз, читает stdout построчно. Обновляется при каждой новой строке. **Предпочтительнее poll** — эффективнее по ресурсам.

### localsignal — локальная реактивная привязка

Биндится к свойствам виджета напрямую. Типы: `"poll"` или `"listen"`. Не требует `enter()`. Локальный, иммутабельный.

### Передача переменных

Переменные из `enter([])` нужно **явно передавать** в функции как параметры. Они не являются глобальными.

---

## Выражения (Rhai)

### Строковая интерполяция

Только через **backtick-строки**:

```rhai
let name = "world";
let greeting = `Hello, ${name}!`;   // работает
let broken = "Hello, ${name}!";     // НЕ работает — литеральная строка
```

### Операторы

| Тип | Операторы |
|-----|----------|
| Арифметика | `+`, `-`, `*`, `/`, `%` |
| Сравнение | `==`, `!=`, `<`, `<=`, `>`, `>=` |
| Логика | `&&`, `\|\|`, `!` |
| Regex | `=~` (match), `!~` (not match) |
| Optional | `?.`, `?.[index]` |

### Управление потоком

- `if/else`, тернарный `? :`
- `match` выражения
- `for item in array { ... }` — предпочтительный способ генерации списков виджетов

### Функции

```rhai
fn my_widget(param1, param2 = "default") {
    return box(#{ ... }, [ ... ]);
}
```

Поддерживаются параметры по умолчанию.

---

## Встроенные функции

### Математика

`abs`, `sign`, `sqrt`, `exp`, `ln`, `log`, `sin`, `cos`, `tan`, `ceil`, `floor`, `round`, `min`, `max`, `powi`, `powf`

### Строки

`len`, `contains`, `starts_with`, `ends_with`, `index_of`, `sub_string`, `split`, `trim`, `to_lower`, `to_upper`, `replace`, `remove`, `truncate`

### Массивы

`len`, `push`, `pop`, `shift`, `insert`, `remove`, `sort`, `filter`, `map`, `reduce`, `any`, `all`, `find`, `contains`, `reverse`

### Объекты (Map)

`keys`, `values`, `contains`, `get`, `set`, `remove`, `len`, `mixin`, `fill_with`

### Утилиты

| Функция | Описание |
|---------|----------|
| `formattime()` | Форматирование UNIX-timestamp |
| `formatbytes()` | Форматирование размера файлов |
| `get_env()` | Чтение env-переменной |
| `jq()` | jaq-совместимый JSON-фильтр |
| `to_string()` | Конвертация в строку |
| `to_int()` / `to_float()` | Числовые конвертации |
| `parse_json()` | Парсинг JSON-строки |
| `to_json()` | Сериализация Map в JSON |

---

## Модули

### Стандартная библиотека (stdlib)

| Модуль | Функции |
|--------|---------|
| `std::regex` | `find`, `find_all`, `is_match`, `replace` |
| `std::command` | `run(cmd)`, `run_and_read(cmd)` |
| `std::text` | `to_lower`, `to_upper`, `to_camel_case`, `to_slug`, `truncate_chars` |
| `std::env` | `get_env`, `set_env`, `get_current_dir`, `get_home_dir`, `get_username` |

### API-библиотека

| Модуль | Функции |
|--------|---------|
| `api::linux` | `get_cpu_info`, `get_ram_info`, `get_disk_info`, `get_gpu_info`, `get_battery_perc`, `get_kernel_version` |
| `api::wifi` | `scan`, `connect`, `disconnect`, `current_connection`, `enable_adapter`, `disable_adapter` |
| `api::slib` | `call_fn`, `list_fns` (вызов функций из shared library) |

### Пользовательские модули

```rhai
// mymodule.rhai
fn greet() { return "Hello"; }     // auto-exported
private fn internal() { ... }       // скрыта
let PI = 3.14159; export PI;        // переменные — explicit export

// main
import "mymodule" as m;
m::greet();  m::PI;
```

---

## Стилизация

### Инлайн-стили

Свойство `style` принимает SCSS-строку, применяется через GTK CSS:

```rhai
box(#{ style: "background-color: #1e1e1e; border-radius: 12px; padding: 4px;" }, [...])
```

### Pango Markup (в label)

Свойство `markup` у `label` рендерит Pango-разметку:

```rhai
label(#{ markup: "<span size='15pt' color='#a6e3a1'>icon</span> <span size='11pt'>text</span>" })
```

Поддерживаемые атрибуты `<span>`: `size` (pt), `color`/`foreground`, `weight` (bold), `style` (italic), `font_family`.

### GTK CSS vs Web CSS

**Не поддерживается:** flexbox, float, absolute positioning, width/height в CSS.
**Используйте вместо этого:** `halign`, `valign`, `hexpand`, `vexpand`, `spacing` как свойства виджетов.
**Поддерживается:** transitions, @keyframes анимации, box-shadow, border-radius, gradients.

Подробнее: [[GTK-CSS-Reference]]

### Внешние CSS-файлы

Файл `ewwii.scss` / `ewwii.css` загружается автоматически. Официальный пример ewwii-bar использует внешний SCSS.

> **Примечание:** В нашем проекте внешний CSS не работал при тестировании (причина не выяснена). Текущее решение: inline `style` на каждом виджете.

---

## UContainers

### localbind

Привязывается к GTK4-свойствам дочернего виджета. Каждое свойство `localbind` соответствует GTK-свойству child.

---

## Паттерны из реальных конфигов

Анализ конфигов [BinaryHarbinger/binarydots](https://github.com/BinaryHarbinger/binarydots/tree/main/config/ewwii), [Byson94/Oris](https://github.com/Byson94/Oris/tree/683a259ac0024b41bef9be57beebd8b6db7b33a6/src/share/oris/ewwii), [AxOS/Theom](https://github.com/AxOS-project/Theom/tree/8aef8d66c3a92392e6edb91d32d4ca4ce2f0d693/src/share/theom/config/ewwii).

### 1. `space_evenly: false` — всегда явно

Все community-конфиги ставят `space_evenly: false` на **каждом** `box`. Без этого GtkBox распределяет пространство равномерно между детьми, что вызывает лишние отступы.

### 2. Модульная организация

```rhai
import "widgets/top_bar" as _topbar;
import "style.rhai" as style_file;
import "std::command" as cmd;
```

Конфиги разбиваются на модули по функциональности. Импорт с `_` в начале имени — конвенция для side-effect импортов.

### 3. SCSS с `@use` для тем

```scss
@use "theme" as c;
.widget { background-color: c.$bg_main; color: c.$fg_main; }
```

SCSS-модули (`@use`) работают. Все цвета в отдельном файле `_theme.scss`.

### 4. `markup` подтверждён

```rhai
label(#{ markup: "<span font_size=\"large\">Activate Linux</span>" })
```

`label(markup:)` реально используется в production-конфигах. Атрибут `font_size` (синоним `size`) принимает: `xx-small`, `x-small`, `small`, `medium`, `large`, `x-large`, `xx-large`, или числовое значение.

### 5. `scale` с placeholder `{}`

```rhai
scale(#{ onchange: "pamixer --set-volume {}", min: 0, max: 101, value: volume })
```

`{}` в `onchange` заменяется на текущее значение ползунка.

### 6. background-image через inline style

```rhai
box(#{ style: `background-image: url("${path}"); background-size: cover;` }, [...])
```

Динамические фоновые изображения через `style` + backtick-интерполяцию.

### 7. Глобальная CSS-анимация

```scss
* { transition: all 0.2s cubic-bezier(0.165, 0.84, 0.44, 1); }
```

Плавные переходы на все свойства через глобальный селектор.

### 8. Множественные `enter()` блоки

```rhai
enter([  poll(...), listen(...) ]);
enter([  defwindow("bar", ...), defwindow("calendar", ...) ]);
```

Переменные из первого `enter()` доступны во втором. Удобно для разделения переменных и окон.

---

## Советы по производительности

- **`GSK_RENDERER=cairo`** — снижает потребление RAM с ~200MB до нормы (отключает GPU-ускорение)
- **`listen` > `poll`** — listen обновляется мгновенно без лишних вызовов
- **`api::linux`** — встроенные функции (CPU/RAM/disk) без спавна процессов
- **Не ставить `import` внутри циклов** — перезагрузка модуля на каждой итерации

---

## Полезные ссылки

- [Введение](https://ewwii-sh.github.io/docs/intro)
- [Знакомство](https://ewwii-sh.github.io/docs/getting_familiar)
- [Конфигурация](https://ewwii-sh.github.io/docs/config_and_syntax/configuration)
- [Основы конфигурации](https://ewwii-sh.github.io/docs/config_and_syntax/config_fundamentals)
- [Рендеринг и best practices](https://ewwii-sh.github.io/docs/config_and_syntax/rendering_and_best_practices)
- [Язык выражений](https://ewwii-sh.github.io/docs/config_and_syntax/expression_language)
- [Переменные](https://ewwii-sh.github.io/docs/config_and_syntax/variables)
- [Виджеты и параметры](https://ewwii-sh.github.io/docs/widgets/widgets_and_params)
- [Свойства виджетов](https://ewwii-sh.github.io/docs/widgets/props)
- [Стилизация](https://ewwii-sh.github.io/docs/theming_and_ui/styling_widgets)
- [Stdlib](https://ewwii-sh.github.io/docs/modules/stdlib)
- [API-библиотека](https://ewwii-sh.github.io/docs/modules/apilib)
- [Глобальные функции](https://ewwii-sh.github.io/docs/modules/global)
- [Пользовательские модули](https://ewwii-sh.github.io/docs/modules/user_defined)
- [Пример: Starter Bar](https://ewwii-sh.github.io/docs/examples/starter_bar)
- [GitHub: ewwii-bar](https://github.com/Ewwii-sh/ewwii/tree/main/examples/ewwii-bar)
- [GitHub: eii-manifests](https://github.com/Ewwii-sh/eii-manifests)
- [GTK4 Migration Guide](https://ewwii-sh.github.io/articles/en/guide_to_gtk4/)

### Сообщество

- [BinaryHarbinger/binarydots](https://github.com/BinaryHarbinger/binarydots/tree/main/config/ewwii) — полный конфиг с музыкальным плеером, OSD, календарём
- [Byson94/Oris](https://github.com/Byson94/Oris/tree/683a259ac0024b41bef9be57beebd8b6db7b33a6/src/share/oris/ewwii) — десктоп-окружение на ewwii
- [AxOS/Theom](https://github.com/AxOS-project/Theom/tree/8aef8d66c3a92392e6edb91d32d4ca4ce2f0d693/src/share/theom/config/ewwii) — конфиг дистрибутива AxOS
- [GitHub: поиск ewwii.scss](https://github.com/search?q=ewwii.scss&type=code) — примеры SCSS
- [r/unixporn: ewwii](https://www.reddit.com/r/unixporn/search/?q=ewwii) — скриншоты и конфиги

---

Назад к [[Home]] | См. также: [[Ewwii-Migration]], [[Rhai-Reference]], [[GTK-CSS-Reference]]
