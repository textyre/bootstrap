# Troubleshooting History — 2026-02-07 — Picom Animations, Rules, GTK Menu Styling

VM: Arch Linux (VirtualBox, NAT 127.0.0.1:2222), user: textyre
Picom: v12.5 (upstream, pacman), backend: glx

## Решено

### Picom: Изоляция проблем с анимациями через A/B тестирование

- [x] **Систематическая изоляция конфигурации** — Пользователь обнаружил что open-анимация не работает. Провели серию A/B тестов, последовательно включая/выключая секции конфига:

  **Хронология экспериментов (продолжение из предыдущей сессии):**

  | # | Конфигурация | Результат |
  |---|-------------|-----------|
  | 1 | Все эффекты + rules + animations 0.2s | Open не работает, close работает |
  | 2 | Duration увеличен до 1.0s | Open всё равно не работает |
  | 3 | Пресет `fly-in` вместо `appear` | Не помогло |
  | 4 | Убран `!focused` opacity rule | Open **заработал** на dock (ewwii bar) |
  | 5 | Per-window animations (только `window_type = 'normal'`, 5s) | Анимируется только тень, не окно |
  | 6 | Custom opacity animation `{ curve: linear, duration: 5.0 }` | Синтаксис парсится, визуально не заметно в VM |
  | 7 | Возврат к simple config (appear/disappear 0.2s) | Стабильный baseline |
  | 8 | Только animations, всё остальное закомментировано | Animations работают |
  | 9 | Backend `xrender` вместо `glx` | Animations "долгие" (xrender медленнее) |
  | 10 | Backend `glx`, duration 0.2s | Нормальная скорость |
  | 11 | Добавлены rules + corner-radius | Работает |
  | 12 | **Rules закомментированы**, shadows/blur/corners активны | Animations работают, open видно |
  | 13 | **Rules раскомментированы** + opacity fix | Финальная конфигурация |

  **Root cause анимаций (из предыдущей сессии):**
  - **BUG [#1393](https://github.com/yshui/picom/issues/1393)**: `!focused` opacity rule подавляет `open/show` анимацию на окнах получающих фокус
  - **VM software rendering**: `appear`/`disappear` пресеты анимируют ТОЛЬКО тень, не само окно (scale-based эффекты не работают в VMware SVGA3D / VirtualBox)
  - **Custom opacity animation**: синтаксис `opacity = { curve = "linear"; duration = 5.0; start = 0; end = 1; }` парсится без ошибок, но визуально не даёт эффекта в VM

  **Финальное решение:** Оставили animations (appear/disappear 0.2s) + rules с `!focused` opacity. Приняли что open-анимация не работает в VM из-за комбинации бага #1393 и software rendering. Close/disappear работает. Dock appear работает (dock не матчится `!focused`).

### Picom: Backend xrender vs glx

- [x] **xrender заметно медленнее для анимаций** — При переключении на `xrender` анимации визуально "долгие" при тех же 0.3s duration. Вернули `glx`. **Вывод:** для анимаций всегда использовать `glx` backend.

### Picom: Opacity leak на dock/desktop/GTK через default rule

- [x] **Default rule без match применял opacity ко всем окнам** — Первое правило в `rules:` `{ opacity = 0.92; }` не имело `match` условия, поэтому применялось ко ВСЕМ окнам, включая dock (ewwii bar), desktop, GTK CSD-тени (`_GTK_FRAME_EXTENTS@`). Правила для dock/desktop задавали `shadow = false`, `blur-background = false`, но НЕ переопределяли opacity. **Fix:** добавлен `opacity = 1;` к правилам dock, desktop, Polybar, DnD, `_GTK_FRAME_EXTENTS@`.

### Picom: Thunar context menu получал opacity от popup_menu rule

- [x] **Порядок rules имеет значение — поздние перезаписывают ранние** — Правило Thunar (строка 76) задавало `opacity = 1`, но правило `popup_menu` (строка 117) шло позже и перезаписывало на `opacity = 0.95`. Контекстные меню Thunar — это X11 окна с `window_type = popup_menu` И `class_g = Thunar`. **Fix:** перенесли правило Thunar в конец `rules:` (после popup_menu), чтобы его `opacity = 1` имел приоритет.

### GTK3: Rounded corners для контекстных меню

- [x] **Полное решение через GTK CSS + picom синхронизацию** — Потребовалось 4 итерации чтобы найти правильный подход:
  1. ❌ Первая попытка: `window.csd { border-radius }` + `.popup { border-radius }` — неправильные селекторы для меню
  2. ❌ Вторая попытка: `menu { border-radius }` + `menuitem:first-child/:last-child` — скруглило фон, но чёрные углы остались (picom `corner-radius = 0`)
  3. ❌ Третья попытка: отключили picom corner-radius для popup_menu (чёрные углы ушли, но углы стали просто квадратные)
  4. ✅ Финальное решение (по рецепту adw-gtk3 issue #100):
     - GTK CSS: `.csd menu { border-radius: 10px }` + `.csd.popup decoration { border-radius: 10px; box-shadow: ... }` + `menuitem { border-radius: 6px; padding: 7px 6px }` + `menu { margin: 4px; padding: 6px }`
     - Picom: убрали `corner-radius = 0` для popup_menu, вернули глобальный corner-radius
     - Оба уровня (GTK drawing + compositor clipping) теперь синхронизированы на 10px

## Не решено

### Известные ограничения (не баги конфигурации)

- [ ] **Open-анимация не работает в VM** — Комбинация бага [#1393](https://github.com/yshui/picom/issues/1393) (opacity rule подавляет open) + software rendering (scale-анимации только на тени). Будет работать на bare metal с GPU. Не требует действий.
- [ ] **GTK3 menu не clip'ает контент по border-radius** — `menuitem` hover-подсветка может выступать за скруглённые углы `menu`. Частично решено скруглением самих `menuitem` (`border-radius: 6px`), но не идеально. Ограничение GTK3.

## Ошибки ассистента (самокритика)

### Неэффективная отладка анимаций

- [ ] **Слишком много итераций до понимания root cause** — Потребовалось ~6 деплоев прежде чем найти баг #1393. Правильный подход: сразу проверить picom issues по ключевым словам "open animation not working" или "!focused opacity animation". Ассистент сначала менял duration, пресеты, триггеры — всё мимо.

- [ ] **Не проверил picom logs с самого начала** — `picom --log-level=debug` мог бы показать подавление анимации раньше. Вместо этого ассистент менял конфиг вслепую.

- [ ] **Неправильный синтаксис custom animation** — Первая попытка кастомной opacity-анимации использовала `timing = "5s linear"` (CSS-подобный синтаксис). Picom показал warning "transition missing duration value". Правильный синтаксис: `opacity = { curve = "linear"; duration = 5.0; start = 0; end = 1; }`. Нужно было сразу проверить upstream документацию.

### Поверхностный поиск информации

- [ ] **3 итерации вместо 1 для GTK menu CSS** — Первоначальный поиск был слишком общим ("GTK3 CSS border-radius all windows"). Не были найдены конкретные примеры рабочих конфигов. Ассистент утверждал что "GTK3 menu виджет не поддерживает border-radius" и "полностью синхронизировать GTK-углы с picom невозможно для SSD-окон" — оба утверждения оказались неверными. Правильный ответ был в adw-gtk3 issue #100 с самого начала.

### Неправильные предположения о GTK версии

- [ ] **Искал для GTK3, когда пользователь сказал "у меня GTK4"** — Пользователь явно указал что у него GTK4, но ассистент продолжал искать GTK3 решения. Хотя в итоге Thunar действительно использует GTK3 (libgtk-3.so.0), это нужно было проверить сразу через `ldd /usr/bin/thunar`, а не предполагать.

### Избыточная уверенность в невозможности

- [ ] **Преждевременно заявил о невозможности решения** — Вместо того чтобы искать реальные примеры (Reddit, GitHub dotfiles, adw-gtk3), ассистент собрал теоретическую информацию из документации и сделал неверный вывод о невозможности. Пользователь справедливо указал: "Такого не может быть, ищи получше".

### Создание файлов без проверки

- [ ] **Создал gtk-4.0/gtk.css.tmpl без проверки что он нужен** — Создал файл для GTK4 хотя основная проблема (Thunar) была в GTK3. Файл не вреден, но был создан преждевременно.

## Ссылки и источники

### Официальная документация
- [GTK3 CSS Properties](https://docs.gtk.org/gtk3/css-properties.html) — справка по CSS свойствам
- [GTK4 CSS Overview](https://docs.gtk.org/gtk4/css-overview.html) — обзор CSS в GTK4
- [GTK4 CSS Properties](https://docs.gtk.org/gtk4/css-properties.html) — справка по CSS свойствам GTK4
- [GtkPopover (GTK4)](https://docs.gtk.org/gtk4/class.Popover.html) — CSS node structure: `popover > arrow + contents`
- [GtkPopoverMenu (GTK4)](https://docs.gtk.org/gtk4/class.PopoverMenu.html) — adds `.menu` class to popover node

### GitHub Issues и PR
- [adw-gtk3 #100: Context Menus](https://github.com/lassekongo83/adw-gtk3/issues/100) — **КЛЮЧЕВОЙ ИСТОЧНИК**: рабочий CSS для rounded corners на GTK3 context menus
- [yshui/picom #733: Weird borders with rounded corners](https://github.com/yshui/picom/issues/733) — `blur-background-frame = false` как workaround
- [yshui/picom #1226: Border around GTK-dialogs](https://github.com/yshui/picom/issues/1226) — артефакты GTK + picom
- [yshui/picom #1393: Open animation suppressed by !focused opacity](https://github.com/yshui/picom/issues/1393) — баг анимаций (из предыдущей сессии)
- [catppuccin/gtk #2: Corner radius](https://github.com/catppuccin/gtk/issues/2) — SCSS переменная для radius в теме
- [GNOME Discourse: Remove GtkPopoverMenu rounded corners](https://discourse.gnome.org/t/can-you-remove-a-gtkpopovermenus-rounded-corners/10961) — popover shape "hardcoded", но `contents` node стилизуется
- [GNOME Discourse: Adding rounded corners](https://discourse.gnome.org/t/adding-rounded-corners/10924) — RGBA visual + compositor requirement
- [GNOME Discourse: GTK-4.0 config folder](https://discourse.gnome.org/t/how-does-the-config-folder-gtk-4-0-work/10624) — `~/.config/gtk-4.0/gtk.css`

### Forum discussions
- [Xfce Forum: Global override to remove round corners](https://forum.xfce.org/viewtopic.php?id=18536) — `!important` не работает в GTK CSS
- [Arch Forum: GTK3 ugly menus, no border/shadow](https://bbs.archlinux.org/viewtopic.php?id=204050)
- [Arch Forum: Menu elements of gtk3 applications](https://bbs.archlinux.org/viewtopic.php?id=142064) — `menu > menuitem:hover` селектор
- [EndeavourOS: Picom corner-radius weird squares](https://forum.endeavouros.com/t/picom-with-corner-radius-in-i3wm-shows-weird-squares/27867)
- [Manjaro: Xfce, GTK and Qt remove rounded corners](https://forum.manjaro.org/t/xfce-gtk-and-qt-remove-rounded-corners-using-css/66879)

### Bugzilla
- [Mozilla #1748091: Padding around GTK menu windows on picom](https://bugzilla.mozilla.org/show_bug.cgi?id=1748091)
- [Mozilla #1509931: CSD sharp corners on Wayland](https://bugzilla.mozilla.org/show_bug.cgi?id=1509931)

### Прочее
- [GTK CSS properties gist](https://gist.github.com/ptomato/0fb634ef4098bb89026f) — неофициальная справка по GTK CSS
- [DeepWiki: GTK CSS Styling](https://deepwiki.com/GNOME/gtk/6.1-css-styling) — обзор CSS в GTK

## Файлы изменённые в сессии

| Файл | Что сделано |
|------|-------------|
| `dotfiles/dot_config/picom.conf.tmpl` | ~10 итераций: A/B тесты анимаций (rules on/off, shadows on/off, blur on/off, backend glx/xrender), duration 0.2→0.3→1.0→0.2, раскомментирован `rules:`, добавлен `opacity = 1` к dock/desktop/Polybar/DnD/GTK_FRAME, перенесён Thunar rule в конец, убран `corner-radius = 0` у popup_menu |
| `dotfiles/dot_config/gtk-3.0/gtk.css.tmpl` | СОЗДАН: CSD window border-radius, `.csd menu` + `.csd.popup decoration` (border-radius, box-shadow), `menuitem` (border-radius: 6px, padding), `separator` (margin) |
| `dotfiles/dot_config/gtk-4.0/gtk.css.tmpl` | СОЗДАН: CSD window border-radius, `popover.menu > contents` border-radius |
| `wiki/Picom-Configuration.md` | Создан в предыдущей сессии, не менялся |
| `wiki/Display-Setup.md` | Не менялся (уже существовал) |

## Ключевые выводы

### GTK3 Context Menu CSS Architecture
```
X11 window (window_type = popup_menu)
├── picom corner-radius: 10px (compositor-level clipping)
└── GTK3 drawing:
    ├── .csd.popup decoration { border-radius: 10px; box-shadow: ... }
    ├── menu { margin: 4px; padding: 6px; border-radius: 10px }
    └── menuitem { border-radius: 6px; padding: 7px 6px }
```

Оба уровня ДОЛЖНЫ быть синхронизированы:
- picom clip (corner-radius) обрезает пиксели на уровне композитора
- GTK CSS (border-radius) рисует скруглённый фон на уровне приложения
- Без GTK CSS: чёрные углы (picom обрезает, но GTK рисует квадратное)
- Без picom: визуально квадратные (GTK рисует скруглённое, но X11 окно прямоугольное)

### Picom rules: порядок и приоритет
- Правила применяются последовательно
- **Поздние правила ПЕРЕЗАПИСЫВАЮТ свойства ранних** для окон, матчащихся обоим
- Default rule (без match) → применяется ко ВСЕМ окнам
- Для исключений из default: либо добавить явный override (opacity = 1), либо переместить правило в конец

### GTK CSS файлы
- GTK3: `~/.config/gtk-3.0/gtk.css`
- GTK4: `~/.config/gtk-4.0/gtk.css`
- `!important` НЕ поддерживается в GTK CSS
- Thunar 4.20 использует GTK3 (libgtk-3.so.0), не GTK4

### Picom animations: ключевые находки (сводка двух сессий)

| Факт | Детали |
|------|--------|
| Duration в **секундах** | `0.2` = 200ms, `200` = 200 СЕКУНД |
| Пресеты | `appear`/`disappear` (scale+fade), `slide-in`/`slide-out`, `fly-in`/`fly-out` |
| Триггеры | `open`, `close`, `show`, `hide`, `geometry` |
| `rules:` override | При наличии `rules:` глобальные `active-opacity`, `inactive-opacity` игнорируются |
| BUG #1393 | `!focused` opacity в `rules:` подавляет open-анимацию на focused окнах |
| VM rendering | Scale-анимации рисуют только тень. Opacity fade — парсится, не виден |
| Backend | `glx` быстрее `xrender` для анимаций |
| Custom syntax | `opacity = { curve = "linear"; duration = 5.0; start = 0; end = 1; }` |
| Неправильный syntax | ~~`timing = "5s linear"`~~ → picom warning "missing duration" |

## Итог

**Анимации (5 решено, 2 ограничения VM):**
- ✅ A/B тестирование завершено — найден стабильный конфиг
- ✅ Backend: `glx` (xrender слишком медленный для анимаций)
- ✅ Appear/disappear 0.2s — работает для close, dock open
- ✅ Geometry trigger тестирован (тайловые окна) — работает для close
- ✅ Custom opacity animation синтаксис найден
- ⚠️ Open-анимация не работает (BUG #1393 + VM software rendering)
- ⚠️ Scale-анимации в VM — только тень

**Rules и opacity (3 решено):**
1. ✅ Opacity leak на dock/desktop/GTK — добавлен explicit `opacity = 1`
2. ✅ Thunar context menu opacity — перенесён rule в конец
3. ✅ Rules порядок и приоритет задокументирован

**GTK context menus (1 решено):**
- ✅ Rounded corners через GTK CSS + picom синхронизацию (adw-gtk3 #100 рецепт)

Picom конфигурация стабильна. GTK context menus имеют скруглённые углы, padding, box-shadow. Всего ~13 деплоев за сессию.
