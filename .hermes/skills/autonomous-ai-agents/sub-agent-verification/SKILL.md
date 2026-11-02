---
name: sub-agent-verification
description: "Verify sub-agent output yourself before claiming done."
version: 1.1.0
author: Hermes Agent
category: autonomous-ai-agents
tags: [delegation, verification, quality, sub-agents, opencode]
metadata:
  hermes:
    tags: [delegation, verification, quality, sub-agents, opencode]
    related_skills: [opencode, hermes-handoff]
---

# Sub-Agent Output Verification

When you delegate work to a sub-agent (`delegate_task`, `opencode run`, or any external coding agent), **do not trust self-reported success.** Sub-agents can report "file written" or "test passed" while the actual output has syntax errors, missing imports, or broken escaping. Always independently verify before telling the user the work is done.

## Mandatory Verification Layers

### 1. Syntax / Compilation Check

```python
uv run python -c "import ast; ast.parse(open('path/to/file.py').read()); print('Syntax OK')"
```

```bash
node -e "require('fs').readFileSync('path/to/file.js','utf8'); console.log('Syntax OK')"
```

### 2. Module Import / Load Test

```bash
cd /project && uv run python -c "import sys; sys.path.insert(0,'.'); from src.module import app; print('Import OK')"
```

This catches missing transitive imports, circular dependencies, and runtime config errors that syntax checks miss.

### 3. Functional Smoke Test

```bash
terminal(command="uv run uvicorn src.api:app --host 127.0.0.1 --port 8081", background=true)
sleep 2
curl -s http://127.0.0.1:8081/api/endpoint
process(action="kill", session_id="<id>")
```

For non-server code (including native apps): run the test suite, or launch the binary with a ~3s aliveness probe then kill.

### 4. Smoke Test New Modules

After a multi-file build, write a standalone smoke script that imports new classes and exercises key paths in the project venv. Catches import-order issues, circular imports, schema FK errors, type annotation mismatches, runtime path resolution.

### 5. Project Test Script Check

Verify the project's canonical test command works (`npm run test`, `swift test`, `uv run python -m pytest tests/ -v`). If `package.json` has a placeholder test script, fix it first — opencode won't fix it on its own.

### 6. Git State Review

```bash
git diff --stat          # See file-level scope
git status --short       # Check for unexpected files
```

Compare against expected file list from the spec.

### 7. Content Verification

Grep output for expected markers. All expected markers must appear. Missing markers = edit didn't land.

## Test-Summary Parsing Gotchas

- **`swift test` prints TWO summary lines**: the legacy XCTest line ("Executed N tests, with 0 failures") AND a swift-testing line ("✔ Test run with 0 tests in 0 suites passed"). Grepping `tail -3` can surface the always-empty swift-testing line and make a green suite LOOK like zero tests ran. Grep `Executed .* tests, with`, take the last match, and confirm N matches expectation. Same class of trap as any runner that prints per-suite plus total lines.
- **A subagent pasting a passing summary is still a self-report** — rerun and count yourself.

## Orchestrating Sequential Subagents on the SAME Files

Real case (2026-08-22, Repo Pulse): a pagination task was mid-flight on
ContentView.swift/Checker.swift when a follow-up "refactor to shared pagination"
was dispatched against the intended final state. Both would edit the same files
and clobber each other. Protocol:

1. Before dispatching any task, check for live children that touch overlapping files (`delegate_task(action='list')`).
2. If a follow-up depends on an in-flight task's output, do NOT dispatch it early. STOP the premature one immediately (`action='stop'` — safe at iteration boundaries; partial result still returns).
3. Verify the first task yourself (tests + build + git log), THEN re-dispatch the follow-up describing the verified state in its context brief.
4. When a completed task modified files you previously read, re-read them before your own edits or the next brief.

## Briefing UI-Building Subagents (SwiftUI bug class, real case)

Flag these up front in UI-task briefs:

