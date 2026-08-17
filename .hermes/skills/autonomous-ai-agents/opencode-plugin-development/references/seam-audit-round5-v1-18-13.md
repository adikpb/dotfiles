# Integration-seam ROUND-5 audit (2026-08-09) — v1.18.13 / v2026.8.3

Fresh audit of the integration-seam contract (wiki/concepts/plugin-requirements.md
R1-R7 + the 8 pages it links), verified against both vendored clones at the
pinned tags (`git describe`: opencode v1.18.13 = a105350; hermes v2026.8.3 =
3c27eb6). One NEW substantive finding; everything else re-verified clean.

## NEW FINDING — v2 durable read surfaces are EMPTY for v1-run sessions

The contract's R2 / opencode-session-reading direct the bridge to read tails
and ranges via `GET /api/session/:id/history`, `/context`, `/message/:id`,
`/event?after=` — described as "the durable aggregate". At v1.18.13 those
endpoints return **nothing** for sessions run by the v1 classic runner, which
is precisely the population the contract's own idle signal (`session.status`)
carries.

### Proof chain (cite path:line)

1. `history` / `event?after=` read `EventTable`, filtered to the manifest's
   definitions: `readAggregate` (packages/core/src/event.ts:63-108), called by
   `V2Session.history` (core/src/session.ts:352-359) and `V2Session.events`
   (:346-351, `events.durable`).
2. The session manifest is `SessionDurable = SessionEvent.DurableDefinitions`
   (schema/src/durable-event-manifest.ts:7-10). Only `SessionEvent` carries a
   `durable:` field anywhere in schema (grep `durable:` → only
   schema/src/session-event.ts:39,45); SessionV1 events have none, so
   `Durable` (durable-event-manifest.ts:12-15) contributes zero v1 types.
3. Every `SessionEvent.*` publisher lives under packages/core/src/session/*
   (v2 core: runner/publish-llm-event.ts, input.ts, projector.ts, compaction.ts,
   revert.ts, message-updater.ts). No publisher in packages/opencode/src (the
   v1 runtime) writes a durable event — v1 emits only non-durable
   `SessionV1.Event.*`/`MessageV2.Event.PartDelta` (opencode/src/session/
   session.ts:537-886, message-v2.ts:55-61). EventTable rows are inserted only
   for definitions with `durable` (core/event.ts:217-218, 337).
4. `context` reads `SessionMessageTable` (core/src/session/history.ts:35-49;
   store.ts:39-44), written ONLY by the v2 projector (core/src/session/
   projector.ts:114-121). `message/:id` reads the same table (store.ts:45-58).
5. `result.get(sessionID)` reads the SHARED `SessionTable` (store.ts:35-38),
   which v1 also populates (core/src/session/sql.ts:22) → **v2 history/context/
   message on a v1-run session return HTTP 200 with `{data: [], hasMore:false}`
   or NOT_FOUND-able empty — never a 404**, so "route exists" does not signal
   emptiness.
6. The v1 content actually exists in legacy `message`/`part` tables
   (core/src/session/sql.ts:68-98; opencode/src/session/message-v2.ts:30),
   readable via the legacy cursor-paginated `GET /session/{id}/message`
   (instance httpapi handlers/session.ts:106-145, Link/X-Next-Cursor headers).

### Contract impact

- R2 "Tail on idle: GET /api/session/:id/history?after=…" + R5 "use the v2
  route when both consumers work (history/context/prompt)" compose to an
  **empty tail for exactly the v1-idle sessions the contract centers on**.
- The R2 retry-with-backoff note ("durable row commits asynchronously after
  the idle event") only covers a v2-side commit lag; on the v1 path there is
  no durable row at all — retry never converges.
- Fix direction for the wiki: route tail/range reads **by engine** — v2-run
  sessions → v2 durable routes; v1-run sessions → legacy message/part API
  (currently specified NOWHERE in the wiki as a tail/range source), or
  document a projection. `session.status`-idle (v1) sessions must not feed
  v2 history/context.

## Verified-clean this round (spot-checked, no new gaps)

- R1: banner `opencode server listening on http://…` (cli/cmd/serve.ts:20);
  4096-first fallback rebind only when `--port 0` (server.ts:117-121; explicit
  port does NOT fall back); `--mdns` flips hostname to 0.0.0.0 (network.ts:70-74);
  auth required/empty-disables (opencode server/auth.ts:24-26;
  packages/server/src/auth.ts:40-42; both authorization middlewares :90/:42);
  `?auth_token=` fallback in both middlewares; `PromptConflictError` + idempotent
  `id` (core/session.ts:374-381); `resume:false` admit-only (:382); wait/shell/
  skill/compact 503 stubs (:387-424); prompt handler maps only
  NotFound/Conflict (server/handlers/session.ts:140-170).
- R2: v1 `/event` unbounded queue + `{id,type,properties}` envelope + 10s
  heartbeat + location filter + no replay (instance handlers/event.ts:15-71);
  v2 `/api/event` capacity 256 + 15s comment heartbeat + `encodeUnknownSync`
  throw (server handlers/event.ts:9,16,37; protocol groups/event.ts:52
  ServerDefinitions only); history limit 50 default / 100 max
  (server/handlers/session.ts:17,339; protocol groups/session.ts:87);
  dispose-fails-pending-without-terminal (permission/index.ts:54-61;
  question/index.ts:74-81).
- R3/R3b: ask blocks with no server-side timeout (permission/index.ts:98-107);
  one-directional same-session sibling fan-out (:109-166, publishes
  `permission.replied {reply:"always"}`); CorrectedError vs bare RejectedError
  (core/src/v1/permission.ts:7-17); Hermes gate `request_tool_approval`
  (approval.py:3299), hardcoded `display_target` (:3360), rule_key derivation
  (:3345-3357), smart branch only at :3749/:4117, indistinguishable returns
  (:3033-3038, :3146-3152, :3212), timeout 300 (:2798-2809), load-at-import
  (:4350-4351), `command_allowlist` persistence (:2546-2554), tirith
  session-max (:3888-3902), unregister-unblocks-all (:2325-2335).
- R4: question tool serve-enabled (tool/registry.ts:202-203;
  effect/runtime-flags.ts:41,56); plan-completion confirm question
  (tool/plan.ts:30-44).

## Audit method used (reusable)

To test "endpoint X returns the session's data" claims in the dual-surface
server: (a) find the endpoint's handler + service call; (b) find which db
table/aggregate the read targets; (c) grep the schema for `durable:` markers
to learn which engine writes that aggregate; (d) repo-wide grep for the event
publishers of that aggregate; (e) check whether the session-row lookup
(`result.get` / `requireSession`) is shared across engines — a shared table
masks the emptiness as a 200-with-empty-body instead of a 404.

## Minor line-cite drift (claim correct, cite off)

- R1 cites the `--mdns`→0.0.0.0 flip at cli/network.ts:17-19; the flip logic
  is at network.ts:70-74 (17-19 declares the hostname default 127.0.0.1).