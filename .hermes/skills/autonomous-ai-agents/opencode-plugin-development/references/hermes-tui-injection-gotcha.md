# Hermes TUI ↔ plugin message injection — gateway-mode gotcha

Context: hermes-opencode plugin (OpenCode bridge) runs INSIDE a Hermes process
(`tui_gateway.entry`). It processes OpenCode "asks" (questions, permissions)
on its OWN background threads (SSE reader; permission FIFO worker). To surface
an ask into the local TUI conversation it must inject a message via
`PluginContext.inject_message`.

## The trap
`inject_message` (hermes_cli/plugins.py) has two branches:
1. `cli = self._manager._cli_ref` is set → push to `cli._pending_input` /
   `_interrupt_queue`. Works from ANY thread (plain thread-safe queues).
2. `cli_ref is None` (gateway mode) → requires `session_key` + config grant
   `plugins.entries.<id>.allow_gateway_injection: true` + a live
   `_gateway_message_injector`. Returns False otherwise ("gateway mode
   requires an existing session_key").

**In a headless `tui_gateway.entry` session, `cli_ref` is ALWAYS None**
(plugins.py: "In gateway mode _cli_ref is None"). So background-thread
injection FAILS — the ask is dropped or logged refused. This is by design,
not a bug to patch around in the plugin.

## Why "capture cli_ref" / "use the session key" both fail
- `cli_ref` is None in gateway mode → no CLI queue to push to.
- `session_key` alone is rejected unless `allow_gateway_injection: true` is
  set, AND it routes through the gateway injector — wrong destination (a
  gateway platform), not the local TUI turn.
- The gateway injector (`gateway/run.py._schedule_plugin_message_injection`)
  is ONLY installed when a real gateway runner is active. In headless tui
  there is none → `has_gateway_message_injector` is False → no delivery.

Empirical proof technique (no guessing):
- `grep` agent.log for `inject_message: gateway mode` / `cli_ref=False` /
  `wake.start(tui): disabled` / `no live gateway is available`.
- `ps aux | grep tui_gateway` — if only `tui_gateway.entry` (no
  `gateway/run.py` process), the gateway injector is NOT installed.
- Build a probe that calls the REAL `PluginContext.inject_message` against
  the installed hermes_cli package: Case A (cli_ref set) → True + queued;
  Case B (cli_ref None) → False; Case B2 (session_key set, no
  allow_gateway_injection) → still False. This proves the gate behavior.

## What actually works (supported surface)
- Question ask: OpenCode `question.asked` event yields a real id and is
  HELD for the agent. The agent answers via the plugin's
  `opencode_question_reply` TOOL — no inline injection needed. (Verify the
  OTHER agent actually used the tool; a naive tester may report "no id
  appeared" when the id WAS produced and held.)
- Permission ask: headless gateway with no human approver → fail-closed
  reject is CORRECT, not a bug. Harden `_handle_permission` so a raised
  `permission_reply` (e.g. HTTP 404 when OpenCode aged out the request)
  can never wedge the ask: wrap the primary reply in try/except → one
  fail-closed reject, pop `_pending` in `finally`.

## The only real fix for inline injection
A Hermes-side change: expose a plugin-reachable LOCAL conversation injection
handle (wire the plugin's gateway injector to `HostSupervisor.submit_turn`,
or add `PluginContext.inject_local_message` resolved by the host). Not
doable from the plugin alone — do NOT write dead "inject regardless" code
that registers its own injector with no delivery target; it just logs a
different failure.
