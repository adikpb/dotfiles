# ROUND-4 audit (2026-08-09) — fresh opencode-side re-verification

Scope: all 10 opencode-side wiki pages re-audited fresh against
`.slim/clonedeps/repos/anomalyco__opencode` @ v1.18.13 (entities/opencode-http-api,
opencode-runtime, opencode-sdk, opencode-plugin-api; concepts/opencode-config,
opencode-commands, opencode-event-streams, opencode-permissions,
opencode-question-api, opencode-session-reading). Read-only: findings only, no
edits. Round-3 convergence held for everything re-checked; 2 NEW substantive
contradictions + 4 precision slips surfaced.

## Substantive contradictions (fix these in the wiki)

1. **`ReplyInput` has NO `sessionID`.**
   Wiki `concepts/opencode-permissions.md:27`: `ReplyInput { sessionID,
   requestID, reply }`.
   Source: `packages/schema/src/v1/permission.ts:56-58` —
   `ReplyInput = Schema.Struct({ requestID: ID, ...ReplyBody.fields })` =
   `{ requestID, reply, message? }`. `sessionID` exists only on the
   `permission.replied` EVENT payload (`schema/src/v1/permission.ts:62-65`,
   published from `opencode/src/permission/index.ts:115-119`), not on the
   reply input. Bridge code must not expect sessionID on the reply body.

2. **`GET /api/session/{id}/message` (plural) does not exist on the V2 surface.**
   Wiki `entities/opencode-http-api.md:57`: row claims V2 message list,
   protocol group `session.messages`.
   Source: the V2 `server.session` group has only the SINGULAR
   `session.message` at `/api/session/:sessionID/message/:messageID`
   (`packages/protocol/src/groups/session.ts:360`). The plural list lives on the
   V1 instance surface only: `GET /session/:sessionID/message`
   (`packages/opencode/src/server/routes/instance/httpapi/groups/session.ts:85,179`).
   A GET to `/api/session/{id}/message` has no matching V2 route — delete the
   row or relabel it V1.

## Precision slips (behavior claims correct; cite/wording off)

3. `opencode-permissions.md:44-45` cites "permission index.ts:74-81" for
   dispose-fails-pending-asks; the `addFinalizer` is actually at
   `opencode/src/permission/index.ts:54-61` (74-81 is inside `ask`).
4. `opencode-event-streams.md:36` cites "schema/src/event-manifest.ts:63-74"
   as the full manifest; the `PermissionV1`/`QuestionV1` definition lines are
   70/76 (Definitions spans 63-82).
5. `opencode-http-api.md:31` legacy prompt body enum omits `system?` — present
   at `packages/sdk/js/src/gen/types.gen.ts:2588-2601` (opencode-sdk.md:92-93
   does list it). Cosmetic.
6. `opencode-http-api.md:36` — `GET /experimental/tool` REQUIRES `provider` +
   `model` query params (400 without; `groups/experimental.ts:57-61`). Missing
   load-bearing fact, not a wrong claim.

## Re-verified clean (convergence confirmed)

- Endpoint table: all verbs/paths; `wait`/`compact`/`shell`/`skill` 503 stubs
  (`core/session.ts:421-424` etc.); history default 50 / max 100 / `hasMore`;
  `session.active` GET (not POST); interrupt idle no-op; `/api/health` =
  `v2.health.get` (openapi.json:9780-9784); v2 prompt body
  `{id?, prompt:{text,files?,agents?}, delivery?, resume?}`.
- Two-surfaces-on-one-port mounting (instance httpapi api.ts: RootHttpApi +
  InstanceHttpApi roots vs protocol ServerApi `/api`).
- SSE: v1 envelope `{id,type,properties}`, 10s `server.heartbeat`,
  `server.instance.disposed`, undefined-location drop, unbounded queue; v2
  `/api/event` fatal on v1-only types, 256 dropping queue, 15s `: heartbeat`,
  no disposed frame.
- Permissions: evaluate semantics, same-session sibling fan-out,
  CorrectedError/RejectedError message strings, both HTTP surfaces, dispose
  fail-without-event.
- Questions: tool params vs `custom` on Info only, `que_*` IDs, lifecycle +
  dispose, plan-tool confirm ask, enablement rule, `OPENCODE_CLIENT` default
  `cli`.
- Commands: builtins init/review, `source`/`hints`, config/MCP/skill sources,
  `CommandV2.Info` (no source/hints), legacy `/command` (openapi.json:2662).
- SDK/plugin/config: group+method lists, v2 surface, part types
  (types.gen.ts:2588-2602), `plugin?: Array<string>` (:1226), plugin type
  shapes, loaders, `ConfigPluginV1.Spec`, glob auto-discovery,
  `opencode plugin <module>` (cli/cmd/plug.ts:178-179).

## Method notes (fresh-audit pass, worth reusing)

- Claim taxonomy → evidence map. Endpoints → protocol groups
  (HttpApiGroup/HttpApiEndpoint) + server handlers + `packages/sdk/openapi.json`
  paths (ground truth for route existence, incl. plural-vs-singular). Event
  types → `schema/src/event-manifest.ts` + SSE handlers. Payload shapes →
  schema files + sdk gen `types.gen.ts`. Defaults/limits → HANDLERS (e.g.
  `DefaultSessionHistoryLimit = 50` in `server/handlers/session.ts:17`) vs
  bounds in group schemas (`SessionHistoryLimit ≤ 100`,
  `protocol/groups/session.ts:87`). CLI verbs → `cli/cmd/*.ts`. Config keys →
  `core/src/v1/config/*`.
- Naming: OpenAPI identifier (`v2.session.permission.reply`) ≠ protocol
  endpoint id (`session.permission.reply`) ≠ wiki-invented labels
  (`permission.session.reply` was a swap). Cite the protocol group line.
- Exhaustive audits exhaust the tool-iteration budget: batch parallel reads,
  grep-with-context over full-file reads, and verify LOAD-BEARING claims
  (routes, limits, error behavior, payload shapes) before citation trivia;
  summarize "verified clean" for the remainder instead of leaving it unstated.