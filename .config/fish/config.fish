eval "$(/opt/homebrew/bin/brew shellenv)"

fish_add_path -g "/usr/local/bin"

## change this - java home
set -gx JAVA_HOME (/usr/libexec/java_home)

# rustup
fish_add_path -g "$(brew --prefix rustup)/bin"


# uv
fish_add_path -g "/Users/bijoykozhampurath/.local/bin"

if status is-interactive
    starship init fish | source
    fzf --fish | source
    zoxide init fish | source
    sesh completion fish | source

    # https://docs.astral.sh/uv/getting-started/installation/#shell-autocompletion
    uv generate-shell-completion fish | source
    uvx --generate-shell-completion fish | source
end
