# The following lines were added by Docker Desktop to add commands to your PATH.
export PATH="$PATH:/Users/bijoykozhampurath/.docker/bin"
# End of Docker Desktop section.

set -g fish_greeting ""
set -gx EDITOR "nvim"
## change this - java home
set -gx JAVA_HOME (/usr/libexec/java_home)

eval "$(/opt/homebrew/bin/brew shellenv)"
fish_add_path -g "/usr/local/bin"
# rustup
fish_add_path -g "$(brew --prefix rustup)/bin"
# uv
fish_add_path -g "$HOME/.local/bin"
# Added by LM Studio CLI (lms)
fish_add_path -g "$HOME/.lmstudio/bin"
# bun
set -gx BUN_INSTALL "$HOME/.bun"
fish_add_path -g $BUN_INSTALL/bin

if status is-interactive
    starship init fish | source
    enable_transience
    fzf --fish | source
    zoxide init fish | source
    uv generate-shell-completion fish | source
    uvx --generate-shell-completion fish | source
end

