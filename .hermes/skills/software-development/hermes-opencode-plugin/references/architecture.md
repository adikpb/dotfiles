# hermes-opencode plugin — module architecture

Final layout after the `88cd624` → `f09a995` → `5388acb` → `bc1aaef` refactors.
One concern per module; no thin back-compat wrappers; infrastructure extracted;
dispatch is register-based; the full question state machine lives in
`QuestionBridge` (no question logic on `Bridge`/ `ApprovalBridge`).

## Modules (`hermes_opencode/`)

- **`ask_bridge.py`** (new) — `AskBridge`: the shared base BOTH ask families
  subclass. Owns the shared `Fifo` worker + lifecycle (`client`/`directory`/
  `lock`/`stop`, `start()`, `submit`, `_safe`) and the overridable one-time
  worker hook `_on_started`. Also owns `AskSurface` protocol, `HELD` sentinel,
  a module-level `_safe_call` (shared by `AskBridge._safe`, `EventRouter._safe`,
  and the reply paths), and `CLARIFY_TIMEOUT_PREFIX` (single source of truth,
  imported by `bridge.py` + `questions.py`). Defines the Template-Method helper
  `_run_handle(event, body, register=None, release=None)` so both subclasses
  share id-extraction + try/except + inflight-release without copying it.
  - **`start()` contract (HIGH-severity):** `_on_started` is submitted by
    `AskBridge.start()`, NOT in `__init__`. With an injected already-running
    FIFO, submitting in `__init__` lets the worker run `_on_started` before the
    subclass finishes setting its attributes (e.g. `ApprovalBridge._approval_callback`),
    and the swallowed `AttributeError` silently leaves setup undone. `Bridge._wire`
    constructs BOTH bridges, then calls `self._approval.start()` +
    `self._question_bridge.start()`. Regression test: `StartHookTestCase`
    ("init does not run setup; start() does").

- **`approval.py`** — `ApprovalBridge(AskBridge)`: the PERMISSION/gate path ONLY.
  `enqueue_permission` uses the base `_run_handle`; `_handle_permission_body`
  + `_reconcile` are the worker body; replies (`_reply`/`_reject`/`reconcile`
  loop) route through `self._safe`. Has NO question methods and NO question
  state.

- **`questions.py`** — `QuestionBridge(AskBridge)`: owns the ENTIRE question
  path. Its OWN logger (`hermes_opencode.questions`). Members: the held
  registry (`_held`, `question_registry_pop`, `held_question_ids`), the in-flight
  set (`_inflight`), and the FULL question state machine — `mode()`
  (`question_reply_mode`, default `tool`), `is_clarify_active()`, `_ask_default()`
  (mode-driven default asker: holds/relays/rejects), `route_parts()` (message-part
  fallback routing), `resolve_id()` (pick the server `que_*` id), inject-once /
  route-once dedup (`_injected_question_ids` / `_seen_callids` +
  `already_injected`/`mark_injected`/`seen_callid`/`mark_seen_callid`),
  `format_inject()` (pure formatter), `relay_question()` (clarify panel), `_reply`/
  `_reject`, and `pop_and_reply()` (the fail-closed agent-facing reply used by
  `bridge.answer_question`). It imports only `ask_bridge` — never `approval` or
  `bridge`. `enqueue(event)` runs the body through the base `_run_handle`.
  - **No `_ask_question` back-reference:** the default asker is `_ask_default`
    (mode-driven). `Bridge` may pass a custom `ask_question=` callable, but the
    bridge never pushes its OWN question logic into the bridge via that hook.

- **`inject.py`** — CLI/TUI conversation delivery. Official path is
  `ctx.inject_message(content, session_key=...)` (classic CLI queues via
  `_cli_ref`). Ink TUI does **not** set `_cli_ref` and is a gateway host
  (`HERMES_GATEWAY_SESSION=1`); when `inject_message` returns False the
  fallback steers the live TUI turn (`agent.steer`) or `_enqueue_prompt`.
  Bind the per-turn session_key on the agent thread via `Injector.bind`.

