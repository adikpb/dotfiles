eval "$(/opt/homebrew/bin/brew shellenv)"

## change this - java home
set -gx JAVA_HOME (/usr/libexec/java_home)

# cargo
fish_add_path ~/.cargo/bin

# uv
fish_add_path "/Users/bijoykozhampurath/.local/bin"

if status is-interactive
    # starship
    starship init fish | source

    test -e {$HOME}/.iterm2_shell_integration.fish ; and source {$HOME}/.iterm2_shell_integration.fish

    # https://docs.astral.sh/uv/getting-started/installation/#shell-autocompletion
    uv generate-shell-completion fish | source
    uvx --generate-shell-completion fish | source
end
