---
name: diagnose-hermes-tool-availability
description: "Diagnose Hermes tool issues: unavailable tools (config, registry, check_fn, cache chain, env bridge) and truncated/misbehaving output (source-level hardcoded limits, tool_output config caps)."
version: 1.1.0
author: Hermes Agent
tags: [hermes, debugging, troubleshooting, tools, check_fn, truncation, vision]
---

# Diagnose Hermes Tool Availability

When a tool configured in `platform_toolsets` is not available to the agent,
it is almost always one of three things: the **toolset filter** excluded it,
the per-tool **check_fn** rejected it, or the **check_fn cache** served a
stale `False` that locked the tool out at session creation.

## Quick Triage

1. **Is the toolset enabled?** — Check `platform_toolsets.cli` in
   `~/.hermes/config.yaml`. TUI sessions resolve via
   `_load_enabled_toolsets()` → `_get_platform_tools(cfg, "cli")`.

   **⚠️ Important:** The TUI gateway hardcodes `"cli"` as the platform
   for tool resolution, even though the system prompt may say
   `Platform: tui`. Always check `platform_toolsets.cli`, **not**
   `platform_toolsets.tui` — the latter has no effect on TUI sessions.

2. **Is the tool registered?** — Import `tools.registry` and check
   `registry._entries` for the tool name.

3. **Does the check_fn pass?** — Import the tool's check function and call
   it directly. If it returns `True` in a fresh Python process, the gate is
   open and something else (caching, below) is at play.

## The check_fn Cache (Most Common Root Cause)

Tools register with an optional `check_fn` callable that gates availability.
The registry wraps every check_fn call in `_check_fn_cached()` with a
**30-second TTL cache** (`_CHECK_FN_TTL_SECONDS = 30`).

### The trap

If the check function returns `False` once (transient glitch, startup race,
import hiccup), the result is cached for 30 seconds. Tool definitions are
computed **once per AIAgent initialization** — a session that starts within
that 30-second window inherits the cached `False` and never re-probes. The
tool is locked out for the entire conversation.

A **60-second grace window** (`_CHECK_FN_FAILURE_GRACE_SECONDS = 60`) means:
if a check fails within 60 seconds of a previous success, the failure is
treated as a flake and the last-good value is returned instead — but only
when there *was* a prior success to fall back on.

### Diagnosis

Check `~/.hermes/logs/agent.log`:

```
WARNING tools.registry: check_fn check_terminal_requirements
        returned False; dependent tools will be unavailable this turn
```

- **"returned False"** — the check function completed normally (no exception)
- **"raised"** — the check function threw an exception
- If you see neither, the tool was excluded at the toolset level

Cross-reference the log timestamp against your session start time. If the
last `returned False` was within 30 seconds of session creation, a stale
cache is the root cause.

### Fix

Start a new session. The cache expires in 30 seconds. A fresh probe will
re-evaluate and (assuming the check function passes) the tool will appear.

## The Trace Chain (Deep Investigation)

### 1. Config → Toolset Resolution

```yaml
# ~/.hermes/config.yaml
platform_toolsets:
  cli:
    - terminal      # this must include the tool's toolset
```

For TUI sessions, `_load_enabled_toolsets()` in `tui_gateway/server.py`
reads `platform_toolsets.cli` (via `_get_platform_tools`). It also checks
`HERMES_TUI_TOOLSETS` env var for manual overrides.

### 2. Registration

Each tool auto-registers via `registry.register()` in its source file:

```python
# tools/terminal_tool.py
registry.register(
    name="terminal",
    toolset="terminal",
    check_fn=check_terminal_requirements,
    ...)
```

List all registered tools:
```python
from tools.registry import registry
print(sorted(registry._entries.keys()))
```

### 3. Environment Bridging

The terminal tool reads config via `_ensure_terminal_env_bridged()` which
copies `terminal.*` config values to `TERMINAL_*` env vars if they are not
already set. If `TERMINAL_ENV` is already in `os.environ`, the bridge is a
no-op.

