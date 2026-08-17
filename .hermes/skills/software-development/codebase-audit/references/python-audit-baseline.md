---
name: python-audit-baseline
description: "Confirm Python tests collect green before auditing code."
version: 1
author: hermes-agent
license: MIT
metadata:
  hermes:
    tags: [code-review, python, audit, pytest, ruff, baseline, recon]
    related_skills: [code-review-recon, requesting-code-review, test-driven-development]
---
# Python Audit Baseline (runnable preconditions before recon)

Use when about to do a READ-ONLY audit, smell recon, or pre-commit review of a
Python package. Before concluding anything is "clean", establish that the
project's test suite actually **runs** — not just that the linter is happy.
This is the precondition step that `code-review-recon` assumes but does not
perform; it pairs with that skill (scan smells AFTER the baseline is green).

## Why this is its own step
`ruff check` only lints. It will NOT catch an `ImportError` raised while
pytest *collects* a test module. A stale import in any `test_*.py` aborts the
whole run at collection time and silently drops that module's coverage. A recon
that reports "the code is clean" while a test module cannot even import is
wrong — and it is itself the most important finding of the audit.

## Workflow
1. **Lint first (fast signal).** `ruff check <pkg>` — expect clean. If it
   fails, those are findings too, but lint problems are rarely the headline.
2. **Run the FULL suite, read the collection summary.** Prefer the project's
   runner; `uv run pytest -q` works when a `uv.lock` is present, else
   `python -m pytest -q`. Read the LAST line: `N passed`, `N errors during
   collection`, or `interrupted`. Distinguish:
   - `errors during collection` → a module failed to import (HIGH; see below).
   - `N passed` → green; proceed to smell scanning.
   - a single test failing → that is a test/behavior finding, not necessarily a
     collection break.
3. **If collection fails, locate the bad import.** Grep for the missing symbol
   across `tests/` AND the package; it is almost always a name moved to another
   module. Run the suite **per file** (`pytest tests/test_x.py`) to isolate
   which module breaks and keep the rest green while you diagnose.
4. **Treat a collection break as HIGH.** Minimal fix: re-export the moved
   symbol from its new home to match the repo's own backward-compat alias
   precedent (e.g. `from .newmod import _sym` re-exported in the old module),
   rather than rewriting the tests — unless the test import is genuinely wrong.
   A collection break hides the module's coverage, so it outranks most smell
   findings.
5. **Only then scan for smells** (hand off to `code-review-recon`). Findings
   are now against a verified-current, runnable tree.

## Invocation notes
- `ruff format --check` may report reformatting even when `ruff check` is clean
  (format and lint are separate gates). Don't fail an audit on formatting
  diffs unless the repo enforces `ruff format` in CI; just note them as LOW.
- In a throwaway/CI shell, `python` may be missing while `python3`/`uv` exist;
  fall back before concluding "no interpreter". The missing binary is an
  environment issue, not a code finding.

## Pitfalls
- **`ruff` clean ≠ suite green.** The single most common false "clean" in a
  read-only recon. Always run the suite.
- **Collection errors are easy to miss** if you only run the happy-path module.
  Run the whole suite once; the summary line tells you if any module failed to
  import.
- **A green test COUNT can still be hiding a dead module — read the summary line,
  not just the tail.** `pytest -q | tail -3` often prints `N passed` and looks
  healthy even when an earlier line reported `ERROR collecting tests/test_x.py`
  and that module was dropped from the run. A collection error ABORTS that
  module (and its coverage) but pytest still reports the remaining modules as
  passed — so "165 passed" can mean "164 from other modules + 1 module that
  silently didn't run". **Always grep the full output for `ERROR collecting` /
  `errors during collection` before trusting a green number.** Confirm a specific
  module actually ran: `pytest tests/test_x.py -q` should report its tests, not
  a collection ImportError. One real session: moving a symbol to a new module
  broke a test's import; the full suite still printed "165 passed" for ~two
  rounds before a read-only audit subagent noticed the import and flagged it as
  HIGH. The fix (re-export the symbol at the old location) then made
  `test_x.py` report `33 passed`.
- **`ruff --fix` (and import auto-sort) will PRUNE a re-export it thinks is
  unused.** If you add `from .newmod import _sym` to `oldmod.py` purely to
  re-export a moved symbol for backward compat, ruff's import sort sees nothing
  referencing `_sym` inside `oldmod.py` and DELETES the import — silently
  re-breaking every importer (including the test suite). If you must keep a
  re-export, reference it in-module (e.g. `_sym = _sym`) or add
  `# noqa: F401` so the linter leaves it. Re-run the suite after ANY ruff
  auto-fix on a module that contains a backward-compat alias.
- **Don't "fix" the test import reflexively.** A moved symbol should be
  re-exported at the old location for backward compat (other importers,
  `wiki/` docs, and the suite may all reference it). Editing the test to point
  at the new module is fine only when the old module no longer exists.
