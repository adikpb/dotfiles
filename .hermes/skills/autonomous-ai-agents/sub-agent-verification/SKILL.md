---
name: sub-agent-verification
description: "Verify sub-agent output yourself before claiming done."
version: 1.0.0
author: Hermes Agent
category: autonomous-ai-agents
tags: [delegation, verification, quality, sub-agents, opencode]
metadata:
  hermes:
    tags: [delegation, verification, quality, sub-agents, opencode]
    related_skills: [opencode, hermes-handoff]
---

# Sub-Agent Output Verification

When you delegate work to a sub-agent (via `opencode run`, `delegate_task`, or any external coding agent), **do not trust self-reported success.** Sub-agents can report "file written" or "test passed" while the actual output has syntax errors, missing imports, or broken escaping. Always independently verify before telling the user the work is done.

## Mandatory Verification Layers

### 1. Syntax / Compilation Check

```python
# Python
uv run python -c "import ast; ast.parse(open('path/to/file.py').read()); print('Syntax OK')"
```

```bash
# JavaScript/TypeScript (also validates require resolution)
node -e "require('fs').readFileSync('path/to/file.js','utf8'); console.log('Syntax OK')"
```

### 2. Module Import / Load Test

Verify the module imports cleanly in the project's venv:

```bash
cd /project && uv run python -c "import sys; sys.path.insert(0,'.'); from src.module import app; print('Import OK')"
```

This catches missing transitive imports, circular dependencies, and runtime config errors that syntax checks miss.

### 3. Functional Smoke Test

Start the server and hit changed endpoints:

```bash
terminal(command="uv run uvicorn src.api:app --host 127.0.0.1 --port 8081", background=true)
sleep 2
curl -s http://127.0.0.1:8081/api/endpoint
process(action="kill", session_id="<id>")
```

For non-server code: run the test suite or an assertion script.

### 4. Smoke Test New Modules

After a multi-file build (especially new modules like tools/, models/, ledger), write a standalone smoke script that:

```python
# tests/smoke_feature.py — imports new classes, exercises key paths
from src.ledger import InvestigationLedger
from src.models import InvestigationVerdict
from src.tools.db_queries import get_stats_window, run_tool

# Seed minimal data, test lifecycle
run_id = ledger.start_run(alert_id=1, model_used="test")
eid, seq = ledger.record_event(run_id, "tool_call", "db_queries", "summary")
ledger.complete_run(run_id, "completed")
```

Run it in the project's venv:
```bash
.venv/bin/python tests/smoke_feature.py
```

This catches:
- Import-order issues and circular imports
- Missing transitive dependencies
- Schema FK constraint errors (we hit one when `investigation_runs.alert_id` referenced a non-existent alert)
- Type annotation mismatches (e.g., `callable` → `Callable` from `collections.abc`)
- Runtime path resolution from relative imports

### 5. Project Test Script Check

After an opencode build, verify the project's canonical test command works:
```bash
npm run test
uv run python -m pytest tests/ -v
```

If `package.json` has a placeholder test script (`echo "Error: no test specified" && exit 1`), fix it first — it's a common artifact of `npm init` that opencode won't fix on its own but will silently use.

### 6. Git State Review

```bash
git diff --stat          # See file-level scope
git status --short       # Check for unexpected files
git diff --cached --stat # If staged
```

Compare against expected file list from the spec. Unexpected files may indicate scope creep; missing expected files mean the edit didn't land.

### 7. Content Verification

For frontend/template changes, grep the output for expected markers:

```bash
curl -s http://127.0.0.1:8081/ | grep -oE '(new-class|newFunction)' | sort -u
```

All expected markers must appear. Missing markers = edit didn't land.

## When to Fix vs Re-Delegated

| Situation | Action |
|-----------|--------|
| Syntax error in sub-agent's code | Fix yourself — simple mechanical fix |
| Wrong approach entirely | Re-delegate with clearer spec |
| Small adjustment (styling, naming) | Fix yourself — faster |

## Recovering Truncated Batch Delegation Reports

When `delegate_task` batch results come back, the consolidated message may
**truncate or collapse each subagent's report** (summaries get clipped to
head+tail, JSON output wrapped in `[... middle omitted ...]`). Do NOT treat the
truncated version as the full report — the complete text is always on disk:

