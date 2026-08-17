# Surface-consistency audit ROUND 4 (2026-08-12) — convergence round

Round 4 of the audit loop on hermes-opencode-plugin (v1-only bridge). The
maintainer had applied the Round-3 surface findings; this round verified the
6 briefed fix groups and hunted NEW tool-surface / config-surface / docs /
test-fake inconsistencies. READ-ONLY (report written to /tmp only).
Companion to `surface-consistency-audit-round3-2026-08-12.md` and the
parallel `residue-sweep-r4-2026-08-12.md` (behavioral/residue dispatch).

## Gates

- `uv run ruff check .` → clean (exit 0)
- `uv run pytest -q` → **161 passed + 1 subtest** (51.76s; R3 was 157+1 —
  the suite grew by 4 tests since)
- mtimes snapshotted before/after (stat -f "%m %N" on all py/md/yaml):
  unchanged (max = tests/test_bridge.py 07:49:49 both times); `git diff
  HEAD --stat` identical across the run — no concurrent edits (the R2R2
  moving-target method did not trigger)
- Working tree: 18 modified files + untracked uv.lock; fixes are
  uncommitted working-tree changes, as in R3

## Fix groups 1-6 — all VERIFIED-FIXED

1. opencode_command schema params have descriptions (tools.py:172-183:
   name "Command name; omit to list...", args "Template arguments
   ($1..$n, $ARGUMENTS)...", directory "Project directory for the
   command listing/run..."); prompt `wait` description covers the
   cross-directory poll fallback (tools.py:94-96: "...for a session in a
   different directory it polls the directory-scoped status map instead
   and may hold for the full timeout").
2. README prompt row matches the new wait text (README.md:87 — same
   cross-directory poll sentence) and keeps the stream-down re-read.
   Other tool rows: no drift — every README signature lists exactly the
   schema's params.
3. wiki/log.md superseded banners: [2026-08-10] "final once-over" entry
   (log.md:33) → banner :34-35; [2026-08-10] "turn-complete injection"
   entry (:84) → banner :85-86; both point at the 2026-08-11 migration
   entry. (The third v2-flavored dated entry, :82 "question_reply_mode
   default reject -> gate", describes the same-day-removed gate era and
   is self-corrected by the immediately following :87 "gate REMOVED"
   entry + :89 auto_first deletion — chronological narrative, not a
   current-behavior claim.)
4. wiki/concepts/opencode-session-reading.md:72-73 diag2_e2e.py citation
   annotated: "the diag2_e2e.py probe was removed in the 2026-08-11
   v1-only migration".
5. Test fakes record full kwargs: FakeBridgeClient.create_session records
   (sid, agent, model, directory) and prompt records (session_id, text,
   agent, model, directory) (test_bridge.py:55-64); ToolBridgeClient
   mirrors it (test_tools.py:55-62).
   test_prompt_forwards_config_agent_model_and_directory pins forwarding
   end-to-end incl. the model dict conversion (test_bridge.py:300-323).
6. tail_size default unified on 8: read.py:143-144 (limit None -> 8,
   pinned test_read.py:142-146 "(None, 8)"), bridge.py:182/215/457,
   tools.py:260/266/285, config.py:86 (clamped [1,100]). Test CFG dicts
   still inject their own 40 (test_bridge.py:21, test_tools.py:25) as
   intended.

## NEW findings (4)

### N1 (nit) — three schema params still bare `_STRING` with no description
tools.py:114 (opencode_session_tail.session_id), :131
(opencode_session_read.session_id), :154 (opencode_question_reply.question_id)
are still bare `_STRING`. The R3 N2 fix covered only opencode_command's
name/args/directory — the finding was a CLASS and only one instance was
fixed. The id params and the reply question_id are exactly where ambiguity
costs the most.
Fix: `"session_id": {"type": "string", "description": "The opencode session id (from a prompt result or turn-complete notification)."}` for both; `"question_id": {"type": "string", "description": "The ask id from the injected '[opencode] question' message."}`.

### N2 (nit) — README opencode_prompt signature order drifts from the schema
README.md:87 lists `opencode_prompt(session_id?, prompt, directory?, agent?,
timeout?, wait?)` — session_id before prompt — while the schema properties
(tools.py:67-99) define prompt first and only prompt is required; every
other README tool row matches schema property order. Agents reading the
signature string infer the wrong call shape.
Fix: reorder to `opencode_prompt(prompt, session_id?, directory?, agent?,
timeout?, wait?)`.

### N3 (nit) — wiki blocking-handoff bullet still claims purely event-driven wait
plugin-requirements.md:98-101 "Blocking ... router.wait_for_complete resolves
on the v1 session.status idle event (one GET /session/status re-read only as
a stream-down fallback)" — no cross-directory caveat, while the fixed schema
text (tools.py:94-96) and README.md:87 now document the directory-scoped
status-map poll for turns outside the bridge directory (bridge.py:494-506
`_wait_idle`; the router's /event subscription never sees foreign-directory
idle). R3 N1 fixed schema+README only; the wiki's R1 handoff bullet carries
the same stale claim the fix was targeting — after fixing one surface,
re-grep the OTHER surfaces for the old text.
Fix: append: "For a session in a different directory than the bridge's,
wait=true polls the directory-scoped status map instead of the event stream
and may hold for the full timeout."

### N4 (nit) — opencode-session-reading.md MessageV1 summary omits flat info.modelID
opencode-session-reading.md:92-94 prints "MessageV1 = {info: {id, role,
time: {created}, model?: {providerID, modelID}}, parts}" and labels the flat
form V2-core. Live-verified 2026-08-11 (live-v1-runtime-verification):
assistant messages carry `info.modelID` FLAT while user messages nest
`info.model` — the code (read.py:51-55) and the page's own shaping table
(:108 "info.modelID / info.model.modelID") handle both. Summary lines lag
the tables: a shape summary that omits a form the table documents is a
reader trap, not a table error.
Fix: extend the shape at :92-93 to
`{info: {id, role, time: {created}, modelID?, model?: {providerID, modelID}}, parts}`
(user msgs nest model, assistant msgs carry flat modelID).

