# OpenCode v1/v2 API surface — integration pitfalls (recon knowledge bank)

Condensed from a v1-vs-v2 recon of the `hermes-opencode-plugin` (opencode
v1.18.16 live target; vendored audit clone v1.18.13). The lessons apply to ANY
opencode server/plugin bridge, not just this repo. Read this before any
v2-adoption or v1/v2 migration work on an opencode integration.

## Surface split (one port, two engines)
- Root paths (`/session`, `/event`, `/permission`, `/question`, `/command`,
  `/global/health`) = **V1 instance surface**. Bare JSON, NO `{data}` envelope.
- `/api/...` = **V2 protocol groups**. `{data: ...}` envelope, strict schemas
  (`additionalProperties: false`).
- A reply MUST go to the route matching the event's surface:
  `permission.asked` -> root route; `permission.v2.asked` ->
  `/api/session/.../permission/.../reply`. Mixing 404s.

## Where v2 genuinely helps
1. **INTERRUPT (the one real win).** `POST /api/session/{id}/interrupt`
   (opId `v2.session.interrupt`, `handlers/session.ts` ~366, `groups/session.ts`
   ~345). Idempotent; idle/missing = no-op; **preserves durable inbox rows**
   (`specs/v2/session.md:22-27`; `CONTEXT.md:176`; `AGENTS.md:155`). V1 only has
   an unwired, unspecified `/api/session/:id/abort` (opId `session.abort`) — not
   a clean contract.

## Where v2 does NOT help / regresses
2. **TURN-COMPLETE via replay.** `GET /api/session/{id}/event?after=<seq>`
   (`handlers/session.ts` ~357 `session.events`) replays durable events after a
   seq then tails live. This FIXES the reconnect/replay gap (v1 `/event` has no
   replay on reconnect). BUT the v2 durable stream carries only
   `step.started/completed/failed` + `delta` + `tool.*` + `prompt.admitted/
   prompted` — **NO `session.status` idle/busy and NO `session.next.start/stop`**
   (`specs/v2/session.md:175`). It therefore cannot replace the v1 idle event as
   a turn-boundary signal; you'd have to infer completion from `step.completed`
   + the `active()` registry (weaker). The "tail-fingerprint dedup" hack in a v1
   bridge is v1-surface-specific and only disappears if you stop consuming v1
   idle events.
3. **BUSY/IDLE.** V1 `session.status` idle is the authoritative turn-boundary;
   v2 has no status event. V2's "is running" = `GET /api/session/active` (the
   coordinator active registry) — foreground drains of THIS process only,
   `{type:"running"}`, **EMPTY after restart**, background subagents NOT parented
   (`specs/v2/session.md:29-33,169`). Strictly weaker than v1's persistent,
   directory-scoped `/session/status` map (absent = idle).
4. **ACTIVE SET.** `GET /api/session/active` is process-local, NOT
   directory-scoped, restart-emptying, foreground-only. V1
   `/session/status?directory=` is directory-scoped and persists until idle. Do
   not substitute one for the other.

## Stubs / cross-surface traps
- `POST /api/session/{id}/wait` = **503 `OperationUnavailableError` stub**. No
  server-side blocking wait; completion detection stays client-side (event replay
  or `active()` polling).
- **CROSS-SURFACE BUG:** a v2-coordinator session is INVISIBLE to the v1 router
  and to the v1 `/session/status` map. Any v1 completion wait on it times out,
  then the final re-read (`session_id in client.session_status(...)`) finds it
  absent -> **MISREPORTS a still-running v2 session as completed**. Never mix
  surfaces for the same session.
- **RESUMABLE vs FORKED:** v1 `prompt_async` = fire-and-forget fork (ephemeral).
  v2 `prompt` with `resume:true` = durable inbox admit + advisory wake (FIFO
  queue, may not start immediately); `resume:false` = admit-only (does not run).
  `admittedSeq` is the durable seq of `PromptAdmitted`.

## Verified source anchors (vendored opencode clone)
- `handlers/session.ts`: `session.events` (`after=`) ~357; `session.interrupt` ~366
- `groups/session.ts`: `session.interrupt` endpoint ~345; `session.abort` ~91
- `specs/v2/session.md`: `active()` :29-33/:169; interrupt :22-27; replay :175-181;
  inbox FIFO :158; `session.next.*` unshipped :173
- `AGENTS.md:155` / `CONTEXT.md:176` — v2 interrupt no-op-on-idle contract

## Bridge file:line refs (current v1-only plugin, commit 4ed2f26)
- `events.py`: `wait_for_complete` :139-169; `forget()` re-arm :118-135;
  `_needs_busy`/`_saw_busy` :75-76; `session.status` dispatch :210-237; no replay
  :13-14
- `bridge.py`: `_on_busy` :167-176; `_on_idle` :180-205; `_on_turn_complete`
  (fingerprint dedup) :207-269 (`:243`/`256-259`); `baseline_fp` :494-505; stale
  check :571-582; `_wait_idle` + v1 `/session/status` re-read :550-567/:585;
  `_poll_status_idle` :588-609; cross-directory skip :486-493
- `client.py`: `session_status` (absent=idle) :193-206; `directory=` param
  :201-205; Basic auth :115-124; `prompt_async` (204, parts body, `messageID`
  `^msg`) :242-280
- `read.py`:1-13 still uses the v1 cursor API — v2 replay is **UNUSED** in this
  plugin (untested path).

## Recommendation pattern (recon outcome)
ADOPT v2 interrupt (gate behind v2-coordinator session ownership). HYBRID: keep
v1 `session.status` idle as the completion trigger; adopt `event?after=` ONLY for
reconnect robustness. KEEP v1 `/session/status` for the active set. Do NOT adopt
v2 for busy/idle or the active set — it regresses both.