- `~/.hermes/cache/delegation/subagent-summary-<n>-<timestamp>.txt` — complete per-task summaries, one file per task.
- `~/.hermes/cache/delegation/live/deleg_<id>/task-<n>.log` — full live transcript (tool calls + results); also a per-task report file the subagent may write.
- Subagents commonly write standalone report files to `/private/tmp/*.md` or `*.json` — check `find /private/tmp -name "*report*"`.

Recovery recipe (verified 2026-08-09):

```python
# 1) List the summary files:
#    search_files(pattern="*", target="files", path="~/.hermes/cache/delegation")
# 2) Extract a JSON-escaped report from a summary file:
import json, re
raw = open("<summary-file>").read()
m = re.search(r"```json\n(\{.*?\})\n```", raw, re.S) or re.search(r"(\{.*\})", raw, re.S)
report = json.loads(m.group(1))["report"]   # full markdown, unescaped
```

The `.txt` summary files are the authoritative source; the logs truncate long
`summary:` lines at write time, so do not rely on the log tail for report text.

**Stall case (wedged worker, batch ended with no completion event — #60203):**
the `.txt` summary files may NEVER get written even when tasks report
`status=completed` in the live log — the batch wedged after the audits
finished but before delivery. In that case the log TAIL IS ALL YOU HAVE:
`live/deleg_<id>/task-<n>.log` final lines carry the truncated `final |
status=completed ... summary: ...(+N chars)` fragment (the first ~2000 chars
of each summary — often exactly the findings header + first item, since
agents front-load their key findings). Recovery: (a) `ls` the live dir and
grep each log for `final | status=`; (b) extract the visible fragment and
verify any finding visible in it against ground truth immediately — the
round-4 stalled batch's one visible fragment ("tirith row is INVERTED")
turned out to be real and critical; (c) re-dispatch the SAME blind tasks —
fresh agents re-derive everything, and the fragments double as an early
warning list to cross-check against the re-dispatch's results.

Reusable extractor: `scripts/extract_delegation_report.py
~/.hermes/cache/delegation/subagent-summary-<n>-<ts>.txt /tmp/report.md` —
recovers the full report from either summary-file format (fenced JSON, bare
JSON, or plain markdown). See `references/recon-wiki-build-session.md` for a
full session walk-through.

## Requesting File-Backed Reports

For big recon/analysis tasks, tell the subagent up front to **write the full
report to a known path** (e.g. `/tmp/<task>_report.md`) and return only a short
pointer in its final summary. This sidesteps every truncation path and cuts
round-trips: read the file directly with `read_file` and verify contents.
Example pattern that worked: agent wrote `hermes_plugins_report_final.md`
(14 KB) to /tmp; parent read it directly, no truncation, no re-extraction.

## Writing Specs for Delegation

For `opencode run`, write a markdown spec with numbered requirements and attach both spec + target files:

```
opencode run "Implement features in spec.md" -f src/target.py -f spec.md
```

Include constraints explicitly: "Do not refactor unrelated code."

## Repeated Recon-Verify-Fix Loops (audit until convergence)

When the user asks to "repeat the recon" or "loop until subagents find nothing"
(common for keeping a contract wiki / implementation spec honest against a
codebase), run a fixed-point loop:

1. **Round shape:** dispatch 3 READ-ONLY leaf subagents in one batch, split by
   vantage — content-owner side (e.g. opencode wiki pages vs opencode source),
   counterpart framework side (hermes pages vs hermes source), and integration
   seams (the spec pages vs BOTH sources).
2. **Brief every round with what's already fixed:** "ROUND N: prior corrections
   were applied; do NOT re-report those unless still WRONG in the wiki. Hunt
   for NEW gaps. Cite path:line for each finding." Explicitly offer the
   terminal answer: **"'NO NEW FINDINGS' is a valid and valuable result."** —
   without that affordance, agents invent noise to justify their run.
3. **Verification gate:** every load-bearing finding is a self-report. Re-verify
   against ground truth (vendored clones, `openapi.json`, source files) with
   `sed`/`grep`/`read_file` BEFORE writing anything. Two rounds in a row the
   audit found HIGH items the previous round's fixes had half-applied (wrong
   HTTP method, plural-vs-singular route names) — the verify step is what
   catches them. Round-N re-verification must ALSO check identifiers the fix
   INTRODUCED, not just the code path it touched: fix reports use shorthand
   type names, and that shorthand leaks into the fixed file's docstrings.
   Grep the pinned source for every new name the fix claims before calling
   it complete.
4. **Batch-level failure:** if a whole round returns only error text (HTTP 429
   rate limits, connection loss) with no usable findings, re-dispatch the SAME
   tasks. Do not proceed on empty results and never fabricate a round.
