---
name: codebase-audit-loop
description: Loop fresh read-only audit agents until no findings remain.
---

# Codebase audit loop

Drive a self-correcting audit of a codebase using **independent, parallel,
read-only subagents** dispatched in rounds until a round comes back clean. Each
round applies worthwhile findings, re-verifies against the project's test/lint
suite, commits, then re-loops. This catches bugs that a single reviewer (or a
single pass) misses — including ones the code's own design docs claim are
already handled.

## When to use
- After a refactor / extraction / "deeper cleanup" pass you want independently verified.
- As a standing quality gate on a module before declaring it done.
- When the user says "keep auditing until there's nothing left to act on."

## The loop (per round)

1. **Dispatch N parallel read-only subagents** (3 works well). Give each a
   *slice* of the file surface so different lenses see the code (e.g. round 1:
   ask-bridge family / orchestration / client+io; round 2: re-slice the same
   files differently so a fresh set of eyes re-examines them). They must NOT
   share notes — each is independent.
2. **Each subagent returns concrete findings only**: `file:line`, severity
   (HIGH=bug/regression, MED=quality, LOW=cosmetic), minimal fix. If clean, it
   says so explicitly.
3. **You triage**: apply the worthwhile ones; skip false positives (verify
   against the code AND the project's tests — a test often proves a flagged
   "bug" is intended behavior).
4. **Re-verify**: run the project's suite + linter (e.g. `pytest` + `ruff
   check`). Green before committing.
5. **Commit** the round. Then **re-dispatch** a fresh round. Stop only when a
   full round returns nothing actionable.

## How to brief the subagents (CRITICAL — these are user-corrected rules)

- **Vague, not prescriptive — and frame it as "make this codebase better."** Give
  architecture context (one line per module) + an open-ended goal that asks for
  abstraction/structure improvement, e.g. *"help make this codebase better. Reason
  about how the concerns are divided, whether the abstractions are pulling their
  weight, where the structure could be cleaner or more honest, and any behavior
  that looks wrong or fragile. Think about the design as a whole; do not limit
  yourself to a checklist."* The user explicitly asked to **drop specific
  checklists** ("stop making instructions too specific — give vague instructions
  on how we need to make this codebase better, abstractions and all that"). A
  prescriptive list of things to inspect (e.g. "check threading, check failure
  handling, check the dir header") biases and narrows them — and worse, it
  anchors them to your own prior assumptions. Do NOT list subsystems or
  scenarios.
- **No references to prior work.** Do NOT mention previous implementations,
  fixes, or prior audit findings. A reference to "the reconcile is already
  fail-closed" makes the agent assume it and miss a regression. Fresh eyes only.
- **Do NOT instruct them to "be independent" / "start fresh" / "read-only".**
  "Read-only, do not edit" is fine; the *independence lecture* is noise and the
  user explicitly asked to drop it.
- **Re-slice scopes each round** so the same code is seen from a new angle (round
  1: ask-bridge family / orchestration / client+io; round 2: re-slice the same
  files differently). Different lenses catch different things.

A ready-to-copy prompt skeleton lives in `templates/audit_delegation_prompt.md`.

## Pitfalls (learned the hard way)

- **Verify HIGH-severity claims against the ACTUAL upstream source before
  acting.** A subagent flagged a HIGH bug (approval callback captured on the
  wrong thread) that *contradicted the plugin's own design doc* (which claimed
  the worker-thread capture was correct) and an earlier "clean" audit. Trusting
  the doc would have meant dismissing a real, serious, latent bug. The fix:
  dispatch a **dedicated verification subagent** that reads the real dependency
  source (e.g. `tools/terminal_tool.py`, `tools/approval.py` in the host repo)
  and reports file:line evidence. The verification confirmed the claim — the
  callback lived in a `threading.local` populated only on the main thread, so the
  worker captured `None` and every interactive permission ask silently
  **fail-denied**. Caught and fixed only because we verified instead of trusting.
- **A test often disproves a "bug"** — and a green count can hide a dead module.
  When a subagent says X is broken, grep the tests for the contract it claims is
  violated. One round flagged "bare-string `session.status.status` should fan
  out" — a test proved the opposite (malformed status must be dropped as
  "unknown"). Reverted when the test went red. ALSO: a collection error in ANY
  `test_*.py` aborts just that module but pytest still reports the rest as
  "passed", so a "165 passed" line can hide a module that silently didn't run.
  Grep the full output for `ERROR collecting` / `errors during collection` and
  confirm specific modules actually execute (see `python-audit-baseline`). Never
  trust a bare green number.
- **Re-dispatching fresh rounds surfaces regressions your own changes
  introduced.** Don't assume a prior round's "clean" still holds after you edit.
  This loop caught a regression where one round's refactor broke a test module's
  import; the "165 passed" stayed green for ~two rounds because the broken module
  was silently dropped from collection. Only a fresh audit subagent noticed the
  dead import.
- **Don't rush structural MEDs.** Blocking-I/O-on-reader-thread, shared-resource
  double-stop, and `_delegated` reaping are real but high-blast-radius; fold
  them into a dedicated pass where you can verify carefully, not a drive-by.
- **`ruff --fix` can silently prune a backward-compat re-export** you added to
  satisfy an importer, re-breaking the suite. After any auto-fix on a module with
  an alias, re-run the suite (see `python-audit-baseline`).

## User workflow preference (embedded)
- **Show the delegation prompt(s) and get explicit approval before dispatching
  a non-trivial multi-agent run.** The user asked to see the template and
  approve it first. Do this for any audit loop or sizable delegation.
- Keep briefs vague (above); the user repeatedly asked to stop making the
  instructions specific / checklist-like.

## Verification gate
Always finish a round with the project's real test + lint command. For this
plugin that was `cd <repo> && source .venv/bin/activate && ruff check
hermes_opencode tests && python -m pytest -q`. Substitute the repo's own suite.
A round is only "clean" when the suite is green AND no actionable findings
remain — not when you've run out of ideas.