- `NavigationLink(value:)` inside `List(selection:)` without a matching `.navigationDestination` never sets the selection binding — drive List selection directly from the binding instead.
- A detail view gated `if let selected, let result` shows the wrong empty state while results load async. Render detail for a selected item even when its async data is nil; show a loading state.
- macOS version gates: `ContentUnavailableView` is macOS 14+; check API availability against the deployment target stated in the brief.
- Headless verification limits: builds + binary-launch-aliveness are verifiable without a display; interactive GUI behavior is not. Have the subagent state plainly what was and wasn't verified.

## When to Fix vs Re-Delegated

| Situation | Action |
|-----------|--------|
| Syntax error in sub-agent's code | Fix yourself — simple mechanical fix |
| Wrong approach entirely | Re-delegate with clearer spec |
| Small adjustment (styling, naming) | Fix yourself — faster |

## Recovering Truncated Batch Delegation Reports

Batch results may truncate/collapse each subagent's report. The complete text
is always on disk:

- `~/.hermes/cache/delegation/subagent-summary-<n>-<timestamp>.txt` — complete per-task summaries.
- `~/.hermes/cache/delegation/live/deleg_<id>/task-<n>.log` — full live transcript.
- Subagents commonly write standalone report files to `/private/tmp/*.md` or `*.json`.

Recovery recipe (verified 2026-08-09):

```python
import json, re
raw = open("<summary-file>").read()
m = re.search(r"```json\n(\{.*?\})\n```", raw, re.S) or re.search(r"(\{.*\})", raw, re.S)
report = json.loads(m.group(1))["report"]
```

