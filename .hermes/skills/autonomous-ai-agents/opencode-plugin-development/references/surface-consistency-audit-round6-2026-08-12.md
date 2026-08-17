# Surface-consistency audit — ROUND 6 (2026-08-12)

Convergence round of the surface audit loop on hermes-opencode (v1-only bridge
to opencode serve, vendored ground truth at v1.18.13,
`.slim/clonedeps/repos/anomalyco__opencode`). Verification ran against the
real wire contracts: `packages/sdk/openapi.json` (requestBody schemas,
additionalProperties:false, required sets, patterns), the route groups
(`packages/opencode/src/server/routes/instance/httpapi/groups/{session,
permission,question,event}.ts`), the handlers (`handlers/session.ts`,
`handlers/event.ts`), `packages/opencode/src/session/{prompt,message-v2}.ts`,
and `packages/schema/src/v1/session.ts` + `schema/src/model.ts`.

Baseline: `uv run ruff check .` clean; `uv run pytest -q` → 167 passed +
1 subtest; mtimes static (no moving target); vendored repo confirmed at tag
v1.18.13 (commit a105350 "release: v1.18.13").

## Briefed Round-5 fix groups — VERIFIED-FIXED

### F1 — client.prompt_async payload field is `messageID` (client.py:272)

Real v1 prompt_async body (`POST /session/{sessionID}/prompt_async`),
from openapi.json requestBody (matches PromptInput at
`packages/opencode/src/session/prompt.ts:1499-1520`, minus sessionID):

```
{ messageID: string pattern ^msg,        # NOT `id`
  model: {providerID, modelID},          # required both, additionalProperties:false
  agent: string?, noReply: bool?, tools: Record<string,bool>?,
  format?, system?, variant?,
  parts: [TextPartInput|FilePartInput|AgentPartInput|SubtaskPartInput] }
required: [parts]; additionalProperties: false; response 204 No Content
```

client.py:272 `payload["messageID"] = message_id` is correct; an `id` key
would 400 (additionalProperties:false). PromptInput field set confirmed
field-for-field.

### F2 — fakes' permission_reply params match AskSurface (rid, reply, message, directory)

AskSurface protocol (approval.py:48-59): `permission_reply(rid, reply,
message=None, directory=None)`, `question_reply(rid, answers)`,
`question_reject(rid)`, `permission_list(directory=None)`.
All three fakes now match:
- tests/test_approval.py:39 — `permission_reply(self, rid, reply, message=None, directory=None)`
- tests/test_bridge.py:94 — same
- tests/test_tools.py:89 — same

Wire bodies also verified: `POST /permission/:requestID/reply` =
`{reply, message?}` (groups/permission.ts:12-15; Reply literals
`["once","always","reject"]` — plugin sends only once/reject);
`POST /question/:requestID/reply` = `{answers: [[label,...]]}`
(groups/question.ts:12-16); `POST /question/:requestID/reject` takes no body
(client sends `{}` — harmless).

## NEW findings (2, both bug)

### N1 — create_session model payload uses the WRONG ref shape → 400 when model configured

- Where: hermes_opencode/client.py:232 (`body["model"] = model` in
  create_session); dict built in hermes_opencode/bridge.py:46-53
  (`_model_ref` → `{"providerID": provider, "modelID": model_id}`).
- Real wire: `POST /session` requestBody `model` =
  `{id (string, REQUIRED), providerID (string, REQUIRED), variant?}`,
  `additionalProperties: false` (openapi.json; source
  `packages/schema/src/model.ts:14-18` `Model.Ref`, consumed by
  `Session.CreateInput` in core/src/session.ts:79-84). Effect decode of
  `{providerID, modelID}` fails: required `id` missing (and `modelID` is an
  unknown key) → HTTP 400 on every create with config
  `plugins.entries.hermes-opencode.model` set.
- The trap: prompt_async's model field is the OTHER ref —
  `{providerID, modelID}` (PromptInput ModelRef, prompt.ts:1494-1497). The
  SAME `_model_ref` dict is passed to both create_session and prompt
  (bridge.py:467 + :474), so it is right for one route and fatal for the
  other. **One logical value, two wire shapes — shape per endpoint, never
  reuse one dict across routes.**
