# hermes-opencode-plugin: v1→v2 permission/question recon

Repo: `hermes-opencode-plugin` (NousResearch). Committed **v1-ONLY** at `4ed2f26`
(deferred v2 migration). OpenCode runtime in play: **v1.18.16** at `/opt/homebrew/bin/opencode`.
Vendored opencode source under `.slim/clonedeps/repos/anomalyco__opencode/`.

## Critical caveat (drives every v2 decision)
The v1 runtime the plugin needs — the **omo-slim orchestrator** — runs as a v1 agent on
opencode v1.18.16 and emits **only v1 events** (`permission.asked`, `question.asked`).
The v2 protocol (`/api/...`, `*.v2.asked` families) is a SEPARATE surface. Anything that
assumes v2 events fire, or that the v2 REST lists are populated, is **dead surface** under
the current runtime. Verify runtime emission before adopting any v2 path.

## File:line map (v1-only implementation)
- `hermes_opencode/events.py`
  - `:1-15` docstring — v1 `/event` subscription, directory-scoped; location-filters
    `event.location.directory === instance.directory`.
  - `:178` `iter_events(directory=self._directory)` — location scoping at the event layer.
  - `:198-242` `_dispatch` — handles ONLY `permission.asked` (:238) and `question.asked` (:241).
    No v2 family handling. `:240`/`_on_permission`, `:242`/`_on_question`.
- `hermes_opencode/approval.py`
  - `:301-338` `reconcile(directory)` — re-sync after (re)connect. `:320`
    `perm_pending = self._client.permission_list(directory=directory)` (GET /permission,
    ALL sessions; bridge filters client-side). `:332-338` auto-approves same-session fan-out
    ("once"), rejects stale orphans.
  - `:256-298` `_handle_question` / question reject — event-driven ONLY; **no** GET /question
    reconcile; dispose fails silently (questions never queried at REST).
  - `:55` `question_reply(rid, answers)`, `:59` `permission_list`, `:51` `permission_reply`.
  - `:101-103` `decide_reply` → `{reply:"once", message:None}`; `:335`/`:338` reject w/ reason.
- `hermes_opencode/bridge.py`
  - `:138-140` wires `on_permission=enqueue_permission`, `on_question=_on_question`,
    `on_reconnect=lambda: reconcile(directory)`.
  - `:144` initial `reconcile` to reject orphans from before the process existed.
- `hermes_opencode/client.py`
  - `:20` `GET /permission` → pending v1 permission asks (all sessions, no location param).

## v1 vs v2 endpoint surface
Permission:
- v1: `GET /permission` (all sessions) · `POST /permission/:rid/reply` {reply,message?}
- v2: `GET /api/permission/request` (location-scoped) · `POST /api/session/:sessionID/permission/:requestID/reply` {reply,message?} — **body identical to v1**
Question:
- v1: `GET /question` · `POST /question/:rid/reply|reject` {answers}
- v2: `GET /api/question/request` (location-scoped) · `POST /api/session/:sessionID/question/:requestID/reply` {answers:string[][]} — **body identical to v1**
Events:
- v1: `permission.asked` / `question.asked`
- v2: `permission.v2.asked` / `question.v2.asked` (separate v2 stream; see caveat above)

## Recon verdict (4 candidates) — where v2 genuinely helps
1. **Permission listing** — `GET /api/permission/request` (location-scoped) GENUINELY
   simplifies reconcile orphan filtering (`approval.py:320` / `bridge.py:140,144`).
   **Adopt (hybrid):** swap the reconcile fetch to the v2 list to drop cross-directory noise.
2. **Question pending** — `GET /api/question/request` would ADD reconnect coverage the
   bridge completely lacks (questions never REST-queried). Genuine capability gain but
   **conditional** on runtime emitting/storing v2 asks (currently it doesn't). **Keep v1**
   until runtime moves to v2.
3. **Reply bodies** — v1/v2 permission AND question reply bodies are identical, so migrating
   yields NO simplification (only path/route change). **Hybrid:** safe to migrate permission
   reply to v2 path (sessionID already in props `approval.py:166`/`:177`) only if runtime
   serves v2 reply; otherwise keep v1.
4. **v2 event families** — do NOT help: v1 runtime emits only v1 asked events; subscribing
   to `*.v2.asked` is dead dispatch and risks double-handling if BOTH families are wired.
   **Keep v1 dispatch.**

## Recon methodology (how this was produced)
- `search_files(target=content)` on `events.py`/`approval.py`/`bridge.py`/`client.py` for
  `asked|permission|question|reconcile|reconnect|/permission|/question`.
- Confirm v2 routes against vendored opencode: `packages/sdk/openapi.json`
  (`/api/permission/request` ~:12729, `/api/question/request` ~:14519) and `specs/v2/api.html`;
  v2 event families in `packages/schema/src/permission.ts` (`permission.v2.asked` :43).
- Confirm v1-only reality from `wiki/concepts/opencode-question-api.md`
  ("Plugin status (2026 08 11): the plugin is V1-ONLY").

## Subagent execution note (output-contract discipline)
Tasks with a machine-validated JSON output contract MUST return ONLY the JSON object —
a ```json fence is acceptable but optional. NO prose before/after. A leading explanation
makes the whole response fail `json.loads` ("Expecting value: line 1 column 1"). Build the
structured answer in-tool, then emit the bare JSON last.
