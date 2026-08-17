---
name: code-review-recon
description: "Read-only refactor recon: structural smells, prioritized."
version: 1
author: hermes-agent
license: MIT
metadata:
  hermes:
    tags: [code-review, refactor, python, recon, static-analysis, smells]
    related_skills: [simplify-code, requesting-code-review, residual-version-surface-audit, documentation-audit]
---

# Code Review Recon (read-only, diagnostic)

Use when asked to do a READ-ONLY structural review / refactor recon of a
Python codebase: find structural smells, confusing control flow, functions
that are too long / do too much, misleading names, leaky abstractions,
scattered concerns, and error-handling inconsistencies — and report concrete
findings with file:line, the smell, and a minimal restructure. Do NOT edit
anything. This is the diagnostic precursor to `simplify-code` (which does the
cleanup) and distinct from `requesting-code-review` (pre-commit gated review
with security scans + auto-fix).

## When to use
- "Find REFACTORS", "code review (recon)", "structural smells", "smell audit".
- The mandate is diagnose + rank, not fix. Output a prioritized report.

## Workflow
1. **Inventory** the target modules: `wc -l` for size, then read every
   `.py` in the focus dir (not just the big ones — small files hold the
   shared base classes / protocols that explain the structure).
2. **Capture the architecture constraints FIRST.** If the task supplies
   design rules (e.g. "event-driven, FIFO worker serializes replies",
   "no thin delegating wrappers", "router register-based", "X must be
   canonical realpath"), write them down. Findings must respect them —
   a smell is only a smell if it violates or ignores a stated constraint,
   not if it *is* the constraint (e.g. a big orchestrator class that is
   explicitly "intentionally large but cohesive" is not a finding).
3. **Scan systematically** for the smell categories in
   `references/smell-checklist.md`.
4. **VERIFY apparent structural bugs before reporting** (see Pitfalls).
   Read-only recon that ships a false-positive structural claim wastes the
   reader's trust — confirm with the parser, not the eyeball.
5. **Prioritize** each finding HIGH / MED / LOW and give a minimal
   concrete restructure (name the helper to extract, the method to move,
   the guard to add).
6. **Report** grouped by priority: `file:line — smell — minimal fix`.

## Report format
```
HIGH
1. path:line — <smell> — <minimal restructure>
MED
...
LOW
...
```
Lead with outcomes; prefer bullets. State files touched (should be none —
read-only) and any false starts you disproved.

## Recon -> Implement -> Independent Re-Audit loop

When the user asks for simplifications / abstractions / refactors (or "clean
this up", "recon then fix"), run a three-phase loop. The user explicitly
wants this shape: **subagents do READ-ONLY recon; you implement; then a fresh
re-audit runs that does NOT see the recon findings.**

**Phase 1 — Recon (parallel, read-only subagents).** Spawn 3+ leaf subagents
in ONE `delegate_task(tasks=[...])` fan-out, each scoped to one lens
(simplification / abstraction / refactor). Hard rules for each:
- `DO NOT edit anything` — they return findings only.
- Give each the architecture constraints up front (event-driven, no thin
  wrappers, the specific invariants for this codebase) so findings respect
  them.
- Require `file:line — severity — minimal fix` per finding; tell them to
  verify apparent bugs (AST, not eyeball) before reporting.

**Phase 2 — Implement (you, not the subagents).** Synthesize the recon
findings, dedupe cross-agent consensus, and FILTER against the hard invariants
+ "don't break the 163/164 tests / ruff clean". Edit the code yourself,
repoint any tests that referenced moved symbols, then run the suite.

**Phase 3 — Independent re-audit (fresh, NO reference to Phase 1).** Spawn a
SEPARATE subagent with the instruction "Start completely fresh: do NOT assume
any prior review existed. Audit the CURRENT state as if you have never seen it
before." Do NOT pass it the recon findings. This is the whole point: a fresh
auditor catches what the first pass missed. **This session, the recon found
only MED/LOW items; the fresh re-audit independently found a HIGH-severity
race** (a worker thread could run `_on_started` before the subclass finished
`__init__`, silently leaving setup undone) — the recon never noticed it.

**Do NOT skip Phase 3 or feed it the recon output.** Re-running the same lens
on the same context just confirms its own blind spots. The loop converges when
the fresh re-audit comes back clean or only with items you've already decided
are out of scope.

## Pitfalls (read these)
- **Verify structural bugs with AST, not read_file.** Read the file with
  `ast.parse` before claiming a method is misindented / at module level /
  outside its class. `read_file` renders `LINE|CONTENT` and the indentation
  cue is easy to misread — a method shown at column 0 may actually be
  indented inside its class. A one-shot script resolves it:
  ```python
  import ast
  src = open(path).read(); tree = ast.parse(src)
  for n in ast.walk(tree):
      if isinstance(n, ast.ClassDef) and n.name == "Bridge":
          print("Bridge spans", n.lineno, "to", n.end_lineno)
          for it in n.body:
              if isinstance(it, (ast.FunctionDef, ast.AsyncFunctionDef)):
                  print("  method", it.name, "line", it.lineno)
  ```
  (Caught a real false positive this way: methods that *looked* module-level
  were actually class methods; only `_render_template` was correctly
  module-level.)
- **Don't flag size alone.** A 800-line orchestrator can be cohesive by
  design. Flag specific >60-line *functions that mix concerns*, not the
  module's length.
- **Respect stated design rules.** If a rule says "no thin delegating
  wrappers", a `def f(x): return x.g()` wrapper IS a finding. If a rule
  says "questions independent of ApprovalBridge", question logic leaking
  into the orchestrator IS a finding. The constraints are the rubric.
- **Hunt the duplicates the task names.** Recon prompts often hint at known
  trouble spots: repeated `try/except` reply-with-fail-closed blocks that
  could share one helper; injected-path duplication; status-watcher vs
  idle-event overlap; per-call param canonicalization gaps vs a
  canonicalized default. Check those first — they're usually real.
- **Stale/contradictory docstrings are smells too.** A docstring that
  describes the opposite of the code (e.g. "header is suppressed" while the
  code sets the header) is a misleading comment — flag it, especially when
  it touches a critical design point (canonical directory, fail-closed,
  serialization).
- **Cross-reference usages before calling a helper dead.** Grep the whole
  repo (not just `hermes_opencode/`) for a symbol before labeling it
  "unused / redundant"; tests and `wiki/` docs often reference it.