5. **Apply + lint + log:** patch pages (keep `sources:`/`confidence:`
   frontmatter), update index count + section lines, append ONE log entry
   listing everything fixed, then run the wiki lint (see
   `scripts/wiki-lint.py` here) before re-dispatching.
6. **Convergence:** loop until a round returns NO NEW FINDINGS (or only
   already-fixed items). Report per round: findings count, what was verified,
   what changed.
7. **Final round = BLIND (real case 2026-08-09):** for the LAST round the
   user ordered "don't report previous findings to the sub agent" — zero
   prior-round briefing, same 3-way READ-ONLY split. Blind rounds catch
   REGRESSIONS in applied fixes that briefed rounds cannot: the blind round-4
   audit caught a tirith-persistence row applied verbatim from round 3 that
   was semantically INVERTED ("always on tirith = permanent" written when the
   code comment says "pure tirith findings are session-max by design"). A
   re-report of a supposedly-fixed item by an un-briefed agent is a
   regression signal: re-verify against the clone before assuming the fix
   was right.
8. **Live-run gate (real case 2026-08-11): static review cannot see runtime
   shape.** Reviewers — even told to verify against the source — confirm
   routes exist and bodies match, but miss SEMANTICS only executing the real
   artifact reveals: a route that BLOCKS until the turn completes
   (`POST /session/{id}/message` vs the 204 `prompt_async` fork), a response
   shape nested differently than the fakes (`{info:{role,...},parts}` vs
   flat `role`), and races (status-map absence before the turn starts).
   Each round must RUN the real end-to-end artifact against a real server
   (spawned or live) in addition to pytest: unit fakes with idealized
   shapes mask every one of these. In the 2026-08-11 v1-migration audit,
   the 3-agent behavioral round returned zero runtime findings after
   source-verifying every route; a ~15-min live e2e + one-off probes found
   3 real bugs (blocking prompt route, info-nested message shape shaping
   every row "assistant", absent-before-start idle race). Also check
   entrypoints pytest doesn't collect (`scripts/`): a broken e2e smoke can
   ship green.
9. **Fix-introduces-bug convergence (real case 2026-08-12, v1-migration
   rounds 5-7).** A fix that substitutes one dedup signal for another in an
   identity-free event domain (v1 idle events carry NO turn identity) is
   itself a bug candidate: R5's fork-time tail baseline fixed the
   delayed-prior-idle misattribution but broke overlapping forks (fork#2's
   baseline read after turn-1's rows commit swallows turn-1's completion →
   missed notification + permanent leak) and zero-row completions with
   non-empty baselines. Rule: when events carry no identity, do NOT refine
   the same ambiguous signal further — add an ORTHOGONAL observation and
   gate on the combination. Here: busy events prove a turn RAN, so an
   unchanged-fp idle AFTER a busy is a real zero-row completion while the
   same idle without a busy is a duplicate replay (busy_seen gate); the
   wait path re-reads the tail after an event resolution and falls back to
   status-map polling when the fingerprint did not advance past the pre-fork
   baseline. Every fix round must be re-audited by the next round, and
   convergence is PER-AGENT, not global: a residue agent reporting 0 while
   the behavioral agent reports new bugs means the loop continues until ALL
   agents report 0.
10. **Live-probe complement to the e2e gate.** e2e smoke covers spawn /
    health / prompt / tail / commands / SSE but NOT `wait=true` or the
    delegated-fork reap path. For those, write a temp `scripts/_*.py`
    probe: pass the cfg dict DIRECTLY to the Bridge constructor (never
    `load_bridge_config()` — it reads Hermes' own config, not the probe's),
    run against the real server, assert the internal state that proves the
    fix (e.g. `_delegated` entry popped after the idle, `_pending_tails`
    buffered), then DELETE the probe. Test-side mirror: when code under
    test captures a fork-time tail baseline, fakes must advance
    `message_pages` AFTER the fork read (in the finish thread, before the
    idle dispatch) — a pre-advanced page makes the baseline capture the
    completed turn and the verification rejects the real resolution.
    Full walkthrough: `references/v1-migration-convergence-rounds.md`.

## Pitfalls

- **Append-only log files glue lines when the file lacks a trailing newline**: a
  patch whose `new_string` ends without `\n` concatenates onto the last line,
  and the NEXT append then glues onto that. After every log append, verify the
  tail: `tail -c 120 <file> | od -c` (must end in `\n`), or run the lint glue
  check (`\S## \[` patterns). Fix by re-patching with the glued string as
  `old_string`.
