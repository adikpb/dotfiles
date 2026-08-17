# Plugin repo release prep (2026-08-10, hermes-opencode)

Steps taken to take the hermes-opencode plugin repo from dev state to
GitHub-ready. Reuse for this repo (or any Hermes directory plugin).

## 1. Scrub iteration-marker comments from SHIPPED code only

Patterns to find: `\b[RF][0-9]+[a-z]?\b` (R1..R7, F1..F3), `\bt1[0-9]\b`,
`P2`, `round-N audit`, `audit F<N>`. They appear in module docstrings
(`"""R6 session reading..."""`), inline comments (`# F2: ...`), and log
strings. **The in-repo wiki KEEPS its R-tags**: it is the internal
requirements contract (`wiki/plugin-requirements.md` IS the R1-R7 spec),
gitignored, never pushed — do not scrub it.

Scrub checklist: keep the meaning, drop the tag ("per R6" → "per the read
contract"). Touch module docstrings, inline comments, logger strings, and
test docstrings; then re-grep the shipped paths (`hermes_opencode`, `tests`,
`__init__.py`, README, plugin.yaml) to confirm zero hits.

## 2. Author + license

- `plugin.yaml` `author:` field → the release identity (e.g. `adikpb`).
- Add `LICENSE` (MIT, `Copyright (c) <year> <author>`) — opencode itself is
  MIT, so it matches the ecosystem default.

## 3. Drop scratch diagnostics

One-off probe/diag scripts (`probe_*.py`, `diag*_e2e.py`) are debugging
artifacts: they embed hardcoded paths, test credentials, and ad-hoc timing.
DELETE them before release. Keep the real test harness (`e2e_smoke.py`) —
verify it generates its own password (no hardcoded Basic header).

## 4. Rewrite unpushed commit authors (rebase --root --exec)

Only safe while nothing is pushed. Order matters:

1. Commit ALL pending changes FIRST (`git add -A && git commit`) — the
   rebase refuses to run with a dirty tree (`cannot rebase: You have
   unstaged changes`).
2. `git rebase --root --exec 'git commit --amend --no-edit --author="<Name> <<email>>"'` —
   `--exec` applies the amend to EVERY commit. Use the GitHub noreply address
   (`<user>@users.noreply.github.com`) when no personal email is known.
3. Set repo-local identity: `git config user.name <Name>` and `user.email`
   (repo-local only; never touch global config).

## 5. Refresh the INSTALLED plugin copy after SHA-rewrites

The installed clone (`~/.hermes/plugins/<id>`) is on the OLD history;
SHA-rewriting makes the old HEAD NOT an ancestor of the new head, so a
plain `git pull` would create a divergent merge. Because plugin enable state
and config live in `config.yaml` (keyed by plugin id), NOT inside the plugin
dir, a hard reset is safe:

```
git -C ~/.hermes/plugins/hermes-opencode fetch origin
git -C ~/.hermes/plugins/hermes-opencode reset --hard origin/main
```

Then verify: `git rev-parse --short HEAD` matches the repo, plugin.yaml
author, and `hermes plugins list` still shows ENABLED.

## 6. Verify with the inherited-environment rule

- `ruff check` lints PYTHON only: passing `plugin.yaml`/`README.md`/`LICENSE`
  to it parses YAML/MD as Python and floods E501/syntax noise. Lint
  `hermes_opencode tests scripts __init__.py` only.
- Subprocess pytest runs MUST INHERIT the environment. Overriding `env=` with
  only `PATH`/`HOME` drops `PYTHONPATH`, which carries `~/.hermes/hermes-agent`
  — the import source of `tools` and `hermes_cli` modules. Stripped env →
  16 spurious `ModuleNotFoundError: No module named 'tools'` failures (the
  tools `from tools.registry import tool_result` at call time). A `python -c
  "import tools"` check passes (inherited env) while the stripped-env pytest
  fails — that mismatch is the tell.
- Trailing-newline verification (wiki log entries): `od -c` output is
  ambiguous — its bare offset columns tokenize as pseudo-bytes and the final
  `\n` can sit on an offset-only line. Read the last byte directly:
  `open(f, "rb").seek(-1, 2); assert fh.read(1) == b"\n"`.
- Final gate: full suite + ruff + the E2E smoke (6/6) re-run after the
  comment scrub, then `git log --format=%h|%an|%s` to show the rewritten
  history.