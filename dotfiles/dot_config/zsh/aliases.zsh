# ~/.config/zsh/aliases.zsh — Shell aliases

# File listing
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'

# Common tools
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Git shortcuts
alias gs='git status'
alias gl='git log --oneline -20'
alias gd='git diff'
alias ga='git add'
alias gc='git commit'
alias gp='git push'

# Modern replacements
alias cat='bat --paging=never --style=plain'
alias vim='nvim'

# Safety
alias rm='rm -I'
alias cp='cp -iv'
alias mv='mv -iv'

# Directory stack
alias d='dirs -v'
alias 1='cd -1'
alias 2='cd -2'
alias 3='cd -3'
