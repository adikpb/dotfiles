# Hermes Plugin Load Path (verified 2026-08-11, hermes-opencode plugin)

Companion to `references/hermes-plugin-surface.md` (the loader CONTRACT). This file
is the load-path REALITY: what breaks at runtime, how to prove a plugin actually
loads, and the dev-loop that makes installed copies unnecessary.

## 1. The silent-load failure: top-level absolute self-imports

The directory loader (`hermes_cli/plugins.py`, `_load_directory_module`) imports
the plugin root as the synthetic `hermes_plugins.<slug>` package:

```python
spec = importlib.util.spec_from_file_location(
    module_name, os.path.join(plugin_dir, "__init__.py"),
    submodule_search_locations=[plugin_dir])
```

`plugin_dir` becomes the package's search location, and the dir is **never
inserted into `sys.path`**. Consequences:

- A plugin whose root `__init__.py` or internal modules import themselves by
  top-level name (`from hermes_opencode import register` in the root shim,
  `from hermes_opencode.bridge import Bridge` inside `register()`) raises
  `ModuleNotFoundError` **at load time**.
- The loader catches the exception into `loaded.error`. `hermes plugins list`
  still shows the plugin (manifest read succeeds); the tools never register.
  The only symptom is an ERROR line in `~/.hermes/logs/agent.log` — or silence.
- **Tests and E2E smokes mask it**: pytest runs from the repo root (cwd is on
  sys.path as `''`), and ad-hoc smoke scripts do `sys.path.insert(0, base)`.
  The live runtime has neither. A plugin can pass 160+ tests for weeks and
  never have loaded once in production.

### Fix pattern (shim + package)

Root `__init__.py` shim — relative-first with absolute fallback, lazily inside
`register()`:

```python
def register(ctx) -> None:
    try:
        from .hermes_opencode import register as _register   # loader context
    except ImportError:
        from hermes_opencode import register as _register   # pytest context
    return _register(ctx)
```

Why the fallback: pytest imports the root as a bare top-level module (repo root
as package root, because `tests/` has its own `__init__.py`), where a relative
import raises `ImportError("attempted relative import with no known parent
package")` — so the shim must not do a plain relative import either. The lazy
import inside `register()` keeps the module-level import-free (required for
pytest collection). Package-internal imports must be relative
(`from .bridge import Bridge`), which resolves in every context: top-level
package, `hermes_plugins.<slug>` subpackage, pip entry point.

## 2. Verification: loader replication (the only honest check)

`hermes plugins list` reads the manifest and does NOT prove `register()` ran.
Replicate the loader in a subprocess with a scrubbed sys.path:

```python
# child (run via sys.executable so the venv is inherited)
os.chdir("/tmp")                      # neutral cwd
sys.path = [p for p in sys.path if p not in ("", "/repo/root")]  # scrub
spec = importlib.util.spec_from_file_location(
    "hermes_plugins.hermes_opencode", "/path/to/plugin/__init__.py",
    submodule_search_locations=["/path/to/plugin"])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)
module.register(FakeCtx())
# FakeCtx must expose the REAL contract: register_tool(name, schema, handler, emoji=None, **kw)
# and config={"auto_serve": False} so a Bridge start does not spawn a real server.
```

Assert the expected tool names land in the fake registry, assert rc 0. Run it
from `execute_code`/terminal with the venv python; parent asserts returncode.
Keep it as a regression test in the plugin's suite (subprocess isolation avoids
polluting the pytest process's import state).

## 3. Symlink dev-loop (no copy/sync ritual)

Replace the installed clone with a symlink to the dev repo:

```bash
rm -rf ~/.hermes/plugins/<slug> && ln -s /path/to/repo ~/.hermes/plugins/<slug>
```

- The loader follows the symlink (`Path.exists()`, `submodule_search_locations`
  all resolve through it) and reads the dev tree live — commits land in the
  runtime without any fetch/checkout sync.
- Verified: `hermes_cli/plugins.py` contains zero git operations (no clone/
  pull/fetch in the loader), so a symlinked repo gets no surprise git writes.
- Workspace hygiene: keep the repo tree identical to what an install would
  clone (root `__init__.py` + `plugin.yaml` present); gitignored subdirs
  (e.g. `wiki/`) are invisible to the loader and stay local.
- Pre-swap check: confirm installed HEAD == repo HEAD (`git -C <both> rev-parse
  --short HEAD`) so the swap loses nothing.

## 4. TUI agent+gateway double-load topology

A Hermes TUI session loads a plugin TWICE (agent context + gateway context;
symptom: the same config-warning line appears twice ~2s apart in agent.log).
Any load-time side effect runs twice. For plugins that spawn a server:

- Two `auto_serve` spawns on one port → second spawn dies EADDRINUSE, printed
  as opencode's generic "Error: Unexpected error" + "ServeError" AFTER its
  listening banner (opencode prints the banner before the bind succeeds).
- Fix pattern (probe-first): before spawning, health-check the configured
  endpoint — healthy server with matching auth ⇒ ATTACH (reuse); unreachable ⇒
  spawn; auth mismatch ⇒ hard fail (never attach to a server whose credentials
  don't match, never spawn into an occupied port).

## 5. Debugging serve-spawn failures (opencode-specific notes)

- The spawned process's stdout+stderr merge into `hermes-opencode-serve-*.log`
  under TMPDIR; the plugin UNLINKS it on failure paths (banner timeout, health
  fail), so a crashed spawn's log may be GONE by the time you look. A surviving
  file is usually from a PREVIOUS successful spawn — don't misattribute it.
- opencode's own error log: `~/.local/share/opencode/log/opencode.log`
  (tracebacks for "Unexpected error" land there).
- **Timing tells**: "bridge down: cannot reach … Connection refused" appearing
  ~2ms after the config warning means NO spawn attempt happened (spawn takes
  ~1s to banner) — the PROBE path failed, not the spawn.
- **Which binary**: `which opencode` / `ps` may show `/opt/homebrew/bin/opencode`
  while `/usr/local/bin/opencode` is a stale or absent install; a manual repro
  via the wrong path yields empty output and a misleading rc.
- **Exception-layer trap**: a health check that wraps connection errors into a
  broader exception class (e.g. `ServeAttachError`) defeats callers that catch
  the narrow type (`OpenCodeError`) — probe-first code then never spawns and
  the "bridge down" error is instant. Keep the low-level checker propagating
  raw `AuthRequired`/`OpenCodeError`; wrap into friendly messages at call sites
  (attach path, post-spawn check). A readiness loop must tolerate exceptions
  per attempt, not on first failure.