- Fix: in create_session map the model to
  `{"id": model["modelID"], "providerID": model["providerID"]}` (drop
  variant); keep `{providerID, modelID}` for prompt_async. Add a unit test
  asserting the create body keys (a fake that echoes the client payload
  would have caught this).
- e2e_smoke never sets model, so the live smoke cannot catch it either.

### N2 — read.py tool-part shaping reads the wrong fields; the test fake mirrors the bug

- Where: hermes_opencode/read.py:75-96 (`shape_message` tool branch) reads
  `part.get("name")`, `part.get("callID")`, `part.get("input")`,
  `part.get("output")` at TOP level.
- Real wire: `SessionV1.ToolPart` =
  `{type: "tool", callID, tool: <name>, state: ToolState, metadata?}`
  (schema/src/v1/session.ts:315-322); ToolState =
  `{status: pending|running|completed|error, input: {...}, output (completed),
  error (error), ...}` (:259-313). GET /session/:id/message page items carry
  the STORED parts verbatim (`{info, parts}`, message-v2.ts:118-121), so
  live tool parts have `tool` (not `name`) and input/output nested under
  `state`.
- Consequence on a live server: tool_name → literal "tool", arguments → "{}",
  result content → None, tool_call_id → "{mid}-tool".
- The fake `tool_msg` in tests/test_read.py:24-36 encodes the SAME wrong
  shape (`{"type":"tool","name":..., "input":..., "state":{"status":
  "completed"}, "output":...}`), so the whole suite is green while the live
  shaping degrades. **A fake that mirrors the code under test's assumptions
  instead of the real wire contract locks in wire bugs** (same class as the
  R5 messageID-pinned-by-fake finding). Re-derive fake part shapes from
  schema/src/v1/session.ts, not from the shaper.
- Fix: read `part["tool"]` for the name, `part["callID"]`,
  `part["state"]["input"]`, and `part["state"].get("output")` or
  `part["state"].get("error")` for the result; rewrite test_read.py's
  tool_msg to the real `{callID, tool, state}` shape (keep one flat-fallback
  branch only if the shaper keeps one).

## Verified checks (no finding)

- Permission reply `{reply, message?}` and question reply/reject bodies match
  groups/permission.ts + question.ts exactly.
- GET /session/:id/message: handler returns a BARE items list + `Link` +
  `X-Next-Cursor` headers (handlers/session.ts:123-142); MessagesQuery =
  `{limit?, before?}` only (groups/session.ts:43-47) — client.messages()
  matches.
- MessageV2 page items = `{info: {id, role, sessionID, time:{created},
  model:{providerID, modelID} | modelID}, parts}` — read.py's info-driven
  reads (incl. the nested-vs-flat model fallback) are consistent.
- `/event` stream contract: frames `{id, type, properties}`; first frame
  `server.connected`; `server.heartbeat` every 10s; terminal
  `server.instance.disposed` (takeUntil, handlers/event.ts:59-66) — client
  raises StreamClosed without yielding it, matching.
- `GET /command` → bare array; `GET /session/status` → `{sessionID:
  {type:"busy"|"idle"}}` map; `POST /session` success = bare Session info
  (no `data` envelope) — all as documented in client.py.
- Reply literals: client sends only `once`/`reject`, both valid
  PermissionV1.Reply values.

## Method lessons

1. Per-endpoint wire schema, not per-value: when one logical value (model
   ref) travels to multiple routes, diff each route's requestBody schema
   (openapi.json required + additionalProperties:false + pattern) — the
   two-ref split (Model.Ref vs PromptInput ModelRef) only shows up there.
2. Fake fidelity is against the REAL wire (schema/src/*, openapi.json), never
   against the code under test — a fake that echoes the shaper's assumptions
   is a mirror, not a test.
3. openapi.json `additionalProperties:false` + `required` is the 400-prediction
   tool for every client body; verify each request-building method even when
   no production call site currently hits the broken path (N1 is latent until
   a user sets config `model`).
4. Cross-check e2e smoke coverage: it never sets `model`, so route-body bugs
   on that path live only in unit tests that assert the payload keys.

Process note: this round's audit report file could not be written at audit
time (tool-iteration cap hit before the final write); the machine-validated
JSON findings summary was the deliverable. Re-verify N1/N2 in the next round
via this reference, not the (missing) report file.
