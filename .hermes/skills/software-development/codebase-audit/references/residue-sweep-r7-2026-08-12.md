# Round 7 residue sweep (r7_1) — 2026-08-12 ledger

Continuation of the hermes-opencode-plugin v1-only audit loop. Round 7 = verify all 8 Round-6 fix groups with exact anchors + full-repo re-sweep (every `.py` in `hermes_opencode/`, `scripts/`, `tests/`; `plugin.yaml`, `pyproject.toml`, `ruff.toml`; `README.md`; all 24 wiki pages). Result: **8/8 fix groups verified, 2 LOW findings, 0 CODE_PATH v2 residue.** Report written to `/tmp/v2_audit_r7_1_residue.md`; final response was the machine-validated JSON contract.

## Fix-group anchors verified (state these exact lines in the next round's brief)

| Group | What | Anchors (current tree) |
|---|---|---|
| G1 | events.py EventRouter `on_busy` ctor arg + dispatch fires it after on_idle | events.py:58,62 (ctor args), 66/70 (stored), 235-238 (`idle` fired at :235-236, `busy` at :237-238) |
| G2 | bridge.py `_on_busy` records `entry["busy_seen"]=True` | bridge.py:139 (wiring), 169-178 (`:178` sets busy_seen) |
| G3 | `_on_turn_complete` delivery gate: `if fp == last_fp:` deliver only if busy_seen, else skip; busy_seen consumed on delivery | bridge.py:209 (def), :226 (docstring), :250 (`fp == entry.get("last_fp","")`), :258 (`if not entry.get("busy_seen", False): return`), :260-261 (last_fp update + busy_seen=False) |
| G4 | prompt(): forget() gated on `directory is None or directory == self._directory`; baseline_fp read pre-fork for event-wait route only; `_wait_idle` gained baseline_fp; stale resolution falls back to `_poll_status_idle` | bridge.py:489,496 (gate + forget), :498-508 (baseline_fp, read before client.prompt at :509), :532-534 (pass through), :543-549 (def + param), :574-584 (tail re-read, `:581 if _tail_fp(tail) == baseline_fp:` → `:584` poll fallback), :592 (def _poll_status_idle) |
| G5 | client.py create_session normalizes ModelRef {providerID, modelID} → Session Model {id, providerID} | client.py:219 (def), :234-240 (comment + `body["model"] = {"id": model_id, "providerID": ...}`) |
| G6 | client.py reply methods first param `request_id` → `rid` | client.py:333-334 (permission_reply), :348 (question_reply), :351 (question_reject); docstring :338 "to match the AskSurface protocol" |
| G7 | question rendering: no `type != custom` option filter; per-question `custom` bool default true; "custom (type your own)" hint; choices = all labels [:4] or None | bridge.py:346-364 (`:363 q.get("custom", True)` → `:364` hint), :425-443 (`:441 choices = labels[:4] or None`) |
| G8 | tests: new tests + _status_event helper + rid fakes + v1 OPTIONS + Session-shape assert | test_bridge.py:226 (_status_event), :275, :328, :348, :364, :527 (new tests), :52/70-71 (status_dirs), :85-95 (rid fakes); test_approval.py:39-45 (rid fakes), :213 (OPTIONS `[{"label":"y"},{"label":"n"}]`); test_client.py:89-91 (Session shape assert) |

Verification method: fresh greps for each symbol (`grep -n "busy_seen\|_on_busy\|last_fp" hermes_opencode/bridge.py` etc.), then read the enclosing region to confirm LOGIC (dispatch order idle→busy, gate semantics, baseline compare), not just presence. All greps were re-run from scratch after a context compaction — do not trust handoff-summary anchors, see SKILL.md pitfall.

## Ground-truth facts (vendored openapi.json, `.slim/clonedeps/repos/anomalyco__opencode/packages/sdk/openapi.json`)

Python path-walk adjudication (print operationId + requestBody schema per route):

- **v1 `POST /session/{sessionID}/prompt_async`** (session.prompt_async): body properties `messageID` (pattern `^msg`), `model` ({providerID, modelID} required both, additionalProperties false), `agent`, `noReply`, `tools` … — **the optional idempotency field is `messageID`, NOT `id`**.
- **v2 `POST /api/session/{sessionID}/prompt`** (v2.session.prompt): body has `id` (pattern `^msg_`), `prompt`, `delivery` (steer|queue), `resume`; required `prompt`; additionalProperties false.
- **v1 `POST /session`** (session.create): `model` = {id, providerID, variant?} required [id, providerID] additionalProperties false (NOT ModelRef) — confirms G5.
- **`POST /question/{requestID}/reply`**: body {answers: array of QuestionAnswer} required, additionalProperties false.

