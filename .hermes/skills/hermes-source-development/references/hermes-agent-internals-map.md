# Hermes Agent internals map for plugin/bridge development (v2026.8.3)

Verified by direct source read of `NousResearch__hermes-agent` at tag **v2026.8.3** (release 0.20.0, commit 3c27eb6). This complements `hermes-plugin-surface.md` (the *loading/registration* surface) with the *runtime engine* surfaces a bridge plugin (e.g. Hermes↔OpenCode) must touch: the agent loop, where messages may enter a session, the tool registry, the SQLite session store, skills, cron, gateway adapters.

## Architecture rules that gate everything (AGENTS.md at repo root)

- **Per-conversation prompt caching is sacred.** Anything that mutates past context, swaps toolsets, or rebuilds the system prompt mid-conversation invalidates the cache. The one sanctioned exception is context compression.
- **The core is a narrow waist.** New capability order: extend existing code → CLI command + skill → service-gated tool (`check_fn`) → plugin → MCP server → new core tool (last resort).
- **Never a synthetic user message injected mid-loop**; never two same-role messages in a row. Violations are rejected in review.

## 1. Agent loop (how a user message becomes model calls + tools)

- `run_agent.py:412 class AIAgent` — the ONE agent class used by CLI, gateway, cron.
- `AIAgent.chat(message)` (run_agent.py:7710) → `run_conversation(...)` → `agent/conversation_loop.py:1228 run_conversation(agent, user_message, system_message, conversation_history, task_id, stream_callback, persist_user_message, ...)`.
- **Per-turn prologue**: `agent/turn_context.py:330 build_turn_context()` — resets retries/iteration budget, MCP refresh, sanitizes surrogates, hydrates todo/memory nudges, and **appends the user message** to the in-memory list at `turn_context.py:561 messages.append(user_msg)`. The system prompt is restored-or-built once (`agent/conversation_builder.py:470 _restore_or_build_system_prompt`) and cached on `AIAgent._cached_system_prompt` for the session's life.
- **Model loop**: `conversation_runner.py:1402` `while api_call_count < agent.max_iterations ...` → `AIAgent._interruptible_api_call` (streaming) or `_anthropic_messages_create` → tool dispatch to `agent/tool_executor.py:629 execute_tool_calls_concurrent` / `:1335 execute_tool_calls_sequential` / `:2025 execute_tool_calls_segmented`.
- **Compaction**: post-response `should_compress()` check; engine at `agent/conversation_compression.py` `_compress_context` (run_agent.py:7115 forwards), gated by `CompressionCommitFence` + per-session DB compression lock + a single admission slot (`_try_admit_compression_job`).
- **Persistence**: `AIAgent._flush_messages_to_session_db` (run_agent.py:1983) writes new messages (dedup via intrinsic `_DB_PERSISTED_MARKER`), `_persist_session` at turn end.
- `persist_user_message=` decouples clean transcript text from API-only synthetic prefixes; `persist_user_display_kind` (`auto_continue`, `model_switch`, …) renders as a timeline event, not a user bubble, while the model receives it unchanged.

## 2. Message injection surfaces (where a plugin can put a message into a session)

| Surface | Location | Caveat for bridge plugins |
|---|---|---|
| **`PluginContext.inject_message(content, role="user")`** | `hermes_cli/plugins.py:495` | **CLI-only** — returns False in gateway mode ("no CLI reference (not available in gateway mode)"). If `cli._agent_running` → pushes `cli._interrupt_queue` (interrupts mid-turn), else `cli._pending_input` (starts new turn). |
| **`run_conversation(persist_user_message=...)`** | `agent/conversation_builder.py:1228` | Programmatic/turn-accurate; model still sees message even when transcript shows an event. |
| **SessionDB append/batch/replace/compact** | `hermes_state_guard.py` functions `append_message`/`append_ua`/`replace_messages`/`archive_and_compact` | Direct DB write — visible only on /resume/reload, not pushed into a live turn. |
| **Gateway inbound** | `gateway/run.py:14206 _handle_message` → `:16149 _handle_message_with_agent` | All platform input enters via `MessageEvent` (gateway/platforms/base.py:2054). `pre_gateway_dispatch` hook (in `VALID_BOMBS`, plugins.py:135) can skip/rewrite/allow before dispatch. |
| **`hermes send` CLI** | `hermes_cli/send_cmd.py:316 cmd_send` | Outbound only. |
| **send_message engine** | `tools/send_message_tool.py` | **Not an agent-callable model tool** (v2026.3 does not ship it as a registry tool): "The agent should not decide on its own to fire off cross-platform messages." It is the shared transport for **cron delivery, `hermes send`, the gateway notifier, `mcp_serve.py`** — import the module helpers. |

