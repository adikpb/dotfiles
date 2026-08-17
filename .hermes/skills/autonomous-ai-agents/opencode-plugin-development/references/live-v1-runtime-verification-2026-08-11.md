# Live v1 runtime verification (opencode 1.18.16, 2026-08-11)

Post-migration live e2e + probe findings that static review missed. The
round-2 behavioral audit (3 agents, told to verify routes against the
vendored source) returned zero runtime findings; a live run against a real
`opencode serve` 1.18.16 (homebrew) found all three bugs below in ~15
minutes. All facts verified live + against the vendored source at 1.18.16.

## 1. `POST /session/{id}/message` BLOCKS; `prompt_async` is the fork route

- `POST /session/{sessionID}/message` → handler `prompt` →
  `promptSvc.prompt(...)` — **BLOCKS until the turn completes** (streams a
  single final-message JSON at the end). handlers/session.ts (instance
  httpapi).
- `POST /session/{sessionID}/prompt_async` → handler `promptAsync` → forks
  the turn, returns **204 No Content** immediately (~0.04s live).
- Both take the same body: `PromptPayload = Struct.omit(SessionPrompt.PromptInput.fields,
  ["sessionID"])` → `{parts, agent?, model?, id?}`.
- Symptom when a client uses the blocking route: HTTP timeout (10s) trips
  mid-turn; the turn STILL completes server-side (message appears in the
  tail) → looks like a server bug / flaky network.
- Fix: client.prompt posts to `prompt_async`, handles the 204 empty body
  (return `{}`, never `unwrap_data(None)`).

## 2. `GET /session/status` map lifecycle (wait-semantics race)

Live probe (1s poll, prompt_async → full PONG turn):

```
t=0.0s  prompt_async returned (0.04s); map: ABSENT;      tail: []
t=1.1s  map: {type:"busy"};                              tail: [user]
t=5.2s  map: busy;                                       tail: [user, assistant]
t=12.3s map: ABSENT (idle);                              tail: [user, assistant]
```

Consequences:
- **Absence at first check = "turn not started yet", NOT "already done".**
  The map only gains the entry when the forked turn starts (~1s after the
  204). A blocking wait with an early `absent ⇒ done` return resolves
  before the turn starts → false "completed" with an empty tail.
- Correct wait: event-primary (`router.wait_for_complete` on the v1
  `session.status idle` event) + one final map re-read after an event
  timeout (stream-outage rescue) + no-router fallback = map poll loop
  gated on saw-busy (absence counts as done only after the entry was
  observed busy at least once).
- **Assistant text in the tail is NOT completion**: the first text part
  appears while the turn is still busy (t=5.2s vs idle at t=12.3s). e2e
  completion checks must key on the idle event / status map, not on
  "assistant row exists".

## 3. MessageV1 response shape (GET /session/{id}/message)

Real messages: `{info: {id, role, sessionID, time: {created}, modelID | model:
{providerID, modelID}}, parts: [...]}`.

- User messages: `info.model` NESTED `{providerID, modelID}`; assistant
  messages: flat `info.modelID` (no nested model). Read BOTH.
- Flat `msg.get("role")` → None → **every message shapes as "assistant"**
  (unit fakes with flat `{id, role, parts}` dicts mask this entirely).
- Fix: shape from `info` with flat fallbacks; update unit fakes to the real
  `{info, parts}` shape AND keep one flat-fallback test.

## 4. SSE close mid-chunk: `http.client.IncompleteRead`

- On server shutdown/restart mid-chunked-stream, `resp.read1()` raises
  `http.client.IncompleteRead` — a subclass of `HTTPException`, NOT
  `OSError`/`TimeoutError` — so it escapes read loops catching only those.
- Uncaught, the event router's blanket `except Exception` logs
  "opencode event router crashed; reconnecting" with a full traceback on
  EVERY normal shutdown (scary noise, but harmless).
- Fix: catch `IncompleteRead` in the read loop → raise `StreamClosed`
  ("SSE stream closed mid-read") → router logs the quiet "event stream
  ended (server.instance.disposed)" path instead.

## 5. e2e smoke token matching

- `prompt_async` returns before the turn starts; the USER message contains
  the expected token ("Reply with exactly the single word PONG" contains
  "PONG"). Matching any row = false positive on the user's own prompt.
- Wait for an ASSISTANT row containing the token (or failure text) only.
- Also: prompt_async's instant return means the old "absent from status
  map" completion check can fire before the turn starts — wait for the
  durable trace instead.

## 6. Live probe methodology

One-off scripts (deleted after use) beat source reading for shape/semantics:

- **Status-map lifecycle**: spawn via `ensure_serve({..., "port": 0})`,
  `create_session()` + `prompt()`, then every 1s print
  `session_status()` membership + shaped tail roles until idle.
- **Raw message dump**: `GET /session/{id}/message` → `json.dumps` each
  message (this is what discovered the `info`-nesting).
- **Live bridge wait=True**: `Bridge(ctx=None, cfg={auto_serve: True,
  hostname, port: 0, username, password, prompt_timeout, tail_size})`
  → `.start()` → `prompt(..., wait=True)` → assert `timed_out is False`
  and an assistant PONG row (live: resolved in ~18s event-driven).
- Gotcha: `load_bridge_config()` takes NO arguments (reads hermes_cli
  config internally) — probe scripts must pass a cfg dict to `Bridge`
  directly, exactly like the tests do.
- Env for spawned auth: `OPENCODE_SERVER_PASSWORD`/`OPENCODE_SERVER_USERNAME`
  must be set BEFORE importing/spawning.