Consequence: a doc writing the v1 prompt body as `{parts, agent?, model?, id?}` conflates the two surfaces — `id` on the v1 route 400s. **That was finding 1.**

## Findings (2, both LOW)

1. **STALE_DOC, LOW — wiki/concepts/plugin-requirements.md:77.** R1 v1 prompt_async body shape `{parts, agent?, model?, id?}` should be `{parts, agent?, model?, messageID?}` (v1 field per openapi; `id` is the v2 prompt body field, pattern ^msg_). Fix: swap `id?` → `messageID?`, note the v2 `id` is not interchangeable.
2. **CODE_PATH, LOW — tests/test_tools.py:80,83.** FakeBridgeClient still declares `question_reply(self, request_id, answers)` / `question_reject(self, request_id)`; group 6 renamed the protocol params to `rid` (client.py:334,348,351) and updated the fakes in test_bridge.py:85-95 + test_approval.py:39-45 but not this one. Cosmetic (bridge.py:623 calls positionally) — pure naming-consistency residue. Fix: rename to `rid`.
   - False-positive guard applied: `hermes_opencode/approval.py:148,150` `question_registry_pop(self, request_id)` is an INTERNAL registry-key name, NOT the AskSurface protocol param — not a finding. Distinguish internal API params containing the old token from protocol-surface params.

## Sweep evidence

- `.py` sweep (v2 + stale-marker alternation): every hit EXPLANATORY — v1-only docstrings (events.py:3,8; client.py:4-5; tools.py:20; bridge.py:13-14; read.py:4-7), correct v1 shapes (client.py:236-240 ModelRef; read.py:52-54 info.modelID), Hermes version stamps (serve.py:8, approval.py:11 "v2026.8.3"), and the INTENTIONAL v2-ignore tests (test_events.py:95-110 `test_v2_permission_family_ignored` / `test_v2_question_family_ignored` — deliberate guards for the v1-only router, EXPLANATORY per SKILL.md step 13).
- `plugin.yaml`, `pyproject.toml`, `ruff.toml`: zero hits. `README.md`: only `:17 **v2026.8.3**.` (version stamp); question tool rows correctly say "v1 question route".
- Wiki: all 24 pages classified. plugin-requirements / session-reading / permissions / agent-registry carry v1-only banners + "server reference only" markers → EXPLANATORY; opencode-http-api / sdk / runtime / plugin-api / commands / event-streams / message-injection / config / question-api / plugin-hooks are opencode server-surface reference → EXPLANATORY; hermes-side pages (plugin-surface, plugin-hooks, tool-registry, agent-runtime, approval-route, spotify, comparison, SCHEMA, index) → EXPLANATORY; log.md v2 mentions are dated historical entries → HISTORICAL-LOG (note :35/:86 explicitly flag "entry predates it and describes the then-current v2-first behavior").
- `.pyc` false positives seen again (`__pycache__/approval.cpython-311.pyc` matched `request_id`) — inert, source newer.

## Mtime snapshots (moving-target proof)

- Snapshot 1: session start (before any reads) — baseline = Round-6 working tree.
- Snapshot 2: `2026-08-12T05:20:22Z` — newest mtimes were round-6 artifacts (tests/test_client.py 1786511106, tests/test_bridge.py 1786511453, .pytest_cache/.ruff_cache 1786511484-1786511750); `git status --porcelain` unchanged between snapshots. No file moved during the audit.

## Reporting discipline notes for the next round

- Keep the findings ARRAY to fixable items (CODE_PATH/STALE_DOC) — do NOT pad with EXPLANATORY/HISTORICAL-LOG entries; the convergence loop ends only at 0 findings and explanatory items belong in the /tmp report ledger. r7 closed with 2 LOW findings (a body-shape typo + a cosmetic fake-param name) and still satisfied the "all agents report 0" convergence pressure by proving every other hit was explanatory.
- Verify group-by-group with the anchor table above; report the anchors you actually checked (line numbers are post-fix).
