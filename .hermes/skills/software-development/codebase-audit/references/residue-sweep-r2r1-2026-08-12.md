# Round-2 RESTART (r2r-1) residue sweep — 2026-08-12

Continuation of the hermes-opencode v1-only audit loop. The round-2 batch
was rate-limited before applying fixes, so this restart VERIFIED the two
briefed findings against the working tree, then re-swept the whole repo.
Report: /tmp/v2_audit_r2r_1_residue.md. Read-only pass.

## Briefed findings verification — FINAL: both VERIFIED-FIXED

The rate-limited round-2 batch recorded both STILL PRESENT (prior verdict
kept below for the flip record). The restart run re-read the working tree
and found the maintainer had applied the fixes CONCURRENTLY — a live
instance of the STILL-PRESENT → VERIFIED-FIXED flip (SKILL.md step 11,
live-editor discipline). Final state of the restart run:

1. `wiki/concepts/plugin-requirements.md:76` (R1 V1 bullet) — now names
   `POST /session/{id}/prompt_async` as the delegation route (parts body,
   204 No Content, turn forked); the `POST /session/{id}/message` mention
   at line 78 is the correctly-labeled blocking sibling ("streams the turn
   to completion and is never used").
2. `wiki/concepts/plugin-requirements.md:243-245` (R5) — now "via
   `POST /session` / `POST /session/{id}/prompt_async`" plus "No `/api/*`
   route is used anywhere in the plugin."

Prior batch's verdict (both were PARTIAL fixes): lines 80-81 correctly
added "`prompt_async` is fire-and-forget" but the old route name in the
main claim was never replaced → self-contradictory bullet (SKILL.md step
11). The wiki file is git-ignored (round-2 Delta 3); ground truth always
comes from reading the file + `client.py`.

## Live-verified route semantics (opencode 1.18.16 — supersedes 1.18.13 source-map for these routes)

- `POST /session/{id}/prompt_async` — v1 fire-and-forget prompt: **204 No
  Content, forks the turn** (starts the session if needed). THE plugin
  prompt route (`client.py:246-271`, `tests/test_client.py:55,67`).
- `POST /session/{id}/message` — exists but **BLOCKS until the turn
  completes**; plugin uses it only via GET as the read surface
  (`client.py:288`).
- `GET /session/status` — map gains the session's entry when the forked
  turn starts, DELETES on idle → absence = idle (but absent also means
  "not started yet"; the event stream is the reliable signal).
- Reads = MessageV1 `{info:{id, role, time:{created}, model...}, parts}`.
- V1 PromptInput payload (1.18.16): `{agent?, model?: {providerID,
  modelID}, parts:[{type:"text",text}]}`; idempotency field is `id`
  (client.py sends `payload["id"]`), NOT `messageID`; no `noReply`.

## Classification ledger (7 findings, 0 CODE_PATH)

- **CODE_PATH: 0** — zero `/api/` calls in any .py; only explanatory
  docstrings ("the v2 surface is deliberately NOT used": client.py:4-8,
  events.py:3-9, bridge.py:13-16, tools.py:20-21). events.py deliberately
  ignores `permission.v2.asked`/`question.v2.asked` (tests/test_events.py:95-110).
- **STALE_DOC (2 medium)**: the briefed pair above (F1, F2) — both now VERIFIED-FIXED in the final tree (see the flip record above).
- **STALE_DOC (2 low)**: plugin-requirements.md:108 idempotency bullet
  (doc says `messageID` + "send a fresh one"; code sends `id` and
  bridge.prompt() never passes one — claimed behavior unwired); README.md:16
  version stamp "verified against v1.18.13" vs live 1.18.16.
- **HISTORICAL-LOG (3 low)**: plugin-requirements.md:346-348 superseded
  "treat the v2 stream best-effort" guidance in a dated resolved-questions
  bullet (no v2 stream exists post-migration — annotate-superseded);
  opencode-agent-registry.md:112-116 DELETED-section whose CURRENT-state
  parenthetical (113-114) still names `POST /session/{id}/message` —
  stale "now" clause inside history, still a finding; `.hermes/plans/
  2026-08-10_104534-opencode-bridge-plugin-skeleton.md` pre-migration plan
  ("v2 API preferred with v1 fallbacks", v2 create/prompt/history routing)
  — annotate-superseded or archive.
- **EXPLANATORY (correct, no action)**: opencode-http-api.md, opencode-sdk.md,
  opencode-runtime.md:45-46, opencode-session-reading.md (v1-only banner),
  message-injection.md:23-40 (documents BOTH legacy routes with correct
  semantics — the model fix), opencode-permissions.md / opencode-question-api.md
  / opencode-commands.md / opencode-event-streams.md (v2 marked "server
  reference only"), opencode-plugin-api.md, plugin-requirements.md:28-41,82-92
  ("reference only, dropped 2026-08-11").
- **HISTORICAL-LOG (no action)**: wiki/log.md changelog (entries describe
  past states; the 2026-08-11 migration entry is the correction).

## Method deltas beyond round 2

- Concurrent-maintainer triage: `git status --short` distinguishes
  "fixed in working tree" from "still present" for TRACKED files; git-ignored
  wiki/ must be read directly (Delta 3 still holds).
- Version-stamp drift is a low STALE_DOC (README "verified against X" vs
  code's own newer stamp); internal code-docstring contradictions
  (client.py:16 "v1.18.13" vs client.py:248 "v1.18.16") are report-appendix
  nits, not findings.
- Sweep scope must include `.hermes/plans/` — pre-migration plans are
  stale-architecture residue.

## Restart run final state (report /tmp/v2_audit_r2r_1_residue.md)

- Briefed findings: 2/2 VERIFIED-FIXED (not re-reported as findings;
  surfaced as verified-fixed info rows so the parent sees they were checked).
- CODE_PATH: 0 live. Residual only: stale PRE-migration `.pyc` caches
  (hermes_opencode/ + tests/ `__pycache__`) still carry v2 strings but are
  mtime-invalidated (source Aug 12 > pyc Aug 11) → inert, regenerated on
  next import; hygiene-only (`rm -rf __pycache__`).
- STALE_DOC: 0 after re-check of the prior batch's low items:
  plugin-requirements.md:108-110 idempotency bullet now reads "the plugin
  sends no idempotency key (`messageID`/`id` are legacy-only)" — updated;
  README.md:16 still stamps opencode v1.18.13 vs live 1.18.16 — cosmetic,
  noted in the report appendix, not a finding.
- HISTORICAL-LOG (no action): wiki/log.md changelog;
  opencode-agent-registry.md:99-116 "Historical: … DELETED 2026-08-11";
  `.hermes/plans/2026-08-10_104534…` plan snapshot predating the v1-only
  decision (optional annotate-superseded).
- EXPLANATORY: every other v2 mention correctly labeled — two-surface
  server reference tables (opencode-http-api.md incl. the `prompt_async`
  row), "not used by the plugin" docstrings (client.py:4-8, events.py:8,
  bridge.py:13-16, read.py:3-9), and negative tests
  (tests/test_events.py:95-117 assert v2 event families are ignored).
- Final JSON emitted: 4 findings (2 verified-fixed info, 1 pyc low,
  1 plan info). Machine-validated output: ONLY the JSON object in the
  final message — the report file carries the prose.
