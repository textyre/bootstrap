# ~/.config/zsh/keybindings.zsh — Key bindings

bindkey -e  # Emacs mode

# History search
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Navigation
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word       # Ctrl+Right
bindkey '^[[1;5D' backward-word      # Ctrl+Left
bindkey '^[[H' beginning-of-line     # Home
bindkey '^[[F' end-of-line           # End
bindkey '^U' kill-whole-line

# Edit command in $EDITOR (Ctrl+X Ctrl+E)
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line
