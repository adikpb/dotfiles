# Hermes directory-plugin loader contract + symlink install (2026-08-10)

Found while symlinking the installed copy; the swap exposed that the plugin
had NEVER actually loaded live as a directory plugin. Committed at `dbd1090`
with `tests/test_shim.py` as the regression guard.

## Loader contract (hermes_cli/plugins.py at v2026.8.3)

- Directory plugins import via
  `spec_from_file_location("hermes_plugins.<slug>", <dir>/__init__.py,
  submodule_search_locations=[<dir>])` (plugins.py:1873) — the plugin dir
  becomes the module's `__path__`, and **nothing ever adds it to
  `sys.path`** (zero `sys.path.insert`/addsitedir for plugins anywhere in
  hermes_cli).
- The package is likewise NOT in the runtime's site-packages unless the
  user pip-installed it separately.
- Consequence: **any top-level absolute self-import inside the plugin
  fails** — `from hermes_opencode import register` in the root shim AND
  `from hermes_opencode.bridge import Bridge` inside `register()` both
  raise `ModuleNotFoundError: No module named 'hermes_opencode'`.

## Silent failure modes (why tests never caught it)

- pytest runs with the repo root on `sys.path` (cwd) → the absolute import
  works in CI and every test; only a live directory load breaks.
- The loader wraps register() errors (plugin marked error/absent tools) but:
  `hermes plugins list` still shows the manifest/entry (it reads the
  manifest, may not exec modules), agent.log gets no obvious plugin line,
  and the hermes session starts "fine" with the plugin's tools just missing.
- `hermes plugins list` is NOT proof of load. Proof = a loader-style import
  with `register()` actually called (or the plugin's tools present in a live
  session).

## The fix (both levels)

- Root shim: relative-first, absolute fallback, imports INSIDE
  `register()`:
  ```python
  try:
      from .hermes_opencode import register as _register
  except ImportError:
      from hermes_opencode import register as _register
  ```
  Contexts: loader (relative resolves via `__path__`), pytest bare
  top-level import (relative raises ImportError → fallback via cwd), pip
  entry point (shim unused), standalone scripts (fallback).
- Package-internal imports: ALL relative (`from .bridge import Bridge`).
- Caveat: run `pytest` after the change — the relative-first shim must not
  regress the bare-top-level collection path (158-error class).

## Regression test recipe (tests/test_shim.py)

Subprocess replication of the loader with a scrubbed environment so the
absolute fallback CANNOT secretly satisfy the test:

1. Child runs with `sys.path` scrubbed of `""`, `os.curdir`, and the repo
   root (`os.path.realpath` compare); `sys.modules` purged of
   `hermes_opencode*` and `hermes_plugins*`.
2. Create the namespace parent (`hermes_plugins` with `__path__=[]`),
   then `spec_from_file_location(...)` on the plugin dir `__init__.py`
   with `submodule_search_locations=[plugin_dir]`, `exec_module`.
3. Fake ctx MUST implement the loader's real contract
   `register_tool(name, schema, handler, emoji=None, **kw)` (collect into a
   dict) — an invented registry API (`add_dynamic_tool`) fails with
   AttributeError at the first real register call.
4. `ctx.config = {"auto_serve": False}` — otherwise register() spawns a
   real `opencode serve` and the event-stream thread floods stderr with
   `IncompleteRead`/`ValueError` noise (fail-soft reconnect is by design;
   keep the test hermetic).
5. Assert sorted registered tool names equal the 5-tool registry.
6. Test-wiring pitfalls that cost four retries: the child script lives in
   an f-string in the parent → every literal `{}` must be `{{}}` (brace
   escaping), and post-write lint (SyntaxError: f-string empty expression)
   catches it; also run `ruff --fix` for the trailing-newline W292.

## Symlink install (user directive, retires the sync ritual)

- `rm -rf ~/.hermes/plugins/hermes-opencode` (was a git clone at the same
  rev) then `ln -s <repo> ~/.hermes/plugins/hermes-opencode`. The loader
  follows symlinks transparently (`Path.exists()` + submodule search
  locations on the symlinked dir; no islink/realpath handling anywhere).
- Benefits: pushes/commits are live immediately; no fetch+checkout after
  every change; `git -C <installed> status` resolves to the repo.
- **Forbidden through the symlink**: `git fetch origin && git reset --hard
  origin/main` (the old peer-install refresh) would destroy dev work in the
  repo. Push instead; the loader sees the new tree on next session.
- The loader never does git ops on plugins (zero git calls in plugins.py),
  so no surprise pulls mutate the dev repo.