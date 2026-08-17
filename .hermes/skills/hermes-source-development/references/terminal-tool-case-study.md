# Terminal Tool Case Study

## Symptom

The `terminal` tool was not available to the agent, but `process` (same
toolset) was. Both appeared in `registry._entries`. The config had
`terminal.backend: local` and `TERMINAL_ENV=local` was set.

## Trace

### 1. Config correct

`~/.hermes/config.yaml` had `terminal: {backend: local}` and
`platform_toolsets.cli` included `terminal`. ✓

### 2. Registration correct

`registry._entries` contained `terminal`, `process`, `close_terminal`,
`read_terminal`. ✓

### 3. check_fn returned False in main process

Logs at `~/.hermes/logs/agent.log`:

```
2026-07-27 21:38:54,946 WARNING tools.registry: check_fn
  check_terminal_requirements returned False;
  dependent tools will be unavailable this turn
```

The message said "returned False" (not "raised"), meaning the function
completed normally without an exception.

### 4. check_fn returned True in sandbox

```python
from tools.terminal_tool import check_terminal_requirements
print(check_terminal_requirements())  # True
```

This ruled out a code bug — the function works when called fresh.

### 5. Cache timing match

| Event | Time |
|-------|------|
| `check_fn` returned False | 21:38:54 |
| Session started | 21:39:11 (session `20260101_120000_xxxxxx`) |
| Gap | **17 seconds** (within 30s TTL) |

The session's agent tools were initialized within the 30-second TTL window
after the failed check, inheriting the cached `False`.

## Root Cause

The `_check_fn_cached` in `tools/registry.py` cached a `False` result from
`check_terminal_requirements()` at 21:38:54. The `AIAgent` was created at
21:39:11 — 17 seconds later, still within the 30-second `_CHECK_FN_TTL_SECONDS`.

The check function had returned `False` once (possibly a transient issue
at the prior session's teardown or during gateway initialization), and the
cache poisoned every subsequent session creation within the window.

## Fix

Closed the session and started a fresh one. With >30s elapsed, the cache
expired and the next probe returned `True`.

## Preventive Notes

- A new TUI gateway start clears the in-memory cache (fresh process).
- Waiting 30+ seconds between sessions avoids stale cache inheritance.
- The `_CHECK_FN_FAILURE_GRACE_SECONDS = 60` grace period only helps when
  there was a *prior success* — it does not help when the very first probe
  fails.

---

## Extended Investigation: Deeper Architecture Gaps

In a follow-up investigation, the following non-obvious architecture points
were surfaced (none turned out to be the *immediate* cause, but each is a
potential future root cause):

### TUI Env Propagation Chain

The TUI launch chain involves **three processes**:

```
Python launcher (hermes_cli/main.py:_launch_tui line 2189)
  └─ env = os.environ.copy()
  │  apply_terminal_config_to_env(env=env)  → sets TERMINAL_ENV=local in env dict
  └─ subprocess.call(argv, env=env)          → Node.js TUI (ui-tui/dist/entry.js)
       └─ Node.js spawns Python gateway subprocess (tui_gateway/entry.py)
            └─ check_terminal_requirements() reads os.getenv("TERMINAL_ENV")
```

**The gap:** The Python launcher passes its `env` dict to `subprocess.call`,
which the Node.js TUI inherits. But Node.js may spawn the Python gateway
subprocess with *its own* environment — not guaranteed to include the
launcher's `TERMINAL_ENV`. If the var is lost:
- `_ensure_terminal_env_bridged()` should backfill from config
- But it only runs once (one-shot `_terminal_config_bridge_attempted` flag)
- If the bridge fails silently (exception caught at DEBUG level), the flag
  stays True forever, and subsequent bridge attempts are skipped

**Key source lines:**

| File | Line(s) | Purpose |
|------|---------|---------|
| `hermes_cli/main.py` | 2211-2214 | Build env dict, apply terminal config |
| `hermes_cli/main.py` | 2319 | `subprocess.call(argv, env=env)` → Node.js |
| `tools/terminal_tool.py` | 1333-1335 | `_terminal_config_bridge_attempted` guard |
| `tools/terminal_tool.py` | 1343-1346 | Silent catch: bridge failure logged at DEBUG |
| `tools/terminal_tool.py` | 1353-1354 | `_get_env_config()` calls bridge + reads env |

### Log Silence Analysis

When investigating a "returned False" log line, check what was NOT logged:

| Log message seen | What it means |
|---|---|
| `check_fn ... returned False` | Function ran normally, returned False |
| `check_fn ... raised` | Function threw exception, caught as False |
| (none of the above) | Tool excluded at toolset level |
| **Absence of:** `Unknown TERMINAL_ENV '...'` | env_type WAS "local" — failure came from cache |
| **Absence of:** `Terminal requirements check failed: ...` | Exception path NOT triggered |

If `env_type` was any value other than "local" (docker, ssh, modal, etc.),
the function would log either "Unknown TERMINAL_ENV" or one of the backend-
specific error messages. The complete absence of any such log means
`os.getenv("TERMINAL_ENV", "local")` returned `"local"` — the function
*succeeded* but the cached value was stale False.

### _terminal_config_bridge_attempted Race

The global flag is set to True **before** the try block:

```python
_terminal_config_bridge_attempted = True   # ← set BEFORE bridge attempt
try:
    apply_terminal_config_to_env(env=None, override=False)
except Exception:
    logger.debug("terminal config → env fallback bridge failed", exc_info=True)
```

If `apply_terminal_config_to_env()` raises (config parse error, import
failure, yaml error), the flag is already True and **no subsequent call
will ever retry the bridge**. The env var remains whatever it was — or
absent, falling back to `os.getenv("TERMINAL_ENV", "local")` default.

### Reference: Can check_terminal_requirements() actually return False?

The function only returns False in these branches:

1. `env_type == "docker"` → docker not found or `docker version` fails
2. `env_type == "singularity"` → apptainer/singularity not found
3. `env_type == "ssh"` → TERMINAL_SSH_HOST or TERMINAL_SSH_USER missing
4. `env_type == "modal"` → various modal setup failures
5. `env_type == "daytona"` → DAYTONA_API_KEY not set
6. `else` → Unknown env_type value

Notably, `env_type == "local"` always returns True (no conditions).
