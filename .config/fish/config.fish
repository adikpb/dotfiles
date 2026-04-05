set -g fish_greeting ""
set -gx EDITOR "nvim"
## change this - java home
set -gx JAVA_HOME (/usr/libexec/java_home)

eval "$(/opt/homebrew/bin/brew shellenv)"
fish_add_path -g "/usr/local/bin"
# rustup
fish_add_path -g "$(brew --prefix rustup)/bin"
# uv
fish_add_path -g "/Users/bijoykozhampurath/.local/bin"
# Added by LM Studio CLI (lms)
fish_add_path -g /Users/bijoykozhampurath/.lmstudio/bin
# bun
set -gx BUN_INSTALL "$HOME/.bun"
fish_add_path -g $BUN_INSTALL/bin $PATH

if status is-interactive
    starship init fish | source
    fzf --fish | source
    zoxide init fish | source
    sesh completion fish | source
    uv generate-shell-completion fish | source
    uvx --generate-shell-completion fish | source
end
