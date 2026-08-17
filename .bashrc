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
    command -v starship &> /dev/null && eval "$(starship init bash)"

    # FZF
    command -v fzf &> /dev/null && eval "$(fzf --bash)"

    # Zoxide
    command -v zoxide &> /dev/null && eval "$(zoxide init bash)"

    # Sesh completions
    command -v sesh &> /dev/null && eval "$(sesh completion bash)"

    # UV completions
    command -v uv &> /dev/null && eval "$(uv generate-shell-completion bash)"
    command -v uvx &> /dev/null && eval "$(uvx --generate-shell-completion bash)"
fi

