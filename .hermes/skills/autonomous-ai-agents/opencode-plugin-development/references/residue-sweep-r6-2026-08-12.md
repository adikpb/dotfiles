# Residue ROUND-6 sweep — v1-only migration residue audit (2026-08-12)

Repo: hermes-opencode-plugin (v1-only bridge to opencode serve). READ-ONLY sweep.
Buckets: CODE_PATH (executable v2 usage) / STALE_DOC (doc CLAIMS v2 usage by the
plugin) / EXPLANATORY (explains v2 NOT used / banner-marked reference / negative
test) / HISTORICAL-LOG (dated append-only log entries).

## Result

- **Task-1 verification: VERIFIED-FIXED at bridge.py:75** — comment reads
  `# wait=false sessions: {"last_fp", "in_flight"}` exactly. The briefed line was
  :70; bridge.py grew ~5 lines of fix work since R4, so the line drifted.
  Content is correct; the R4/R5 tracking reference should be updated to :75.
  **Line-number drift ≠ regression — re-locate by content, not the briefed line.**
- **Task-2 full sweep: ZERO CODE_PATH / ZERO STALE_DOC** — 3rd consecutive
  convergence round. 528 raw `v2|/api/` hits; all classify EXPLANATORY /
  HISTORICAL-LOG / Hermes version string (`v2026.8.3`), or sit in excluded
  `.slim/clonedeps` vendored-clone noise.

## Sweep integrity

- Moving-target guard: mtimes snapshot before (max 1786508972) and after — static.
- Working tree: 19 modified files + untracked `uv.lock` on HEAD `cc47714`
  (`git diff --stat`: 1152 ins / 1295 del) — uncommitted fix work is the NORMAL
  mid-audit state; do not treat it as a failure signal.
