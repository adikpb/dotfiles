# Official inject: `ctx.inject_message` only

Source: https://hermes-agent.nousresearch.com/docs/user-guide/features/plugins#injecting-messages
(verified against `PluginContext.inject_message` in the pinned Hermes clone).

```python
# Active CLI conversation
ctx.inject_message("...", role="user")

# Existing gateway conversation (Telegram/Discord/…)
ctx.inject_message("...", role="user", session_key="agent:main:telegram:dm:…")
```

Signature: `ctx.inject_message(content: str, role: str = "user", *, session_key: str | None = None) -> bool`

## CLI

- No `session_key`. Host uses `PluginManager._cli_ref`.
- Idle → queued as next input (new turn). Mid-turn → interrupt (same as the user hitting Enter).
- Non-`user` roles are prefixed `[role]`.
- Returns `True` if queued.

## Gateway

- `session_key` required (stable routing key, not the CLI session id).
- Also requires `plugins.entries.<plugin>.allow_gateway_injection: true`.
- Returns `False` if key omitted, grant missing, or no live gateway injector.

## What this plugin must not do

- Do not poke `_pending_input` / `_interrupt_queue` / `_cli_ref` yourself. That reimplements the host API and silently no-ops on Ink TUI (only classic `cli.py` sets `_cli_ref`).
- Do not import `tui_gateway.server` to `agent.steer` or `_enqueue_prompt`. The user rejected that as non-standard after pointing at the docs above.
- Ink TUI is a gateway host. Hermes `tui_gateway.server` registers
  `set_gateway_message_injector` and delivers via `prompt.submit`.
  Grant `plugins.entries.hermes-opencode.allow_gateway_injection: true`
  or official inject returns False at the grant check.

## Permission is a different API

TUI permission prompts go through `request_tool_approval`, not `inject_message`. Bind the agent-thread session_key onto the FIFO worker before the gate (`permission.ApprovalBridge.bind_session`) so `_gateway_notify_cbs[session_key]` matches. Missing that bind is why a live TUI run saw `approval_required` / "awaiting human review (approval queued but not delivered)" with no prompt.

## User correction this session

"bro i ran this in a tui, that means it was interactive." Do not diagnose a missing inject or missing approval prompt as "you weren't in a TUI." Being in the Hermes TUI is not sufficient for official `inject_message` to land.