The check function reads `env_type` from `_get_env_config()`:
```python
env_type = os.getenv("TERMINAL_ENV", "local")
```

If `env_type == "local"`, `check_terminal_requirements()` returns `True`
immediately (no Docker/SSH/Modal probe needed).

### 4. Same-Toolset, Different Availability

Tools in the same toolset can have different check_fn requirements:

| Tool | check_fn | Available when |
|------|----------|----------------|
| `process` | None | Always (when toolset enabled) |
| `terminal` | `check_terminal_requirements()` | `TERMINAL_ENV=local` (or Docker/SSH/etc. met) |
| `read_terminal` | `env_var_enabled("HERMES_DESKTOP")` | Only in desktop GUI |
| `close_terminal` | `env_var_enabled("HERMES_DESKTOP")` | Only in desktop GUI |

If `process` is available but `terminal` is not, the toolset is enabled but
the check_fn for `terminal` is rejecting it.

### 5. Sandbox vs Main Process

`execute_code` runs in a sandbox subprocess with its own Python import
state. The `_check_fn_cache` is per-process (fresh = empty in sandbox).
The check function may pass in the sandbox but have failed in the main
process — logs are the authoritative record of the main process behavior.

### 6. TUI Env Propagation Chain (Python → Node.js → Python Gateway)

The TUI launch chain involves three processes carrying env vars:

```
Python launcher (hermes_cli/main.py:_launch_tui)
  └─ builds env dict with TERMINAL_ENV=local
  │  (apply_terminal_config_to_env(env=env))
  └─ subprocess.call(argv, env=env)  →  Node.js TUI
       └─ spawns Python subprocess (tui_gateway/entry.py)
            └─ check_terminal_requirements() reads os.getenv("TERMINAL_ENV")
```

**The gap:** The Python launcher passes its `env` dict to Node.js, but Node.js
spawns the Python gateway subprocess with *its own* environment — which may or
may not include the launcher's `TERMINAL_ENV=local`. If the var is lost across
this hop, the `_ensure_terminal_env_bridged()` fallback should set it from
config — but only on **first call** (see `_terminal_config_bridge_attempted`
pitfall below).

**Diagnosis:** Instrument `check_terminal_requirements()` with a debug log of
the actual `env_type` value it reads (`logger.info("env_type=%r", env_type)`).
A missing `TERMINAL_ENV` combined with a silent bridge failure is
indistinguishable from a stale cache at the aggregate log level.

### 7. coding_selection() Silent Toolset Collapse

When the agent sits in a repository directory with project context files
(AGENTS.md, CLAUDE.md, .cursorrules), `coding_selection()` can return a
narrowed toolset (typically `["coding", "project"]`) that **excludes
`terminal`**. This happens inside `_load_enabled_toolsets()` at the
`if not explicit:` branch in `tui_gateway/server.py`, **before** the fallback
to `_get_platform_tools()` — so the configured `platform_toolsets.cli` list
is never consulted.

**Diagnosis:** Check if the session CWD is inside a repo with project context
files. If so, the toolset may have been collapsed by coding posture, not by
a check_fn failure. Move outside the repo or pass `--toolsets all` to bypass.

## Workaround: If you can't wait for a fix

When tools are gated and starting a new session isn't practical, see
`references/execute-code-workaround.md` — it covers writing/reading files
and running shell commands via Python stdlib inside `execute_code`, a
reliable fallback when `terminal`, `read_file`, `write_file`, or `patch`
are unavailable.

For a full walkthrough of a TUI tool-availability investigation (config
check → code path tracing → platform registry audit → GitHub issue
search), see `references/tui-full-investigation-case-study.md`. This is
a good template for structuring your own investigation.

## Tool Output Truncation

When a tool returns successfully but the result is cut short, the truncation
is happening at one of these layers:

| Layer | Limit | Config key |
|-------|-------|------------|
| `tool_output.max_bytes` | 50,000 chars (terminal-only) | `tool_output.max_bytes` |
| `tool_output.max_lines` | 2,000 lines (read_file limit clamp) | `tool_output.max_lines` |
| `tool_output.max_line_length` | 2,000 chars/line (read_file view) | `tool_output.max_line_length` |
| Vision aux model `max_tokens` (hardcoded) | 2,000 tokens | NOT configurable — must patch source |

