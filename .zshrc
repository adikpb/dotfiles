# Editor
export EDITOR='nvim'

# Java
export JAVA_HOME=$(/usr/libexec/java_home)

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# PATH additions
export PATH="/usr/local/bin:$PATH"
[ -d "$(brew --prefix rustup)/bin" ] && export PATH="$(brew --prefix rustup)/bin:$PATH"
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/.lmstudio/bin" ] && export PATH="$HOME/.lmstudio/bin:$PATH"

# Bun
[ -d "$HOME/.bun" ] && export BUN_INSTALL="$HOME/.bun" && export PATH="$BUN_INSTALL/bin:$PATH"

# Interactive-only initializations
if [[ $- == *i* ]]; then
    # Starship prompt
    command -v starship &> /dev/null && eval "$(starship init zsh)"

    # FZF
    command -v fzf &> /dev/null && source <(fzf --zsh)

    # Zoxide
    command -v zoxide &> /dev/null && eval "$(zoxide init zsh)"

    # Sesh completions
    if command -v sesh &> /dev/null; then
        mkdir -p ~/.zsh/completions
        sesh completion zsh > ~/.zsh/completions/_sesh 2>/dev/null
        fpath=(~/.zsh/completions $fpath)
        autoload -U compinit && compinit
    fi

    # UV completions
    command -v uv &> /dev/null && eval "$(uv generate-shell-completion zsh)"
    command -v uvx &> /dev/null && eval "$(uvx --generate-shell-completion zsh)"
fi

