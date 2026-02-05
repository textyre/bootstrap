# План миграции с Polybar на Ewwii

**Дата:** 2026-02-05  
**Статус:** Планирование

## Что такое Ewwii

**Ewwii** (Elkowar's Wacky Widgets Improved Interface) — переработка eww с ключевыми отличиями:

| Характеристика | eww | ewwii |
|----------------|-----|-------|
| Язык конфигурации | Yuck (Lisp) | **Rhai** (Rust-like) |
| GTK версия | GTK3 | **GTK4** |
| Hot reload | Частичный | Полный |
| Расширяемость | Ограниченная | Плагины + Rhai модули |

## Текущая функциональность Polybar

### "Три плавающих острова"

```
[ЛЕВЫЙ]              [ЦЕНТР]          [ПРАВЫЙ]
Workspaces+Add       Clock/Date       System Info
```

- Override-redirect, прозрачный фон
- Border radius 14px, высота 32px
- Multi-monitor: 4 бара на монитор

### 9 модулей

- workspaces (dynamic 1-10)
- date, network, volume, cpu, memory
- controlcenter, powermenu

### Динамические воркспейсы

- WS 1-3 фиксированные
- WS 4-10 создаются по требованию
- Иконки через rofi меню
- Можно изменить/удалить

## Маппинг Polybar → Ewwii

| Polybar | Ewwii |
|---------|-------|
| `[bar/name]` | `defwindow("name", ...)` |
| `modules-left` | `box({ halign: "start" }, [...])` |
| `internal/date` | `poll("time", { interval: "1s", ... })` |
| `internal/pulseaudio` | `listen("volume", { cmd: "pactl subscribe" })` |
| `custom/script tail=true` | `listen("var", { cmd: "script" })` |

## Ключевое преимущество

```rhai
defwindow("workspaces", #{
    geometry: #{
        width: "auto",  // <-- Автоматический размер!
        height: "32px",
    },
}, workspaces_widget())
```

В Polybar ширина задается статически через env var.  
В Ewwii — автоматически по контенту.

## План миграции (8 фаз)

### Фаза 0: Подготовка
- [ ] Установить ewwii на VM
- [ ] Проверить зависимости (GTK4, layer-shell)
- [ ] Создать директорию конфигурации

### Фаза 1: Базовый скелет (MVP)
- [ ] Создать `ewwii.rhai.tmpl` с минимальной структурой
- [ ] Создать `ewwii.scss.tmpl` с базовыми стилями
- [ ] Создать `launch.sh` для ewwii
- [ ] Интегрировать в i3 config

### Фаза 2: Статические модули
- [ ] Clock/Date виджет (poll 1s)
- [ ] CPU виджет (poll 2s)
- [ ] Memory виджет (poll 3s)
- [ ] Network виджет (poll 3s)
- [ ] Volume виджет (poll 0.5s)

### Фаза 3: Динамические воркспейсы
- [ ] Портировать `workspaces.sh` → JSON output
- [ ] Создать workspaces widget в Rhai
- [ ] Реализовать состояния (focused, occupied, empty, urgent)
- [ ] Портировать кнопку "+"
- [ ] Портировать контекстное меню

### Фаза 4: Интерактивность
- [ ] Click handlers для всех модулей
- [ ] Scroll handlers для volume
- [ ] Портировать rofi скрипты

### Фаза 5: Три острова
- [ ] Workspaces island (левый, auto width)
- [ ] Clock island (центр)
- [ ] System island (правый)

### Фаза 6: Стилизация
- [ ] Перенести цвета в SCSS переменные
- [ ] Стили островов (background, border, radius)
- [ ] Стили модулей
- [ ] Hover/active состояния

### Фаза 7: Multi-monitor
- [ ] Детект мониторов через xrandr
- [ ] Передача monitor в defwindow

### Фаза 8: Финализация
- [ ] Удалить polybar конфигурацию
- [ ] Обновить i3 config
- [ ] Протестировать theme switching
- [ ] Документировать изменения

## Оценка трудозатрат

| Фаза | Оценка |
|------|--------|
| 0. Подготовка | 1-2 часа |
| 1. MVP | 2-3 часа |
| 2. Статические модули | 2-3 часа |
| 3. Динамические WS | 4-6 часов |
| 4. Интерактивность | 2-3 часа |
| 5. Три острова | 2-3 часа |
| 6. Стилизация | 2-4 часа |
| 7. Multi-monitor | 1-2 часа |
| 8. Финализация | 1-2 часа |

**Итого:** 17-28 часов (2-4 дня)

## Риски

| Риск | Вероятность | Митигация |
|------|-------------|-----------|
| Ewwii нестабилен | Средняя | Сохранить polybar как fallback |
| Rhai синтаксис незнакомый | Низкая | Примеры в репозитории ewwii |
| GTK4 отсутствует | Низкая | Установить gtk4 пакет |
| Документация неполная | Высокая | Ориентироваться на примеры |

## Критерии успеха

### Must Have
- [ ] Три острова отображаются
- [ ] Workspaces 1-10 работают
- [ ] Динамическая ширина WS острова
- [ ] Все click handlers работают
- [ ] Volume scroll работает
- [ ] Theme switching через chezmoi

### Should Have
- [ ] Hot reload конфига
- [ ] Нет visible flicker
- [ ] Multi-monitor поддержка

### Nice to Have
- [ ] Анимации переходов
- [ ] Гранулярный hover контроль
- [ ] Уведомления об ошибках

---

Назад к [[Home]]
