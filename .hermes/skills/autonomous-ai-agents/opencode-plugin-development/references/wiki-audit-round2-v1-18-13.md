# OpenCode v1.18.13 ↔ bridge wiki — ROUND-2 audit findings (2026-08-09)

Source-verified ROUND-2 audit of the hermes-opencode-plugin wiki (`<repo>/wiki/`) against the
vendored clone `anomalyco__opencode` @ tag v1.18.13 (commit a105350). ROUND-1 items
(`wait`/`compact`/`shell`/`skill` stubs, v1/v2 surface split, event envelope, auth, prompt
payloads) were already applied to the wiki and are NOT repeated here. These are the NEW gaps /
still-wrong claims found after R1. All paths relative to `packages/` in the clone unless
absolute. Wire truth = `packages/sdk/openapi.json` (162 paths).

## Wrong claims still in the wiki (fix targets)

1. **[HIGH] `POST /api/session/active` → actually GET**
   - Source: `packages/sdk/openapi.json` `/api/session/active: ['get']`;
     `packages/protocol/src/groups/session.ts:146` `HttpApiEndpoint.get("session.active", ...)`.
   - Wiki: `wiki/concepts/opencode-session-reading.md:30`, `wiki/concepts/plugin-requirements.md:71,88`.
   - Fix: `GET /api/session/active`. (`entities/opencode-http-api.md:55` already says GET — pages contradict.)

2. **[HIGH] Replay path still `/api/session/:id/events` (plural) in 4 pages — actual path is `/event` (singular)**
   - Source: openapi `/api/session/{sessionID}/event`; `packages/protocol/src/groups/session.ts:327`
     `HttpApiEndpoint.get("session.events", "/api/session/:sessionID/event", ...)` — operationId is
     `session.events` but the URL is singular; v2 SDK `Session3.events` → url `/api/session/{sessionID}/event`
     (`packages/sdk/js/src/v2/gen/sdk.gen.ts`). The plural is a trap: verify openapi.json paths, never the
     method/operationId name.
   - Wiki: `entities/opencode-http-api.md:54,75`, `concepts/opencode-event-streams.md:49`,
     `concepts/opencode-session-reading.md:42`, `concepts/plugin-requirements.md:214`.

3. **[MEDIUM] `SessionInput.Admitted` has `id`, NOT `messageID`**
   - Source: `packages/schema/src/session-input.ts:15-23` → `{admittedSeq, id, sessionID, prompt, delivery,
     timeCreated, promotedSeq?}`. Response is wrapped `{data: Admitted}` (`protocol/src/groups/session.ts:213`).
   - Wiki: `concepts/plugin-requirements.md:56` ("contains `messageID`, ..."). Reading `admitted.messageID`
     yields `undefined`; idempotency key = `admitted.id`.

4. **[MEDIUM] Question tool input has NO `custom` field**
   - Source: `packages/schema/src/question.ts:28-44` — `Prompt = Struct({question, header, options, multiple})`;
     `custom` exists only on the response `Info` (:35-40). Tool params: `{questions: Array(Question.Prompt)}`
     (`packages/opencode/src/tool/question.ts:6-8`).
   - Wiki: `concepts/opencode-question-api.md:21` lists `custom?` in the accepted input shape.

5. **[MEDIUM] v2 `/api/event` lifecycle misdescribed**
   - Source: `packages/server/src/handlers/event.ts:37` — keepalive is an SSE comment `": heartbeat\n\n"`
     every 15 s (`Stream.tick("15 seconds")`), NOT a `server.heartbeat` event; no `server.instance.disposed`
     terminal frame (stream just ends). The disposed terminal + 10 s `server.heartbeat` event exist ONLY on the
     v1 instance stream (`packages/opencode/src/server/routes/instance/httpapi/handlers/event.ts:42-66,63-66`).
   - Wiki: `concepts/opencode-event-streams.md:47` ("only connected/heartbeat/disposed lifecycle events" for
     /api/event); `entities/opencode-http-api.md:70-72` generalizes the v1 lifecycle to both streams.
   - Fix: reconnect detection on `/api/event` = socket close/error; also note 256-capacity dropping queue →
     `EventV2.SubscriberOverflow` failure.

