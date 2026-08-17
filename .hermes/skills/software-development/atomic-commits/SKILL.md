---
name: atomic-commits
description: Use when planning atomic commits from a dirty tree.
version: 1.0.0
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [git, commits, gitignore, submodules, stow, planning]
    related_skills: [plan, github-pr-workflow]
---

# Atomic commits from a dirty tree

Use when the user wants a commit plan, a dirty-tree breakdown, or help syncing a working copy without mixing unrelated changes. Planning only until they approve.

The built-in `plan` skill is implementation/TDD-shaped. Do not force failing tests or a subagent-driven-development handoff onto a commit-only request. Save a markdown plan if `/plan` is in play; otherwise show the table in the reply.

## Recon (read-only, before proposing anything)

1. `git status -sb`, remotes, recent `git log --oneline` (match this repo's message style).
2. `git submodule status` and `git ls-files -s` on any nested path git reports as "new commits". Mode `160000` is already a submodule.
3. For each untracked or dirty directory: `git -C <path> remote -v` and `du -sh`. A nested clone with its own origin is a checkout, not a new file tree.
4. Read every existing `.gitignore` (root and package-level). Run `git status --ignored --porcelain` so you do not re-propose files that are already ignored.
5. `git diff --stat` then the actual diffs, grouped by package. Do not stage from memory.

See `references/recon-checklist.md`.

## Submodule vs ignore vs vendor

| Situation | Action |
|---|---|
| Nested repo already a gitlink (`160000`) | Keep it. Bump the recorded SHA if the checkout moved. Parent stores one commit id, not the working tree. |
| Nested clone is a project the user already publishes elsewhere | Submodule if clones of *this* repo need that SHA; otherwise ignore. Never vendor `node_modules` or a 100M+ source tree. |
| Nested clone is only for local typing / browsing (for example a kitty source checkout next to `tab_bar.py`) | Ignore. Do not add a second submodule. |
| Generated caches (`*.json` dumps, lockfiles the user does not run, installer tails) | Ignore or strip. |

Do not propose "maybe we can try submodules" until recon shows the path is *not* already a submodule.

## Commit sequence

Ignore rules first so later `git add` cannot pick up checkouts.

Then portable-path / username / installer-tail cleanup (LM Studio and similar tools append hardcoded home copies after a portable line already exists — strip the tail, keep `$HOME`).

Then one commit per revertible unit. Match existing conventional-commit style (`feat(scope):`, `fix(scope):`, `chore(scope):`). A commit is too big when two packages or two unrelated reasons share it. A commit is too small when it cannot stand alone (for example a gitignore change that only exists so the next file can be added — that pairing is fine).

Leave untracked:

- Empty stubs (0-byte files the live config does not reference)
- IDE extras that only make sense with an ignored checkout (`pyrightconfig.json` pointing at `./kitty/`)
- Dependency manifests with no lockfile and no runtime role (`package.json` leftover from plugin typing)

If a plan file is written under `.hermes/plans/` inside the repo, add `.hermes/` to that repo's gitignore in the first ignore commit.

## Stow / home-dir trees

When the repo root *is* the Stow package (`.config/`, `.bashrc` at root), new root files will land in `$HOME` on the next stow. Call that out. Do not add `.stow-local-ignore` unless the user uses it.

This user's `~/dotfiles` layout: `references/adikpb-dotfiles.md`.

## Handoff

Show the commit table (message + paths + what each contains) and wait. Offer to execute the sequence. Do not push until they ask. Do not offer a fresh-subagent-per-task implementation loop for "just commit this."
