# Dotfiles (chezmoi)

Dotfiles управляются через [chezmoi](https://www.chezmoi.io/).

## Структура

```
dotfiles/
├── .chezmoi.toml.tmpl      # chezmoi configuration
├── dot_xinitrc             # ~/.xinitrc (X11 initialization)
├── dot_config/i3/config    # ~/.config/i3/config (i3 configuration)
└── README.md               # этот файл
```

## Установка

Во время bootstrap процесса chezmoi автоматически инициализируется и применяется:

```bash
chezmoi init --apply https://your-repo-url/scripts/dotfiles
```

## Ручное использование

### Первый запуск
```bash
chezmoi init https://your-repo-url/scripts/dotfiles
chezmoi apply
```

### Обновление dotfiles
```bash
chezmoi pull --apply
```

### Просмотр изменений
```bash
chezmoi diff
```

### Редактирование dotfile
```bash
chezmoi edit ~/.xinitrc
```
