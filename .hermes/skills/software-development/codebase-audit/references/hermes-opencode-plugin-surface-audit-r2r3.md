# hermes-opencode-plugin surface audit — ROUND-2 RESTART #3 (r2r3)

Audit of ~/src/hermes-opencode-plugin, 2026-08-12.
Mode: READ-ONLY subagent; task = verify 13 briefed round-2 findings + hunt NEW surface
inconsistencies (tool schemas, config keys, test fakes vs real client, version pins,
stage lists, defaults). Full human report: /tmp/v2_audit_r2r3_3_surface.md.

## Key context: live-editor tree
The maintainer edited the working tree DURING the audit (17 files modified vs HEAD,
uncommitted). 7 of the 13 briefed findings flipped STILL-PRESENT → VERIFIED-FIXED between
my first read and my final snapshot (events.py, bridge.py, tools.py, client.py,
plugin-requirements.md, opencode-agent-registry.md, e2e_smoke.py, test_config.py).
Mid-audit the suite was red (test_reconnect_after_stream_closed: UnboundLocalError `exc`
at events.py:161 — fixed by the maintainer's `except StreamClosed as exc:`) and went green
before the final run. Final evidence: `uv run pytest -q` → 155 passed; `uv run ruff check .`
→ 1 error (E501 tools.py:77).

## The 13 briefed findings — final status (as of final snapshot)
1. F1 plugin-requirements R1/R5 `/session/{id}/message` route + messageID idempotency — **VERIFIED-FIXED** (now prompt_async `{parts, agent?, model?, id?}`; "no idempotency key is sent"; R5 :243-245; arch step 6 :313-315).
2. F2 opencode-agent-registry.md:113-114 stale route — **VERIFIED-FIXED** (:114 now prompt_async).
3. F3 e2e_smoke.py:6-15 header 7 stages + scratch-project claim — **VERIFIED-FIXED** (6 stages s01-s06). Residual: dead `PROJ` scratch dir :30-31 (NEW #4).
4. F4 opencode-session-reading.md:89-106 flat `{id, role, parts, modelID, sessionID, time.created}` message shape — **STILL-PRESENT** (:91-92 + table :98-106). read.py:42-44: v1 cursor API actually returns MessageV1 `{info: {id, role, time, model...}, parts}`; flat is unit-fake fallback.
5. F5 events.py:11-13 "MUST send x-opencode-directory header" — **VERIFIED-FIXED** (now `?directory=` query; header form stalls v1.18.13+).
6. F6 hermes-plugin-surface.md:115-116 config example `server_port` (dead key) — **STILL-PRESENT** (:116; real key `port`, config.py:84).
7. F7 plugin-requirements R2 retry-with-backoff tail fetch + "inject Hermes-shaped entries" — **VERIFIED-FIXED** (:128-131 "One unretried read at idle"; :304-307 "single tail fetch → buffer shaped rows … short completion notice").
8. F8 events.py:95 `wait_for_idle` comment — **VERIFIED-FIXED** (:97 now wait_for_complete).
9. F9 events.py wait_for_complete docstring pre-check parenthetical — **VERIFIED-FIXED** (:124-130 clean).
10. F10 client.py:248 docstring cites v1.18.16 — **VERIFIED-FIXED** (:248 now v1.18.13; all pins 1.18.13).
11. F11 test_config.py:47-48,73-74 default/partial tests missing new config keys — **VERIFIED-FIXED** (defaults test :55-59 asserts prompt_timeout/inject_turn_complete/directory/agent/model). Residual: override test :61-83 still doesn't exercise them (NEW #3).
12. F12 tail_size fallback defaults 40 vs 8 — **VERIFIED-FIXED** (bridge.py:168/201/431, tools.py:239/262 all default 8). Residual: read.py:142 bare `limit = 40` (NEW #2).
13. F13 "Secrets via manifest requires_env:" — **STILL-PRESENT (half)**. plugin-requirements.md:287 fixed to `register_tool(..., requires_env=[...])`; hermes-plugin-surface.md:126 still claims manifest `requires_env:` — plugin.yaml declares none; only declaration is __init__.py:42 `register_tool(..., requires_env=["OPENCODE_SERVER_PASSWORD"])`.

Net: 10 VERIFIED-FIXED, 3 STILL-PRESENT (F4, F6, F13-half).

## NEW findings (5)
1. ruff E501 tools.py:77 — line too long (149 > 120) on the opencode_prompt `timeout` description. `uv run ruff check .` fails.
2. read.py:142 bare default `limit = 40` vs config `tail_size = 8` — latent (all callers pass explicit limits), but diverges from the documented default for bare calls.
3. tests/test_config.py:61-83 — test_override_wins covers none of the newer keys (prompt_timeout, inject_turn_complete, directory, agent, model, question_reply_mode, question_clarify).
4. scripts/e2e_smoke.py:30-31 — dead scratch project (`PROJ` mkdtemp + README write never used; serve cwd = repo).
5. tests/test_bridge.py:27-35 + tests/test_tools.py:32-40 — `text_msg()` fakes build the FLAT shape `{id, role, modelID, sessionID, time:{created}, parts}`; shape_message (read.py:50-60) only reads `time.created` via `info["time"]["created"]` or `msg["created"]`, so fake timestamps are silently None and the primary MessageV1 `{info, parts}` shape is never exercised by bridge/tools tests (only test_read.py uses it).

## Verified-clean surfaces (next round need not re-check)
- Tool schemas (tools.py) ↔ README tools table (:85-91) ↔ wiki: 5 tools, params, required, wait default (false at tool layer; bridge default true) all match. `model` config-only (README:70, no per-call param).
- Config keys (config.py:123-139) ↔ README table (:57-70) ↔ plugin-requirements R7 table (:271-284): 13 keys, identical defaults.
- plugin.yaml provides_tools == TOOL_REGISTRY == __init__.py register loop (5 tools).
- prompt_async route + 204 handling: test_client.py routes `/session/s1/prompt_async[?directory=…]` returning (204, b"", None), body assertions match client.py:257-272.
- session_status semantics (absent = idle) consistent: client.py:202-211 ↔ FakeBridgeClient.statuses ↔ tests.
- AskSurface protocol (approval.py:48-59) satisfied by test_approval.FakeClient.
- Version pins: single v1.18.13 everywhere.

## Open items for the next round
- F4 (session-reading flat shape), F6 (server_port example), F13-half (hermes-plugin-surface.md:126 requires_env manifest claim).
- NEW 1-5 above. Severity: N1 cleanup, N2/N3/N4 nit, N5 cleanup.
