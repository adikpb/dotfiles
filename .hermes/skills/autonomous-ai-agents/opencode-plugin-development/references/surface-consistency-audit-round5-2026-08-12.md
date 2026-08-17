# Surface ROUND-5 verification (2026-08-12) — v2_audit_r5_3_surface

Convergence round of the v1-only surface audit loop. Runs: `uv run ruff check .`
→ "All checks passed!"; `uv run pytest -q` → **165 passed + 1 subtest** (suite
grew +4 since R4's 161; matches the briefed 165 exactly). Mtimes static — no
moving target. READ-ONLY round; no files edited.

## 6/6 briefed R4 fix groups — VERIFIED-FIXED (file:line)

| # | Fix group | Anchor |
|---|---|---|
| 1 | Three bare `_STRING` schema params gained descriptions (tail/read session_id, question_id) | tools.py:114-117, :134-137, :160-163 (`_STRING` remains only as the `answers` array `items` type, tools.py:164) |
| 2 | README `opencode_prompt` row signature reordered to (prompt, session_id?, directory?, agent?, timeout?, wait?) | README.md:87 — matches schema property order tools.py:56-102 |
| 3 | plugin-requirements.md: cross-directory status-map-poll caveat in blocking-handoff bullet; `GET /question` dropped from SSE-reconnect recipe | plugin-requirements.md:102-104 (caveat), :145-146 (recipe) |
| 4 | opencode-session-reading.md MessageV1 summary notes flat `info.modelID` vs nested `info.model` | opencode-session-reading.md:92-96 |
| 5 | `__init__.py` `register_tool` `requires_env` lists BOTH `OPENCODE_SERVER_USERNAME` and `OPENCODE_SERVER_PASSWORD` | __init__.py:42 |
| 6 | Fakes gained `permission_list`/`permission_reply` (+ `question_reject`, `commands`); `test_reconcile_attached_rejects_stale_asks` pins `attach_reconcile=True` | test_bridge.py:85-96 (question_reject :85, permission_list :89, permission_reply :92, commands :95), test_tools.py:78-94, test_bridge.py:337-350 (cfg flip at :342, reject+reason asserts :346-350) |

Clean-sweep confirmations: README tool rows (README.md:87-91) match
TOOL_REGISTRY order (test_tools.py:203-214); config defaults
(config.py:85-105/123-139) match README.md:61-67 + plugin-requirements R7 +
plugin.yaml (declares no config keys, nothing to drift); StubOpenCodeServer
routes match client wire bodies (`{reply,message}`, `{answers}`, `{}` reject,
Link-header cursor); deleted-surface grep over hermes_opencode/*.py — all
hits classified noise (vendored clone) or intentional negative tests
(test_events/test_read). Wiki residue grep — no stale endpoint refs outside
banner-marked history pages.

## NEW findings

### N1 (bug, latent) — `client.prompt()` sends `id`, the real v1 prompt body field is `messageID`

- client.py:269-270: `if message_id: payload["id"] = message_id`
- Real v1 wire (vendored fork = audit ground truth):
  - `packages/opencode/src/session/prompt.ts:1499-1520` — `PromptInput` =
    `{sessionID, messageID?, model?, agent?, noReply?, tools?, format?,
    system?, variant?, parts}` (messageID at :1501). **There is no `id` field.**
  - `packages/opencode/src/server/routes/instance/httpapi/groups/session.ts:70`
    — `PromptPayload = Struct.omit(PromptInput.fields, ["sessionID"])`; both
    `POST /session/{id}/message` and `POST /session/{id}/prompt_async` decode
    it (instance handlers/session.ts:295-329).
  - `packages/sdk/openapi.json:7173-7176` — body prop `messageID`, pattern
    `^msg`; `:7231-7232` — `required: ["parts"]`, `additionalProperties: false`.
  - `packages/sdk/js/src/v2/gen/types.gen.ts:10141-10166` —
    `SessionPromptAsyncData.body = {messageID?, model?, agent?, noReply?,
    tools?, format?, system?, variant?, parts}`.
- Consequence: a body carrying `id` is 400-rejected (unknown property) or
  silently stripped — idempotency broken either way.
- The unit test **pins the wrong contract**: test_client.py:61-68
  (`test_prompt_passes_message_id`) asserts `payload["id"] == "call-123"` on
  the stub route — the value also fails the real `^msg` pattern. A fake that
  echoes back whatever the client sends can lock in a wire shape the real
  server rejects; validate asserted body field names against openapi.json /
  schema sources, not against the client's own payload construction.
- Note the inversion: here the WIKI was right and the code wrong —
  opencode-http-api.md:31 documents the v1 prompt body as
  `{parts, messageID?, model?, agent?, noReply?, tools?}`. Docs can lead code.
- Latency: no production call site passes `message_id` (bridge.py:458,
  tools.py:239-244, scripts/e2e_smoke.py:109/156) — dormant bug, but the
  client method is part of the wire surface and the test cements the wrong
  name.
- Fix: `payload["messageID"] = message_id`; test asserts `payload["messageID"]`
  with a pattern-valid value (`msg-...`); optionally note the key in the
  `prompt()` docstring (client.py:252-262).
- Do not confuse with the OPPOSITE earlier correction: the v2 prompt REPLY
  `SessionInput.Admitted` has `id` NOT `messageID` (R2 correction,
  schema/src/session-input.ts:15-23). v1 prompt BODY = `messageID`; v2 prompt
  REPLY = `id`. Easy to mix up — check the surface you are on.

### N2 (nit) — fake `permission_reply` param-name drift

- Real client: `permission_reply(self, request_id, reply, message=None,
  directory=None)` (client.py:322-324).
- AskSurface protocol: `(self, rid, reply, message=None, directory=None)`
  (approval.py:51-53). test_approval.py:39 FakeClient matches the protocol.
- But test_bridge.py:92 FakeBridgeClient and test_tools.py:87
  ToolBridgeClient: `(self, rid, decision, reason=None, directory=None)` —
  `decision`/`reason` instead of `reply`/`message`.
- Works today (all four approval.py call sites :227/:246/:335/:338 are
  positional; test_bridge.py:347 unpacks positionally), but a future keyword
  call (`reply=`, `message=`) TypeErrors against these two fakes while
  working against the real client — or worse, a call written to the fakes'
  `reason=` silently breaks against the real client.
- Fix: rename fake params to match the protocol.
- Method extension: the TEST-FAKE fidelity layer diffs signatures AND return
  shapes — also diff PARAM NAMES (keyword-call regressions slip through
  positional-only matching fakes).

## Method notes (accumulated this round)

- Suite-count corroboration: brief said "expect 165 passed" — got exactly
  165 + 1 subtest; a count mismatch against the brief is itself a signal
  (new/removed tests landed since the last round).
- "NO NEW FINDINGS is a valid and valuable result" — this round found 2, but
  the discipline is: run the full cross-check (schemas↔README↔wiki tables,
  config defaults↔README/wiki/plugin.yaml, every fake↔real wire) and report
  what the tree actually shows, including clean sweeps.
- Wire-body assertions in unit tests are only as good as the source they were
  written against; when a test asserts a body field, re-derive the field name
  from openapi.json / schema .ts in the vendored clone at least once per
  surface.
