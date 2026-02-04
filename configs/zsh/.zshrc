# .zshrc template

# --- Secrets ---
# Load sensitive data if it exists
if [[ -f "$HOME/.zsh_secrets" ]]; then
    source "$HOME/.zsh_secrets"
fi

# --- Aliases ---
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# --- Prompt ---
PROMPT='%F{blue}%n@%m%f %F{green}%~%f %# '
