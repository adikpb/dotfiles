# OpenCode v1.18.13 ↔ Hermes integration seams — audit findings

Source-verified seam audit (2026-08-09) of the vendored clones
(`.slim/clonedeps/repos/anomalyco__opencode` @ v1.18.13, `NousResearch__hermes-agent`
@ v2026.8.3) against the in-repo bridge wiki (`<repo>/wiki/`, R1–R7). All claims
below verified IN SOURCE at that tag. Use this when wiring the Hermes↔OpenCode
bridge or when fact-checking the wiki's endpoint/event claims.

## Mounted wire surface (serve mode)

`OpenCodeHttpApi` (opencode/src/server/routes/instance/httpapi/api.ts:79-94)
mounts BOTH v2 protocol (`/api/...`, `ServerApi` = `makeApi(...)` from
protocol/src/api.ts with groups: health/location/agent/session/message/model/
provider/integration/credential/permission/fs/command/skill/event/pty/question/
reference/project-copy) AND legacy instance routes (`/session`,
`/experimental`, `/tui`, `/permission`, `/question`, `/event`, ...). No
`packages/protocol/src/http` dir exists at this tag and NO `packages/session`
dir — v2 session core lives in `packages/core/src/session.ts`.

## Dead/stubbed v2 endpoints (ALWAYS 503 OperationUnavailableError)

| Route | Stub site |
|---|---|
| `POST /api/session/:id/wait` | core/src/session.ts:421-424 |
| `POST /api/session/:id/compact` | core/src/session.ts:417-420 |
| `POST /api/session/:id/shell` | core/src/session.ts:387-389 |
| `POST /api/session/:id/skill` | core/src/session.ts:390-392 |

Handler maps them to errors with `ServiceUnavailableError` message
"Session `<operation>` is not available yet" (server/src/handlers/session.ts:184-191,
208-215). The v2 blocking handoff mode in the wiki (R1 "prompt → wait → tail")
CANNOT work at v1.18.13. Working liveness: `GET /api/health` → `{healthy: true}`
(protocol/src/groups/health.ts).

## v2 prompt semantics (core/src/session.ts:360-385)

- Body: `{id?, prompt: {text, files?, agents?}, delivery?, resume?}` (NO `parts`).
- `resume !== false` → `execution.wake(sessionID)` (line 382). `resume: false`
  = admit-only; the turn does NOT run until a later wake/resume.
- `id` reuse = exact-retry reconciliation (`SessionInput.equivalent`); mismatch
  or lifecycle conflict → `ConflictError` (409). Caller-generated `id` gives
  idempotent delegation.
- Legacy prompts: `POST /session/:sessionID/message` (parts body, waits for
  turn), `POST /session/:sessionID/prompt_async` (UNDERSCORE; returns NoContent
  immediately, starts the turn) — verify against sdk/js/src/gen/sdk.gen.ts:641.

## SSE streams

- Legacy instance `/event` and global `/global/event` (opencode instance
  httpapi groups/event.ts, handlers/event.ts): live-only, SSE frames carry
  `id: undefined` (handlers/event.ts:12-19), no replay param, 10s `server.heartbeat`.
- `/event` additionally ends with `server.instance.disposed` then closes
  (handlers/event.ts:53-61). Both are per-DIRECTORY filtered
  (`event.location?.directory === instance.directory`, handlers/event.ts:35-38)
  — the request must carry the project directory (x-opencode-directory).
- v2 `/api/event` (protocol/src/groups/event.ts) also live-only, schema =
  `EventManifest.Latest` (includes `permission.asked`/`replied`,
  `question.asked`/`replied`/`rejected`, `session.status`, deprecated
  `session.idle`).
- The ONLY replay surface: `GET /api/session/:sessionID/event?after=<seq>`
  (singular `event`; protocol/src/groups/session.ts:327-343) → SSE of
  `SessionEvent.Durable`. History: `GET /api/session/:id/history?after=&limit=`
  (handler default limit 50, protocol cap 100, `hasMore`).
- `session.status`/`session.idle` published on idle; status map DELETES the
  entry on idle (session/status.ts:39-47), absent ⇒ idle by default
  (status.ts:32) — useful reconciliation, wiki does not state it.
- Tail-on-idle race: durable rows commit after the status event; protocol
  history doc says "Newly committed events may appear on later pages" — retry
  until stable seq / `hasMore:false`.

## Permission & question services (opencode/src/permission/index.ts, question/index.ts)

- `ask` blocks on a per-id Deferred after publishing the event; pending entries
  fail with bare `RejectedError` ONLY on instance disposal finalizers
  (permission/index.ts:54-61). No timeout, no lease.