## STILL-PRESENT (3 — all R1 findings, never in any briefed list)

### S1 (cleanup) — stale `GET /question` in the reconnect reconcile recipe
wiki/concepts/plugin-requirements.md:329-331 "SSE reconnect ... re-subscribe
+ REST reconcile (`GET /permission`, `GET /question`, history tails)" — the
question query path was deleted 2026-08-10 (log.md:89-94) and reconcile is
permission-only, as the same page's R2 section says (:142-143 "Questions are
never queried (event-driven only; no GET /question)"). R1 finding #7
(surface-consistency-audit-v1-only, plugin-requirements.md:319-321), still
unfixed.
In-page contradiction rule: a "Resolved questions" bullet that contradicts
the page's own updated R-section is stale regardless of its section header —
the header is history, the recipe is prescription.
Fix: drop `GET /question` from the bullet; note questions are never
enumerated.

### S2 (nit) — register_tool requires_env overclaims an optional secret
hermes_opencode/__init__.py:42 `requires_env=["OPENCODE_SERVER_PASSWORD"]`
labels the password as required for the toolset, but an empty/unset password
is the documented default no-auth localhost mode (README.md:80-81, config.py
warnings; `requires_env` only feeds toolset requirements display in Hermes,
registry.py:865-868, no hard gate). plugin.yaml correctly declares no
requires_env (secrets go via register_tool per hermes-plugin-surface.md:125-127),
so the display mismatch is the only drift. R1 finding #13, still present.
Fix: drop the requires_env list, or document that the secret is optional
for localhost binds.

### S3 (nit) — bridge/tools test fakes still lack permission_list/permission_reply
test_bridge.py FakeBridgeClient (:42-84) now has question_reply/question_reject
but no permission_list/permission_reply/commands; test_tools.py
ToolBridgeClient (:46-84) has commands but no permission_list/permission_reply
/question_reject. Both CFGs set attach_reconcile=False (test_bridge.py:23,
test_tools.py:27), so ApprovalBridge.reconcile (approval.py:312 early-return)
never exercises the pending-list surface — flipping the flag to True would
AttributeError against either fake (test_approval.py's fake has all of them,
:39/:45/:48). R1 findings #11/12, partially fixed.
Fix: add `permission_list(directory=None) -> []` and
`permission_reply(rid, reply, message=None, directory=None)` to both fakes
(commands/question_reject to the bridge fake) and add one test calling
reconcile() with attach_reconcile=True.

## Additional sweep confirmations (no finding)

- Config surface complete: every key load_bridge_config() returns is consumed
  (rule_key_prefix -> approval.py:206; prompt_timeout -> bridge prompt/tools;
  directory -> bridge._directory; agent/model -> bridge.prompt;
  question_reply_mode/clarify -> bridge; inject_turn_complete -> bridge
  _on_turn_complete) and every key is in the README config table (:59-70) and
  the wiki R7 table (plugin-requirements.md:272-285) with matching defaults.
  No dead, undocumented, or dead-read keys; `rule_key` config key vs
  `rule_key_prefix` dict key split documented correctly in both tables.
- Tool surface: plugin.yaml provides_tools == TOOL_REGISTRY (5/5);
  plugin.yaml description, pyproject description, README framing consistent.
- Residue sweep (hermes_opencode/ + scripts/ + tests/ + docs): no
  active_sessions/prompt_legacy/V2Collapser/auto_first/_fallback_v1/
  deny_locked/scope=context (test_read.py:151 is a NEGATIVE test asserting
  ValueError); no server_port; tail_size 40 only in the two test CFG dicts;
  session.next.stop mentions are banner-marked log entries, the migration
  entry, and EXPLANATORY reference-page text.
- e2e_smoke.py v1-only; README question wording matches approval.py;
  opencode-agent-registry.md + opencode-permissions.md carry v1-only banners.
- Version pins: README/wikis/client docstrings uniformly claim opencode
  v1.18.13 + hermes v2026.8.3; pyproject/plugin.yaml/__init__.__version__ all
  0.1.0. pyproject dev deps unpinned — repo convention, not a surface claim.

## Method lessons (durable)

1. When a finding is a CLASS ("schema params lack descriptions"), sweep the
   WHOLE class next round — the fix lands on the cited instance only
   (opencode_command), leaving siblings (3 more bare `_STRING` params).
2. Re-check PRIOR rounds' unfixed findings: the brief covers only the last
   round's groups; R1's #7/#11/#12/#13 were never in any briefed list and
   are still in the tree three rounds later. Keep a running ledger.
3. After fixing one surface of a claim (schema + README), re-grep the other
   surfaces for the OLD text (wiki R1 bullet kept the event-only claim).
4. In-page contradiction rule: a "Resolved questions" bullet that
   contradicts the page's own updated R-section is stale regardless of its
   section header — the header is history, the recipe is prescription.
5. Summary lines lag tables: a shape summary that omits a form the page's
   own table documents (flat info.modelID) is a reader trap.
6. Test-fake config masking persists across rounds: attach_reconcile=False
   in the CFG dicts keeps the fakes' missing permission methods invisible —
   re-verify with a flag-flip thought experiment each round.

Full report also written to /tmp/v2_audit_r4_3_surface.md (13-finding
table with file:line index + machine-readable JSON).
