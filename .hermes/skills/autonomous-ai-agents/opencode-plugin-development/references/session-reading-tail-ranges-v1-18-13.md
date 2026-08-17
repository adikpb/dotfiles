# Session reading for a serve bridge: idle, wait, tail + range (v1.18.13)

All symbols read from the vendored clone `.slim/clonedeps/repos/anomalyco__opencode`
(packages/protocol/src/groups/session.ts, packages/schema/src/session-status-event.ts).
Re-verify against the version you ship. This is the surface behind the
"tail-on-idle + on-demand range reads" design (NO full-transcript streaming,
nothing polled).

## Idle signals — modern vs legacy

- **Modern**: `session.status` event `{ sessionID, status: { type: "idle" |
  "busy" | "retry", ... } }` (schema/src/session-status-event.ts:35-41).
  The `retry` variant carries `attempt`, `message`, and an optional `action`
  (reason/error/title/label). React to `type: "idle"`.
- **Legacy**: `session.idle` `{ sessionID }` is marked **deprecated** in-schema
  but still in the event inventory (session-status-event.ts:44-49). Do not
  build the trigger on it.
- **Synchronous alternative (STALE — do not use)**: `POST /api/session/:sessionID/wait`
  is a declared-but-STUBBED route that ALWAYS 503s at v1.18.13
  (`OperationUnavailableError`). The real blocking handoff is client-side:
  poll `GET /api/session/active` until the session leaves the set (v2-engine
  sessions), or consume v1 `session.status {type:"idle"}` events plus a
  quiescence buffer for v1-run sessions. Keep the SSE stream subscribed for
  permissions/questions while the turn is active.
- `GET /api/session/active` — foreground session drains owned by this process
  (absent from the result = inactive). A run that ends in `step.failed` STILL
  leaves the active set (E2E-verified) — the handoff must not assume
  failure = still-busy.

## Range-read endpoints (protocol/src/groups/session.ts)

| Endpoint | Query | Returns | Use |
|---|---|---|---|
| `GET /api/session/:id/history` | `after=<seq>` (exclusive aggregate sequence), `limit` (≤ 100) | `{ data: SessionEvent.Durable[], hasMore }` | Tail + any finite range; paginate with `hasMore` + last seq |
| `GET /api/session/:id/context` | none | `SessionMessage.Message[]` | Active context = all messages after last compaction |
| `GET /api/session/:id/message/:messageID` | none | one `SessionMessage.Message` | Single-message fetch |
| `GET /api/session/:id/events` | `after=<seq>` | SSE: replay durable events after seq, then live | Reconnect-safe resume |
| `GET /api/session` (list) | `limit`, `order`, `cursor` (opaque) | `{ data, cursor.previous/next }` | Session list pagination |

Durable events carry an aggregate sequence and `after` is exclusive, so the
tail (`history?limit=N`) and exact ranges (`history?after=<start>&limit=N`)
are the same mechanism with no polling and no full-transcript fetches.

## Shaping into Hermes entries

opencode `Message` = `{id, role: user|assistant, parts[], modelID, sessionID,
time.created}`; content granularity lives in parts (`TextPart | ToolPart |
ReasoningPart | FilePart | ...`). Normalize to Hermes' messages-table shape
(hermes_state_common.py:252): `role, content, tool_call_id, tool_calls,
tool_name, timestamp, display_kind, display_metadata`:

- assistant text parts → `role: "assistant"`, `content`; ToolPart → an
  assistant row with `tool_calls`, then a `role: "tool"` row (`tool_name` =
  part.name, `content` = part.output), mirroring Hermes' own tool rows.
- `time.created` (ms) → `timestamp`; `message.id`/`sessionID` →
  display_metadata; `modelID` → display_metadata.model;
  `display_kind: "opencode_session"`.

## Design decisions locked in (2026-08-09, user-directed)

- Tail on idle: `history?after=<lastSeq>&limit=N` (default N = 8) shaped into
  Hermes-structured entries; injected pre-turn or as a tool result — never a
  synthetic user message mid-loop (Hermes hard rule).
- Mid-turn deltas (`session.next.*`) only update bridge bookkeeping (status,
  seq); NOT injected into Hermes context.
- Deeper context on demand via a Hermes model tool
  `opencode_session_read(session_id, scope: tail|context|range, after?, limit?)`.
- Reconnect: resume `GET /api/session/:id/events?after=<lastSeq>` (or re-read
  history from the stored last seq) — nothing lost, nothing re-streamed.
- Handoff modes: observed (enqueue + SSE) vs blocking (prompt → active-poll → tail).

## E2E-VERIFIED 2026-08-10 — v1.18.13 durable family (live server)

A prompt via `POST /api/session/:id/prompt` writes these durable events in
order (read back via `GET /api/session/:id/history?limit=N`):

```
session.next.prompt.admitted → session.next.prompted      # SAME messageID, both carry
                                                          # data.prompt.text (dedupe: one user row)
session.next.step.started                                 # data.model.id, data.assistantMessageID
session.next.delta                                        # data.state.kind = "text"|"tool"
session.next.tool.called | tool.success | tool.failed     # tool buckets (data.partID)
session.next.step.completed | step.failed                 # close the step; step.failed carries
                                                          # data.error.message
```

- **`session.next.start` and `session.next.stop` do NOT occur in real v1.18.13
  v2 runs** — the `step.*` family replaced them. Shapers that only handle
  start/delta/stop produce EMPTY tails on a live server.
- Wire shape per event: `{id, type, durable: {aggregateID, seq, version},
  data: {...}}`; the `after=` cursor is `durable.seq` (exclusive).
- A failed model step yields `step.failed` (e.g. provider errors) instead of
  deltas; the session STILL leaves `GET /api/session/active`. Shape the
  failure as an assistant row so tails never silently vanish.
- `history` responded 200 for a fresh v2 session that had run (durables
  present). Engine detection by probe: v2 `history?limit=1` non-empty → v2;
  else legacy `GET /session/{id}/message?limit=1` non-empty → v1 (read via
  the cursor API, `X-Next-Cursor`/Link); both empty → treat as v2.

## SSE transport pitfalls found by E2E (2026-08-10)

- **`GET /event` (v1 instance stream): the `x-opencode-directory` HEADER
  form stalls.** The server returns 200 headers but NO `server.connected`
  and NO heartbeat ever arrives (response body never starts). The
  `?directory=<path>` QUERY form streams instantly
  (workspace-routing.ts:87 reads query first). Always send the directory as
  a query param on `/event`.
- **Python `http.client` chunked `read(n)` aggregates whole chunks** until
  `n` bytes accumulate (`_read_chunked` loops). On a quiet SSE stream the
  only traffic is ~90-byte heartbeat chunks, so `resp.read(4096)` blocks
  ~forever (4+ heartbeats to fill). Use `resp.read1(4096)` (per-chunk read):
  the first chunk with `server.connected` returns instantly; heartbeats keep
  arriving every ~10 s.
- **Probe methodology that worked**: pipe-buffered subprocess stdout is lost
  when the child is SIGKILLed — write progress to a logfile inside the child
  (`open(LOG, "a")` + flush per step) and poll it from the parent. Bisect
  server-side quirks with a raw-socket/curl A/B matrix (same request bytes,
  one header added at a time) rather than guessing — headers were exonerated
  (raw socket with identical bytes worked), and the real culprit was the
  client-side chunked-read aggregation.