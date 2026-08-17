# Surface Consistency Audit — v1-only migration (2026-08-11, audit round 3)

Audit of the hermes-opencode plugin after the v2 API was dropped: tool surface,
config surface, docs (README + wiki), and test-fake fidelity vs the v1-only
code. READ-ONLY. Suite verified: `uv run pytest -q` → 151 passed + 1 subtest;
`uv run ruff check .` → clean. Full report written to /tmp; 15 findings
(4 bug / 3 cleanup / 8 nit) — includes 2 nits merged from a parallel
round-3 dispatch (see rows 14-15).

## The four-layer method (reuse this)

1. **Tool surface** — TOOL_REGISTRY names + each JSON schema vs `plugin.yaml`
   `provides_tools` vs README Tools table vs test schema asserts
   (tests/test_tools.py). Flag: schema params documented nowhere (README
   opencode_prompt row had dropped `directory?`/`agent?`), and doc params that
   don't exist in the schema. plugin.yaml must equal the registry exactly.
2. **Config surface** — for every key in `load_bridge_config()`'s returned
   dict, trace: read site (config.py `_cfg_get` key name) → returned-dict key
   → consumer (grep the key across hermes_opencode/). Three failure classes:
   - **Dead key**: read + documented but never consumed. `prompt_timeout` was
     read (config.py:90,129) and in the README table (README:63) yet
     tools.py:211 and bridge.py:389 hardcode 600 — a user setting it gets
     nothing.
   - **Undocumented key**: consumed but in no table. `agent` (config.py:97,
     bridge.py:414) and `model` (config.py:98, bridge.py:415) were in neither
     README nor the wiki R7 table; `agent` was only discoverable via the tool
     schema description, `model` nowhere at all.
   - **Dead read**: a `cfg.get(...)` that `load_bridge_config()` never
     produces. `bridge.py:61` `cfg.get("directory")` always falls back to
     os.getcwd() in production; only test CFG dicts inject it. A user setting
     that key is silently ignored.
   Note the internal-rename case: config key `rule_key` is returned in the
   dict as `rule_key_prefix` — consistent as long as every consumer uses the
   dict key. Distinguish the CONFIG-FILE key name (documented) from the
   RETURNED-DICT key (internal).
3. **Docs-vs-code** — after a migration, grep the ENTIRE repo (scripts/
   included, not just hermes_opencode/ + docs) for the deleted surface: old
   method names (`active_sessions`, `prompt_legacy`, `create_session_v1`),
   old params (`engine=`, `scope=context`), old routes (`/api/command`,
   `/api/health`), old events (`session.next.stop`). Real case:
   scripts/e2e_smoke.py still called `CLIENT.active_sessions()` and
   `read_session(..., engine="v2")` + read `out['engine']` while
   wiki/log.md:10 claimed "e2e_smoke.py -> v1 flow" — changelog entries are
   NOT evidence of the current tree. Also check: README Configure table rows
   one-to-one vs real keys, wiki "resolved questions" bullets for stale route
   names (plugin-requirements.md:319-321 still listed `GET /question` in the
   reconnect reconcile recipe; reconcile is permission-only).
4. **Test-fake fidelity** — diff each fake's method signatures AND return
   shapes against the real client class. Two failure classes:
   - Fake accepts params the real client doesn't, or returns a different
     shape → tests pass while real code breaks.
   - Fake MISSES methods real code calls, masked by test config: CFG
     `attach_reconcile: False` makes `reconcile()` early-return, so
     FakeBridgeClient (test_bridge.py:38-80) and ToolBridgeClient
     (test_tools.py:43-80) never exercise `permission_list`/
     `permission_reply`/`commands`/`question_reject` — flipping the flag
     would AttributeError against the fake while real code works. Check the
     AskSurface/EventStream protocols to enumerate what a faithful fake needs.
   Also verify requires_env semantics before flagging: `requires_env` in
   Hermes register_tool only feeds toolset "requirements" metadata display
   (registry.py:865-868 — no hard gate), so
   `requires_env=["OPENCODE_SERVER_PASSWORD"]` mislabels an optional secret
   (empty password = valid localhost no-auth mode) as required — a nit, not
   a blocker.

