# OpenCode v1 wire surface — verified facts + consistency-audit checklist

Verified 2026-08-12 (audit round 6) against the vendored opencode source at
`.slim/clonedeps/repos/anomalyco__opencode/`. Truth lives in:

- `packages/sdk/openapi.json` — generated v1+v2 spec (request/response schemas incl. `additionalProperties` flags)
- `packages/opencode/src/session/session.ts` — `CreateInput` + `Model` schema (~line 216)
- `packages/opencode/src/session/prompt.ts` — `PromptInput` + `ModelRef` (~line 1494)
- `packages/opencode/src/server/routes/instance/httpapi/handlers/{session,question,permission,event}.ts` — real decode behavior
- `packages/schema/src/v1/{permission,question}.ts` — event payload shapes
- `packages/opencode/src/session/status.ts` — status map + events

## THE big trap: two different Model shapes (create vs prompt)

- `POST /session` (create): `model` = `{id (required), providerID (required), variant?}` (Session `Model`).
- `POST /session/{id}/prompt_async`: `model` = `{providerID, modelID}` (`ModelRef`).
- Sending the SAME dict (e.g. `{"providerID": p, "modelID": m}`) to both routes → 400 on create:
  missing required `id`, extra `modelID`. `createRaw` decodes `Session.CreateInput` and maps ANY decode
  failure to `400 BadRequest`. A `provider/model` config string must be shaped per call site.

## prompt_async body (PromptPayload)

- required: `parts` (array; `[{type: "text", text}]` matches `TextPartInput` required `type`+`text`).
- `messageID`: pattern `^msg` — NOT `id` (an `id` key 400s; this was audit F1).
- `agent` string, `model` ModelRef; `noReply`/`tools`/`format`/`system`/`variant` optional.
- `additionalProperties: false` — any stray key 400s.

## Other v1 request bodies

- `POST /permission/{requestID}/reply`: `{reply: once|always|reject (required), message?}`,
  `additionalProperties: false`.
- `POST /question/{requestID}/reply`: `{answers: string[][]}` (`QuestionAnswer` = `string[]`),
  `additionalProperties: false`.
- `POST /question/{requestID}/reject`: NO declared request body — an empty `{}` body is ignored by
  the handler (params-only signature), harmless.

## QuestionOption has NO `type` field

- v1 `QuestionInfo` = `{question, header, options: [{label, description}], multiple?, custom?}`
  (`schema/src/v1/question.ts`; `Option` = `{label, description}` only, `additionalProperties: false`).
- custom-ness is the per-question `Info.custom` boolean (default TRUE), never a per-option `type`.
- Filtering options with `o.get("type") == "custom"` is dead code on the real wire; any test fake
  using `{"type": "custom", "label": ...}` options encodes a shape the server can never emit.

## SSE /event wire

- Frames: `{id, type, properties}` (handler maps bus events to this envelope).
- Sequence: `server.connected` first, `server.heartbeat` every 10s, terminal `server.instance.disposed`
  (takeUntil) — a client should treat that terminal frame as the stream end.
- `session.status` props: `{sessionID, status: {type: busy|idle|retry}}`.
- `permission.asked` props = `Request.fields` `{id, sessionID, permission, patterns, metadata, always, tool?}`.
- `question.asked` props = `{id, sessionID, questions, tool?}`.
- Location-filtered: only events whose `event.location.directory === instance.directory` pass; send the
  `?directory=` QUERY form (the `x-opencode-directory` header form stalls the /event response body).

## GET surfaces

- `/session/status` → bare map `{sessionID: {type}}`; idle sessions are DELETED from the map, so
  absence = idle (never "not started yet" on first check after a fork).
- `/session/{id}/message` → bare `[{info, parts}]` + `Link`/`X-Next-Cursor` headers; cursor is opaque
  base64url JSON — pass it back verbatim. **Exact 400 rule (handler `session.ts:110`):**
  `if (ctx.query.before && ctx.query.limit === undefined) return BadRequest` — i.e. `before` REQUIRES
  `limit`, but `limit`-without-`before` (a tail / newest-page read) is ACCEPTED. Audit briefs that state
  "needs before+limit together else 400" are OVER-BROAD; a tail read sending only `?limit=N` does NOT
  400. The only real client-side risk is emitting `before` without `limit` (the `messages()` helper in
  `client.py` permits this if a caller passes `before` alone — guard it).
- `/command` → `Command[]` (`{name, template, hints}` required).
- `/global/health` → `{healthy: true, version}`.

## Latent wire-shape guards (audit these even when green)

The functional path works, but strict-schema residue hides here — catch it:

- `messages()` (`GET /session/{id}/message`): never emit `before` WITHOUT
  `limit`. The handler (`session.ts:110`) 400s on `before`-without-`limit`.
  A tail read (limit-only) is valid; guard the pair inside the helper so any
  caller passing `before` alone defaults `limit`.