Mid-turn steering: `AIAgent.steer / redirect` (run_agent.py) queue pending redirects consumed by the loop — used by TUI/gateway, not the plugin tool path.

## 3. Tool system

**Core snippet (contract):**

```
registry.register(name, toolset, schema, handler,
    check_fn=None, requires_env=None, is_async=False,
    description="", emoji="", max_result_size_chars=None,
    dynamic_schema_overrides=None, override=False)      # tools/registry.py:521
```

- Every tool file calls `registry.register(...)` at module import (`tools/registry.py` docstring: "Each tool file calls registry.register() at module level … model_tools.py queries the registry instead of maintaining its own parallel data structures"). `deregister` is gated by the same `allow_tool_override` policy.
- **Plugin path:** `PluginContext.register_tool(...)` (plugins.py:410) wraps registry.register and tracks the tool. Plugin toolsets resolve through the normal toolsets.py path (`_get_plugin_toolset_names`); `toolsets.py:1230 create_custom_toolset(name, description, tools, includes)` also exists.
- **Schema format** is OpenAI-style: `{"name", "description", "parameters": {"type":"object","properties":{...},"required":[]}}`. Example `SEND_MESSAGE_SCHEMA` at tools/send_message_tool.py:201.
- Assembly: `model_tools.py:294 get_tool_definitions(enabled, disabled)` → `resolve_toolset` (toolsets.py:754) merges static `TOOLSETS` + registry toolsets; schemas only returned when `check_fn` passes. Cached keyed by `(enabled, disabled, registry._generation)`.
- `toolset_distributions.py` is datagen-only (probabilistic toolset pick for batch jobs) — not a plugin surface.

**External-agent tools:** `tools/delegate_tool.py` `delegate_task` (toolset `"delegation"`) spawns **in-process AIAgent subagents** — the only external-agent mechanism. No OpenCode tool exists: `opencode`/`codex` tokens in `tools/*.py` are **port citations** (`"Port of anomalyco/opencode#…"`) and provider names (`"openai-codex"` Responses API), not invocation surfaces of OpenCode. `claude`-named files = conventions only. Let plugin surfaces for OpenCode/Claude ships, none in core. `agent/` has codex_runtime.py / codex_responses_adapter.py as *provider backends* (language for the *agent to be a Claude/Codex client*).

## 4. State / session store

- `hermes_state.py:1895 SessionDB` (SQLite; FTS5 wired via schema/trigram). `messages` DDL in `hermes_state_common.py:261`:
```sql
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sessions(id),
    role TEXT NOT NULL, content TEXT, tool_call_id TEXT, tool_calls TEXT,
    tool_name TEXT, effect_disposition TEXT, timestamp REAL NOT NULL,
    token_count INTEGER, finish_reason TEXT, reasoning TEXT, ...
    active INTEGER NOT NULL DEFAULT 1, compacted INTEGER NOT NULL DEFAULT 0,
    api_content TEXT, display_kind TEXT, display_metadata TEXT
);
```
- `api_content` is the **byte-fidelity sidecar** for prompt-cache-stable replay ("ephemeral memory/plugin injections, persist overrides" — hermes_state.py:6112-6137). Display metadata never changes model content.
- Old message shapes: `append_message`, `append_messages_batch`, `replace_messages`, `archive_and_compact`, `get_messages_as_conversation`, `get_compression_lineage`, `rewind_to_message`. Compression rotation: transcript is archived and the session moves to a child session id (`get_compression_tip`).

## 5. Skills

