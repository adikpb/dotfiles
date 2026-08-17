# TUI Tool Availability Investigation — Full Case Study

## Symptom

In a TUI session (`display.interface: tui`), the tools `terminal`,
`read_file`, `write_file`, `patch`, and `search_files` were absent from
the available tool list. The `process` tool was available (same `terminal`
toolset), and `execute_code` was available.

Config had `platform_toolsets.cli` explicitly listing both `terminal` and
`file` toolsets. No `disabled_toolsets` were set.

## Investigation Path

### Step 1 — Check config

```yaml
# ~/.hermes/config.yaml — relevant sections
model:
  default: deepseek-v4-flash-free
  provider: opencode-zen
  base_url: https://opencode.ai/zen/v1
  api_mode: chat_completions

platform_toolsets:
  cli: [browser, clarify, code_execution, context_engine, delegation,
        file, kanban, memory, session_search, skills, terminal, todo, web]
  # NO "tui" entry
```

`terminal` and `file` are present. Config looks correct. ✓

### Step 2 — Check HERMES_TUI_TOOLSETS env var

Not set. No manual override. ✓

### Step 3 — Check toolset resolution code path

The TUI gateway loads tools via `_load_enabled_toolsets()` in
`tui_gateway/server.py`, which calls:

```python
_get_platform_tools(cfg, "cli", include_default_mcp_servers=True)
```

**Key finding:** The platform is hardcoded to `"cli"`, not `"tui"`.
The system prompt showing `Platform: tui` is the UI rendering layer,
not the tool resolution platform.

### Step 4 — Check platform registry

`hermes_cli/platforms.py` defines a `PLATFORMS` OrderedDict with entries
for `cli`, `telegram`, `discord`, `slack`, etc. — but **no `tui` entry**.

```python
PLATFORMS: OrderedDict[str, PlatformInfo] = OrderedDict([
    ("cli", PlatformInfo(label="🖥️  CLI", default_toolset="hermes-cli")),
    ("telegram", ...),
    ...
    # NO "tui"
])
```

This is a code gap but **does not cause the symptom** because the TUI
gateway bypasses the registry by hardcoding `"cli"`.

### Step 5 — Check for known bugs on GitHub

Searched `site:github.com/NousResearch/hermes-agent` for issues related to
TUI + missing tools + opencode-zen:

| Issue | Relevance | Status |
|-------|-----------|--------|
| #32660 — `-tui` parsed as `-t ui` (0 tools) | Related but fixed in v0.19.0 | Fixed |
| #21658 — Subagent tool delegation intersection | Different scope (subagents) | Open |
| #22573 — Native tools stripped by hermes-yuanbao in disabled_toolsets | Different trigger | Fixed |
| #22601 — Composite + configurable toolset mixing bug | Fixed before v0.19.0 | Fixed |
| #51381 — anthropic_messages tool serialization (missing `name` field) | Uses `chat_completions` mode, not affected | Open |

### Step 6 — Check disabled_toolsets

The user's config has no `disabled_toolsets` set. ✓

### Step 7 — Analyze what tools ARE available vs missing

| Tool | Available? | Toolset |
|------|-----------|---------|
| `execute_code` | ✅ | code_execution |
| `web_search`, `web_extract` | ✅ | web |
| `browser_*` | ✅ | browser |
| `delegate_task` | ✅ | delegation |
| `clarify` | ✅ | clarify |
| `memory` | ✅ | memory |
| `session_search` | ✅ | context_engine |
| `skill_manage`, `skill_view`, `skills_list` | ✅ | skills |
| `todo` | ✅ | todo |
| `process` | ✅ | terminal |
| `terminal` | ❌ | terminal |
| `read_file`, `write_file`, `patch`, `search_files` | ❌ | file |
| `tool_search`, `tool_describe`, `tool_call` | ✅ | built-in |
| `project_*` | ✅ | deferred project tools |

The `process` tool being available but `terminal` not is unusual — they
are in the same `terminal` toolset. This could be a `check_fn` cache
issue (see the `terminal-tool-case-study.md` reference) or a tool
definition resolution issue specific to the `opencode-zen` provider's
`chat_completions` mode.

### Step 8 — Check provider-specific behavior

The `opencode-zen` provider with `chat_completions` API mode uses standard
OpenAI tool format. Known issue #51381 affects `anthropic_messages` mode
only (missing `function.name` field in serialized tools). Not applicable here.

## Key Code Locations

| Component | File |
|-----------|------|
| TUI toolset entry point | `tui_gateway/server.py` (`_load_enabled_toolsets`) |
| Platform → toolset resolution | `hermes_cli/tools_config.py` (`_get_platform_tools`) |
| Platform registry (missing `tui`) | `hermes_cli/platforms.py` (`PLATFORMS`) |
| check_fn cache | `tools/registry.py` (`_check_fn_cached`) |
| Terminal check function | `tools/terminal_tool.py` (`check_terminal_requirements`) |
| Toolset definitions | `toolsets.py` (`TOOLSETS`, `_HERMES_CORE_TOOLS`) |
| CLI arg parsing (historical bug) | `hermes_cli/main.py` (`_wants_tui_early`) |

## Lessons for Future Investigations

1. **Platform string in system prompt is misleading.** `Platform: tui` in
   the system prompt does NOT mean the tool system uses `platform_toolsets.tui`.
   The TUI gateway always resolves via `platform_toolsets.cli`.

2. **Start with the code path, not the config key name.** The fact that
   `_load_enabled_toolsets()` calls `_get_platform_tools(cfg, "cli")` is
   the authoritative fact. The displayed platform name is a rendering detail.

3. **Cross-reference tool availability with check_fn.** If `process` is
   available but `terminal` is not, the toolset is enabled but the
   `check_fn` for `terminal` rejected it — or a stale cache entry is
   blocking it.