6. **[MEDIUM] Legacy route typed `prompt-async` (hyphen) in runtime page**
   - Source: openapi `/session/{sessionID}/prompt_async` (underscore);
     `packages/sdk/js/src/gen/sdk.gen.ts:641` (`Session.promptAsync` → url `/session/{id}/prompt_async`).
   - Wiki: `entities/opencode-runtime.md:46` → `POST /session/{id}/prompt-async`. (`opencode-http-api.md:32`
     is already correct.)

## New undocumented surfaces (add to wiki, bridge-relevant)

- v2 session LIST with cursor pagination: `GET /api/session` query `workspace`, `limit` (default 50,
  `packages/server/src/handlers/session.ts:16,36`), response `{data, cursor}` (`protocol/src/groups/session.ts:109-118`).
- v2 message LIST: `GET /api/session/:id/message` (`v2/gen/sdk.gen.ts` `Session3.messages`) — only the
  single-message route is documented.
- `GET /api/health` liveness (openapi `['get']`) — absent from wiki endpoint table.
- `GET /experimental/tool/ids` + 400-when-`provider`/`model`-missing caveat.
- v1 `GET /session/status` (instance group `SessionPaths.status`, `instance/httpapi/groups/session.ts:80`) and the
  status-map rule: entry DELETED on idle (`packages/opencode/src/session/status.ts:42-47`), `get()` defaults
  absent ⇒ `{type:"idle"}` (:30-33) — "absent = idle" reconciliation fact still not in wiki.
- Legacy session list query params: `scope=project|path|roots|start|search|limit`
  (`instance/httpapi/groups/session.ts:30-38`).

## Lifecycle / security nuances

- `POST /api/session/:id/interrupt` is a NO-OP on an idle session (`protocol/src/groups/session.ts:355`) — good
  for cancel, useless as wake/keepalive.
- `OPENCODE_SERVER_PASSWORD=""` (empty string) DISABLES auth — `instance/httpapi/middleware/authorization.ts:90`
  `if (!ServerAuth.required(config)) return effect`; bridge should treat empty as unset/error.
- `opencode plugin <module>` CLI is `src/cli/cmd/plug.ts:178-179` (`command: "plugin <module>"`, registered
  `packages/opencode/src/index.ts:102`) — wiki `concepts/opencode-config.md:71-72` points at `src/config/` (wrong dir).
- v2 SDK GET rewriting: for `/api/*` paths the directory/workspace headers are rewritten to `location[directory]` /
  `location[workspace]` query keys, not bare `directory` (`packages/sdk/js/src/v2/client.ts:34`) — legacy surface
  uses bare `directory`.

## ROUND-2 verified-correct (no action)

- v1 `/event`: envelope `{id,type,properties}` (`instance/httpapi/handlers/event.ts:40`), frame `id: undefined`
  (:16), `server.connected` first (:70), 10 s heartbeat (:63), disposed terminal (:42-61), per-directory filter (:35-38).
- v2 `ServerDefinitions` excludes `session.status`/`permission.asked`/`question.asked` (`packages/schema/src/event-manifest.ts:57-61`).
- `wait`/`compact`/`shell`/`skill` 503 stubs (`packages/core/src/session.ts:387-424`); `history` default 50 / max 100
  (`server/src/handlers/session.ts:16-17`, `protocol/src/groups/session.ts:87`); `session.create` location default =
  `process.cwd()` (`server/src/handlers/session.ts:75`).
- v2 prompt payload `{id?, prompt:{text,files?,agents?}, delivery?, resume?}`, `resume:false` admit-only
  (`protocol/src/groups/session.ts:205-224`, `core/src/session.ts:360-385`).
- Hooks catalog matches `packages/plugin/src/index.ts:222-335`; `permission.ask` has no trigger call-site.
- Question tool enabled in serve mode (`packages/opencode/src/effect/runtime-flags.ts:56` default `cli`).
- `{plugin,plugins}/*.{ts,js}` auto-discovery (`packages/opencode/src/config/plugin.ts:21`).
