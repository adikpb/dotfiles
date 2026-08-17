# Hermes plugin packaging: pyproject + pip entry point (2026-08-10)

Verified against the docs guide
(`website/docs/developer-guide/plugins/index.md`) and the loader
(`hermes_cli/plugins.py`) at Hermes v2026.8.3. Committed at `412239c` (repo
root cleanup), 158 tests green, `uv pip install -e .` round-trip verified.

## Two installation styles, one codebase

1. **Directory plugin** (repo cloned into `~/.hermes/plugins/<name>`):
   `plugin.yaml` manifest + root `__init__.py` with `register(ctx)`. No
   pyproject needed (docs: "Directory plugins (no pyproject.toml needed)").
   Loader imports the root `__init__.py` AS `hermes_plugins.<slug>`
   (plugins.py:1873 — slug = manifest key, dashes->underscores), then calls
   `register(ctx)`.
2. **Pip / entry-point plugin**: `pyproject.toml` with
   ```toml
   [project.entry-points."hermes_agent.plugins"]
   hermes-opencode = "hermes_opencode"
   ```
   `ep.load()` imports the module (`importlib.metadata`), and the loader
   calls `getattr(module, "register", None)` (plugins.py:1791) — so the
   entry MODULE (the package `__init__.py`) MUST expose `register(ctx)`.

## Single-implementation pattern (CORRECTED 2026-08-10)

- `register()` lives in the package: `hermes_opencode/__init__.py`, and ALL
  package-internal imports are RELATIVE (an absolute
  `from hermes_opencode.bridge import Bridge` inside it fails the same way
  the shim's did — keep `register()`'s lazy imports relative).
- Repo-root `__init__.py` is a SHIM: `__version__` constant + `register(ctx)`
  with a RELATIVE-FIRST, absolute-fallback import INSIDE the function body:
  ```python
  def register(ctx):
      try:
          from .hermes_opencode import register as _register
      except ImportError:
          from hermes_opencode import register as _register
      return _register(ctx)
  ```
  Contexts: directory loader (`hermes_plugins.<slug>`, plugin dir on
  `__path__` but NOT on sys.path — absolute fails, relative resolves);
  pytest bare top-level import (relative raises ImportError, fallback
  resolves via cwd on sys.path); pip entry point (shim unused).
- Module level must stay import-free: pytest imports a root `__init__.py` as
  a bare top-level module `__init__` when `tests/` has its own `__init__.py`
  (parent-package resolution). A top-level relative import
  (`from .hermes_opencode import ...`) there = 158 collection errors.
- **The earlier \"absolute is harmless\" guidance was WRONG** — the absolute
  form can never load as a directory plugin and fails SILENTLY at runtime
  (see `hermes-plugin-loader-symlink-2026-08-10.md`).
- Directory-plugin loader naming (`hermes_plugins.<slug>`) means there is
  NO self-import collision — the shim is not the `hermes_opencode` module.

## Pitfalls (each cost a real failure this session)

- **PEP 639 license conflict**: setuptools rejects `license = "MIT"` (SPDX
  expression) together with a `License :: OSI Approved :: MIT License`
  classifier — `uv pip install -e .` fails with "License classifiers have
  been superseded by license expressions (PEP 639)". Keep exactly one (the
  expression).
- **Editable install leaves `hermes_opencode.egg-info/` in the repo root**
  and a blanket `git add -A` COMMITS it. Fix: `*.egg-info/` in .gitignore +
  `git rm -r --cached hermes_opencode.egg-info` + remove the dir.
- **`plugin.yaml` `provides_tools` must exactly equal the tool registry**
  names — after deleting a tool (e.g. `opencode_questions`), the manifest
  must drop it too or the manifest lies.
- **Temp verify scripts run from TMPDIR**: `python /tmp/script.py` puts the
  SCRIPT's dir on sys.path, NOT the cwd — `import hermes_opencode` fails
  with ModuleNotFoundError unless the script does
  `sys.path.insert(0, repo_root)`.

## Verification recipe (round-trip)

```bash
uv pip install -e . --python .venv/bin/python
# check: entry_points().select(group="hermes_agent.plugins") has
#   ('hermes-opencode', 'hermes_opencode'); ep.load() callable register()
# simulate directory style: importlib.util.spec_from_file_location(
#   "hermes_plugins.hermes_opencode", "__init__.py",
#   submodule_search_locations=["."]) ... call m.register(FakeCtx()) and
#   compare registered tools vs TOOL_REGISTRY and plugin.yaml provides_tools
uv pip uninstall hermes-opencode --python .venv/bin/python
```

## Housekeeping side effect

The repo's AGENTS.md (clonedeps pointer note) was deleted at the user's
request ("get rid of the agents.md"). The `.slim/clonedeps/...` clone info
lives on in `.ignore`/`.gitignore` rules; nothing else referenced AGENTS.md.