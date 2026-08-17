# Hermes message-injection surfaces (v2026.8.3)

Every way to push a message into a Hermes conversation, plugin-reachable or
not. All cites at the hermes-agent v2026.8.3 clone. Use this to pick the
right channel for event delivery (turn completions, external notifications)
vs standing context.

## One-shot delivery (plugin API)

- **`PluginContext.inject_message(content, role="user") -> bool`** —
  `hermes_cli/plugins.py:495`. THE canonical plugin injection API.
  - Agent mid-turn → `cli._interrupt_queue.put(msg)` (interrupt + inject,
    `plugins.py:515`). Agent idle → `cli._pending_input.put(msg)` (starts a
    new turn, `plugins.py:518`). Non-user roles wrap text as `[role] content`
    (`plugins.py:511`).
  - **TUI/local process ONLY**: needs the manager's private `_cli_ref`; in
    gateway mode logs a warning and returns `False` (`plugins.py:507-509`).
    A `False` return is the "no delivery channel" signal — the plugin should
    keep its fallback (e.g. the tail/read tools) and NOT advance any dedup
    state so a later event can retry.

## Standing per-turn context (plugin API, cache-safe)

- **`ctx.register_hook("pre_llm_call", cb)`** — `plugins.py:1177`; contract
  docstring `plugins.py:1919-1929`. Callback returns `{"context": "..."}`
  (or a plain string) and it is injected into the CURRENT turn's user
  message before every LLM call. Never persisted to session DB; system
  prompt stays byte-identical so the prompt-cache prefix survives. This is
  the "always-visible state" channel (userStories.json:2078 uses it to
  inject a STANDING.md every turn).
- Hook names (`AGENTS.md:748`): `pre_tool_call`, `post_tool_call`,
  `pre_llm_call`, `post_llm_call`, `on_session_start`, `on_session_end`.
- `ctx.register_middleware(kind, cb)` — `plugins.py:1196`: behavior-
  modification contract per caller, not a message channel.

## Under-the-hood primitives (not plugin-reachable directly)

- `agent.interrupt(message, hard_cancel=False)` — `run_agent.py:3020`: the
  running agent's interrupt-with-payload; abort in-flight turn, re-run with
  the message appended. What the CLI interrupt path ultimately drives.
- Raw queues `cli._pending_input` / `cli._interrupt_queue` —
  `cli.py:4633-34`, fed at `cli.py:7095-7099`; the TUI slash worker and
  built-in `/queue`-style commands put here too
  (`tui_gateway/methods_tools.py:571`, `tui_gateway/server.py:11745`).
  `inject_message` is the sanctioned wrapper; plugins can't reach the queues
  directly (private `_cli_ref`).

## Session-store writes

- `SessionState.append_message(...)` — `hermes_state.py:6060`: arbitrary
  role rows, returns row id. `append_messages_batch(...)` — `hermes_state.py:
  6207`: atomic multi-row batch in one transaction (the turn flush path).
  Params include timestamp, `display_kind`/`display_metadata`, and
  `api_content` (byte-fidelity sidecar "sent vs stored" for inject-style
  rows). Rows appear on the NEXT turn (loop rebuilds context from the store).
  No interrupt, no queue. PluginContext does NOT expose SessionState.

## Gateway / platform / process level

- **Messaging platforms**: adapter→session pipeline via
  `gateway/platforms/base.py:4808 interrupt_session_activity` etc. In
  gateway mode `inject_message` refuses by design (`plugins.py:508`) — a
  platform message IS the injection channel there.
- **Webhooks** (`hermes webhook subscribe`, skill ref `webhooks.md`): POST
  with HMAC → prompt template → NEW session run → delivery to a target;
  `--deliver-only` pushes literal text with zero LLM cost. Session-starter,
  not live-session injection.
- **Cron**: scheduled runs with `context_from` chains and skills; deliveries
  framed header/footer (keeps role alternation), not mirrored into a live
  session (skill ref `background-systems.md`).
- **External process**: `hermes chat -q/-p` + `--resume <id>` — one process
  per invocation, no IPC into a running TUI. Fire-and-forget delegation
  only (tmux orchestration pattern from the hermes-agent skill).

## Non-paths (checked, ruled out)

- `ctx.register_context_engine` (`plugins.py:635`) replaces the
  ContextCompressor (`agent/context_engine.py` ABC): context MANAGEMENT /
  compression, not a message channel. Only one engine plugin allowed.
- MCP servers = tool-call surface. `notify`/`deliver` = outbound platform
  delivery. Desktop/TUI gateway clients talk to the same `_pending_input`
  path via HTTP methods (peers of inject_message, not new APIs).

## Fit for the opencode bridge

- One-shot completion delivery → `inject_message` (what the bridge uses).
  Quirk: agent idle → wakes it as next input; that is desired for delegation
  continuation but needs a config escape hatch (`inject_turn_complete`).
- Standing "latest opencode state" visibility → `pre_llm_call` hook
  (ephemeral, cache-safe, no interrupt side effects). Not yet used.