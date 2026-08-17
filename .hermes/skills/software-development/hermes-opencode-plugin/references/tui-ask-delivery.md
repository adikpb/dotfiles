# TUI ask delivery — 2026-08-15 Hermes TUI drive

Hermes TUI session, opencode serve `127.0.0.1:4096` v1.18.18, model
`deepseek-v4-flash-free`, directory `~/src/test-plugin`.
Tools driven via the deferred catalog (`tool_describe` → `tool_call`) **from inside
the Hermes TUI**, not a gateway or a standalone script.

This corrects the earlier calibration that "inject only fails outside an interactive
TUI." Being in the TUI was not enough for any of the three event-driven pillars to
land in the conversation.

## Permission — gate reached, no human prompt

- Session: `ses_example_tui_ask_a`
- OpenCode emitted `bash` `call_example_3`
  (`touch /tmp/opencode-probe.txt && echo probe-done`).
- Hermes gate returned `status: "approval_required"`. Plugin mapped that via
  `decide_reply` to `reject` + `"awaiting human review (approval queued but not
  delivered)"`.
- Raw tool state (GET `/session/<sid>/message`):
  `"The user rejected permission to use this specific tool call with the following
  feedback: awaiting human review (approval queued but not delivered)"`.
- **No** Hermes allowlist/approval prompt with an `opencode`-prefixed rule appeared
  in the TUI. Nothing to approve.
- `/tmp/opencode-probe.txt` was never created. `GET /permission` was `[]` after
  the reject (empty list does not mean no ask fired). Session went idle; no abort.

**Root cause (source, not harness):** Ink TUI is a gateway host
(`HERMES_GATEWAY_SESSION=1`). `request_tool_approval` looks up
`_gateway_notify_cbs[get_current_session_key()]`. A miss does **not**
wait: it `submit_pending` and returns `status: "approval_required"`
immediately. The plugin used to map that to an opencode `reject`, so a
later human Allow was a no-op (usage 2026-08-16: prompt painted, click
Allow, `/tmp/opencode-probe.txt` never created).

Two misses produce that shape:
1. FIFO worker ContextVar empty (`"default"`) while notify is registered
   under the TUI `session_key`.
2. This worker is a second plugin load (TUI agent+gateway double-load)
   that has no notify cb; a sibling waiter painted the prompt and is
   blocked in `_await_gateway_decision`.

Fix: bind a notify-registered key when one exists; if the gate still
returns `approval_required` on a bound gateway host, **do not reject**
(leave the ask for the notify waiter). Headless still fail-closes.

Do not wait for a TUI approval dialog on a **pre-fix** build. If the tail
shows that reject string, the ask already fail-closed. Distinguish this from
a BLOCKED `[opencode]` tool error and from an opencode-internal prose denial.

## Question — real `que_` id, reply tool worked, still no inject

- Session: `ses_example_tui_ask_b`
- OpenCode emitted a structured `question` tool (not empty `{}`): header
  `Case choice`, options `UPPERCASE` / `lowercase`,
  `callID=call_example_4`.
- `GET /question` (header `x-opencode-directory` = the project dir) returned
  `que_example_tui` while the session was `busy`.
- **No** `[opencode] question` user message was injected into the TUI conversation.
- `opencode_question_reply(question_id="que_example_tui",
  answers=["UPPERCASE"])` → `{"answered": true}`.
- Tail then showed the question tool result, a successful `write` of `qtest.txt`,
  and assistant text picking UPPERCASE. `cat qtest.txt` → `UPPERCASE`.

This is the working question path when inject is silent: recover the id from
`GET /question`, reply via the tool, confirm with tail + the written file. Do
not sit waiting for an inject that may never arrive. Distinct from the earlier
shape where `GET /question` was `[]` and a `callID`-as-`que_` reply 404'd
(`references/inject-silent-noop-repro.md`).

## What to do next time

1. After `opencode_prompt`, immediately probe `GET /question` and `GET /permission`
   with the exact project `x-opencode-directory` (no trailing slash) plus
   `opencode_session_tail`. Do not wait for `[opencode] question` or a Hermes
   approval prompt.
2. If a `que_*` is pending, answer it with `opencode_question_reply` even when
   no inject landed.
3. If the tail already contains `approval queued but not delivered`, the
   permission ask is done and rejected — do not expect a later prompt.
4. Confirm side effects with `terminal` (`ls`/`cat`), not from the assistant
   prose alone.
