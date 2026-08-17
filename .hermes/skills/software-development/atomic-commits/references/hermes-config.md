# Hermes config in this stow-root repo

User command: `cd ~/dotfiles && stow -t ~ .`. Do not add a `hermes/` package or run `stow -t ~/.hermes`.

Track only `.hermes/config.yaml` (live path `~/.hermes/config.yaml -> ../dotfiles/.hermes/config.yaml`). `hermes config set` writes through the symlink.

Root gitignore (never a blanket `.hermes/`):

```
.hermes/*
!.hermes/.gitignore
!.hermes/config.yaml
```

`.stow-local-ignore` must include `\.hermes/plans` so workspace plans are not stowed over `~/.hermes/plans`.

On a new machine: `mkdir -p ~/.hermes` before `stow .`, or Stow folds the whole home onto the tiny repo folder.

Never track `.env`, `auth.json`, `memories/`, `state.db`, `sessions/`, `hermes-agent/`, `profiles/`.
