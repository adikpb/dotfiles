# Surface-consistency audit ROUND 3 (2026-08-12) — verification + new findings

Round 3 of the audit loop on hermes-opencode-plugin (v1-only bridge). The
maintainer had just applied the Round-2R NEW surface findings; this round
verified those 6 groups in the current tree and hunted for NEW
tool-surface/config-surface/docs/test-fake inconsistencies. READ-ONLY.
Companion to `behavioral-audit-r2r2-2026-08-12.md` and
`surface-consistency-audit-v1-only-2026-08-11.md`.

## Gates

- `uv run ruff check .` → clean (exit 0)
- `uv run pytest -q` → 157 passed + 1 subtest (50.55s)
- mtimes snapshotted before/after: unchanged (max = tests/test_bridge.py,
  tests/test_read.py) — no concurrent edits this round (the R2R2 moving-target
  method still applies; it just did not trigger)
- Working tree: 17 modified files + untracked uv.lock; fixes are uncommitted
  working-tree changes

## Fix groups 1-6 — all VERIFIED-FIXED

1. MessageV1 fakes: test_bridge.py:28-39 + test_tools.py:32-43 text_msg =
   `{info: {id, role, modelID, sessionID, time: {created}}, parts}`;
   test_read.py:10-21 (user msgs nest `info.model`) + :24-36 tool_msg
   (assistant flat `info.modelID`) also match the live v1 wire.
   `FakeBridgeClient.session_status(directory=None)` (test_bridge.py:66) and
   `ToolBridgeClient.session_status(directory=None)` (test_tools.py:64) match
   real `OpenCodeClient.session_status(directory=None)` (client.py:202).
2. test_config.py:43-59 test_defaults_when_no_config and :61-96
   test_override_wins both cover prompt_timeout / inject_turn_complete /
   directory / agent / model / question_reply_mode / question_clarify.
3. scripts/e2e_smoke.py: no PROJ symbol, no tempfile import (grep exit 1);
   scratch dir replaced by REPO; v1 flow only (create_session → prompt_async
   → assistant-row PONG match).
4. read.py:143-144 `if limit is None: limit = 8` (pinned by
   test_read.py:142-146 `(None, 8)`); all tail_size fallbacks on 8:
   bridge.py:175 (_on_idle), :213 (_on_turn_complete), :446 (prompt),
   tools.py:248 + :271; config.py:86 default 8 clamped [1,100].
5. Wiki: opencode-session-reading.md:91-93 MessageV1 primary (flat form
   labeled V2-core); hermes-plugin-surface.md:115-116 `port` (no
   `server_port` anywhere in repo), :84 register_tool includes requires_env;
   plugin-requirements.md:76-81 prompt_async 204-fork + "blocking sibling
   `POST /session/{id}/message` ... is never used", :108-110 no idempotency
   key, :129-130 "One unretried read at idle", R5 :241-250; opencode-agent-
   registry.md:112-116 deleted-fix history now says POST /session +
   POST /session/{id}/prompt_async.
6. read.py imports only typing.Any — no logging import/logger.

Bonus: R2R2 behavioral residuals spot-checked fixed — forget() stale-idle
(events.py:110-120, pinned test_events.py:171-186), non-dict status guard
(events.py:189), _down_reason reset on start (bridge.py:99), `_INT` gone,
`_as_bool("false")->False`, stop() clears _delegated/_injected_questions/
_pending_tails (bridge.py:152-157).

## NEW findings (3)

### N1 (nit) — cross-directory wait=true undocumented on the tool surface
tools.py:88-95 schema `wait` description and README.md:87 say wait=true is
purely event-driven; plugin-requirements.md:96-101 same. Code (bridge.py:480-
492 `_wait_idle`) polls the directory-scoped status map whenever
`directory != bridge directory` — the router's /event subscription can never
deliver that session's idle — and the poll can hold the full
prompt_timeout. No "cross-directory" text anywhere in README/wiki.
Fix: add to the schema wait description + README row: "For a session in a
different directory than the bridge's, wait=true polls the directory-scoped
status map instead of the event stream and may hold for the full timeout."

### N2 (nit) — opencode_command schema params have no descriptions
tools.py:169-171: name/args/directory are bare `_STRING`, unlike every other
tool schema. directory's purpose is undocumented at the schema level.
Fix: add per-param descriptions (name: "Command name; omit to list",
args: "Template arguments ($1..$n, $ARGUMENTS)", directory: "Project
directory (default: bridge directory)").

### N3 (cleanup) — test fakes drop prompt/create payload kwargs
FakeBridgeClient.prompt (test_bridge.py:60-64) and ToolBridgeClient.prompt
(test_tools.py:60-62) accept agent/model/directory but record only
`(session_id, text)`; create_session records `(sid, agent, model)` dropping
directory. bridge.prompt forwards agent/model/directory on BOTH calls
(bridge.py:444-445), so a regression that stops forwarding config
agent/model on the prompt call (or directory on create) passes silently.
Generalizes the surface-audit "fakes MISSING methods real code calls" class:
fakes that DROP call kwargs in their records create the same blind spot.
Fix: record full kwargs and add one assert that config agent/model reach
client.prompt.

## STILL-PRESENT (1)

### S1 (nit) — wiki/log.md dated changelog entries describe v2 as current
log.md:34-35 ([2026-08-10] "wait_for_complete resolves on the v2
session.next.stop {complete} event or the v1 session.status idle",
"permission_list is v2-first: GET /api/permission/request ... v1 fallback")
and :82 (turn-complete "v2 session.next.stop + v1 session.status idle both
trigger"). Suggested fix from the surface-consistency audit (add a
"superseded by the 2026-08-11 v1-only migration entry above" pointer) still
unapplied — the top-of-file migration entry supersedes them but nothing
points readers at it.

## Clean-sweep confirmations (no finding)

- No `server_port` anywhere (README/wiki/config/plugin.yaml/serve.py all
  `port`). plugin.yaml has no requires_env (correct: env secrets documented
  via register_tool, not the manifest); provides_tools == TOOL_REGISTRY (5).
- No doc lists tail_size 40 (only test CFG dicts, which is fine).
- No /message prompt-route claim: plugin-requirements.md:78 "never used";
  opencode-agent-registry.md:108 inside the banner-marked deleted-fix
  history (EXPLANATORY).
- `opencode_questions`/`question_list`/`auto_first` residue: only
  opencode-question-api.md:110-112, which EXPLICITLY says the tool was
  removed — accurate, not stale.
- README.md:117-119 question wording now matches code: id-less dropped with
  a warning (approval.py:172-174), unanswerable fail closed to reject
  (approval.py:276-279) — the R2R wording finding is fixed.
- prompt_async 204 → `{}` (client.py:279; fakes return `{}`); test_client
  :50 asserts the parts body on prompt_async; test_events.py:115-117
  session.next.* frames are a NEGATIVE ignore-test (allowed).
- README tool table params match all five schemas; pyproject + plugin.yaml
  descriptions consistent.

## Method lessons (durable)

1. Fake-recording fidelity is a fourth fake check: signature match is not
   enough — verify the fake RECORDS the kwargs real code passes, else
   payload-forwarding regressions pass silently.
2. Every schema param needs a description; a bare `_STRING` with no
   description is a finding, directory-scoped params especially.
3. When a tool param changes behavior based on directory scope, the schema
   description must say so — the code comment in _wait_idle is not a
   surface.
4. Changelog pages need superseded pointers after a migration, or the
   dated entries keep reading as current behavior.

Full report also written to /tmp/v2_audit_r3_3_surface.md (11-finding
table with file:line index).
