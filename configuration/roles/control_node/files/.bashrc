# === DEVGRU .bashrc ===
# Author: DEVGRU
# Description: Configuration file for customizing shell behavior and aliases.
# Last Updated: 2026-01-227

# History
HISTSIZE=1000
HISTFILESIZE=2000
HISTCONTROL=ignoredups:erasedups
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"

# Colorize ls and grep
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# === Git branch in prompt ===
parse_git_branch() {
  git branch 2>/dev/null | grep '\*' | sed 's/* //'
}

# === Colors ===
RESET='\[\033[0m\]'
RED='\[\033[0;31m\]'
GREEN='\[\033[0;32m\]'
BLUE='\[\033[0;34m\]'
CYAN='\[\033[0;36m\]'
YELLOW='\[\033[1;33m\]'
GRAY='\[\033[1;30m\]'

# === Prompt ===
# Format: [HH:MM] user@host:~/path (branch) $
PS1="${GRAY}[\A]${RESET} ${CYAN}\u${RESET}:${BLUE}\w${RESET} \$(parse_git_branch && echo \"(${YELLOW}\$(parse_git_branch)${RESET})\")\$ "

# PATH
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# === Aliases ===
alias ll='ls -la'
alias la='ls -A'
alias cls='clear'
alias reload='source ~/.bashrc'

# Editors
alias e='micro'
alias v='nvim'

# DevOps tools
alias ans='ansible-playbook'
alias pass='gopass'
alias g='git'


# Network
alias ipinfo='curl ifconfig.me'
alias ping6='ping -6'
alias digdev='dig @1.1.1.1 +short'
alias trace='mtr --report'