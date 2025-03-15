eval "$(/opt/homebrew/bin/brew shellenv)"

## change this - java home
set -gx JAVA_HOME (/usr/libexec/java_home)

# pyenv
set -gx PYENV_ROOT $HOME/.pyenv
fish_add_path $PYENV_ROOT/bin

pyenv init - | source

# Created by `pipx` on 2024-06-10 13:29:40
contains $HOME/.local/bin $PATH; or set -gx -a PATH $HOME/.local/bin 

# starship
starship init fish | source

# Set up fzf key bindings
fzf --fish | source

# cargo
fish_add_path ~/.cargo/bin

test -e {$HOME}/.iterm2_shell_integration.fish ; and source {$HOME}/.iterm2_shell_integration.fish