Stall case (#60203): summary files may never get written even when tasks report
completed — grep each live log tail for `final | status=` fragments, verify
visible findings against ground truth, and re-dispatch the same tasks blind.

Reusable extractor: `scripts/extract_delegation_report.py <summary.txt> <out.md>`.

## Requesting File-Backed Reports

For big recon/analysis tasks, tell the subagent up front to **write the full
report to a known path** (e.g. `/tmp/<task>_report.md`) and return only a short
pointer. Sidesteps every truncation path.

## Writing Specs for Delegation

For `opencode run`, write a markdown spec with numbered requirements and attach both spec + target files. Include constraints explicitly: "Do not refactor unrelated code."

For `delegate_task` sequential builds: give each task a self-contained context block listing exact existing APIs/files to reuse, the plan-file section it covers ("do ONLY Task N"), required verification commands, and the commit message format.

## Repeated Recon-Verify-Fix Loops (audit until convergence)

Fixed-point loop pattern for keeping specs/wikis honest against a codebase:

1. Dispatch READ-ONLY leaf subagents split by vantage; offer "'NO NEW FINDINGS' is a valid result."
2. Re-verify every load-bearing finding against ground truth before acting; also check identifiers the fix INTRODUCED.
3. Whole-round failure → re-dispatch same tasks; never fabricate a round.
4. Convergence is PER-AGENT, not global. Final round = blind (no prior-round briefing) to catch regressions in applied fixes.
5. Static review cannot see runtime shape — run the real artifact end-to-end plus targeted probes each round.
6. Fix-introduces-bug rule: when events carry no identity, don't refine the same ambiguous signal further — add an ORTHOGONAL observation and gate on the combination.
7. URL/site-state claims are a HARD gate: curl-verify existence/status yourself; subagents invent pages to justify their runs.
8. Residue sweeps: exclude `__pycache__`; classify mentions CODE_PATH / STALE_DOC / EXPLANATORY / HISTORICAL-LOG.

Full walkthroughs: `references/v1-migration-convergence-rounds.md`,
`references/audit-loop-convergence.md`.

## Delegation Briefing Style (user-mandated, hard rule)

When the user delegates refactor/simplification/cleanup sweeps, **do NOT prescribe the edits.** Give the subagent only:

1. Goal (what class of improvement: refactor for clarity, simplify dead code, etc.).
2. Scope (which dirs/files it owns — or "the whole repo").
3. Hard verification gates (the real build/test commands that must pass).

Never include line numbers, exact function names to delete, or step-by-step "do X then Y" instructions. The subagent must **recon the code itself and decide what to change** — that is the point. Over-specifying wastes the delegation and the user explicitly rejects it ("they are supposed to recon and solve on their own", "stop being overly specific").

Exception: when you have ALREADY done the recon and want a mechanical application of a known change, a precise brief is fine. But for "audit and improve" sweeps, stay vague.

## Convergence Loop: Single Recon → Parallel Split

For open-ended "make the code better" campaigns, use this fixed-point pattern:

1. **Single autonomous subagent first.** Vague brief, full-codework recon, let it converge when it reports nothing else worth touching. One agent avoids parallel clobbering and establishes ground truth on the current state.
2. **Then fan out the SAME task across parallel subagents on DIVIDED slices** of the codebase (e.g. library / views / tests+scripts). Each owns a non-overlapping slice and converges independently. Both verification gates run per-lane.
3. **Run phases in order.** If there are two distinct campaigns (e.g. refactor, then simplification), finish the single→split cycle for the first before starting the second. Don't interleave.
4. **Don't narrate prior loops inside a loop's brief.** Each subagent brief states only its own goal/scope/gates. Saying "the previous loop removed X so now you do Y" over-constrains and leaks stale assumptions — the recon agent re-derives current state itself.
5. **Verify the merged result yourself** (full `swift test` + app build, or the project's canonical gates) after the batch returns. Parallel lanes can still collide on shared files or introduce compile errors the per-lane build didn't catch (a lane only builds what it touches).

This pattern directly replaced an earlier approach of dispatching precise step-by-step briefs, which the user rejected as over-managing the agents.

## Pitfalls

- **Sequence subagents that touch the same files** — see the orchestration section above; stop-and-redo beats parallel clobbering.
- **Over-specified briefs kill the value of delegation**: the user wants subagents to recon and decide, not execute a script. Give goal + scope + verification gates only.
- **Append-only log files glue lines when the file lacks a trailing newline**: a patch whose `new_string` ends without `\n` concatenates onto the last line. Verify tails end in `\n`; fix by re-patching with the glued string as `old_string`.
- **Write `&` literally in patch `new_string`**: an escaped `\&` lands literally in the file.
- **Template literals inside Python triple-quoted strings**: JS `` `${var}` `` inside Python strings gets broken escaping from codegen. Check for both `\\\\` and backtick escaping.
- **Self-reported success is not evidence**: always run the suite/build yourself.
- **OpenCode permission requests may be auto-rejected in background mode**: output looks successful anyway. Verify independently.
- **File path mismatches**: check `git diff --stat` against expected scope.
- **read_file dedup false-positive after a transient miss**: bypass with explicit `offset`/`limit`.
- **Oversized `execute_code` args time out the stream**: factor checks into scripts/ and run via terminal.
- **Fix-report terminology becomes doc content**: grep the codebase for every identifier a fix report introduces before calling it done.
- **Residue sweeps**: exclude `__pycache__`/`*.pyc`; verify suffixed names against pinned source, not vibes.

## Reference Files

- `scripts/wiki-lint.py` — re-runnable wiki lint (index count vs pages, wikilink resolution, orphan pages, frontmatter keys, log.md glue check)
- `scripts/extract_delegation_report.py` — recover full reports from delegation summary files
- `references/handoff-as-spec-workflow.md` — handoff → opencode run → multi-file implementation → post-build verification
- `references/dashboard-feature-reproduction.md` — template-literal escaping missed by opencode, caught by independent verification
- `references/recon-wiki-build-session.md` — 3 parallel recon subagents → disk-file report recovery
- `references/v1-migration-convergence-rounds.md` — audit-loop convergence rounds 5-7 walkthrough
- `references/audit-loop-convergence.md` — convergence loop reference

## Related

- `opencode` — the specific CLI tool for delegating coding tasks
