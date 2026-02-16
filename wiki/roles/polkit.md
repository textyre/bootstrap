# Роль: polkit

**Phase**: 6 | **Направление**: Services

## Цель

Настройка PolicyKit (polkit) для управления привилегиями без sudo. Разрешает пользователям из группы `wheel` выполнять системные операции (управление сервисами, монтирование устройств, управление сетью) без ввода пароля или с упрощённой аутентификацией.

## Ключевые переменные (defaults)

```yaml
polkit_enabled: true  # Включить настройку polkit

# Целевая группа (обычно wheel или sudo)
polkit_admin_group: wheel

# Правила для группы wheel
polkit_allow_systemctl: true         # Управление systemd сервисами без пароля
polkit_allow_mount: true              # Монтирование USB/съёмных дисков
polkit_allow_power_management: true   # Перезагрузка, выключение, suspend
polkit_allow_network_manager: true    # Управление NetworkManager
polkit_allow_package_manager: false   # Установка пакетов (опасно, default: off)
polkit_allow_timedate: true           # Изменение даты/времени

# Настройка аутентификации
polkit_require_auth: false  # false — без пароля, true — с паролем админа

# Список пользовательских правил (JavaScript)
polkit_custom_rules: []
# Пример:
# - name: 50-wheel-systemd
#   content: |
#     polkit.addRule(function(action, subject) {
#         if (action.id == "org.freedesktop.systemd1.manage-units" &&
#             subject.isInGroup("wheel")) {
#             return polkit.Result.YES;
#         }
#     });

# Путь к правилам
polkit_rules_dir: /etc/polkit-1/rules.d
```

## Что настраивает

**На всех дистрибутивах:**
- JavaScript-правила в `/etc/polkit-1/rules.d/`
- Разрешения для группы `wheel` на:
  - Управление systemd сервисами (`org.freedesktop.systemd1.manage-units`)
  - Монтирование устройств (`org.freedesktop.udisks2.filesystem-mount`)
  - Power management (`org.freedesktop.login1.power-off`, `reboot`, `suspend`)
  - NetworkManager (`org.freedesktop.NetworkManager.*`)
- Перезапуск `polkit.service` (если требуется)

**На Arch Linux:**
- Пакет: `polkit`
- Путь: `/etc/polkit-1/rules.d/`

**На Debian/Ubuntu:**
- Пакет: `policykit-1`
- Путь: `/etc/polkit-1/rules.d/` (или `/var/lib/polkit-1/localauthority/`)

**На Fedora/RHEL:**
- Пакет: `polkit`
- Путь: `/etc/polkit-1/rules.d/`

## Зависимости

- `base_system` — polkit и dbus
- `user` — группа `wheel` должна существовать

## Примечания

### Пример правила: systemd без пароля

Файл `/etc/polkit-1/rules.d/50-wheel-systemd.rules`:

```javascript
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
```

Результат: пользователи из `wheel` могут выполнять `systemctl start/stop/restart` без `sudo`.

### Основные action ID

| Действие | Action ID |
|----------|-----------|
| Управление systemd сервисами | `org.freedesktop.systemd1.manage-units` |
| Перезагрузка/выключение | `org.freedesktop.login1.reboot`, `power-off` |
| Suspend/hibernate | `org.freedesktop.login1.suspend`, `hibernate` |
| Монтирование USB | `org.freedesktop.udisks2.filesystem-mount` |
| Управление NetworkManager | `org.freedesktop.NetworkManager.settings.modify.system` |
| Изменение времени | `org.freedesktop.timedate1.set-time` |

### Поиск action ID

```bash
# Список всех доступных actions
pkaction | grep -i systemd

# Подробности об action
pkaction --verbose --action-id org.freedesktop.systemd1.manage-units
```

### Проверка правил

```bash
# Проверка прав для текущего пользователя
pkcheck --action-id org.freedesktop.systemd1.manage-units --process $$ -u

# Тестирование без реального выполнения
systemctl restart test.service  # Если не запросит пароль — правило работает
```

### Безопасность

- **Не разрешайте** установку пакетов (`polkit_allow_package_manager: false`) без пароля — это полный root.
- **Ограничьте** правила конкретными действиями, избегайте wildcard (`*`).
- **Аудит**: логи polkit в journalctl (`journalctl -u polkit`).

### Альтернатива: sudo с NOPASSWD

Polkit — более гранулярная альтернатива `sudo NOPASSWD`. Вместо:

```sudoers
%wheel ALL=(ALL) NOPASSWD: /usr/bin/systemctl
```

используйте polkit для контроля только над systemd, без полного sudo.

## Tags

- `polkit`
- `security`
- `privilege-management`
- `systemd`

---

Назад к [[Roadmap]]