- Format: dir with `SKILL.md` (required) + optional `references/` `templates/` (see module docstring tools/skills_tool.py:1-66). Frontmatter: `name ≤64`, `description ≤1024` (both required), optional `version`, `license`, `platforms: [macos|linux|windows]`, `prerequisites: {env_vars, commands}` (normalized to required_environment_variables), `conditions` (tool-gated show). agentskills.io compatible.
- Execution: two model tools `skills_list` (metadata, tier 1) + `skill_view` (full content + linked files, tier 2/3), toolset `"skills"`, gated by `check_skills_requirements`. The system prompt carries an **index** of available skills built by `agent/prompt_builder.py:1584 build_skills_system_prompt` (LRU + disk snapshot `.skills_prompt_snapshot.json`); the agent loads a skill on demand via `skill_view` — progressive disclosure.
- Search dirs: `~/.hermes/skills/`, repo `skills/`, `optional-skills/` (opt-in catalog), `skills.external_dirs` (read-only). Plugins register namespaced skills `ctx.register_skill(name, path)` → loadable as `<plugin>:<name>`, **not** in the `<available_skills>` index (opt-in loads only, plugins.py:1217).

## 6. Cron + Gateway

- **Cron**: internal JSON-file scheduler. `cron/jobs.py` (`jobs.json`), `cron/scheduler.py` runs an `AIAgent` turn per trigger (`_build_job_prompt` :2443) then delivers via the send_message transport (`_deliver_result` :1461). Agent-facing surface: the **`cronjob` model tool** (tools/cronjob_tools.py, toolset `"cronjob"`); job fields include `prompt|script|skill(s)`, `schedule`, `deliver` (platform/`local`), `context_from` (chaining incl. `attach_to_session` continuable jobs → dedicated thread / mirrored DM).
- **Gateway**: `gateway/run.py` `GatewayRunner` (:…, main class at :4432) binds incoming staged `MessageEvent` to a session via `gateway/session.py` (SessionSource/SessionEntry, key generation, expiry policy), then runs the cached `AIAgent`. Outbound via `gateway/delivery.py` (`resolve_delivery_transport`).
- **Adapters**: platform transport = `BasePlatformAdapter` (gateway/platforms/base.py:…, ABSTRACT class `:~2759`) — messenger subclass w/ `connect/disconnect` + `send(chat_id, text, ...) -> SendResult` etc. Plugin path: `~/.hermes/plugins/<p>/plugin.yaml` + `adapter.py`, `ctx.register_platform` (plugins.py:950) → **zero core changes**. See `gateway/platforms/ADDING_A_PLATFORM.md` for hooks (`env_enablement_fn`, `apply_yaml_config_fn`, `cron_deliver_env_var`, `standalone_sender_fn`).

## Key-file index

| File | What it holds |
|---|---|
| `run_agent.py` | AIAgent + streaming + persist + compress forwarder |
| `agent/conversation_runner.py` store live loop | `run_conversation`, compression checks |
| `agent/turn_context.py` | prologue, user-msg admit, persist overrides |
| `agent/tool_executor.py` | tool-call execution (concurrent/sequential/segmented) |
| `agent/conversation_compression.py`, `context_compressor.py` | compaction engine + fence |
| `hermes_state.py`, `hermes_state_common.py` | SessionDB + `messages` DDL |
| `model_tools.py`, `toolsets.py`, `toolset_distributions.py` | toolset resolution/schema assembly |
| `tools/registry.py` | ToolRegistry (register/deregister) |
| `hermes_cli/plugins.py` | PluginContext (register_tool/inject_message/register_skill/…, VALID_HOOKS at :135) |
| `cron/jobs.py`, `cron/scheduler.py` | jobs.json store; scheduler/delivery |
| `gateway/run.py`, `gateway/session.py`, `gateway/platforms/base.py | WhatsApp … adapters | gateway runner, session model, adapter ABC |

## Operational shortcuts

- Source layout: top-level dirs `agent/`, `tools/`, `hermes_cli/`, `gateway/`, `cron/`, `skills/`. No `hermes/agent` — the `hermes/` name is a file, not a dir.
- When searching for a capability, grep both `tools/` and `hermes_cli/`; version refs (v2026.3) shift line numbers — rerun `git describe` and re-grep before quoting file:line.