- `reply`:
  - unknown requestID → 404 (permission: NotFoundError, index.ts:112).
  - `reject` (with message → CorrectedError, else RejectedError) fans out to ALL
    same-session pending asks (index.ts:129-139) — cross-session asks NOT
    rejected automatically.
  - `always` fans out ONLY to same-session asks whose EVERY pattern is now
    allowed by the merged approved rules (index.ts:153-166); non-matching
    siblings STAY PENDING. Reply the remainder explicitly after fan-out.
  - "always" approval is IN-MEMORY per-instance (`approved` list), NOT persisted
    — lost on server restart; wiki "persisted ... in opencode session patterns"
    is wrong. v2 `GET /api/permission/saved` is a different mechanism.
- Question service: identical block-on-Deferred model; `reject` → RejectedError
  "The user dismissed this question". No fan-out (one ask = one requestID).
- Bridge crash recovery: on (re)start, `GET /api/permission/request` +
  `GET /api/session/:id/question` (+ `/api/question/request`), reject orphans.

## Auth (server/auth.ts, instance httpapi middleware/authorization.ts)

- Password required ⇒ EVERY route (incl. SSE GET) needs Basic auth.
  Username default `opencode` (OPENCODE_SERVER_USERNAME).
- `?auth_token=<base64(user:pass)>` query credential ALSO accepted
  (authorization.ts:77-83) — logs/URLs leak; the web UI and pty-ticket paths
  are exempt (isPublicUIPath).
- SDK `createOpencodeServer` (sdk/js/src/server.ts:22-100): no password option;
  spawn env = `{...process.env, OPENCODE_CONFIG_CONTENT}` — password must
  already be in env. Startup detection = stdio string match "opencode server
  listening on <url>", 5s default timeout, `stop()` kills proc.

## Serve/network (opencode/src/cli/network.ts, cli/cmd/serve.ts)

- CLI defaults: hostname `127.0.0.1`, port `0` (AUTO — actual bound port only
  visible in the listening banner); SDK defaults: 127.0.0.1:4096.
- `--mdns` flips default hostname to `0.0.0.0` (and mDNS on by default
  publishes "opencode.local"); config `server.hostname/port/cors/mdns*`
  can also override CLI defaults. A bridge that binds "127.0.0.1" must pass it
  explicitly and warn if attaching to an existing server.
- Serve does not auto-terminate: `Effect.never` (serve.ts:22). No built-in
  healthck beyond stdout line + `GET /api/health`.
- instances are per-request keyed by directory (InstanceState/ScopedCache);
  requests/SSE for the same directory share instance state (permission pending,
  status map). Instance disposal emits `server.instance.disposed` and rejects
  pending asks. `disposeDirectory` forces it.

## Hermes-side (v2026.8.3) — verified refs

- `tools/approval.py`: `request_tool_approval`  → :3299; gate `_run_approval_gate`
  :2979 (order: yolo → session cache → cron → CLI/gateway → deny/session/always
  persist); `_get_approval_timeout()` 2798 (300s fail-closed);
  `check_dangerous_command` 3229; `fail_closed_when_no_human=True` blocks
  non-interactive (plugin path opts IN; command path stays fail-open).
- CLI prompt `[o]nce/[s]ession/[a]lways/[d]eny` at approval.py:2561 area; the
  per-thread approval-callback fast-deny guard (approval.py:2608-2633) exists.
- Session/pattern/persist: `approve_session` 2386, `is_approved` 2460,
  `approve_permanent` 2474, `save_permanent_allowlist` 2546.
- Contextvars (NOT env): `set_current_session_key` :171 (approval.py) — must
  bind per thread/async task.
- plugins: `pre_tool_call` approval directive + `rule_key` control incl. default
  `plugin_rule:<tool>:<sha256(reason)[:12]>` (if plugins.py:2136-2290 shifted,
  re-grep exact lines). User config: `load_config()`/`cfg_get` config.py: 2886.

## Wiki claims that contradict code (as found 2026-08-09)

1. plugin-requirements.md R1: "v2 `resume:false` = fire-and-forget" — actually
   ADMIT-ONLY (no wake).
2. plugin-requirements.md R1/R2 + opencode-http-api.md: `POST /api/session/:id/wait`
   blocking mode — endpoint always 503s.
3. plugin-requirements.md: `GET /api/session/:id/events` — path is `/event`
   (singular).
4. plugin-requirements.md: `permission.asked {id, sessionID, permission, ...}`
   shown as the flat SSE payload — envelope is `{id, type, properties}`.
5. opencode-http-api.md: `POST /session/{id}/prompt-async` — path is
   `/session/:sessionID/prompt_async` (underscore), SDK-generated.
6. R3b consequence: no opencode reply support for requests already resolved by
   sibling fan-out — expect 404 on reply.
7. session-reading: `/api/session/active` = v2-only (legacy is
   `/session/status`); absent ≠ idle for the v1 map.