# Dirty-tree recon checklist

Run these before proposing commits. All read-only.

```bash
git status -sb
git remote -v
git log --oneline -15
git submodule status
git ls-files -s | awk '$1==160000'
git status --ignored --porcelain
git diff --stat
```

For each untracked or "new commits" path:

```bash
git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null
git -C "$path" remote -v
git -C "$path" status -sb
du -sh "$path" "$path/node_modules" 2>/dev/null
```

Mode `160000` in `git ls-files -s` means the parent already records a submodule SHA. `git submodule status` showing `+<sha>` means the checkout moved; the next parent commit is a pointer bump only.

Also read every tracked `*gitignore*` and the root `.gitmodules` before talking about ignore rules or new submodules.
