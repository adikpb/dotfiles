# v1-Only Residue Sweep — Round 2 (2026-08-11)

Result: **2 NEW findings (both STALE_DOC, low severity). ZERO CODE_PATH v2
residue.** All 23 round-1 fixes re-verified correct on disk (wiki/ is
git-ignored in this repo — `git status`/`git log -- wiki/` show NOTHING for
it; verify fixed docs by reading files, not via git).

## Findings (the round-1 sweep missed both)

- **F1 — STALE_DOC (low)** `wiki/concepts/plugin-requirements.md:76` (R1,
  "V1 (what the plugin drives)") still names `POST /session/{id}/message`
  as the plugin's prompt route. Round-1 behavioral fix switched
  client.prompt() to `POST /session/{id}/prompt_async` (the `/message` POST
  BLOCKS until the turn completes; prompt_async = 204 No Content, turn
  forked). R1 mentions prompt_async only as a trailing server-trivia
  sentence, so the doc misdescribes the actual prompt path.
- **F2 — STALE_DOC (low)** `wiki/concepts/plugin-requirements.md:242-244`
  (R5) repeats it: "`prompt` (parts body, agent/model/directory) via
  `POST /session` / `POST /session/{id}/message`". The POST form of
  `/session/{id}/message` is never called (only the GET cursor read is).

Fix for both: rename the route to `/session/{id}/prompt_async` (parts body
identical; note 204/fork). Root cause of the miss: round-1 fixed the CODE
and the specifically-named doc files (R7 table, permissions banner, index
one-liner, README) but never swept the docs that *claim* the plugin's route
("what the plugin drives / uses"). **Lesson: after any route change, grep
docs for the OLD route token AND for "what the plugin (drives|uses)" phrasing.**

## Classification ledger (everything the `v2` grep actually hit)

- **CODE_PATH (bug): none.** No `/api/*` routes, no v2 read engines
  (history/context/event?after), no v2 event families dispatched
  (session.next.*, permission.v2.*, question.v2.*), no deleted-machinery
  names (active_sessions / create_session_v1 / prompt_legacy /
  _deny_locked_out / _fallback_v1 / question_registry_delete), no
  read_session(engine=...). Verified: client/bridge/read/events/approval/
  config/serve/tools, both `__init__.py` files, scripts/e2e_smoke.py,
  plugin.yaml, pyproject.toml.
- **EXPLANATORY (allowed):** docstrings explaining v2 is deliberately not
  used — client.py:4-8,207,250-254; bridge.py:13-16,412; read.py:3-4;
  events.py:8-9,192; tools.py:20. Negative tests asserting v2 families are
  ignored (tests/test_events.py:95-110). Banner-marked wiki reference pages
  ("V1-ONLY / reference only / dropped 2026-08-11") and index.md:33-34.
- **HISTORICAL-LOG (accepted):** wiki/log.md dated entries (superseded by
  the top 2026-08-11 v1-only migration entry).
- **FALSE POSITIVES — grep `v2` matched version strings "v2026.8.3":**
  approval.py:11, serve.py:8, README.md:17, wiki hermes-agent-runtime.md:15,
  hermes-plugin-surface.md:15, hermes-approval-route.md:100,
  .slim/clonedeps.json:27. Classify explicitly, never report.
- **OUT OF SCOPE:** .slim/clonedeps/repos/... (vendored upstream clone).

## Re-verification checklist (all passed, do not re-report unless wrong)

e2e_smoke.py s03/s04 (session_status-free PONG-wait on ASSISTANT rows +
scope print + failure-row tolerance); client.prompt_async route; iter_events
query-only directory (no x-opencode-directory header); IncompleteRead →
StreamClosed; _parse_sse_frame dict guard; messages() X-Next-Cursor fallback;
read.shape_message MessageV1 info-nesting with flat fallback; bridge._wait_idle
event-primary + single map re-read + saw_busy-gated poll; start() idempotent;
run_command wait=False; prompt timeout from cfg['prompt_timeout'];
approval question_registry_pop (delete method gone); config 'directory' key
wired; opencode-permissions.md v1 GET /permission reconcile + banner;
plugin-requirements.md R7 table (agent/model/directory rows); index.md:34;
README question-id drop-wording + Configure table + opencode_prompt signature.

## Known residual (accepted — do NOT report)

prompt() wait=False "running" from a single session_status() read at submit
time (may read False before the forked turn starts).
