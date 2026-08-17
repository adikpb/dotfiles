# ROUND-3 (r3_1) residue sweep ledger — hermes-opencode-plugin, 2026-08-12

Round 3 of the v2-residue audit loop. Prior state: Round 2R verified all round-2 findings fixed
(pyc purge, SUPERSEDED banner, R1/R5 prompt_async); 157 tests green, ruff clean, live e2e 6/6.

## Verification ledger (5 items, verification-first pass)

| Item | Result |
|------|--------|
| V1 no `__pycache__` in repo | **FAIL — REGENERATED.** Round 2R purge did not stick: running the suite recreated `__pycache__/` (root), `hermes_opencode/__pycache__/` (9 .pyc), `tests/__pycache__/` (10 .pyc); 20 .pyc total, mtime 2026-08-12 07:25-07:26 = the test run. All gitignored + untracked (`git check-ignore` ok; `git ls-files` clean). `.venv/**` caches = third-party, accepted. |
| V2 plan file SUPERSEDED banner | PASS — `.hermes/plans/2026-08-10_104534-opencode-bridge-plugin-skeleton.md` L3-6 banner present; body still describes v2 design but is banner-marked historical. |
| V3 plugin-requirements.md R1 (~L76) prompt_async | PASS — L75-81: v1 surface `POST /session` + `POST /session/{id}/prompt_async`; blocking sibling `POST /session/{id}/message` explicitly "is never used" (explanatory, correct). |
| V4 plugin-requirements.md R5 (~L243) prompt_async | PASS — L243-248: "via `POST /session` / `POST /session/{id}/prompt_async` … No `/api/*` route is used anywhere in the plugin." |
| V5 no stale `/api/` route references | PASS — all `/api/` mentions classified; zero live code paths (see ledger). |

## Findings (2, both LOW)

- **R3-1** CODE_PATH(build artifact)/LOW — `__pycache__` regenerated in repo source dirs. Fix:
  `find . -name __pycache__ -type d -not -path './.venv/*' -exec rm -rf {} +`, plus
  `PYTHONDONTWRITEBYTECODE=1` for pytest/e2e or a purge step in the round loop (else it re-fails every round).
- **R3-2** STALE_DOC/LOW — wiki/concepts/opencode-session-reading.md:72-73 cites `scripts/diag2_e2e.py`
  in an E2E evidence note; the script was deleted in the v1-only migration (scripts/ has only e2e_smoke.py).
  Fix: cite e2e_smoke.py only or mark the evidence block historical.

## Bucket classification ledger (every v2 //api/ mention, 84 /api/ hits + v2 sweeps)

- CODE_PATH (live v2 usage): **0** in .py/scripts/tests/config — plugin is v1-only everywhere.
- EXPLANATORY (in-code "v2 deliberately NOT used" commentary): client.py:4-8,207,252-261; events.py:3,8,116,207-208;
  bridge.py:13-16,431-433; tools.py:20-21; read.py:3-9; serve.py:143-153. Plus approval.py:11 "verified at
  v2026.8.3" = HERMES version stamp (noise class, not opencode v2).
- EXPLANATORY (wiki reference docs of opencode's dual surface, v2 labeled reference-only/dropped):
  opencode-http-api.md, opencode-sdk.md:31,80-99, opencode-runtime.md:45-46, message-injection.md:23-41,
  opencode-permissions.md:16,53,83-85,119 ("server reference only"), opencode-question-api.md:62-65,85,
  opencode-commands.md:36,48,67, opencode-event-streams.md:61-105, opencode-session-reading.md:35-57,70,76-87,
  plugin-requirements.md:35-36,82-92,235,260,349,357, opencode-agent-registry.md:15-19 (migration banner),
  44-51,99-116 ("DELETED 2026-08-11"/"Historical:" sections).
- HISTORICAL-LOG (accepted): wiki/log.md (whole file), the SUPERSEDED plan file.
- Intentional behavior tests (correct, not residue): tests/test_events.py:95-117 — v2 permission/question
  families + session.next.* frames dispatched and asserted IGNORED.
- Out of scope: `.slim/clonedeps/repos/**` third-party clones (opencode CONTEXT.md, hermes-agent
  sqlite3ext.h `prepare_v2`/`create_function_v2` C symbols — `\bv2\b` noise class); `.venv/**`.
- Checked-and-accepted: client.py:18 docstring `POST /session/:id/message` shape note (v1 route, accurate,
  cross-referenced by the prompt_async docstring).

## Tool-evidence record (the reusable gotcha)

- `search_files` (ripgrep-backed) for `__pycache__` and `*.pyc` → **0 results**; `find` → dirs present.
  Ripgrep skips gitignored + hidden paths; search_files is not evidence of absence for gitignored residue.
  `git status` also shows nothing for ignored paths — use `git check-ignore`/`git ls-files` to classify.
- Sweep pattern set that worked: one regex alternation per class — `api_route`, `\bv2\b`,
  `/session/{id}/message`-family, v2 event names (session.next|permission.v2|question.v2|Admitted|resume|…),
  prompt_async (expected-usage baseline), global/health (expected v1 baseline). Confirmed expected-usage
  tokens exist so a missing hit is a signal, not silence.

## Live state at close

157 tests green, ruff clean, e2e 6/6; report written to /tmp/v2_audit_r3_1_residue.md; final JSON:
2 findings, both LOW.
