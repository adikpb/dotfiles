# v1-only migration + residue audit, round 1 (2026-08-11)

The plugin dropped the opencode v2 API completely and is now v1-only. This
reference records the migration's shape (so future sessions never rebuild
v2 paths) and the round-1 residue-audit method + findings (so future rounds
sweep the same way and know what was already caught).

## The migration (what changed)

Files rewritten: `hermes_opencode/{client,read,events,approval,bridge,tools,serve}.py`,
`tests/*`, `scripts/e2e_smoke.py`, `README.md`. Working tree uncommitted
(`git diff HEAD` shows the migration).

- client.py: v2 endpoints DELETED — `active_sessions` (v2 `GET /api/session/active`),
  `create_session` v2 shape, v2 prompt shape, `history`, `context`, v2
  permission/question routes. Names promoted: `create_session_v1` -> `create_session`,
  `prompt_legacy` -> `prompt` (parts body + agent/model/directory). NEW:
  `session_status()` = `GET /session/status` map; absent key = idle (the
  status service deletes entries on idle). `commands()` via `GET /command`;
  `health()` via `GET /global/health`; `permission_list` v1-only.
- read.py: `V2Collapser` / `detect_engine` / `_event_seq` / engine routing
  deleted; `read_session(client, session_id, scope="tail"|"range", after, limit)`
  is v1 cursor API only (`GET /session/:id/message?before=&limit=`, Link-header
  pagination). `scope=context` and the `engine` output field dropped. Returns
  `{session_id, scope, entries, after, has_more}` — NO `engine` key.
- events.py: `session.next.stop` handling (`_last_stop`, on_turn_complete
  callback) and `permission.v2.asked` / `question.v2.asked` dispatch deleted;
  `wait_for_complete` resolves on `session.status idle` only. `session.next.*`
  appears only in the ignore-comment (line ~192).
- approval.py: family concept deleted; always v1 root routes.
- bridge.py: deny-lock/fallback machinery deleted (`_deny_locked_out`,
  `_fallback_v1`, v2->v1 try/except, `fallback:"v1"`); `prompt()` v1-only with
  `_wait_idle` via `session_status()`; `answer_question()` v1-only.
- tools.py: `opencode_session_read` drops `scope=context` + `engine` field
  (enum is `["tail","range"]`); `opencode_question_reply` drops the
  `session_id` param (v1 reply needs only `question_id`).
- Tests: 65 v2-referencing tests deleted/rewritten; suite 151 passed + 1
  subtest, ruff clean.

## Residue audit method (round 1)

1. Grep the DELETED names across ALL files INCLUDING `scripts/` — the unit
   suite does not execute scripts/e2e_smoke.py (needs a live `opencode serve`),
   so a green `pytest -q` proves nothing about it. Sweep targets:
   `hermes_opencode/*.py`, `tests/*.py`, `scripts/*.py`, `README.md`,
   `plugin.yaml`, `pyproject.toml`, `wiki/**/*.md`.
2. Filter noise dirs out of recursive greps: `.slim/clonedeps` (vendored
   reference clones of hermes-agent/opencode), `.venv`, `__pycache__`,
   `.pytest_cache`, `.ruff_cache`, `.git`. A naive `grep -ri v2` hits tens of
   thousands of lines of clone/venv noise.
3. For every suspicious hit, read the file AROUND the match — the grep line
   alone cannot tell CODE_PATH from a comment from a docstring.
4. Prove staleness STATICALLY instead of running e2e:
   `inspect.signature(fn)` (param removed -> TypeError on call) and
   `hasattr(cls, name)` (method removed -> AttributeError). This is read-only
   and conclusive.
5. Classify each mention into three buckets; report only the first two:
   - **CODE_PATH** (bug): executable code using/containing v2.
   - **STALE_DOC** (bug): doc (README/wiki/docstring/config table/tool table)
     that CLAIMS the plugin uses v2 behavior.
   - **EXPLANATORY** (allowed): docstring/comment explaining why v2 is NOT
     used; banner-marked reference pages ("V1-ONLY", "reference only",
     "ROOT-CAUSE HISTORY"); DATED changelog entries (log.md entries before the
     migration are history, not stale claims); negative tests asserting v2
     families are ignored; opencode internal type names (EventV2,
     MessageV2.cursor/page) in explanatory contexts.
6. Wiki rule: pages WITH a v1-only banner are reference and fine; pages
   WITHOUT a banner that still prescribe deleted v2 plugin behavior are stale
   even if the rest of the page is opencode-server reference.
7. Run `ruff check .` + `pytest -q` as evidence, and note in the report that
   scripts/ are outside the suite.

## Round-1 findings (all confirmed; 3 total)

1. **CODE_PATH — scripts/e2e_smoke.py:115** — `if SID not in CLIENT.active_sessions():`
   `active_sessions` was deleted (v2 `GET /api/session/active`); `hasattr`
   proves it is gone. Stage s03 raises AttributeError on every run.
   Fix: `if SID not in CLIENT.session_status():` — v1 status map absence = idle.
2. **CODE_PATH — scripts/e2e_smoke.py:125 (also :134)** —
   `read_session(CLIENT, SID, scope="tail", limit=20, engine="v2")` — no
   `engine` kwarg exists anymore (TypeError); line 134 `out['engine']` reads a
   removed result field (KeyError). Fix: drop `engine="v2"`; print
   `out['scope']` instead.
3. **STALE_DOC — wiki/concepts/opencode-permissions.md:47-48** —
   "reconcile via `GET /api/permission/request` (v2, location-scoped; falls
   back to v1 `GET /permission`)" prescribes the deleted v2-first reconcile;
   `client.permission_list()` (client.py:304-308) and
   `ApprovalBridge.reconcile()` (approval.py:304-341) are v1-only.
   Fix: reword to v1 pending list + "v2 route is server reference only,
   dropped 2026-08-11", add the v1-only banner.

## Checked-and-allowed (EXPLANATORY) — don't re-report these next round

- Module docstrings: client.py:4-5, 207, 250; read.py:4, 7; events.py:3, 8,
  192; bridge.py:13-14, 408; tools.py:20; serve.py:8 ("Hermes v2026.8.3" is
  the Hermes version, not opencode v2).
- tests/test_events.py:95-111 (v2 families ignored) and :113-120
  (session.next.* ignored); tests/test_read.py:132-135 (scope="context"
  rejected with ValueError).
- Wiki with banners: plugin-requirements.md (14-19), opencode-session-reading.md
  (14-20), opencode-agent-registry.md (14-19).
- Wiki server-reference pages: opencode-http-api.md, opencode-event-streams.md,
  opencode-commands.md, opencode-question-api.md, message-injection.md,
  opencode-sdk.md, opencode-plugin-api.md, opencode-runtime.md, index.md.
- wiki/log.md: dated changelog; the 2026-08-11 entry documents the drop.
- Out of sweep scope: `.hermes/plans/2026-08-10_...-skeleton.md` — dated
  pre-migration plan snapshot (v2-preferred design), superseded.

## Evidence recorded

- `uv run ruff check .` -> clean; `uv run pytest -q` -> 151 passed + 1 subtest.
- `hasattr(OpenCodeClient, 'active_sessions') == False`; `hasattr(...,
  'session_status') == True`.
- `inspect.signature(read_session)` params: client, session_id, scope, after,
  limit (no engine).
- Report artifact: `/tmp/v2_audit_1_residue.md` (findings + classification
  appendix), machine-validated JSON summary with `total_findings: 3`.
