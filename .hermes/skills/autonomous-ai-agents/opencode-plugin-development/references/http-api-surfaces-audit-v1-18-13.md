# OpenCode HTTP surface inventory (v1.18.13) — wiki audit findings

From the 2026-08-09 wiki-vs-source audit of the hermes-opencode-plugin bridge wiki. Source of truth: vendored clone tag v1.18.13 (commit a105350). All paths relative to `packages/` in `anomalyco__opencode`.

## Two HTTP stacks on one port — separate service backends

`packages/opencode/src/server/routes/instance/httpapi/server.ts:141-181` mounts FIVE route trees together:

| Tree | Paths | Backend |
|---|---|---|
| `RootHttpApi` | `/global/*` (health, dispose, upgrade, config, event) | control/global handlers |
| `EventApi` | `/event` (SSE) | `EventV2Bridge` → raw `{id,type,properties}` projection |
| `InstanceHttpApi` | `/session*`, `/permission*`, `/question*`, `/tui*`, `/experimental/*`, `/file`, `/mcp`, `/config`, `/provider`, `/widget` | V1-opencode runtime services (`@/permission`, `@/question`, `@/session`) |
| `ServerApi` (protocol) | `/api/*` (`/api/session`, `/api/permission/*`, `/api/question/*`, `/api/command`, `/api/event`, `/api/model`, `/api/agent`, `/api/provider`, `/api/integration`, `/api/credential`, `/api/fs`, `/api/skill`, `/api/location`, `/api/reference`, `/api/project-copy`, `/api/pty`, `/api/health`, `/api/message`) | **V2 core services** (`SessionV2`, `PermissionV2`, `QuestionV2`) |
| `PtyConnectApi` | WebSocket pty upgrade | ticket auth |

The wiki conflates these; **v2 `/api/...` routes are NOT backed by the same services the tools use at runtime**. This is the single most dangerous drift for a bridge.

## Permission: two independent pending pools

- V1 runtime service `packages/opencode/src/permission/index.ts` — what tools actually call via `ctx.ask()`:
  - publishes `permission.asked` / `permission.replied` (names from `packages/schema/src/v1/permission.ts:61-66`), payload `{id, sessionID, permission, patterns, metadata, always[], tool?}`
  - reply semantics (index.ts:109-167): `reject` → CorrectedError(feedback) or RejectedError + fan-out `reject` to same-session siblings; `always` → in-memory only `approved` rules (NOT persisted; the `approved.push` in core/src/permission.ts:250-256 is the v2 `save` variant) + fan-out `always` to siblings whose patterns all become allow; `once` → resolves ONLY the replied request, NO fan-out (siblings stay pending!).
- V2 protocol paths `/api/permission/request`, `/api/session/:sid/permission[:/rid][/reply]` — backend `packages/core/src/permission.ts` (`PermissionV2`), payload `{action, resources, save[], source?}` (schema `packages/schema/src/permission.ts:27-36`), publishes `permission.v2.asked/replied`.
- To answer a V1 event: `POST /permission/:requestID/reply` body `{reply, message?}` (legacy instance tree, `groups/permission.ts:31-43`, handler src/instance/httpapi/handlers/permission.ts → V1 service). V2 `save` flag → `PermissionSaved` table.

## SSE streams — schema coverage matrix

| Stream | Scope | Shape | Manifest coverage | Heartbeat / terminal |
|---|---|---|---|---|
| `GET /event` | one directory (header/query) | `{id,type,properties}` raw | full legacy `Definitions` incl. `session.status`, `permission.asked`, `question.asked` | `server.connected` first; `server.heartbeat` 10s; ends `server.instance.disposed` |
| `GET /api/event` | ALL locations (no filter) | encoded vs `ServerDefinitions` union | **excludes** `session.status`/`session.idle`/`permission.asked`/`question.asked` (those are legacy-only); includes `session.next.*` durable+delta, `models.dev.*`, etc. | `server.connected`; `: heartbeat` (comment) 15s; bounded 256 dropping queue → `EventV2.SubscriberOverflow` kills stream under slow consumer |
| `GET /api/session/:sessionID/event?after=` | one session | `SessionEvent.Durable` (durable only; live deltas like `text.delta` NOT included) | replay `after` (exclusive aggregate seq) then live | no heartbeat |

