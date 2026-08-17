---
name: codebase-audit
description: "Audit codebases: recon, loop, docs, residual APIs."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [audit, recon, code-review, documentation, pytest, residual-api]
    related_skills: [requesting-code-review, simplify-code, sub-agent-verification]
---

# Codebase Audit

Class-level workflow for read-only and looping audits of a codebase: establish a runnable baseline, scan structural smells, verify docs against source, hunt residual old-version API surface, then loop independent reviewers until a round is clean. Do not edit during recon. Do not trust a subagent's "clean" claim.

Absorbed from: `python-audit-baseline`, `code-review-recon`, `codebase-audit-loop`, `documentation-audit`, `residual-version-surface-audit`. Session checklists and residue sweeps live under `references/`.

## When to Use

- "Find REFACTORS", structural smells, smell audit, read-only recon
- "Keep auditing until nothing is left", post-refactor independent verification
- "Audit these docs/wiki pages against the clone", dual-cite findings
- "Confirm 100% v1-only / zero residual v2 surface" after a migration
- Before claiming a Python package is clean — suite must actually collect

Don't use for: pre-commit security scan + auto-fix (`requesting-code-review`); implementing the cleanup (`simplify-code`).

## Procedure (always in this order)

1. **Baseline (Python)** — lint + full suite must collect green. See [Python test baseline](#python-test-baseline).
2. **Pick the lens** — recon / docs-vs-source / residual-version / or the loop. One mandate per pass.
3. **Inventory** — list target files, read them. Do not sample only the big files.
4. **Verify before reporting** — parser/grep/tests, not eyeball. A false-positive structural claim wastes the next pass.
5. **Report** — `file:line — smell/claim — evidence — minimal fix`, grouped HIGH / MED / LOW.
6. **If looping** — apply worthwhile findings, re-run the suite, commit, re-dispatch a *fresh* independent round. Stop only when a full round is clean.

## Python test baseline

`ruff check` is not a test run. A stale import in any `test_*.py` aborts collection and silently drops that module's coverage. A recon that says "clean" while a test module cannot import is itself the headline finding.

1. `ruff check <pkg>` (fast signal).
2. Full suite: prefer the project runner; else `uv run pytest -q` / `python -m pytest -q`. Read the LAST line: `N passed` vs `errors during collection` vs `interrupted`.
3. Collection break → isolate with `pytest tests/test_x.py`. Grep the missing symbol in `tests/` AND the package. Treat as HIGH. Prefer re-exporting a moved symbol to match the repo's own alias precedent over rewriting tests.
4. Only after green, proceed to smell scanning.

Full write-up: `references/python-audit-baseline.md`.

## Structural recon (read-only)

Mandate is diagnose + rank, not fix. Output a prioritized report.

1. Inventory focus modules (`wc -l`, then read every `.py` in the focus dir — small files hold the shared base classes).
2. Capture architecture constraints FIRST. A smell is only a smell if it violates a stated constraint, not if it *is* the constraint (an intentionally large cohesive orchestrator is not a finding).
3. Scan the categories in `references/smell-checklist.md`.
4. Verify apparent structural bugs with the parser before reporting.
5. Prioritize HIGH / MED / LOW with a *minimal* restructure (name the helper to extract, the method to move, the guard to add).

Report format:

```
HIGH
1. path:line — <smell> — <minimal restructure>
MED
...
LOW
...
```

Full write-up + behavior checklist: `references/code-review-recon.md`, `references/behavior-audit-checklist.md`.

## Documentation / contract audit

Verify wiki, API contracts, and bridge specs against a vendored source clone. Recency of an edit is not accuracy. Every finding needs dual citations (code `path:line` + doc line).

1. Inventory + read everything. Extract load-bearing claims: signatures, line cites, constants/enums, config keys+defaults, DB schemas, *semantic* claims (fail-open vs fail-closed, who fires what).
2. Batch-verify symbol locations (one grep per page). The whole audit usually fits in 4–6 tool turns.
3. Verify signatures, not just presence. Hunt INVERTED branches (doc swapped if/elif).
4. Verify "X via Y" delegation by searching production call sites (exclude `tests/`). Two entry points are often *parallel*, not wrapping.
5. Distinguish def-line cites from call-site cites, and handler-def lines from registry-registration lines.

Full procedure + pitfalls: `references/documentation-audit.md`. Session residue sweeps (hermes-opencode plugin wiki, v1.18.13 source map) stay in `references/` as dated banks — do not treat them as current truth without re-grepping.

## Residual old-version API surface

After a version migration, treat the audit as SCOPED checkpoints. Re-grep source; do not trust the prior round's "fixed" claim.

1. Model/shape normalization — constructor emits the new shape only when all required keys are present.
2. Routes in code/tests/scripts — old prefix (e.g. `/api/`) gone from clients. Docs MAY still list old routes as server reference if scope excluded them.
3. Envelope / event types / wrappers — distinguish SSE `data:` frame prefix (allowed) from a v2 `{data: ...}` JSON envelope (not).
4. Docs/wiki version annotations — un-annotated "live version X.Y.Z" is a finding.
5. Green gate — `ruff check .` + `pytest -q`; report pass count verbatim.

Checklist: `references/v1-only-audit-checklist.md`. Full write-up: `references/residual-version-surface-audit.md`.

## Audit loop (until a round is clean)

Independent, parallel, read-only subagents in rounds. Each round: dispatch → triage → apply → re-verify suite → commit → re-dispatch.

1. Dispatch N=3 parallel read-only agents. Slice the file surface so different lenses see the code; re-slice next round. They must NOT share notes.
2. Each returns concrete findings only (`file:line`, HIGH=bug, MED=quality, LOW=cosmetic) or an explicit clean.
3. You triage against the code AND the tests — a test often proves a flagged "bug" is intended.
4. Re-verify (`pytest` + `ruff check`). Green before committing.
5. Stop only when a full round returns nothing actionable.

**Brief them vaguely.** Frame "make this codebase better" plus one-line architecture context. Do not hand a prescriptive checklist — the user-corrected rule is that over-specific briefs make agents hunt the list instead of the design.

Template: `templates/audit_delegation_prompt.md`. Full write-up: `references/codebase-audit-loop.md`.

## Pitfalls

- Collection-green is not behavior-green. Baseline first.
- `read_file` dedup in a fresh subagent can refuse with "File unchanged since last read" even though *this* agent never read it. Re-read with offset or a different tool; do not skip the file.
- Scope the residual-version grep. A `/api/` check scoped to code/tests/scripts does not flag wiki reference tables.
- Session residue markdown under `references/` is a knowledge bank, not a live audit. Re-verify.

## Verification

- Suite last line is `N passed` (no collection errors).
- Every HIGH/MED finding has `file:line` and a checkable restructure or citation pair.
- Loop stop condition: one full independent round with zero actionable findings.
