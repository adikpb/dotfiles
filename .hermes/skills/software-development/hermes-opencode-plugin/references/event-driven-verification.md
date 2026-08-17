# Event-driven verification (code-level)

Verified against plugin source `hermes_opencode/` (bridge.py, router.py,
fifo.py, approval.py, questions.py, client.py). Companion to the SKILL.md
Pitfalls + design-intent sections. See `references/architecture.md` for the
full module map and the register-based dispatch pattern.

## The three event-driven pillars (design intent)
The plugin is built for COMPLETE event-driven usage. Each is a DEFECT if broken,
not a headless quirk:
1. **Tail-on-idle injection** — `bridge._on_idle` → `_on_turn_complete` →
   `_inject_turn` pushes a `[opencode] turn complete | session <sid>` message into
   the Hermes conversation; the agent then reads via tail/read.
2. **Question + id injection** — `router.py` dispatches `question.asked` →
   `bridge._on_question` → `_inject_question` (tool mode) emits
   `[opencode] question | session <sid> | id <rid>` with a real request id;
   `opencode_question_reply(question_id=rid)` answers it.
3. **Permission routing through Hermes** — `router.py` dispatches
   `permission.asked` → `approval.enqueue_permission` → `approval._handle_permission`
   → `_gate` → `tools.approval.request_tool_approval` (Hermes' real gate). The
   reason carries the `[opencode] session <sid>: <tool>` marker.

## Always non-blocking contract
`Bridge.prompt()` has NO `wait`/`timeout` params (removed). It returns
`{"session_id", "running": True, "entries", "tail_size"}` immediately; the turn runs
in the background; completion is delivered via the event stream. `run_command`
calls `prompt(rendered, directory=...)` (no `wait=False`). The `_wait_idle` /
`_poll_status_idle` helpers and the `EventRouter.forget` baseline machinery were
deleted. Do not re-add a `wait` flag.

## Routing chain (for source verification)
- `router.py` `EventRouter` uses **register-based dispatch** (not a static
  `if/elif`). `bridge._wire()` registers: `session.status:idle` → `_on_idle`,
  `session.status:busy` → `_on_busy`, `permission.asked` →
  `approval.enqueue_permission`, `question.asked` → `_on_question`, plus
  `on_reconnect` → `approval.reconcile`. All other event types are ignored.
- `approval.py` `ApprovalBridge`: owns a `fifo.Fifo` worker that serializes
  asks; `enqueue_permission` submits a task → `_handle_permission` (gate +
  `decide_reply`). The one-time approval-callback install also runs as a Fifo
  task.
- `questions.py`: owns the question path as free functions (no `ApprovalBridge`
  wrapper methods). `bridge._on_question` calls
  `questions.enqueue_question(self._approval, event)`, which submits
  `handle_question` to the SAME shared `Fifo` worker → `_ask_question` →
  hold/relay/reject; `_reply_question` forwards `directory`. File under
  `hermes_opencode.questions`, separate from the approval gate logger.

## Pitfall: verify in source, not from the tool report
A `reject` with `status: "approval_required"` (message
`awaiting human review (approval queued but not delivered)`) proves the ask reached
Hermes' gate and fail-closed correctly in a headless run. It does NOT prove
permission routing reaches a human in an interactive TUI. To confirm human routing,
check the approval callback is captured LAZILY (see below).

## Fix: lazy approval-callback capture (interactive permission routing)
- Symptom: in an interactive TUI, permission asks fail-close even with a human
  present — no approval prompt surfaces.
- Root cause: `_approval_callback = _capture_approval_callback()` ran at
  `ApprovalBridge.__init__`, but the CLI installs the interactive callback AFTER
  plugin discovery, so the init-time capture was always `None`.
  `request_tool_approval` then had no delivery channel and fail-denied.
- Fix: init `_approval_callback = None`; submit `_install_approval_callback` as
  a `Fifo` task (runs on the single worker thread, after discovery) which
  recaptures `_capture_approval_callback()` then `set_approval_callback(...)`.
  Mirrors the existing lazy `_cli_ref` pattern in `bridge._inject_text`.

## E2E handoff pattern (delegate verification to another agent)
Tell the agent to drive the deferred-catalog bridge
(`tool_search` → `tool_describe` → `tool_call`) for `opencode_prompt` /
`session_tail` / `session_read` / `question_reply` / `command`, NEVER run pytest.
Require the report as a MESSAGE (paste real artifacts: session_id, assistant/
question text, permission outcome + `[opencode]` reason, question outcome + answer
supplied, command names). State explicitly which of the 3 pillars were exercised and
the evidence. If a pillar could not be exercised for a legitimate reason, say so
with evidence rather than claiming pass/fail.

## Tests
`pytest` in repo root (uv venv). Suite is 163 passed + 1 subtest (post the
fifo/router/question refactors). `events.py`/`test_events.py` were renamed to
`router.py`/`test_router.py`; question tests call `questions.*` directly (no
`ApprovalBridge` wrappers); `enqueue_permission` goes through `fifo.Fifo`.
`ruff check` clean. Run `pytest` after any structural change to confirm the
refactor didn't break the shared-FIFO serialization.
