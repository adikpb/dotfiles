# Inject-silent-noop repro — hermes-opencode live drive (tool-driven)

Session date: 2026-08-14. opencode serve `127.0.0.1:4096`, no-auth, opencode
v1.18.16, model `deepseek-v4-flash-free`, bridge `directory=/tmp`. Tools driven via
the deferred Hermes catalog (`tool_search` → `tool_describe` → `tool_call`), i.e. NOT
from a human sitting in the interactive TUI.

## What was driven

| session_id | task | outcome |
|---|---|---|
| ses_example_math | "7×8+13", pure reasoning | completed (tail `69`) |
| ses_example_fib | "first 20 Fibonacci", pure reasoning | completed (tail `...6765 / 17710`) |
| ses_example_ask_wedge | "ask me A or B before proceeding" | emitted `question` tool-part, then **wedged** (see below) |
| ses_example_bash | "list /tmp and count" (bash) | bash tool call emitted, then **blocked** on permission; ask never surfaced |

## Failure 1 — none of the three event-driven pillars injected anything

Across all four turns, NOT ONE of these appeared in the conversation, unprompted or
otherwise:
- `[opencode] turn complete | session … | N rows | …` (sessions A/B above completed)
- `[opencode] question | session … | id …` (session B emitted a question)
- any permission approval prompt (session D blocked on bash)

Yet every **direct read** worked:
- `opencode_session_tail(session_id=...)` returned the shaped rows (incl. the full
  `question` payload and the completed `69` / `17710` answers).
- `GET /session/status` returned `{}` (idle map empty → the turn-complete trigger was
  satisfied).
- `GET /session/<sid>` returned `{"time":{"updated":…},"title":…}` confirming turns
  finished.

Interpretation (against source `bridge.py:_inject_text`): `tool_call`-driven
verification has no live `cli_ref` and no `session_key` ContextVar on the background
watcher/router threads, so `_inject_text` returns `False` ("inject unavailable: no
plugin ctx") and the source deliberately falls back to "tail tool remains the
fallback." **This is a harness/delivery limitation, not necessarily a fix regression.**
The "injected message must arrive unprompted" acceptance criterion can only be satisfied
in a real interactive TUI.

## Failure 2 — structured `question` tool-part with no `que_` id (reply 404, wedged)

Session B tail (verbatim-shaped) showed opencode DID emit a real question:

```
role: assistant, tool_calls: [{id: call_example_2, function:
  {name: "question", arguments: {"questions":[{"header":"Script approach",
  "options":[{"label":"Option A: Python script",…},{"label":"Option B: Shell script",…}],
  "question":"Which approach would you prefer for this task?"}]}}}]
```

But:
- `GET /question` → `[]` (opencode never registered it as a pending `que_*`).
- No SSE `question.asked` injection surfaced.
- `opencode_question_reply(question_id="que_example_missing",
  answers=["Option A: Python script"])` →
  `HTTP 404 Question request not found: que_example_missing`.

The `callID` is not a server `que_` id. Because the pending list was empty, the fix's
`_route_question_parts` → `_resolve_question_id` found no candidate and `continue`d, so
nothing was injected or held. opencode is now stuck mid-turn waiting on an answer it
never exposed as a resolvable request (no server-side timeout).

## Failure 3 — permission ask blocked but never surfaced

Session D (`ls /tmp; wc -l`): opencode config `bash: "*": "ask"` means the delegated
bash must ask. Tail showed the `bash` tool call then a `tool` row with `content: null`
and no result. `GET /permission` → `[]`; `GET /session/status` → `{}`. The ask was held
on the Hermes ApprovalBridge side and **never reached the human as a dialog** — no
approve/deny prompt, no opencode-side pending entry. Turn stalled (silent fail-closed).

## REST probe set (verification without relying on injections)

```
B=http://127.0.0.1:4096
curl -s "$B/session/status"                                  # {} == all idle
curl -s "$B/question"                                        # pending que_* asks
curl -s "$B/permission"                                      # pending permission asks
curl -s "$B/session/<sid>" | python3 -c '… time.updated, title'
curl -s "$B/session/<sid>/message?limit=40"                  # raw tool-call state
```

Use these to confirm completion/blocked-state independently of the (possibly
unavailable) inject path.

## Precondition recipe — smart approval

```
hermes config get approvals.mode      # → smart  (Scenario C precondition)
```

Do NOT grep `~/.hermes/config.yaml` for `approvals.mode` — the file carries an
`approval:` (model-provider) block, not an `approvals.mode` key.