### Vision Tool Truncation (Legacy Aux Path)

When the main model is text-only (no native vision), both `vision_analyze`
and `browser_vision` fall through to the auxiliary vision LLM, which
describes the image and returns the description as text. That text can be
**silently truncated** at a hardcoded ceiling.

**Key finding:** Both `tools/vision_tools.py` and `tools/browser_tool.py`
read `auxiliary.vision.timeout` and `auxiliary.vision.temperature` from
config, but both have a **hardcoded `max_tokens: 2000`** that is never
sourced from config:

| File | Line (v0.19.0) | Value |
|------|----------------|-------|
| `tools/vision_tools.py` (legacy aux path) | ~1249 | `"max_tokens": 2000` |
| `tools/browser_tool.py` (browser_vision) | ~4328 | `"max_tokens": 2000` |
| `tools/vision_tools.py` (video_analyze) | ~1755 | `"max_tokens": 4000` |

**Symptom:** On a text-only main model (e.g. DeepSeek V4), vision tool
results appear incomplete — descriptions end mid-sentence for complex images
(dashboards, UIs, multi-panel screenshots). Simple images fit fine.

**Diagnosis:**
1. Check the main model — if it is text-only, the native vision fast path
   is bypassed and the aux path is used.
2. Confirm by checking `_should_use_native_vision_fast_path()` in
   `tools/vision_tools.py` — returns `False` for text-only models.
3. The hardcoded limit is in the `call_kwargs` dict inside
   `vision_analyze_tool()` and `browser_vision`'s screenshot handler.
4. The `timeout` and `temperature` are already configurable (read from
   `auxiliary.vision.*` in config.yaml), but `max_tokens` is not.

**Fix:** Patch both files to read `auxiliary.vision.max_tokens` from
config.yaml, with a fallback to the existing hardcoded value. Add the
config key to your `auxiliary.vision` section:

```yaml
auxiliary:
  vision:
    max_tokens: 8000   # increase from default 2000
```

See `references/vision-tool-truncation.md` for exact code locations and
patch patterns.

### GitHub Cross-Reference Workflow

When a tool behavior issue is identified in source code (hardcoded limits,
missing config passthrough, incorrect routing), check whether it was already
reported or fixed upstream before patching locally. A merged PR does **not**
guarantee the fix covers the code path you're looking at.

Use `gh` CLI to cross-reference:

```bash
# 1. Find related issues
gh issue list --repo NousResearch/hermes-agent --state all --search "max_tokens vision" --limit 10 --json number,title,state,url

# 2. Find related PRs by file or keyword
gh search prs --repo NousResearch/hermes-agent "vision_tools max_tokens" --limit 10 --json number,title,state,url

# 3. Verify a merged PR actually touches the files you care about
gh pr view 34845 --repo NousResearch/hermes-agent --json files | python3 -c "import sys,json;[print(f['path']) for f in json.load(sys.stdin)['files']]"

# 4. Read issue comments for resolution outcome
gh issue view 34087 --json comments,state,closedAt
```

**Key gotcha:** A fix in a central module (e.g. `agent/auxiliary_client.py`)
does NOT fix tools that build their own `call_kwargs` dicts manually
(e.g. `tools/vision_tools.py`, `tools/browser_tool.py`). Always verify a
PR's file list against the code paths you traced.

**When to create a new issue vs patch locally:**
- Issue exists and is **OPEN** → the fix is not in any release; add a
  comment or create a PR yourself.
- Issue exists and is **CLOSED** → check if the linked PR touched the files
  you found. If not, the fix was incomplete — reopen or file a new issue
  referencing the old one.
- No issue exists → file one with the exact code location, config snippet,
  and reproduction steps.

## Key Code Locations