- `create_session()` (`POST /session`): the model body is the Session Model
  `{id, providerID, variant?}` with `providerID` REQUIRED and
  `additionalProperties:false`. When normalizing a `provider/model` config
  into `{id, providerID}`, a missing/inferred `providerID` would serialize as
  `null` and 400. Only attach `model` when BOTH `id` and `providerID` are
  present; drop or gate otherwise.

  **Self-contradictory pass-through branch (caught in a real audit round 2):**
  do NOT write `elif not (modelID or providerID): body["model"] = model` as a
  "Session-shape pass-through". It is dead for a real `{id, providerID}`
  input (its `providerID` is present so it never reaches this branch) yet it
  FORWARDS degenerate input like `{"id": "x", "providerID": None}` — emitting
  a NULL `providerID` that 400s on `Session.CreateInput`. The correct shape is
  a SINGLE `if modelID and providerID: body["model"] = {"id": modelID,
  "providerID": providerID}` branch and nothing else; any model lacking
  `providerID` is simply not attached.

## v1-only migration: structural residual surface to scrub

When a plugin drops the v2 surface (was v2-capable → now v1-ONLY), the
wire-shape traps above are necessary but NOT sufficient. The residual v2
surface that survives a partial migration is structural, not just payload
shape. Scrub ALL of:

- **Defensive `{data: …}` envelope unwrappers** (e.g. `unwrap_data()`): the v1
  wire returns bare JSON objects/lists with no `{data: …}` envelope. Remove the
  unwrapper and every call site (`data = self.unwrap_data(parsed)`); endpoints
  return `parsed` directly. A leftover unwrapper is dead code that implies a
  v2 contract the plugin no longer has.
- **Test fakes emitting v2 event types** (`permission.v2.asked`,
  `question.v2.asked`, or any `…v2…` family): the v1 `/event` stream never
  emits these. A fake carrying wire-impossible shapes MASKS real bugs (see
  checklist #4). Delete those test cases; assert only v1 event dispatch.
- **v2-rationale docstrings** ("the v2 API is deliberately not used", "the v2
  registry never sees", "without the v2 `/api/event` encode fragility"):
  rewrite to pure v1 phrasing (e.g. "the v1 runtime resolves
  runtime/plugin-registered agents"). KEEP the accurate migration note ("this
  plugin is v1-ONLY") — drop only the contrast-with-v2 framing that implies v2
  is still a live concern.
- **Version pins**: bump the verified-target stamp (README + e2e docstring +
  client docstring) from the old clone tag to the LIVE opencode version
  actually used (e.g. `v1.18.13` → `v1.18.16`). Wiki clone-tag references
  (`vendored audit clone v1.18.13`) stay — only the LIVE-target stamps move,
  and stale "live opencode 1.18.13" E2E notes should be annotated
  `(historical)` so they don't read as the current target.

## Multi-agent audit loop (residual v2-surface hunt)

Run as a looped `delegate_task` fan-out of 3 LEAF lenses, re-dispatch until 0:
1. Source & tests (grep for `/api/`, `{data:}` unwrap, `permission.v2.*`/
   `question.v2.*`, `resume`, "v2 registry never sees"; confirm root v1 routes
   only; run `uv run pytest -q` inside the child).
2. Docs (README + wiki: no line states the plugin DRIVES a `/api/` route; v2
   only as "reference/deferred/historical"; tables match `tools.py`/`config.py`;
   version stamps consistent).
3. Wire-shape correctness (this doc: Model/ModelRef split, no stray keys,
   `messageID` not `id`, `/event` `?directory=` query; plus the two latent
   guards above).
See SKILL.md "Iterative multi-agent v1-consistency audit loop" for the full
protocol. Real result: round 1 = 6 findings (2 wire-shape latent, 4 doc),
all fixed, round 2 = 3 (the create_session pass-through contradiction above
+ 1 doc metadata line), round 3 = 0.

**Pitfall — do NOT poll a delegation with `terminal(sleep …)`.** A
`delegate_task` fan-out re-enters as ONE consolidated message when all
children finish; do not tail the live transcripts to "wait". Stop calling
tools and let the result wake the session automatically.

1. Run `uv run ruff check .` and `uv run pytest -q` first — gate must be green.
2. Verify every briefed fix against the vendored source (openapi.json + handler), not just the diff.
3. For every client payload: check field names, required fields, and `additionalProperties: false`
   against the route's declared schema. A dict reused across TWO routes is the prime suspect (create
   vs prompt Model/ModelRef).
4. Test fakes vs the real wire: a stub that accepts any body, or a fake carrying shapes the wire can
   never produce (option `type:"custom"`), MASKS wire bugs — this is how the create-model 400 and the
   dead option filter both survived. Fakes must use real wire shapes.
5. Docs: README/wiki tool tables vs `tools.py` schemas (names/params/enums); config defaults vs
   documented defaults (README + wiki tables) — keep both tables as the cross-check source.
6. e2e smoke vs real shapes; note what e2e does NOT exercise (model config, permission/question ask
   paths) — uncovered paths are where wire bugs hide.
7. Output contract: when the parent demands machine-validated JSON, emit ONLY the JSON (a ```json
   fence is fine) — NO prose before/after; the validator rejects markdown-wrapped responses.
8. Trust the vendored source over the brief, not vice-versa. Parent "verified facts" can be OVER-BROAD
   vs the real handler (e.g. the brief claimed `/session/{id}/message` "needs before+limit together else
   400", but `session.ts:110` only 400s on `before`-without-`limit`; a `limit`-only tail read is valid).
   When a stated fact and the source disagree, audit against the source and report the PRECISE condition
   (and the exact handler line) rather than repeating the over-broad claim. Also: verify the real package
   path (e.g. `hermes_opencode/`, NOT `opencode_plugin/`) via search before auditing — task briefs often
   name the wrong directory.