- **Write `&` literally in patch `new_string`**: an escaped `\&` landed in a
  file once and rendered as `\&` in markdown — no escaping is needed.
- **Template literals inside Python triple-quoted strings**: When the target is a Python file containing JS template literals (`` `${var}` ``) inside a Python string, the sub-agent's codegen can produce broken escaping. Check for both `\\\\` and `` ` `` escaping.
- **Self-reported success is not evidence**: A sub-agent saying "test passed" ≠ running the suite yourself. Always run it.
- **OpenCode permission requests may be auto-rejected in background mode**: If OpenCode tries to run a verification command, it may be silently denied. The output still looks successful. You must verify independently.
- **File path mismatches**: Sub-agents may write to the wrong path or create unintended files. Check `git diff --stat`.
- **read_file dedup false-positive after a transient "File not found"**: if a
  summary file read races the writer (file not yet visible, or a transient
  error) and the retry then hits "File unchanged since last read", the dedup
  guard will refuse to return content even though the file EXISTS. Bypass by
  calling `read_file` with explicit `offset`/`limit` — paginated reads are
  not deduped. (Real case: summary file confirmed on disk with `ls` at
  6,765 bytes, plain retry refused, paginated read returned full content.)
- **Oversized `execute_code` args time out the stream**: a single large
  script (lint/check logic plus long regex patterns) can exceed the ~8K
  token per-call argument budget and the delivery times out mid-stream with
  no result. Keep inline scripts compact; factor re-runnable checks into the
  skill's `scripts/` dir and run them via terminal instead.
- **Fix-report terminology becomes doc content (real case 2026-08-11).** The
  round-1 report described a fix as "reads MessageV1 info-nesting"; the fixed
  file's docstring inherited the shorthand "the v1 cursor API returns
  MessageV1 {info: ...}" — but no `MessageV1` type exists anywhere in the
  pinned opencode 1.18.x tree, and the file's own line 7 correctly cited
  `MessageV2.page`. The real name was MessageV2 (a legit v1-INSTANCE message
  module; "V2" = message-table generation, NOT the v2 protocol). Lesson:
  when re-verifying a fix, grep the vendored clone for every type/identifier
  the fix's report introduces — a wrong name in the report becomes a wrong
  name in the codebase, and it survives because nobody greps for the name
  itself.
- **Residue-sweep mechanics for converged audit loops.** When the loop is
  down to 0-1 findings per round: (a) exclude `__pycache__`/`*.pyc` from
  sweeps — stale bytecode from pre-fix builds carries old strings
  (`engine=`, deleted function names) and grep hits there are NOT source
  hits; (b) classify EVERY mention into CODE_PATH / STALE_DOC /
  EXPLANATORY / HISTORICAL-LOG buckets and report per-bucket, so an accurate
  reference mention ("v2 is deliberately not used" docstrings, server
  reference docs) is never conflated with residue; (c) do not assume
  "V1"-suffixed names are legit and "V2"-suffixed names are residue — the
  MessageV2/MessageV1 case is the exact inverse; verify names against the
  pinned source, not the vibe. A converged loop legitimately ends with a
  single LOW docstring nit — that IS the valuable result.

## Reference Files

- `scripts/wiki-lint.py` — re-runnable wiki lint (index count vs pages, wikilink resolution, orphan pages, frontmatter keys, log.md trailing-newline/glue check, extra forbidden-pattern checks via `--check`)
- `references/handoff-as-spec-workflow.md` — concrete session case: detailed handoff → opencode run → multi-file implementation → post-build verification
- `references/dashboard-feature-reproduction.md` — concrete session case: template-literal escaping inside Python strings missed by opencode and caught by independent content verification.
- `references/recon-wiki-build-session.md` — concrete session case: 3 parallel recon subagents → disk-file report recovery (subagent-summary-*.txt + /tmp report files) → gitignored project wiki.
- `references/v1-migration-convergence-rounds.md` — audit-loop convergence rounds 5-7 (v1-migration, 2026-08-12): the fix-introduces-bug sequence, the busy_seen orthogonal-observation gate, the wait-path baseline + poll fallback, live-probe recipe, and convergence-round brief anatomy.

## Related

- `opencode` — the specific CLI tool for delegating coding tasks
- `hermes-handoff` — writing structured handoff prompts for sub-agents