| Component | File |
|-----------|------|
| Tool registration | `tools/<tool_name>.py` |
| Registry + check_fn cache | `tools/registry.py` (`_check_fn_cached`, `get_definitions`) |
| TUI toolset resolver | `tui_gateway/server.py` (`_load_enabled_toolsets`) |
| Config-to-env bridge | `tools/terminal_tool.py` (`_ensure_terminal_env_bridged`) |
| Toolset definitions | `toolsets.py` (`TOOLSETS`, `_HERMES_CORE_TOOLS`) |
| Platform toolset resolver | `hermes_cli/tools_config.py` (`_get_platform_tools`) |
| TUI launcher (env build) | `hermes_cli/main.py` (`_launch_tui`, `_normalize_tui_toolsets`) |
| Platform registry | `hermes_cli/platforms.py` (`PLATFORMS` — `tui` is NOT registered) |
| Coding posture | `agent/coding_context.py` (`coding_selection`) |
| Agent tool init | `model_tools.py` (`_compute_tool_definitions`) |

## Pitfalls

- **Env vars differ between processes.** What `execute_code` sees is not
  what the main gateway process sees. Rely on logs, not sandbox tests.
- **The check_fn cache is per-process.** Starting a new TUI gateway (or
  waiting 30+ seconds between sessions) clears the stale cache.
- **`coding_selection()` narrows tools** when sitting in a code repo with
  project context files. Move outside the repo or pin toolsets explicitly.
- **`HERMES_TUI_TOOLSETS` overrides everything.** If set, the auto-detected
  toolset from config is bypassed entirely.
- **`.env` file silently overrides the config bridge.** `~/.hermes/.env`
  is loaded by `run_agent` DURING agent initialization, AFTER the TUI
  gateway's config bridge has already set `TERMINAL_ENV=local`. If `.env`
  sets `TERMINAL_ENV=docker` (or any non-`local` value), the config's
  `terminal.backend` is neutralized and `check_terminal_requirements()`
  will fail if that backend's requirements (Docker daemon, SSH config,
  etc.) are unmet. The agent.log line `Loaded environment variables from
  .../.env` at startup is the diagnostic clue. **`ps eww -p PID` shows
  the spawn-time environment, NOT runtime `os.environ` mutations** —
  trust logs, not `ps`, for runtime env state.

- **`_terminal_config_bridge_attempted` is a one-shot global flag.** The
  env bridge (`_ensure_terminal_env_bridged()`) sets it to `True` BEFORE
  attempting the config read. If `apply_terminal_config_to_env()` fails
  (caught at DEBUG level), subsequent calls skip bridging entirely — the
  flag is already `True`. This means a transient config-load failure at
  startup permanently disables the bridge, and `TERMINAL_ENV` won't be
  backfilled from config on later probes.
- **TUI platform string mismatch.** The TUI gateway always resolves tools
  via `_get_platform_tools(cfg, "cli")`, but the system prompt reports
  `Platform: tui`. If you are debugging missing tools in a TUI session,
  ignore the displayed platform and check `platform_toolsets.cli`.
  The `tui` platform is NOT registered in `hermes_cli/platforms.py`'s
  `PLATFORMS` dict — a known code gap that does not affect tool resolution
  (because the TUI gateway bypasses it), but one that misleads investigators.
- **`-tui` vs `--tui` CLI flag (Hermes < v0.19.0).** In older versions,
  `hermes -tui` (single dash) was parsed as `-t ui`, silently setting
  the toolsets override to the unknown value `ui`, resulting in 0 tools.
  Fixed by PR #33313. If you're on an older version, always use `--tui`.
- **Log silence can mislead.** If `check_terminal_requirements()` returns
  `False` but the log does NOT show "Unknown TERMINAL_ENV" or "Terminal
  requirements check failed", then `env_type` WAS `"local"` — meaning the
  failure came from the **cached** result, not from the function itself.
  A fresh probe (new process, or wait 30s) would return `True`.
- **The grace window needs a prior success.** The 60-second
  `_CHECK_FN_FAILURE_GRACE_SECONDS` only helps when there was a *previous*
  True result. If the very first probe fails (e.g. fresh gateway startup),
  there's no last-good to fall back on — the False is cached directly.