## Current v1-only surface (verified this round)

- Client: `create_session(agent, model, directory)` (POST /session),
  `prompt(session_id, text, message_id, agent, model, directory)` (POST
  /session/:id/message, parts body), `session_status()` (GET /session/status
  map; absence = idle), `messages(session_id, before, limit)` →
  (list, next_cursor|None) (GET /session/:id/message, Link header),
  `health()` (GET /global/health), `permission_list/permission_reply`,
  `question_reply/question_reject`, `commands()` (GET /command),
  `iter_events()` (GET /event, ?directory= query).
- Tools (5): opencode_prompt {prompt, session_id, directory, agent, timeout,
  wait}, opencode_session_tail {session_id, limit}, opencode_session_read
  {session_id, scope:[tail,range], after, limit}, opencode_question_reply
  {question_id, answers}, opencode_command {name, args, directory}.
- Config dict keys: auto_serve, hostname, port, tail_size,
  rule_key_prefix (config key `rule_key`), attach_reconcile, prompt_timeout,
  question_reply_mode, question_clarify, agent, model, inject_turn_complete,
  username, password (env OPENCODE_SERVER_PASSWORD / _USERNAME).
- Wiki pages carry "Plugin status (2026-08-11): v1-ONLY / DELETED" banners
  (opencode-session-reading, opencode-agent-registry, plugin-requirements) —
  v2 material below the banner is server-surface reference, not plugin
  behavior claims.

## Findings (13) — file:line, severity

| # | Sev | Where | Issue |
|---|-----|-------|-------|
| 1-3 | bug | scripts/e2e_smoke.py:115,125,134 | `active_sessions()` deleted → AttributeError; `engine="v2"` kwarg → TypeError; `out['engine']` → KeyError. Script is broken against the v1 client. |
| 4 | bug | config.py:90,129 / README.md:63 | `prompt_timeout` read+documented, never consumed (dead config key). |
| 5 | cleanup | README.md:84 | opencode_prompt row missing `directory?`/`agent?` schema params. |
| 6 | cleanup | README.md:57-67, wiki plugin-requirements.md:271-277 | `agent`/`model` config keys consumed but in no table. |
| 7 | cleanup | wiki plugin-requirements.md:319-321 | Stale `GET /question` in reconnect/reconcile bullet (permission-only since 2026-08-10). |
| 8 | nit | bridge.py:61 | `cfg.get("directory")` dead read (load_bridge_config never returns it). |
| 9 | nit | wiki/index.md:34 | "bridge v1-fallback fix" blurb — machinery deleted 2026-08-11. |
| 10 | nit | wiki/log.md:10 | "e2e_smoke.py -> v1 flow" claim false (see #1-3). |
| 11 | nit | tests/test_bridge.py:38-80 | FakeBridgeClient missing permission_list/permission_reply/commands. |
| 12 | nit | tests/test_tools.py:43-80 | ToolBridgeClient missing question_reject/permission_list/permission_reply. |
| 13 | nit | hermes_opencode/__init__.py:42 | requires_env password mislabels optional secret as required. |
| 14 | nit | wiki/log.md:34-35 (also 74, 82) | Dated changelog entries describe pre-migration v2 behavior as current ("permission_list is v2-first: GET /api/permission/request ... v1 GET /permission fallback"; "wait_for_complete resolves on the v2 session.next.stop ... or the v1 session.status idle event"). Superseded by the 2026-08-11 migration entry (log.md:3-6) — add a "superseded" pointer. |
| 15 | nit | README.md:114-115 | "asks that carry a question id resolve through the question route, others through the reject route" — code DROPS id-less question events with a warning (approval.py:173-181); the reject route is for unanswerable asks (approval.py:280-283). Reword. |

(Parallel-dispatch deltas merged 2026-08-11: rows 14-15; row 9's index.md cite corrected to :34.)
