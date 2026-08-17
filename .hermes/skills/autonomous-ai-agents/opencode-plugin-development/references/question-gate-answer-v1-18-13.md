# Question handling: injected to the main agent, gate REMOVED (2026-08-10)

Supersedes the earlier gate design (this file previously documented
`question_reply_mode=gate`; the gate path is deleted). The user rejected gate
routing outright: "I hate how this is handled, get rid of gate, it shouldnt be
routed through the permissions thing, the permission auxialliary agent has very
different instructions. I want the main agent itself to answer the question. The
agent shouldnt need to query the questions to answer it, that wont be event
driven. Default to tool."

Rule of thumb going forward: **the approval gate is for PERMISSION asks only**.
Questions arrive in the main agent's conversation (injected, like turn-complete
tails) and the agent answers them with a tool call, no query round trip.

## The flow (question_reply_mode=tool, the default)

SSE `question.asked` / `question.v2.asked` → `Bridge._on_question`:

1. mode resolves tool → `_inject_question(event)` formats and injects ONE user
   message via `PluginContext.inject_message` (same channel as turn-complete):

   ```
   [opencode] question | session <sid> | id <rid>
   1. <question text> [options: y, n | custom (type your own): ...]
   Answer with opencode_question_reply(question_id='<rid>', answers=[...]).
   ```

   Once per rid (`_injected_questions` set; router re-fires dedup to 1).
2. `ApprovalBridge.enqueue_question` holds the ask in `_questions[rid]` =
   `{"family": "v1"|"v2", "session_id"}`; the FIFO worker does NOT reply.
3. The agent answers by id: `opencode_question_reply → answer_question(rid,
   answers)` pops the registry and sends on the matching surface
   (`question_reply` root vs `question_reply_v2` session route).

Mode table:

| mode | behavior |
|---|---|
| `tool` (default) | Inject once + hold for the agent; agent answers via `opencode_question_reply`. |
| `auto_first` | Silent: reply first non-custom option per question (legacy `auto_answer_questions: true` alias). Never injects. |
| `reject` | Fail-closed: every ask rejected (questions have NO server-side timeout). Never injects. |
| (any invalid, incl. `gate`) | warn + fall back to `tool` (config.py and `_question_mode` both drop `gate`). |

Fail-closed guard in `_handle_question` (applies in EVERY mode, replaced the old
gate-branch guard): asker returns `None` → reject; not a list → reject; any empty
answer entry (e.g. custom-only options in auto_first) → reject with a warning —
never reply empty answers. `auto_first_answers(questions)` still returns `[]` for
custom-only questions; the handler converts that to a reject.

## Implementation map (hermes_opencode, commit c9c9728)

- `bridge.py`: wiring `on_question=self._on_question` (was
  `self._approval.enqueue_question`); `_on_question` (resolve mode, inject once,
  then enqueue), `_inject_question` (formatter), shared `_inject_text`
  (fail-safe: no ctx → False, `inject_message` raises/refuses → False, never
  raises); `_ask_question_default` now returns HELD for tool (its old "gate →
  unreachable error" branch deleted). Dedup by rid set, NOT content fingerprint
  (that is the turn-complete dedup: shaped rows drop `durable.seq`, so seq
  comparisons silently never fire).
- `approval.py`: `_question_mode()` default → `tool` (else `auto_first` if
  `auto_answer_questions`); `_gate_question` DELETED; `_handle_question` mode
  check removed (the injected asker decides); fail-closed guard added. The
  bridge always passes its own asker; the ApprovalBridge default asker is
  `lambda props: None` — tests must pass an explicit asker.
- `config.py:load_bridge_config()`: default `"tool"`, valid set
  (`auto_first`, `reject`, `tool`) — `gate` warns + falls back.
- `tools.py`: `opencode_question_reply` description teaches the injected-message
  shape (id from the injected message, no listing needed).

## Pitfalls

- **ApprovalBridge default asker returns None** → tool-mode asks get rejected,
  never held, unless the wiring/tests pass an asker (bridge does; direct
  `ApprovalBridge` tests must pass `ask_question=lambda props: HELD` for tool,
  `auto_first_answers(props.get("questions") or [])` for auto_first).
- **Whitelist-filtered config keys**: `load_bridge_config()` returns a FIXED
  whitelist dict — keys not in it never reach the Bridge. Add every new key to
  the returned dict + validation, then assert
  `load_bridge_config()["<key>"] == <default>` in a test (the old gate-era
  `reject` default was README-only and DEAD until wired).
- **Pyright + unittest helpers**: `assertIsInstance`/`assertIsNotNone` do NOT
  narrow through a helper method — return the narrowed value via explicit
  `if not isinstance(...): raise AssertionError(...)` with a return annotation
  (`def ctx(self) -> FakeCtx:`), else lambdas calling the helper stay
  `X | None`.
- **Patch hygiene**: `old_string` must include enough surrounding context —
  twice this session a too-narrow match silently mangled the neighboring block
  (router wiring replaced wholesale; a stale `question_mode = "gate"` line
  survived the config default change). Keep single patch payloads small (a very
  large patch call can time out the stream before delivery).

## Tests (tests/test_approval.py + tests/test_bridge.py)

- `ToolQuestionTestCase` (replaced `QuestionGateTestCase`): tool-is-default
  (cfg without the key → held, no reply, gate-call tracker empty), tool-hold
  never calls gate, pop-then-reply, v2 family kept for the reply route,
  auto_first silent (reply `[["y"]]`, no injection), auto_first custom-only →
  reject, reject mode.
- Bridge injection tests: injected-once-with-shape (assert the exact
  `opencode_question_reply(question_id=...)` instruction + option labels),
  dedup same rid, one-per-ask across rids, NOT injected in auto_first/reject,
  end-to-end answer-by-id after injection. FakeBridgeClient gained
  `question_reply(_v2)`/`question_reject(_v2)` recorders; FakeCtx records
  `inject_message` calls. 158 tests + 2 subtests green at c9c9728.