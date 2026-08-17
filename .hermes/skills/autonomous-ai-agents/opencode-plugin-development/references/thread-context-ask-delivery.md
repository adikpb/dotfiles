# Ask delivery threading — why injection fails & permissions fail-close (verified 2026-08-13, opencode v1.18.16 / Hermes tui_gateway)

Two opencode-ask paths in a Hermes bridge plugin (permission + question) both broke
in a TUI session, and the cause is the SAME defect: **asks are processed on the
plugin's own background threads, which do not carry the TUI's interaction context.**

## Bug 1 — question injected into the conversation never lands

- `question.asked` fires on the SSE **reader thread** (`EventRouter._run`, a daemon
  thread), not the main conversation thread.
- `PluginContext.inject_message(content, session_key=None)` (running Hermes,
  `hermes_cli/plugins.py:~1762`) needs a `session_key` that lives on the MAIN
  thread's context-local. On the reader thread it is absent →
  `WARNING inject_message: gateway mode requires an existing session_key` → returns
  `False`.
- The plugin's `_inject_text` treats `False` as "fall back to tools" and **silently
  drops** the ask message while still holding it → the agent never sees the id and
  `opencode_question_reply`'s "id came from the injected message" contract dead-ends
  (had to `curl GET /question` to recover it).

**Wrong fix:** add an `opencode_question_list` discovery tool / `GET /question`
listing. (User rejected: "I don't want an extra tool, explore other avenues.")
**Right fix:** deliver the ask on the main conversation thread, not the reader thread
— marshal it via a thread-safe queue the main loop drains, or capture the main
thread's `session_key` context-local at register time and re-bind it on the reader
thread before calling `inject_message`. Then inline injection succeeds (original
design). No new tool.

## Bug 2 — permission ask fail-closes in TUI (NOT correct-by-design)

- `permission.asked` is handled on the plugin's **FIFO approval worker thread**.
- The Hermes gate `_is_interactive_cli()` (`tools/approval.py:95`) checks
  `_hermes_interactive_ctx` (a context-local, `None` on the worker thread) then
  falls back to the `HERMES_INTERACTIVE` env var. On the worker thread both are false.
- Because the process is `tui_gateway.entry` (TUI-as-gateway),
  `_is_gateway_approval_context()` is True → the gate takes the **gateway round-trip
  branch** (`approval.py:3344`) that needs a registered notify callback. A local TUI
  has none → no human reached → fail-closed `reject`. The plugin's
  `permission_reply` then RAISED, and even the `_fail_closed_reply_permission`
  catch-up raised → the ask was wedged.
- Log proof: `tools.approval: ... non-interactive non-gateway context ... BLOCKED
  (fail-closed). Set HERMES_INTERACTIVE or HERMES_GATEWAY_SESSION` then
  `permission ask ... handling failed` / `fail-closed reject for ... failed`.

**Wrong fix:** "set HERMES_INTERACTIVE". In tui_gateway mode the session is already a
gateway context, so an env var alone still routes to the gateway round-trip path
(needs a notify callback you don't have). (User rejected: "Why should i set a flag
just to make this work".)
**Right fix:** propagate the MAIN thread's interaction context onto the worker thread,
exactly like the plugin already does for the approval callback
(`approval.py:_capture_approval_callback` captures `_get_approval_callback` from the
registering thread; the worker installs it via `set_approval_callback`). Capture
`HERMES_INTERACTIVE` / the interactive context-local at `ApprovalBridge` construction
(on the registering thread) and re-bind it on the FIFO worker before the gate call —
then `_is_interactive_cli()` returns True → CLI prompt branch → real prompt reaches
the user. PLUS harden `permission_reply` so a reply that can't be delivered is
swallowed+logged, never thrown out of `_handle_permission` (prevents the wedged ask).

## User preference baked from this session

- **No band-aids.** Prefer the principled root-cause fix (thread-context
  propagation / main-thread handoff) over adding a tool or setting an env flag.
- **Scope discipline.** "Confirm the fixes" meant DIAGNOSE and report, not implement.
  Do not write code just because a task sounds action-y. When unsure whether to
  implement, stop and report the plan/diagnosis first. (An over-eager
  implement-then-revert cycle happened here — the user had to say "revert, I only
  asked you to come back to me.")

## How to find the real guards (recon technique)

The vendored clone (`.slim/clonedeps/repos/NousResearch__hermes-agent`, tag
`v2026.8.3`) LAGS the running build. The `session_key` warning text was NOT in the
clone. To read the actual guards, grep the INSTALLED runtime:
`~/.hermes/hermes-agent/hermes_cli/plugins.py` and
`.../tools/approval.py`. Identify the running process via `ps aux | grep hermes`
(e.g. `tui_gateway.entry`) — that tells you which approval-context branch applies.