- **`permission.py`** — `ApprovalBridge(AskBridge)`: the PERMISSION/gate path
  ONLY. `bind_session(session_key, approval_callback)` is called from
  `Bridge.prompt` on the agent thread. The worker rebinds that session_key
  before `request_tool_approval` so Ink TUI's `register_gateway_notify(key)`
  matches (a worker with no ContextVar used to look up `"default"` and
  fail-close with `approval_required`).

- **`approval.py`** — compatibility re-exports of `permission.py`. New code
  imports `hermes_opencode.permission`.

- **`bridge.py`** — top-level orchestrator ONLY. Owns the `EventRouter`, builds
  both `AskBridge` subclasses on ONE injected `Fifo`, the REST reconcile, the
  status-map watcher (turn-complete fallback), an `Injector`, and the TUI
  clarify-callback resolver (`_clarify_callback()`). For questions it wires
  `QuestionBridge` with **callbacks**, not by reaching into question internals:
  ```python
  self._question_bridge = questions.QuestionBridge(
      self._client, self._cfg, directory=self._directory,
      ask_question=self._ask_question_default,   # default asker (delegates to bridge._ask_default)
      inject=self._inject_question_text,         # Bridge performs text delivery
      clarify_callback=self._clarify_callback(), # resolved at wire time
      fifo=self._fifo,
  )
  self._approval.start(); self._question_bridge.start()
  ```
  Routing: `question.asked` → `self._question_bridge.on_event(event)`;
  message-part routing in turn-complete → `self._question_bridge.route_parts(rows, sid, client)`;
  agent answer → `self._question_bridge.pop_and_reply(question_id, answers)`
  (fail-closed via `self._safe`). `Bridge` holds NO question state — all dedup
  lives on `QuestionBridge`. Thin back-compat accessors (`_question_mode`,
  `_clarify_active`, `_resolve_question_id`, `_ask_question_default`) delegate to
  the bridge so old call sites still resolve, but new code calls the bridge
  directly.

- **`router.py`** — `EventRouter`. One directory-scoped v1 `/event` subscription
  with reconnect. **Register-based dispatch** (`register(event_type, handler)`,
  bare or `type:subtype` keys; `server.connected`/`server.heartbeat` stay
  lifecycle-special). `_safe` delegates to `ask_bridge._safe_call`. The dead
  `_stopped` attribute was removed (only `_stop` remains).

- **`fifo.py`** — generic single-worker FIFO task queue. No opencode/approval
  knowledge. `Fifo.submit(task)` enqueues a callable on one daemon worker;
  faults logged, never fatal. The run loop lives here.

- **`client.py`** — `OpenCodeClient`. `iter_events` sends the directory on the
  `x-opencode-directory` HEADER. `question_reply`/`permission_reply`/`question_reject`
  forward `directory` (the 404 fix). `question_list`/`permission_list` are the
  REST pending probes.

## Register-based dispatch pattern (reusable)

```python
class EventRouter:
    def __init__(self, client, directory=None):
        self._routes = {}  # type -> [handler]
    def register(self, event_type, handler):
        self._routes.setdefault(event_type, []).append(handler)
    def _dispatch(self, event):
        etype = event.get("type")
        if etype == "session.status":
            st = (event.get("properties") or {}).get("status") or {}
            sub = st.get("type")
            if sub: self._dispatch_route(f"session.status:{sub}", event)
            return
        if etype: self._dispatch_route(etype, event)
    def _dispatch_route(self, key, event):
        for h in self._routes.get(key, []):
            self._safe(h, event)
```
This keeps the router free of domain semantics; the bridge owns the route
table. Prefer this over `if/elif` when an event surface has more than 2-3 types.

## Tests to repoint on refactor

- Question tests build a `QuestionBridge` directly and call
  `qb.enqueue(event)` / `qb._ask_default(props)` / `qb.held_question_ids()` /
  `qb.question_registry_pop(...)` — never through `ApprovalBridge` wrappers.
- Message-part routing test calls
  `bridge._question_bridge.route_parts(rows, sid, client)`.
- `StartHookTestCase` pins the `AskBridge.start()` race fix (init does not run
  `_on_started`; `start()` does).
- Router tests live in `tests/test_router.py`, built against `register(...)`.
- FIFO ordering test uses `bridge.enqueue_permission(...)`.
