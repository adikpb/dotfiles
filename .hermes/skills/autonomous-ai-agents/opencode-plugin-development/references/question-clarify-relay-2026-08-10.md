# question_clarify: relay opencode asks through the Hermes clarify panel (2026-08-10)

Settled design for the hermes-opencode bridge, tool mode. Opt-in config
`question_clarify` (default `false`), only meaningful in
`question_reply_mode=tool`. Committed at `994c46c`, 158 tests green.

## Goal

The user asked: is there a way to use the Hermes clarify tool for opencode
questions "but not have the clarify tool call or result within the hermes
session". Answer found in the vendored Hermes source (v2026.8.3):

- `tools/clarify_tool.py` is a thin wrapper around a platform callback; the
  callback is `cli._clarify_callback(question, choices, multi_select=False)`
  (cli.py:13103), which renders the modal prompt_toolkit panel and blocks up
  to the configurable clarify timeout (default 120s).
- The callback is reachable FROM THE PLUGIN via the same manager/CLI ref
  `PluginContext.inject_message` uses. Calling it from the bridge FIFO worker
  (not the agent loop) renders the panel with ZERO transcript footprint:
  no tool-call row, no tool-result row, no message. Only a dim terminal
  scrollback line via `_persist_prompt_summary` (cli.py:13084), which is
  toggleable with `display.persist_prompts` (default true).
- The platform callback is NOT thread-captured like the approval callback —
  no `_get_clarify_callback` exists. Resolution walk:
  `ctx._manager._cli_ref._clarify_callback` (TUI mode only; gateway mode has
  no `_cli_ref` -> `None` -> fallback path).

## Wiring (bridge.py)

- `_on_question`: `clarify = question_clarify and self._clarify_callback() is
  not None`; when clear, SKIP the injection; always enqueue so the registry
  holds the family/session mapping.
- `_ask_question_default` (runs inside the approval FIFO worker): in tool
  mode with clarify armed, `_relay_question(props, cb)`; if it returns
  answers (human answered), the worker replies; HELD means timeout/panel
  failure -> inject the ask now (deduped by rid into `_injected_questions`)
  and return HELD so the main agent takes over. Without clarify: plain
  inject+hold as before. reject: return `None` -> `_reject_question`, no
  injection ever.
- `_relay_question`: one callback call per question in the ask. Non-custom
  option labels -> `choices` (labels, `[:4]` — clarify's MAX_CHOICES);
  custom-only ask -> `choices=None` (open-ended prompt). Answer = `.join`
  of what the panel returns (raw string). Multi-select not used.

## Timeout sentinel

On timeout the callback returns
`"The user did not provide a response within the time limit. Use your best
judgement to make the choice and proceed."` — module constant
`CLARIFY_TIMEOUT_PREFIX = "The user did not provide a response within the
time limit"`, matched with `startswith`. Sentinel (or any callback exception)
=> HELD => fall back to inject+hold (the user-chosen behavior; the other
proposed option was reject-on-timeout, rejected by the user).

## Threading

The relay runs in the approval FIFO worker thread, same serialization as
permission asks (a pending human decision holds the question queue). Do NOT
run it on the SSE router reader thread (a 120s human decision would stall the
whole event stream).

## Tests (tests/test_bridge.py)

- FakeCtx gains optional `manager`; `ClarifyApp` exposes
  `_clarify_callback`; `clarify_manager(cb)` helper builds the
  `_manager._cli_ref` chain the bridge walks.
- Cases: relay-answers-without-injection (+ exact `picks` assertion on
  question/choices/multi_select), custom-only -> `choices is None` open-ended,
  timeout sentinel -> inject once + held, clarify enabled but no CLI ref ->
  fallback, callback exception -> fallback.
- config: `question_clarify` default `False` asserted in test_config.

## Config note

`question_clarify` must be added to the `load_bridge_config` RETURNED dict
(whitelist-filtered keys are otherwise dead) — see the
question-gate-answer reference for the dead-key pitfall.