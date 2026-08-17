# Seam audit — ROUND 3 (2026-08-09), opencode v1.18.13 / hermes v2026.8.3

Third round of the read-only 3-subagent audit loop (opencode-side / hermes-side /
integration seams), dispatched after rounds 1-2 were applied. Result: the
**opencode-side agent returned zero actionable findings** (convergence evidence
for the loop); the integration agent returned 4 genuinely new contract gaps
(none contradict existing text); the hermes-side agent returned 6 new gaps
(separate file: `hermes-wiki-audit-round3-v2026-8-3.md`). All load-bearing
claims below were re-verified against the vendored clones before writing.

## F1 — `/api/session/active` only sees v2-coordinator sessions

- Handler: `session.active` service call, `packages/server/src/handlers/session.ts:81-88`.
- Source of the active set: `packages/core/src/session/execution/local.ts:31-36`
  (`active: coordinator.active`) — owned by the v2 `SessionRunCoordinator`.
- A session driven by the v1 classic runner (`SessionRunState`/`Runner`) never
  appears; its idle signal is the v1 `session.status` event.
- Consequence: a pure active-poll blocking handoff can spin to client timeout
  on a v1-run session — the very sessions the contract mandates for
  asks/idle (R5). Fix: for v1, block on `session.status {type:"idle"}` or
  event quiescence + timeout.
- Also corrected the sibling bullet "v2-coordinator foreground session drains;
  absent = inactive" — v1 sessions never appear in this set.

## F2 — Server-side `always` sibling fan-out vs reconnect gap

- Verified: resolving one ask with `"always"` resolves every same-session
  sibling with matching patterns and publishes for each:
  `permission/index.ts:153-166` — `events.publish(Event.Replied, {sessionID,
  requestID, reply: "always"})` (the :160-164 block).
- The bridge never SENDS `"always"` (reply-`once` policy), but the fan-out
  publishes it anyway. During a disconnect spanning that reply the bridge
  saw neither the sibling `permission.asked` (never records the pattern in
  Hermes `command_allowlist`) nor their replies; the later pending-list
  reconcile re-lists them as pending, and a blanket reject (R3) cancels asks
  the model already holds an approval for.
- Contract rule added: on reconcile, treat same-session sibling asks that are
  no longer in pending (or whose session had a replied sibling during the
  gap) as auto-approved `once`. Do not re-ask, do not reject.

## F3 — Startup stale-ask rejection races the fan-out

- Round-2 R3 recovery said "list pending and reject stale asks" without
  ordering. Same-session asks can be mid-fan-out of a just-sent `"always"`
  reply; an immediate blanket reject can cancel them.
- Contract rule added: order the reconcile AFTER stream quiescence — one
  heartbeat/idle cycle with no new permission events, or after the startup
  tail fetch — before rejecting anything.

## F4 — Port resolution in auto-serve

- `serve` defaults `--port 0`; when 4096 is taken it rebinds via a 4096-first
  fallback (`packages/opencode/src/server.ts:117-121` region). The configured
  port is a preference, not the bound port.
- Only reliable signal: serve stdout banner `opencode server listening on
  http://…` (`packages/opencode/src/cli/cmd/serve.ts:20`). The JS SDK spawner
  parses exactly this. Auto-serve must do the same (or probe the fallback),
  else attach/verify hangs on the wrong port.

## Mid-verification item CLOSED (round-2 leftover)

- Task agent ran out of tool calls before confirming the v1 `/event` route
  declares the `directory`/`workspace` query fields. Verified this round:
  `packages/opencode/src/server/routes/instance/httpapi/groups/event.ts:19-25`
  — `HttpApiEndpoint.get("subscribe", EventPaths.event, { query:
  WorkspaceRoutingQuery, ... })` with `.middleware(InstanceContextMiddleware)
  .middleware(WorkspaceRoutingMiddleware) .middleware(Authorization)`.
  The wiki's `?directory=` usage on the v1 SSE stream is valid.

## Round-3 audit method notes

- **Restart decision rule**: user said "it timed out again, restart them" —
  the batch had actually COMPLETED with full reports (the round-2 429s were
  a different batch, already re-dispatched). Before re-dispatching on
  suspicion of failure, read the completion notice's per-task `status=` /
  `api_calls=` lines and the on-disk `subagent-summary-*.txt` files.
  Completed-with-content = process, never restart. Empty/error-only = re-dispatch.
- **Labeled caveats are unverified**: task-2 flagged one item "mid-verification
  (ran out of calls)" — verified it separately before relying on adjacent
  claims. Always scan report tails for these markers.
- **A later round can disprove an earlier applied fix**: round 3 overturned
  the round-2 wiki claim that `pending_approval` is execute_code-specific
  (both command guards return it, approval.py:3905-3927). That is the loop
  converging, not round N+1 being wrong — expect and re-check it.