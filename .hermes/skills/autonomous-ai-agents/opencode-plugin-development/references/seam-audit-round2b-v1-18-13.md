# ROUND-2B seam audit — opencode v1.18.13 ↔ hermes-agent v2026.8.3 (2026-08-09)

Round-2B continuation of `integration-seams-v1-18-13-audit.md` /
`wiki-audit-round2-v1-18-13.md`. Every finding below is NEW (not a re-report of
R1/R2 corrections). Verified against clones:
`.slim/clonedeps/repos/anomalyco__opencode` (v1.18.13) and
`.slim/clonedeps/repos/NousResearch__hermes-agent` (v2026.8.3).

## F1 — HIGH: v2 `/api/event` stream is fatal on v1-only event types

- `packages/server/src/handlers/event.ts:16` — every frame is
  `JSON.stringify(Schema.encodeUnknownSync(OpenCodeEvent)(data))`.
  `encodeUnknownSync` THROWS on union mismatch (no catch anywhere in the map).
- `packages/protocol/src/groups/event.ts:52-54` — `OpenCodeEvent` built from
  `EventManifest.ServerDefinitions` ONLY.
- `packages/schema/src/event-manifest.ts:57-61` (ServerDefinitions) vs `:63-82`
  (full Definitions): ServerDefinitions excludes PermissionV1, QuestionV1,
  SessionStatusEvent, Lsp/Mcp/Tui/Installation/Project/Worktree/Vcs events.
- The bus is shared and UNFILTERED: `EventV2.allBounded` subscribes via
  `events.listen` to every publish (`packages/core/src/event.ts:152-160`,
  `:606-613` `listen` pushes to a plain `listeners[]` array; `notify` at
  `:406-417` calls ALL listeners with every event).
- v1 publishers go through the SAME bus: `packages/opencode/src/question/index.ts:104`
  publishes `QuestionV1.Event.Asked` via `EventV2Bridge.Service`; same for v1
  permission (`permission/index.ts`) and SessionStatus (`session/status.ts`).
- Consequence: the first `session.status` / `permission.asked` /
  `question.asked` crossing the bus makes the encoder throw inside
  `Stream.map` → the SSE response dies with NO terminal frame.
  `server.ts:30-39` merges heartbeat with `haltStrategy:"left"` so the
  keepalive dies too — reconnect detection = socket close/error only.
- Mitigation for a bridge: prefer v1 `/event` for ask routing (it maps
  `{id,type,properties}` with no schema encode, instance handlers/event.ts:40);
  if `/api/event` is used, treat it as best-effort with reconnect + REST
  reconcile (`GET /api/permission/request`, `GET /api/question/request`).

## F2 — wiki path error persists: replay is SINGULAR

- Source: `packages/protocol/src/groups/session.ts:327` —
  `GET /api/session/:sessionID/event` (singular), query `after`.
- Wiki still wrong at: `wiki/concepts/opencode-event-streams.md:49` —
  `GET /api/session/:id/events?after=<seq>` (plural). Following the wiki
  404s. (R2 already flagged 4 pages; this one still drifted at audit time.)

## F3 — MEDIUM: instance dispose fails pending asks WITHOUT a terminal event

- `packages/opencode/src/question/index.ts:74-81` — `Effect.addFinalizer`
  fails every pending deferred with `RejectedError` but NEVER publishes
  `question.rejected` (only the explicit `reject()` route publishes,
  `:134-148`). Same silent-fail pattern in the v1 permission service.
- A bridge holding a pending ask sees `server.instance.disposed` (v1 stream)
  or socket close (v2) and the ask just vanishes — no rejection frame, no
  REST tombstone (the pending map entry is cleared by the finalizer).
- Wiki fix: `hermes-approval-route.md` / `opencode-question-api.md` —
  document: on dispose/stream-close, treat all in-flight asks as
  rejected-with-reason, then reconcile via `GET /question` / `GET /permission`.

## F4 — MEDIUM: opencode NEVER returns busy on prompt — concurrent prompts queue invisibly

- v2 prompt handler maps only `Session.NotFoundError` and
  `Session.PromptConflictError` (`packages/server/src/handlers/session.ts:140-170`).