- 46 files swept: hermes_opencode/*.py (9), scripts/e2e_smoke.py, tests/*.py (11),
  root __init__.py, plugin.yaml, pyproject.toml, ruff.toml, README.md, wiki/** (24).
- Completeness: per-file `v2|V2|/api/` hit-count sweep + deleted-name alternation
  (V2Collapser, detect_engine, _event_seq, _last_stop, _fallback_v1,
  _deny_locked_out, deny-lockout, prompt_legacy, create_session_v1,
  active_sessions, question_list*, auto_first, auto_answer_questions,
  permission.v2.*, question.v2.*, session.next.*, next.stop/start, engine="v2",
  scope="context", SessionV2, PermissionV2, EventV2, fallback:"v1",
  question_registry_get, GET /question reconcile) + live-surface inventory
  (client method list, tool registry, question_reply schema params).

## Classification of every hit file

### Code — hermes_opencode/ (all EXPLANATORY docstrings/comments, no executable v2)
- client.py:3-6 module docstring: v1 instance API; "The v2 protocol surface
  (/api/...) is deliberately NOT used (v2 sessions resolve only config-document
  agents and deny every tool...)". :207 "v1 counterpart of the v2 active set".
  :256 "not the v2 {prompt:{text},resume} wrapper". — EXPLANATORY
- bridge.py:13-14, tools.py:20 module docstrings: "Everything runs on opencode's
  v1 surface (the v2 API is deliberately not used...)". bridge.py:456 prompt()
  docstring "the v2 registry never sees." — EXPLANATORY
- events.py:3,8 module docstring (v1 /event subscribes to the shared EventV2 bus;
  "without the v2 /api/event encode fragility"); :242 comment "Everything else
  (session.next.*, feature/todo events) is ignored:" — EXPLANATORY
- read.py:3-7 docstring: "the plugin deliberately never uses the v2 API, so reads
  use the legacy cursor API... (MessageV2.page: newest N...)" — server type name
  in docstring only, no symbol — EXPLANATORY
- approval.py:11, serve.py:8: "v2026.8.3" Hermes version strings — non-findings.

Live-surface inventory (deleted-name completeness): client methods all v1
(health, session_status, create_session, prompt, messages, permission_list,
permission_reply, question_reply, question_reject, commands, iter_events +
private) — no active_sessions/history/context/v2 routes. Tool registry = exactly 5
(opencode_prompt, opencode_session_tail, opencode_session_read,
opencode_question_reply, opencode_command) — no opencode_questions.
question_reply schema (tools.py:147-168) = question_id + answers only — deleted
session_id param absent. scripts/e2e_smoke.py, config.py, __init__.py: ZERO hits.

### Tests (EXPLANATORY — intentional negative tests)
- test_events.py:95-98 test_v2_permission_family_ignored (permission.v2.asked,
  asserts no callback); :107-111 test_v2_question_family_ignored; :113-120
  test_unknown_events_ignored (session.next.started / session.next.stop /
  feature.updated frames asserted ignored). Note: the 6 v2 hits = 2 per negative
  test (var name `v2` + frame type) + test names.
- test_read.py:151 read_session(scope="context") — asserts deleted scope RAISES.
- test_approval.py:241,350,365 question_registry_pop — LIVE current method,
  matched only the `question_registry` prefix — non-finding.

### README + manifests
- README.md:17 "v2026.8.3" — version string, non-finding.
- plugin.yaml, pyproject.toml, ruff.toml: ZERO hits — clean.

### Wiki — banner-marked / server-surface reference pages (EXPLANATORY)
- plugin-requirements.md — banner :14-16 "the plugin is V1-ONLY... v2 is
  documented as reference only"; :82 "V2 (reference only, dropped 2026-08-11)";
  :251 "No /api/* route is used anywhere in the plugin".
- opencode-session-reading.md — banner :16-19 "reference for the deferred v2
  migration"; :51-55 v2 read table labeled "v2-engine only (server reference;
  not used by the plugin)"; :92-96 MessageV1 flat-modelID note (R4/R5-fixed).
- opencode-agent-registry.md — banner :15-19; :112 "This whole v2-then-fallback
  path was removed in the 2026-08-11 v1-only migration".
- opencode-permissions.md — :16 "the v2 /api/permission/request surface below is
  server reference only"; :80-92 two-engines rule; :118-119 reply-surface rule.
- opencode-http-api.md — `runtime: opencode` entity: "Wire surface of the opencode
  server (v1.18.13)"; :17-23 two-surfaces framing + 404-mixing rule.
- opencode-commands.md — `runtime: opencode` concept: documents BOTH routes
  ("GET /api/command → CommandV2.Service.list()" AND "Legacy GET /command ...
  exposes the same registry"); plugin uses v1 GET /command (client.py:343-347);
  no plugin prescription.
- opencode-question-api.md — v2 protocol group table + v1 instance surface +
  "answer at the route the ask event came from".
- opencode-event-streams.md — title "v1 instance vs v2 protocol"; :61-76 v2
  stream fragility; :103-105 surface matrix.
- opencode-sdk.md :74-84 "## v2 SDK" section; opencode-plugin-api.md :87-103
  "## v2 experimental API"; opencode-runtime.md :42,48 source cites — entity refs.
- message-injection.md :32-42 v2 prompt-route notes (both surfaces documented).
- index.md :14,33,34 blurbs describing the reference pages above.
- hermes-agent-runtime.md:15, hermes-plugin-surface.md:15,
  hermes-approval-route.md:100 — version strings, non-findings.

### Wiki — log.md (HISTORICAL-LOG)
- :1-13 [2026-08-11] v1-only migration entry (the migration record).
- :33-41 [2026-08-10] "final once-over" (v2-first permission_list + session.next.stop
  wait) — carries the R4 superseded banner at :35.
- :53,56,64,65,68 [2026-08-09] dated entries; :76,80,82,84,88-92,126,130
  [2026-08-10/11] dated entries — all accepted as history.

## Method lessons (new this round)

1. **Briefed file:line references go stale as fix work grows the file.** The R5
   brief cited bridge.py:70; the comment now sits at :75 (5 lines of fix work
   since R4). Verifying by the briefed line number alone false-FAILS a
   correctly-landed fix. Re-locate by CONTENT (grep the comment text), confirm
   semantics, then report the CURRENT line so the next round verifies a live
   number. Distinguish line-reference drift from regression.
2. Re-confirmed from prior rounds: mtime snapshot before/after the sweep is the
   moving-target guard; uncommitted fix work on HEAD is normal mid-audit state.
3. Re-confirmed: version-string disambiguation (`v2026.8.3`), vendored-clone
   noise exclusion, per-file hit-count sweep as completeness check, negative
   tests + banner-marked pages are EXPLANATORY.
