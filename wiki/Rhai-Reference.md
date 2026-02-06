# Rhai: Справочник языка

**Источник:** [The Rhai Book](https://rhai.rs/book/) (v1.24.0)
**Контекст:** Rhai — язык конфигурации ewwii. Скрипты пишутся в `.rhai` файлах.

---

## Типы данных

| Тип | Литерал | `type_of()` | Описание |
|-----|---------|-------------|----------|
| Integer | `42`, `-1`, `0xFF` | `"i64"` | По умолчанию i64 |
| Float | `3.14`, `1.0e10` | `"f64"` | По умолчанию f64 |
| Boolean | `true`, `false` | `"bool"` | |
| Character | `'A'`, `'\n'` | `"char"` | Unicode |
| String | `"hello"`, `` `world` `` | `"string"` | Иммутабельные |
| Array | `[1, "a", true]` | `"array"` | Динамический `Vec<Dynamic>` |
| Object Map | `#{ a: 1, b: "x" }` | `"map"` | `BTreeMap<String, Dynamic>` |
| Unit | `()` | `"()"` | Пустое значение (аналог nil/void) |
| Function Ptr | `Fn("name")` | `"Fn"` | Указатель на функцию |
| Timestamp | `timestamp()` | `"timestamp"` | Системное время |
| Range | `1..10`, `0..=5` | `"range"` | Диапазон целых |

> Целочисленные типы **строго различны** — `i32` и `i64` не конвертируются автоматически.

---

## Строки

### Три вида строк

| Синтаксис | Escape | Интерполяция | Многострочность |
|-----------|--------|-------------|-----------------|
| `"hello"` | Да (`\n`, `\t`, `\uXXXX`) | Нет | Через `\` в конце строки |
| `` `hello` `` | Нет | Да (`${expr}`) | Да |
| `#"hello"#` | Нет | Нет | Да (raw-строка) |

### Escape-последовательности (только в `""`)

| Escape | Значение |
|--------|----------|
| `\\` | Обратный слеш |
| `\t`, `\r`, `\n` | Таб, возврат каретки, перенос строки |
| `\"` или `""` | Двойная кавычка |
| `\'` | Одинарная кавычка |
| `\xHH` | ASCII (2 hex) |
| `\uHHHH` | Unicode (4 hex) |
| `\UHHHHHHHH` | Unicode расширенный (8 hex) |

### Строковая интерполяция

Только в backtick-строках:

```rhai
let name = "world";
let s = `Hello, ${name}!`;           // "Hello, world!"
let s = `2 + 2 = ${2 + 2}`;          // "2 + 2 = 4"
let s = `nested: ${`inner ${x}`}`;   // вложенная интерполяция
```

> `"Hello, ${name}!"` — НЕ работает, `${name}` будет литеральным текстом.

### Основные строковые функции

| Функция | Описание |
|---------|----------|
| `len` / `is_empty` | Длина / пустая ли |
| `contains(sub)` | Содержит подстроку |
| `starts_with(s)` / `ends_with(s)` | Начинается / заканчивается |
| `index_of(sub)` | Позиция подстроки (-1 если нет) |
| `sub_string(start, len)` | Подстрока |
| `split(delim)` | Разбить в массив |
| `trim()` | Убрать пробелы |
| `to_lower()` / `to_upper()` | Регистр |
| `replace(from, to)` | Замена всех вхождений |
| `truncate(len)` | Обрезать |

---

## Переменные

### Объявление

```rhai
let x = 42;           // мутабельная
let y;                 // значение = ()
const PI = 3.14159;    // константа (нельзя изменить)
```

### Правила именования

- ASCII буквы, цифры, `_`
- Первый непробельный символ — буква
- Регистрозависимые (`x` != `X`)
- Нельзя совпадать с ключевыми словами

### Область видимости

Блочная. Переменные внутри `{ }` не видны снаружи:

```rhai
let x = 42;
{
    let x = 999;   // shadow — скрывает внешний x
    print(x);      // 999
}
print(x);          // 42 (внешний x не изменён)
```

---

## Операторы

### По приоритету (от высшего к низшему)

| Приоритет | Операторы | Описание |
|-----------|----------|----------|
| Высший | `.`, `?.`, `[]`, `?[]` | Доступ к свойствам/индексам |
| | `!` | Логическое НЕ |
| | `-` (унарный) | Отрицание |
| | `**` | Возведение в степень (правоассоц.) |
| | `*`, `/`, `%` | Умножение, деление, остаток |
| | `+`, `-` | Сложение, вычитание |
| | `<<`, `>>` | Битовый сдвиг |
| | `&` | Битовое И |
| | `^` | Битовое XOR |
| | `\|` | Битовое ИЛИ |
| | `==`, `!=`, `<`, `<=`, `>`, `>=` | Сравнение |
| | `in`, `!in` | Проверка принадлежности |
| | `&&` | Логическое И (short-circuit) |
| | `\|\|` | Логическое ИЛИ (short-circuit) |
| | `??` | Null-coalesce (short-circuit) |
| Низший | `=`, `+=`, `-=`, `*=`, `/=` и др. | Присваивание |

### Оператор `in`

```rhai
"el" in "hello"       // true — подстрока
42 in [1, 42, 99]     // true — элемент массива
"key" in #{ key: 1 }  // true — ключ в map
```

### Elvis-оператор `?.`

```rhai
obj?.prop             // () если obj == (), иначе obj.prop
arr?.[0]              // () если arr == (), иначе arr[0]
```

---

## Управление потоком

### if / else

```rhai
if condition {
    // ...
} else if other {
    // ...
} else {
    // ...
}
```

`if` — выражение (возвращает значение):

```rhai
let x = if decision { 42 } else { 0 };
```

### switch

```rhai
switch value {
    1 => print("one"),
    2 | 3 => print("two or three"),
    4 if x > 10 => print("four and x > 10"),   // guard
    0..50 => print("0 to 49"),                  // range
    _ => print("default"),                       // обязательно последний
}
```

Поддерживает литералы, диапазоны, guard-условия, альтернативы через `|`.

### for

```rhai
for item in array { ... }
for (item, index) in array { ... }    // с индексом
for i in 0..10 { ... }                // range
```

`for` — выражение. `break value` возвращает значение из цикла.

### while / loop / do

```rhai
while condition { ... }
loop { ... break; }             // бесконечный цикл
do { ... } while condition;     // пост-условие
do { ... } until condition;     // пост-условие (инверсное)
```

### try / catch

```rhai
try {
    let x = 1 / 0;
} catch (err) {
    print(`Error: ${err}`);
}
```

`throw;` без аргумента — повторный выброс. Системные ошибки (парсинг, лимиты) — не перехватываемы.

---

## Функции

### Определение

```rhai
fn add(x, y) {
    x + y                    // неявный return (последнее выражение)
}

fn greet(name) {
    return `Hello, ${name}!`;  // явный return
}
```

### Ключевые ограничения

- **Нет замыканий** — функции не захватывают внешние переменные
- **Нет вложенных определений** — только на верхнем уровне
- **Pass-by-value** — аргументы копируются; функция не может изменить переменную вызывающего
- **Нет перегрузки по типу** — различаются только по имени + кол-ву параметров
- **Можно вызвать до определения**

### Проверка существования

```rhai
is_def_fn("add", 2)    // true — функция "add" с 2 параметрами определена
```

### Анонимные функции (лямбды)

```rhai
let f = |x| x * 2;
let g = |x, y| { x + y };
let h = || 42;

[1, 2, 3].map(|x| x * 2)        // [2, 4, 6]
[1, 2, 3].filter(|x| x > 1)     // [2, 3]
```

### Замыкания (closures)

Анонимные функции **автоматически захватывают** внешние переменные:

```rhai
let x = 40;
let f = |y| x + y;     // x захвачен
x = 100;                // x теперь shared
f.call(2)               // 102 (видит обновлённый x!)
```

> Захваченные переменные становятся shared (reference-counted). Все замыкания, захватившие одну переменную, разделяют её значение.

---

## Массивы (Array)

### Создание и доступ

```rhai
let a = [1, "hello", true, [2, 3]];
a[0]       // 1
a[-1]      // [2, 3] (с конца)
a[10]      // ОШИБКА (выход за границы)
```

### Основные операции

| Операция | Синтаксис |
|----------|----------|
| Добавить | `a.push(x)` или `a += x` |
| Объединить | `a.append(b)` или `a += b` или `a + b` |
| Удалить последний | `a.pop()` |
| Удалить первый | `a.shift()` |
| Вставить | `a.insert(pos, x)` |
| Удалить по индексу | `a.remove(pos)` |
| Длина | `a.len()` |
| Очистить | `a.clear()` |
| Содержит | `a.contains(x)` или `x in a` |
| Найти индекс | `a.index_of(x)` |
| Сортировать | `a.sort()` |
| Обратить | `a.reverse()` |

### Функциональные методы

```rhai
a.map(|x| x * 2)                // преобразовать каждый
a.filter(|x| x > 0)             // отфильтровать
a.reduce(|sum, x| sum + x, 0)   // свернуть
a.any(|x| x > 5)                // хоть один > 5?
a.all(|x| x > 0)                // все > 0?
a.find(|x| x > 5)               // первый > 5
a.for_each(|x| print(x))        // выполнить для каждого
```

---

## Object Map

### Создание и доступ

```rhai
let m = #{ name: "John", age: 30, active: true };
m.name          // "John" (через точку)
m["name"]       // "John" (через индекс — любое имя свойства)
m.unknown       // () (несуществующее свойство = unit, не ошибка)
"name" in m     // true
```

### Основные операции

| Операция | Синтаксис |
|----------|----------|
| Получить | `m.get("key")` |
| Установить | `m.set("key", value)` |
| Удалить | `m.remove("key")` |
| Ключи | `m.keys()` → массив |
| Значения | `m.values()` → массив |
| Длина | `m.len()` |
| Содержит | `m.contains("key")` |
| Объединить | `m.mixin(m2)` или `m += m2` |
| В JSON | `m.to_json()` |
| Очистить | `m.clear()` |

### OOP-паттерн

```rhai
let obj = #{
    data: 42,
    inc: |x| this.data += x,      // this = текущий map
    get: || this.data,
};
obj.inc(8);
obj.get()    // 50
```

---

## Модули

### Экспорт

```rhai
// mymodule.rhai
fn greet(name) {                   // автоматически экспортирована
    `Hello, ${name}!`
}
private fn internal() { ... }       // скрыта от импорта

let PI = 3.14159;
export PI;                          // переменные — explicit export
export const TAU = 6.28318;         // объявление + экспорт
export PI as MY_PI;                 // алиас
```

Правила:
- **Функции** — экспортируются автоматически. `private fn` скрывает
- **Переменные** — только через `export`. Становятся read-only
- **Подмодули** — импортированные модули автоматически реэкспортируются

### Импорт

```rhai
import "path/to/module" as m;
m::greet("World");
m::PI
m::submodule::func()
```

Правила:
- Путь — любое строковое выражение
- Импорты блочно-скопированы
- Не ставить `import` внутри циклов (перезагрузка на каждой итерации)
- Рекомендация: все `import` в начале скрипта

---

## Ключевые слова

### Активные

`true`, `false`, `let`, `const`, `if`, `else`, `switch`, `do`, `while`, `until`, `loop`, `for`, `in`, `!in`, `continue`, `break`, `return`, `throw`, `try`, `catch`, `import`, `export`, `as`, `global`, `private`, `fn`, `Fn`, `call`, `curry`, `is_shared`, `is_def_fn`, `is_def_var`, `this`, `type_of`, `print`, `debug`, `eval`

### Зарезервированные (для будущего использования)

`var`, `static`, `match`, `case`, `public`, `protected`, `new`, `use`, `with`, `is`, `module`, `super`, `async`, `await`, `yield`, `default`, `void`, `null`, `nil`

---

## Встроенные математические функции

| Функция | Описание |
|---------|----------|
| `abs(x)` | Модуль |
| `sign(x)` | Знак (-1, 0, 1) |
| `sqrt(x)` | Квадратный корень |
| `ceil(x)`, `floor(x)`, `round(x)` | Округление |
| `min(a, b)`, `max(a, b)` | Минимум/максимум |
| `sin`, `cos`, `tan`, `asin`, `acos`, `atan` | Тригонометрия |
| `ln(x)`, `log(x)`, `log(x, base)` | Логарифмы |
| `exp(x)` | Экспонента |
| `PI()`, `E()` | Константы |

## Конвертация типов

| Функция | Описание |
|---------|----------|
| `to_int(x)` | В целое |
| `to_float(x)` | В дробное |
| `to_string(x)` | В строку |
| `to_debug(x)` | Debug-представление |
| `parse_int(s)` | Строка → целое |
| `parse_float(s)` | Строка → дробное |
| `parse_json(s)` | JSON-строка → значение |
| `to_json(map)` | Map → JSON-строка |

---

## Полезные ссылки

- [The Rhai Book](https://rhai.rs/book/)
- [Типы данных](https://rhai.rs/book/language/values-and-types.html)
- [Строки](https://rhai.rs/book/language/strings-chars.html)
- [Интерполяция](https://rhai.rs/book/language/string-interp.html)
- [Массивы](https://rhai.rs/book/language/arrays.html)
- [Object Maps](https://rhai.rs/book/language/object-maps.html)
- [Переменные](https://rhai.rs/book/language/variables.html)
- [Функции](https://rhai.rs/book/language/functions.html)
- [Замыкания](https://rhai.rs/book/language/fn-closure.html)
- [Модули (export)](https://rhai.rs/book/language/modules/export.html)
- [Модули (import)](https://rhai.rs/book/language/modules/import.html)
- [Ключевые слова](https://rhai.rs/book/appendix/keywords.html)
- [Операторы](https://rhai.rs/book/appendix/operators.html)
- [Playground](https://rhai.rs/book/start/playground.html)

---

Назад к [[Home]] | См. также: [[Ewwii-Reference]], [[GTK-CSS-Reference]]