- v1 `prompt` (`instance/httpapi/handlers/session.ts:295-309`) and
  `promptAsync` (`:311-329`) have NO `mapBusy`; `mapBusy` appears ONLY on
  shell (`:346`), revert/unrevert (`:354,359`), deleteMessage (`:384`).
- So two overlapping prompts on one session both return 200 (v1) / Admitted
  (v2); serialization happens downstream inside the runner, invisible to the
  HTTP caller. The bridge's own active-poll/wait loop is the ONLY serializer.
- v2 `SessionInput.Admitted` (core/src/session/input.ts) is returned
  immediately; `resume:false` = admit-only, no wake.

## F5 — MEDIUM: v1 `/event` "global" subscription is not actually global; unbounded queue

- `instance/httpapi/handlers/event.ts:31` — `Queue.unbounded` (v1) vs v2's
  bounded 256 (`server/src/handlers/event.ts:9`).
- `:36-38` — filter `event.location?.directory === instance.directory`
  DROPS events with undefined location. A stream connected without a
  directory header is still filtered by instance directory, and events
  published outside an instance context (no Location service, no
  InstanceRef — event-v2-bridge.ts:22-23 publishes with `options.location`
  only when set) never reach it. Wiki says "global without one"
  (opencode-event-streams.md:19-20) — that's only true for events that
  carry a matching directory.
- Unbounded v1 queue = memory blowup under burst with a slow consumer
  (v2 fails the subscriber instead).

## F6 — LOW: Hermes v2026.8.3 has NO plugin unload/dispose hook

- `hermes_cli/plugins.py` — searched for `unload|disable|cleanup|dispose|
  stop|terminate|atexit`; no teardown callback surface for plugins
  (registered hooks: middleware, skills, tools, llm override only).
- A bridge plugin cannot rely on a Hermes-side teardown hook to kill the
  spawned `opencode serve` subprocess. The plugin must own teardown itself
  (process-group kill, atexit, or explicit lifecycle command).

## F7 — LOW: `plan_exit` is question-backed

- `packages/opencode/src/tool/plan.ts:30-44` — plan-mode completion asks
  "switch to build agent?" via `question.ask`; answer "No" →
  `Question.RejectedError`. So plan-agent flows emit `question.asked` and
  must be answered through the question API — include in the question-API
  surface inventory.

## Verified non-findings (R1/R2 claims still hold at v1.18.13)

- Session-create-then-prompt race is CLOSED: durable `Created` projector and
  its DB row commit inside the same transaction (core/src/event.ts:320-347),
  HTTP create response sent only after publish returns; concurrent same-id
  creates deterministically return the winner (core/src/session.ts:241-259).
- `?after=` replay has no tail/history gap: wake PubSub registered BEFORE the
  first `readAfter` (core/src/event.ts:565-604); wakes are `sliding(1)`
  coalescing — no loss, benign duplicates possible.
- Per-aggregate wake bookkeeping is per-subscriber (core/src/event.ts:565-583)
  — closing one session stream never kills another's.
- `session.wait` still a stub → 503 (`packages/server/src/handlers/session.ts:197-218`).
- v2 heartbeat 15s SSE-comment vs v1 10s `server.heartbeat` event:
  `server/src/handlers/event.ts:37` vs `instance/httpapi/handlers/event.ts:63`.
- `interrupt`/`revert` live v2 surfaces: `protocol/src/groups/session.ts:345-358`,
  `core/src/session.ts:170-179`.

## Suggested wiki fixes (mapped)

| Finding | Wiki page:line | Fix |
|---|---|---|
| F1 | opencode-event-streams.md:37-47 | Replace "does NOT include" with "v1-only types on the shared bus TERMINATE the v2 stream (encode throw); safe only without v1 publishers; treat as best-effort + reconnect" |
| F2 | opencode-event-streams.md:49 | `/event` singular |
| F3 | hermes-approval-route.md, opencode-question-api.md | dispose/close ⇒ reject-all-pending + reconcile; no terminal frame |
| F4 | plugin-requirements.md (R1 blocking) | prompts never 4xx busy; admitted+queued; bridge wait-loop is the only serializer |
| F5 | opencode-event-streams.md:19-20 | undefined-location events dropped even on "global" subscriptions; v1 unbounded FIFO |
| F6 | process-lifecycle section (if any) | bridge owns subprocess teardown; no Hermes hook |
| F7 | opencode-question-api.md | plan_exit emits question.asked |