Status lineage: `session.status` published only by V1 runtime loop (`packages/opencode/src/session/status.ts:39-48` on `set`; `run-state.ts:62,82`; `prompt.ts:1089` sets busy). V2 executor (`core/src/session/runner/llm.ts`) has "mark busy/retrying/idle durably" as an unchecked TODO — no status events from v2 prompts. V2 idle detection = `GET /api/session/active` (record `{sid:{type:"running"}}`, absent = idle) or last durable `step.ended`/`step.failed`.

## Ground truth dump (from `packages/sdk/openapi.json`, 162 paths)

```python
import json
d = json.load(open('<repo>/packages/sdk/openapi.json'))
print('\n'.join(sorted(d['paths'].keys())))
```

Key non-wiki-covered routes (verified present): `/api/session/{id}/agent` (switchAgent), `/api/session/{id}/model` (switchModel), `/api/session/{id}/interrupt` (live, not stubbed), `/api/session/{id}/compact` (declared → **503 stub** at this tag), `/api/session/{id}/revert/{stage,clear,commit}`, `/api/agent`, `/api/model`, `/api/provider[/{id}]`, `/api/health`, `/experimental/tool`, `/experimental/tool/ids` (**400 if `provider`/`model` missing**), `/experimental/session`, `/experimental/session/{id}/background`, `/global/health`, `/global/upgrade`, `/global/dispose`, `/sync/history`, `/permission`, `/permission/{rid}/reply`, `/question[/{rid}/reply|/reject]`, `/tui/execute-command`, `/tui/open-models`, `/tui/open-sessions`, `/tui/select-session`.

Legacy session options not documented in wiki: list query `scope=project|path|roots|start|search|limit`, `GET /session/:id/message?limit=&before=` (message paging cursor = messageID), prompt body has legacy `parts` + `noReply|model|agent|tools|system|variant` (prompt.ts ~line 1061-1069), `POST /session/:id/prompt_async` (**underscore**).

## Session service details (core/src/session.ts)

- `list` default limit 50 (`packages/server/src/handlers/session.ts:16-17`), cursor `SessionsCursor` base64url JSON with `anchor {id, time, direction}` (protocol/groups/session.ts:55-80); query keys `workspace`, `project`, `subpath`, `directory`, `search`, `order`, `limit`.
- `create` payload `{id?, agent?, model?, location?}`; **location omitted → directory = serve-process `process.cwd()`** (handlers/session.ts:75), not the request's `x-opencode-directory` — always pass location.
- `prompt` body `{id?, prompt:{text,files?,agents?}, delivery?, resume?}` (protocol groups session.ts:205-224), returns `SessionInput.Admitted` `{admittedSeq, id, sessionID, prompt, delivery, timeCreated, promotedSeq?}`; errors: `Session.SessionNotFound` → 404, `PromptConflictError` → 409 Conflict.
- `history` default limit 50 (wiki said “~8”), max 100, `after` = exclusive aggregate seq; `hasMore`.
- `events` handler streams `Stream.orDie`; `interrupt` live; `wait`/`compact`/`shell`/`skill` 503.

## Auth and multi-tenant

- `Authorization: Basic <base64(`opencode:<password>)>` — username default `opencode` (`packages/opencode/src/server/auth.ts:19`); `?auth_token=` query accepted (`middleware/authorization.ts:12,77-83`); `WWW-Authenticate` sent on 401; public UI paths bypass (`isPublicUIPath`); empty-string password = unsecured but `required()` returns false (password set-and-empty disables auth).
- Instance context: `x-opencode-directory` header (or `directory` query for GET/HEAD — SDK rewrites, `packages/sdk/js/src/client.ts:17-31`).

## Audit method that caught these (reuse)

1. `git describe --tags` to pin the clone; read wiki SCHEMA+index first, then the centerpiece spec.
2. Dump `openapi.json` paths — generated-from-code; it is the wire truth; diff against wiki tables row by row.
3. For each wiki endpoint: confirm (a) declared in protocol/group, (b) implemented in handler, (c) wired to the claimed service — all three must hold; stubs surface at (b)/(c).
4. Trace the event name from the **publish call-site** (not the schema!) to know which stream carries it and under which namespace (v1 vs v2).
5. Verify defaults against handler code (documentation defaults like “max 100” were right; API defaults differ: history=50, list=50, tail race retry).
6. Mark severity: HIGH = contradictions that would break the implementer's flow; MEDIUM = missing surface; LOW = nuances. Output per-finding: `[SEV] Title | why it matters | evidence clone path:line / wiki page | wiki coverage | action`, then TOP-5 gaps, <~3500 words.