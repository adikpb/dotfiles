# hermes-opencode-plugin — Surface/Config/Test-Fake Audit, Round 2 (2026-08-11)

Audit track distinct from the wiki-vs-clone audit (hermes-opencode-plugin-wiki-audit.md): this one checks the
PLUGIN'S OWN consistency — tool surface, config surface, README+wiki vs code, test-fake fidelity. Round 2
verified the 10 round-1 fixes and found 13 NEW issues (all docs/comments, no runtime bugs; `pytest` 153 passed).

## Round-1 fixes — verified intact (do NOT re-report unless wrong)

1. e2e_smoke active_sessions/engine references gone
2. config `prompt_timeout` wired (config.py:90 → tools handler → bridge.prompt)
3. question_registry_get removed; only question_registry_pop remains (approval.py + tests)
4. README Configure table has agent/model/directory rows (README:68-70)
5. README opencode_prompt signature has `directory?`/`agent?` (README:87)
6. README question-id wording: `opencode_question_reply(question_id, answers)` (README:90)
7. plugin-requirements.md R7 table synced to config.py keys
8. wiki/permissions v1-only framing
9. wiki/index.md updated (2026-08-11)
10. bridge.run_command wait=False + _wait_idle restructure consistent (bridge/tools/README)

## Post-round-1 changes (consistency-review each)

1. client.prompt → POST /session/{id}/prompt_async, returns {} on 204 (tests updated)
2. read.shape_message reads MessageV1 `{info: {...}, parts}` (flat = unit-fake fallback)
3. config.py returns `directory` key (README Configure table row)
4. bridge.run_command wait=False; bridge._wait_idle restructure
5. e2e_smoke s03/s04 assistant-row PONG wait (replaced old blocking-handoff stage)

## Round-2 findings — 13 OPEN (re-verify before re-reporting in round 3)

| # | Sev | File | Lines | Issue |
|---|---|---|---|---|
| F1 | cleanup | wiki/concepts/plugin-requirements.md | 76-77, 108, 244, 313 | R1/R5 still route prompt via `POST /session/{id}/message` + `{parts, messageID?...}`; idempotency bullets say "fresh messageID" — code uses prompt_async + `{parts, agent?, model?, id?}`, bridge sends no idempotency key |
| F2 | cleanup | wiki/concepts/opencode-agent-registry.md | 113-114 | "prompt() … (`POST /session` + `POST /session/{id}/message`)" — stale route |
| F3 | cleanup | scripts/e2e_smoke.py | 6-15 | Header lists 7 stages incl. removed blocking-handoff stage; stage 3 "scratch project" wrong (sessions land in repo project) |
| F4 | cleanup | wiki/concepts/opencode-session-reading.md | 89-106 | "Shaping into Hermes entries" documents flat Message `{id, role, parts[], modelID...}`; code reads MessageV1 `{info, parts}` |
| F5 | cleanup | hermes_opencode/events.py | 11-13 | Docstring: "MUST send x-opencode-directory" header — client.iter_events deliberately sends `?directory=` (header form stalls v1.18.13) |
| F6 | cleanup | wiki/entities/hermes-plugin-surface.md | 115-116 | Config example uses dead key `server_port`; real key is `port` |
| F7 | cleanup | wiki/concepts/plugin-requirements.md | 128-129, 304-305 | R2 "Retry with short backoff"/"retry-on-race"/"inject Hermes-shaped entries" — bridge._on_idle is single unretried read; only a short notice is injected |
| F8 | cleanup | hermes_opencode/events.py | 95 | Comment "unblock wait_for_idle" — renamed to wait_for_complete |
| F9 | nit | hermes_opencode/events.py | 116 | wait_for_complete docstring "(the bridge prompt handoff)" pre-check claim stale |
| F10 | nit | hermes_opencode/client.py | 248 | prompt docstring cites v1.18.16; repo pins v1.18.13 |
| F11 | nit | tests/test_config.py | 47-48, 73-74 | Only port/tail_size asserted; prompt_timeout/inject_turn_complete/directory/agent/model unasserted |
| F12 | nit | hermes_opencode/tools.py | 239, 262 (+bridge.py:162,195 vs 425) | tail_size fallback default 40 vs 8 (config default 8) |
| F13 | nit | wiki/concepts/plugin-requirements.md | 286 (+hermes-plugin-surface.md:126) | "Secrets via manifest requires_env:" — plugin declares via register_tool(requires_env=[...]) (__init__.py:42); plugin.yaml has no requires_env |

## Verified clean (round 2)

- Tool schemas ↔ README tools table ↔ plugin.yaml ↔ TOOL_REGISTRY (5 tools, all params/defaults/descriptions match)
- README Configure table: all 13 config keys bidirectionally synced, no dead/undocumented keys
- Test fakes (FakeBridgeClient, ToolBridgeClient, FakeClient, FakeReadClient, support.py) match real client signatures
- Routes/events/scopes: prompt_async, /session/status, /global/health, /command, scope tail|context|range, question_reply(request_id, answers)
- pytest: 153 passed

## Stale-name dictionary (reuse for round 3 sweep)

`server_port | messageID | noReply | prompt_legacy | requires_env | question_registry_get | querying | auto_first | engine | active_sessions | MessageV2 | session\.idle | wait_for_idle | tail_role | GET /question | /api/ | /session/\{id\}/message | /session/\{id\}/prompt | session_id=\?`
(Hits at exactly the search limit → truncated; re-run with higher limit.)
