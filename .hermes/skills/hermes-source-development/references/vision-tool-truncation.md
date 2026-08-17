# Vision Tool Truncation — Debugging Reference

Reproduction environment:
- Hermes v0.19.0 (commit cbecd72e)
- Main model: `deepseek-v4-flash-free` via `opencode-zen` (text-only)
- Aux vision: `gemini-3.6-flash` via `gemini` provider
- MacOS 26.5.2

## How the Code Path Works

```
vision_analyze / browser_vision called
  └─ _should_use_native_vision_fast_path()
       └─ checks: main model vision-capable?
            └─ NO (text-only model) → falls to legacy aux path
  └─ vision_analyze_tool() or browser_vision handler
       └─ calls auxiliary LLM with max_tokens=2000 (HARDCODED)
       └─ if image complex → description truncated at 2000 tokens
```

The native fast path (`_vision_analyze_native`) returns pixels directly and
does not have this max_tokens issue — but it only fires for vision-capable
main models on supported provider stacks.

## Code Locations (v0.19.0)

### tools/vision_tools.py — `vision_analyze_tool()` (line ~1066)

The config-read block at ~1231-1244 reads `timeout` and `temperature`:

```python
vision_timeout = 120.0
vision_temperature = 0.1
try:
    from hermes_cli.config import cfg_get, load_config
    _cfg = load_config()
    _vision_cfg = cfg_get(_cfg, "auxiliary", "vision", default={})
    _vt = _vision_cfg.get("timeout")
    if _vt is not None:
        vision_timeout = float(_vt)
    _vtemp = _vision_cfg.get("temperature")
    if _vtemp is not None:
        vision_temperature = float(_vtemp)
except Exception:
    pass
call_kwargs = {
    "task": "vision",
    "messages": messages,
    "temperature": vision_temperature,
    "max_tokens": 2000,          # <-- HARDCODED, never read from config
    "timeout": vision_timeout,
}
```

The `_handle_vision_analyze` function (line ~1476) decides the path:
1. Calls `_should_use_native_vision_fast_path()` — if True, returns pixels
   directly via `_vision_analyze_native()`
2. Otherwise falls to `vision_analyze_tool()` — the legacy aux path

### tools/browser_tool.py — `browser_vision` handler (line ~4285)

Same pattern — reads timeout/temperature from config at ~4302-4315, but
hardcodes `max_tokens: 2000` at line 4328:

```python
call_kwargs = {
    "task": "vision",
    "messages": [...],
    "max_tokens": 2000,          # <-- HARDCODED
    "temperature": vision_temperature,
    "timeout": vision_timeout,
}
```

### tools/vision_tools.py — `video_analyze_tool()` (line ~1635)

Separate tool, same bug — `max_tokens: 4000` hardcoded at line 1755.

## Fix Pattern

In both files, add `max_tokens` reading alongside timeout/temperature, then
use the config value in `call_kwargs`:

```python
# Add this in the config-read block:
_vmt = _vision_cfg.get("max_tokens")
if _vmt is not None:
    vision_max_tokens = int(_vmt)
else:
    vision_max_tokens = 2000  # keep existing default

# Change call_kwargs to use it:
call_kwargs = {
    "task": "vision",
    "messages": messages,
    "temperature": vision_temperature,
    "max_tokens": vision_max_tokens,  # was 2000
    "timeout": vision_timeout,
}
```

Then add to `~/.hermes/config.yaml`:

```yaml
auxiliary:
  vision:
    provider: gemini
    model: gemini-3.6-flash
    timeout: 120
    max_tokens: 8000   # raise from default 2000
```

## Related Issues & PRs

| # | Status | What | Applies to vision_tools/browser_tool? |
|---|--------|------|--------------------------------------|
| [#10809](https://github.com/NousResearch/hermes-agent/issues/10809) | OPEN | Root issue — hardcoded max_tokens=2000 causes truncation | — |
| [#29590](https://github.com/NousResearch/hermes-agent/issues/29590) | OPEN | Explicit request to read `auxiliary.vision.max_tokens` from config | — |
| [#34087](https://github.com/NousResearch/hermes-agent/issues/34087) | CLOSED | Same fix proposed, closed per author request | — |
| PR [#15430](https://github.com/NousResearch/hermes-agent/pull/15430) | CLOSED, not merged | Attempted global refactor to read vision max_tokens from config. Never landed (60+ file PR). | N/A |
| PR [#34845](https://github.com/NousResearch/hermes-agent/pull/34845) | **MERGED** | Fixed `agent/auxiliary_client.py` to stop capping aux output with max_tokens by default | **NO** — vision_tools.py and browser_tool.py build their own `call_kwargs` manually, bypassing the central client |

**Key takeaway:** Despite PR #34845 being merged, the hardcoded `max_tokens: 2000` in `vision_tools.py` and `browser_tool.py` is **still present** in the current codebase (v0.19.0, commit cbecd72e). A local patch is required until someone contributes a proper upstream fix.

### Investigation command log (reproducible)

```bash
# Check if the fix was in the update queue
cd ~/.hermes/hermes-agent && git log --oneline HEAD..origin/main -- tools/vision_tools.py

# Search for related issues
gh issue list --repo NousResearch/hermes-agent --state all --search "hardcoded max_tokens vision" --limit 10 --json number,title,state

# Check if a merged PR touched the actual source files
gh pr view 34845 --repo NousResearch/hermes-agent --json files | python3 -c "import sys,json;[print(f['path']) for f in json.load(sys.stdin)['files']]"
# → Only agent/auxiliary_client.py and tests — NOT vision_tools.py or browser_tool.py
```
