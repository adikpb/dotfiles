# Residue Sweep ROUND-5 (2026-08-12) — convergence re-verification

Round 5 of the v1-only migration audit loop. Task: verify the 2 briefed
frontmatter bumps, then re-sweep the ENTIRE repo for residual v2/old-route
content (4-bucket classification). READ-ONLY. Result: **2/2 frontmatter
VERIFIED; convergence HELD — zero CODE_PATH, zero STALE_DOC.** One
still-present non-v2 nit carried over from the R4 report file (bridge.py:70
comment drift) that the R5 brief did not list.

## Frontmatter verification (2/2)

| Item | State | Evidence |
|------|-------|----------|
| wiki/concepts/plugin-requirements.md `updated:` | VERIFIED | frontmatter line 4: `updated: 2026-08-11` |
| wiki/concepts/opencode-permissions.md `updated:` | VERIFIED | frontmatter line 4: `updated: 2026-08-11` |

## Classification (full deleted-name grep list, every hit bucketed)

- **CODE_PATH (0)** — every v2 mention in code is a docstring/comment
  explaining v2 is deliberately unused (client.py:4-5, :252-259;
  bridge.py:13-14, :446; tools.py:20; read.py:4; events.py:8, :236-237).
  `client.prompt` posts `POST /session/{id}/prompt_async` (client.py:273) —
  the v1 fork route. scripts/e2e_smoke.py: only prompt_async refs (:9,:110),
  R1 findings stay closed. plugin.yaml / pyproject.toml / ruff.toml: zero
  hits; provides_tools = the 5 v1 tools.
- **STALE_DOC (0)** — prior-round STILL-PRESENT candidates re-verified
  FIXED: opencode-permissions.md:53 ("server reference only since the
  2026-08-11 v1-only migration" — the R1 v2-first reconcile claim),
  plugin-requirements.md:146 ("event-driven only; no `GET /question`" — the
  R1 #7 reconcile recipe), test fakes implement permission_list/
  permission_reply (test_bridge.py:89-92 + fix comment :340; test_approval
  :39/:48; test_tools :84/:87). README.md: single v2|/api hit = the Hermes
  version string "v2026.8.3" (:17) — not v2 API.
- **EXPLANATORY** — negative tests (test_events.py:95-99, :107-111,
  :113-120 incl. session.next.started/stop; test_read.py:148-151
  scope="context" RAISES), banner-marked pages (plugin-requirements
  :14-19/:251 "No `/api/*` route is used anywhere in the plugin";
  session-reading :14-20 + v2-engine-only rows; agent-registry :15-19 +
  "DELETED 2026-08-11" section :99-116; permissions :14-17 + v2-protocol
  section :80-87), opencode server-surface pages (http-api full v1+v2
  table, sdk v2-SDK section, runtime, event-streams, commands, question-api
  :110-111 "GET /question listing was removed … opencode_questions tool;
  opencode_question_reply is the only question tool", message-injection
  "TWO surfaces", plugin-api "## v2 experimental API" labeled experimental,
  index, comparison-hook-models).
- **HISTORICAL-LOG** — wiki/log.md dated entries; superseded banners
  verified on both v2-first entries (log.md:34-35 and :85-86); the
  :126-131 agent-registry incident record (`fallback:"v1"` note) is dated
  history. .hermes/plans/…skeleton.md SUPERSEDED banner :3-6 verified.

## Findings

| Sev | Bucket | File:line | Description | Fix |
|-----|--------|-----------|-------------|-----|
| nit | CODE_PATH (non-v2 comment drift) | hermes_opencode/bridge.py:70 | `_delegated` comment still `# wait=false sessions: {"last_fp"}` while entries carry `in_flight` (incr :463, decr :232, pop :233-236). R4 report-file nit, brief omitted it, still unfixed. | comment → `{"last_fp", "in_flight"}` |

## Method lessons (new this round)

1. **Silent shell-quoting grep failure**: a terminal `rg -e 'PAT'` whose
   pattern contains a single quote (e.g. `["']` char classes) breaks the
   shell quoting and returns **0 hits** — indistinguishable from a clean
   result. The R5 Pattern-A grep "found nothing" until re-run via the
   tool-level ripgrep (search_files), which has no shell layer. Rule: run
   deleted-name greps through the tool-level rg, and sanity-check any
   0-hit result against a pattern that MUST match (e.g. a known-present
   deleted name like `session.next`).
2. **Per-file hit-count sweep = completeness check**: `rg -i -c 'v2|/api/'
   --glob '!<noise>' . | sort` lists every file with hits; every listed
   file must be classified, and files ABSENT from the list are provably
   clean. This caught README.md (1 hit) and serve.py/approval.py (1 each)
   that per-file eyeballing would have missed.
3. **Disambiguate version-string hits before classifying**: `v2026.8.3`
   (Hermes version, appears in README.md:17, wiki sources lines,
   approval.py:11, serve.py:8) matches a naive `v2` grep but is NOT v2-API
   residue. Count-and-inspect beats blind classification.
4. **The brief under-counts its own round's findings**: R5 brief said R4
   found "exactly 2 findings" (frontmatter) but the R4 report file also
   carried the bridge.py:70 nit. The report FILE is ground truth — when a
   brief's count disagrees with the round's reference file, re-verify the
   report-file items too (they were simply not listed).
5. Non-v2 findings still must fit the mandated JSON bucket enum: pick the
   least-wrong bucket (CODE_PATH for code artifacts) and say "non-v2" in
   the description rather than dropping the item.
6. Moving-target guard held: two mtime snapshots identical across the run.

## Out of scope (other loops, not v2 residue)

- hermes_opencode/__init__.py:42 `requires_env=[...USERNAME, ...PASSWORD]`
  — optional secret labeled required (R1 #13, surface-loop item;
  requires_env is display-only, no hard gate).
- `__pycache__` regenerates on test runs — gitignored, not a finding.
