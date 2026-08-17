# tool{} Question-Ask Stall + opencode-internal Fail-Closed (headless repro)

Observed live in a read-only Hermes session driving the hermes-opencode plugin via the
deferred `tool_call` bridge (tools invoked as `tool_call(name="opencode_*")`, never by
bare name — bare-name calls fail with `Tool 'opencode_prompt' does not exist`).

## Session 1 — `ses_example_stall_a`

Prompt: `ask me: which shell am I in and what is the current working directory?`

`opencode_prompt` returned `{"running": true}` with the user message only. Stable tail
across repeated `opencode_session_tail` / `opencode_session_read` reads:

```
{"role": "user", "content": "ask me: which shell am I in and what is the current working directory?",
 "display_kind": "opencode_session", "display_metadata": {"message_id": "msg_example_1", ...}}
{"role": "assistant", "content": null,
 "tool_calls": [{"id": "call_example_1", "type": "function",
                 "function": {"name": "tool", "arguments": "{}"}}], ...}
{"role": "tool", "content": null, "tool_call_id": "call_example_1", "tool_name": "tool", ...}
```

**What happened:** opencode emitted the legacy AskUserQuestion v1 shape — a `tool`
tool-call with **empty arguments `{}`** — and the turn FREEZED. No `[opencode] question`
user message was injected into the Hermes conversation. No `que_...` id was ever produced.
`opencode_question_reply` had nothing to answer; the session never went idle.

**Tell:** a lone `tool` tool-call with `arguments: "{}"` and no subsequent assistant
content = ask stalled, not pending. Do not wait for an idle event that will never arrive.

## Session 2 — `ses_example_stall_b`

Prompt: `run: rm -rf /tmp/opencode_probe_check_* then tell me the result`

opencode hit its OWN internal permission gate (`external_directory /tmp/*`) and returned
a **completed assistant turn** — not a Hermes approval prompt:

```
{"role": "assistant",
 "content": "The command was blocked before execution. Permission for `/tmp/*`
  (external directory access) requires interactive approval, which isn't available in
  this session — a plugin flagged it for human confirmation.
  **Result:** `rm -rf /tmp/opencode_probe_check_*` did **not** run. ...", ...}
```

**What happened:** the denial came from opencode's internal permission system, not from
Hermes' approval gate. The destructive command never ran, and no interactive approve/
deny message reached the Hermes conversation. A completed assistant turn that says
"blocked" is a silent fail-closed, not a real approval prompt.

## Takeaways for the e2e skill

- Two distinct question-ask failure modes now documented:
  1. paraphrased prose (completed turn, no id) — `headless-ask-repro.md`
  2. structured `tool{}` stall (frozen turn, no inline question, no id) — this file
- Two distinct permission-deny paths:
  1. Hermes gate BLOCKED tool error (`state.status="error"`, `[opencode]` reason)
  2. opencode-internal fail-closed surfacing as a completed assistant turn (this file)
- No `inject refused` / `handling failed` / `fail-closed` log lines surfaced in Hermes
  tool output for either case — the failures are visible only in the session tail.
- Both sessions left untouched (read-only test).
