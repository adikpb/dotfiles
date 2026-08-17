# adikpb/dotfiles conventions

Stow tree: repo root maps onto `$HOME` (`.config/`, `.bashrc`, `.zshrc`). Origin `https://github.com/adikpb/dotfiles.git`. Messages look like `feat(opencode-free): …`, `feat(nvim: lightbulb): …`.

## Already a submodule

`.config/opencode/plugins/oh-my-opencode-slim` → `git@github.com:adikpb/oh-my-opencode-slim.git`. Parent stores one SHA. Local checkout is hundreds of MB (`node_modules`). Bump the gitlink; do not vendor.

## Ignore, do not submodule

`.config/kitty/kitty/` is a kovidgoyal/kitty clone used only so `tab_bar.py` can see kitty internals. Keep it in `.config/kitty/.gitignore`. `pyrightconfig.json` with `extraPaths: ["./kitty/"]` is the same local-only setup.

## Usually leave untracked

- Empty `tab_bar.py` while `kitty.conf` uses built-in `powerline`
- `.config/opencode/package.json` (`@opencode-ai/plugin`) with no lockfile
- Plugin JSON dumps already ignored by `.config/opencode/plugins/.gitignore` (`*.json`)
- LM Studio installer tails that hardcode `/Users/<name>/.lmstudio/bin` after a portable `$HOME` line
- `.hermes/` if a plan file was written into this repo

## Already ignored

Fisher files (`done.fish`, `sponge.fish`, `fish_plugins`, `fish_variables`), tmux plugin dir, `lazy-lock.json`, `Session.vim`.
