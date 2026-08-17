# Build the hermes-opencode plugin to the Hermes plugin standard

Recipes for the "upgrade to latest capability / SOTA, the standard way" class
of task. Drive these from the official docs
(`https://hermes-agent.nousresearch.com/docs/developer-guide/plugins` and
`.../user-guide/features/plugins`), cross-checked against the pinned clones
under `.slim/clonedeps/repos/{NousResearch__hermes-agent,anomalyco__opencode}`.

## 1. `hermes plugins doctor . --ci` — the authoritative build check

Runs the same discovery → manifest parse → import → `register(ctx)` →
tool/hook registry Hermes itself uses, in a temp `HERMES_HOME`, and **blocks
direct network access during registration** to catch accidental network I/O.
`-ci` makes it exit non-zero on error (for CI).

```bash
cd /path/to/hermes-opencode-plugin
hermes plugins doctor . --ci
```

Clean output (6 tools, no hooks):
```
Plugin Doctor: /path/to/hermes-opencode-plugin
  manifest: hermes-opencode 0.2.0 (standalone)
  OK: runtime discovery, manifest parsing, import, and registration passed
  registrations: 7 tool(s), 0 hook(s)
```

**What it catches:** a `register()` that does network/spawn I/O. This plugin
used to call `bridge.start()` (spawns/attaches `opencode serve` + opens the
SSE socket) directly inside `register()`. Under Doctor's network sandbox that
raised inside registration → **`registrations: 0 tool(s)`**. The fix is to
make `register()` fail-soft (see below); after the fix Doctor reports 6 tools
even with no server reachable.

Confirm `config_schema` validation (docs: mismatches warn, never load-fail):
```bash
TMP=$(mktemp -d); cp -r . "$TMP/hermes-opencode"
mkdir -p "$TMP/home/.hermes"
printf 'plugins:\n  enabled: [hermes-opencode]\n  entries:\n    hermes-opencode:\n      settings:\n        port: "not-a-number"\n' > "$TMP/home/.hermes/config.yaml"
HERMES_HOME="$TMP/home" hermes plugins doctor "$TMP/hermes-opencode" --ci
# → still OK, 7 tools (logs a warning naming `port` + expected type)
```

## 2. Fail-soft `register()` (never let a down server abort registration)

```python
def register(ctx) -> None:
    from .bridge import Bridge
    from .tools import TOOL_REGISTRY, set_bridge

    bridge = Bridge(ctx)
    try:
        bridge.start()          # spawns/attaches opencode + opens SSE — network I/O
    except Exception:           # fail-soft: server down/blocked must not abort registration
        logger.warning("bridge failed to start at register time; tools still registered", exc_info=True)
    set_bridge(bridge)

    for name, schema, handler, emoji in TOOL_REGISTRY:
        ctx.register_tool(name=name, toolset="hermes-opencode",
                          schema=schema, handler=handler, emoji=emoji)
    _register_teardown(ctx, bridge)   # ctx.on_unload(lambda: bridge.stop())
```

Rule: `register()` only wires the registry + teardown. Any work that can fail
on a missing/unreachable server goes inside `Bridge.start()` and is caught
there (or here), so tool registration always completes. Tools then report
bridge state at call time.

## 3. Manifest v2 (`plugin.yaml`)

```yaml
name: hermes-opencode
version: 0.2.0
manifest_version: 2
api_version: 1
description: "<accurate — does NOT list surfaces you removed>"
author: adikpb
license: MIT
homepage: https://github.com/adikpb/hermes-opencode-plugin
kind: standalone
tags: [opencode, coding-agent, bridge, delegation]
provides_tools:
  - opencode_prompt
  - opencode_session_tail
  - opencode_session_read
  - opencode_question_reply
  - opencode_command
  - opencode_abort
config_schema:
  auto_serve:   {type: bool,   default: true,  description: "..."}
  hostname:     {type: str,    default: "127.0.0.1", description: "..."}
  port:         {type: int,    default: 4096,  description: "..."}
  tail_size:    {type: int,    default: 8,     description: "..."}
  rule_key:     {type: str,    default: "opencode", description: "..."}
  prompt_timeout: {type: int,  default: 600,   description: "..."}
  attach_reconcile: {type: bool, default: true, description: "..."}
  question_reply_mode: {type: str, default: "tool", description: "..."}
  question_clarify: {type: bool, default: false, description: "..."}
  inject_turn_complete: {type: bool, default: true, description: "..."}
  directory:    {type: str,    default: "",    description: "..."}
  agent:        {type: str,    default: "",    description: "..."}
  model:        {type: str,    default: "",    description: "..."}
```

`config_schema` types: `str, int, float, bool, list, dict`. A bad-typed value
logs a warning naming the key + expected type — never a load failure. Keep
`provides_tools` in sync with `TOOL_REGISTRY`.

## 4. Minimum-version discipline (document, don't host-guard)

Prefer a direct API call with NO `getattr(ctx, ...)` fallback, and document the
floor in the README:

```python
# register() — requires Hermes >= v2026.8.13 (ctx.on_unload)
ctx.on_unload(lambda: bridge.stop())     # raises on older Hermes → intended signal
```

README "Requirements" table:

| Dependency | Minimum version | Why |
| --- | --- | --- |
| Hermes | v2026.8.13 | `register()` calls `ctx.on_unload(...)` for teardown |
|| opencode | v1.18.18 | `POST /session/{id}/abort` stable at this tag. **`GET /session/list` is BROKEN server-side at v1.18.18 (HTTP 500 for any request)** — no working list endpoint, so the plugin does NOT expose one (removed `opencode_sessions`, commit `326384d`). Track sessions by the `session_id` `opencode_prompt` returns. |

Dropping the host-guard keeps the code honest: an older Hermes raising at load
is the intended signal, not a swallowed bug. (Auth is optional: localhost bind
needs no `OPENCODE_SERVER_PASSWORD`, so do NOT `requires_env`-gate the tools —
that would disable the whole plugin when the var is absent.)

## 5. Surfaces this plugin deliberately does NOT use

- `register_system_prompt_section` — redundant: the model discovers the bridge
  through the tool registry. Removed after the user said the section added no
  value ("the model already knows from the tools").
- `register_approval_transport` — its `present_fn` calling `request_tool_approval`
  recurses (see the recursion footgun in the root SKILL.md Pitfalls) and is
  redundant because the bridge already escalates via the gate. Removed.
