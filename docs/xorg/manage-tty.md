# Управление TTY в Linux

## Переключение между TTY

| Комбинация | Действие |
|------------|----------|
| `Ctrl + Alt + F1` | TTY1 |
| `Ctrl + Alt + F2` | TTY2 |
| `Ctrl + Alt + F3` | TTY3 |
| `Ctrl + Alt + F4` | TTY4 |
| `Ctrl + Alt + F5` | TTY5 |
| `Ctrl + Alt + F6` | TTY6 |
| `Ctrl + Alt + F7` | Обычно X-сессия (если была) |

> **Примечание:** Если вы уже находитесь в TTY (не в X11), можно использовать просто `Alt + F2` (без Ctrl).

## Прокрутка в TTY

В современных ядрах Linux (5.9+) scrollback в TTY **удалён** из соображений безопасности.

### Альтернативы

**tmux:**
```bash
sudo pacman -S tmux
tmux
# Ctrl+B, затем [ — режим прокрутки
# PageUp/PageDown для навигации
# q — выход из режима
```

**Перенаправление вывода:**
```bash
dmesg | less
journalctl | less
command 2>&1 | tee output.log
```

## Аварийные комбинации (SysRq)

| Комбинация | Действие |
|------------|----------|
| `Alt + SysRq + R` | Отнять клавиатуру у X-сервера (raw mode) |
| `Alt + SysRq + E` | SIGTERM всем процессам (кроме init) |
| `Alt + SysRq + I` | SIGKILL всем процессам (кроме init) |
| `Alt + SysRq + S` | Sync — записать буферы на диск |
| `Alt + SysRq + U` | Перемонтировать файловые системы read-only |
| `Alt + SysRq + B` | Немедленная перезагрузка |
| `Alt + SysRq + K` | SAK — убить все процессы на текущем TTY |

### Безопасная перезагрузка зависшей системы

Последовательность **R E I S U B** (с паузой 1-2 сек между клавишами):

```
Alt + SysRq + R  — отнять клавиатуру
Alt + SysRq + E  — завершить процессы
Alt + SysRq + I  — убить процессы
Alt + SysRq + S  — синхронизировать диски
Alt + SysRq + U  — перемонтировать read-only
Alt + SysRq + B  — перезагрузить
```

Мнемоника: **R**eboot **E**ven **I**f **S**ystem **U**tterly **B**roken

### Включение SysRq

Проверить статус:
```bash
cat /proc/sys/kernel/sysrq
```

Включить все функции:
```bash
echo 1 | sudo tee /proc/sys/kernel/sysrq
```

Для постоянного включения добавьте в `/etc/sysctl.d/99-sysrq.conf`:
```
kernel.sysrq = 1
```

## Ссылки

- [Linux Magic System Request Key — Kernel Docs](https://www.kernel.org/doc/html/latest/admin-guide/sysrq.html)
- [Console — ArchWiki](https://wiki.archlinux.org/title/Linux_console)
