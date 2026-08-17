# Audit-Loop Convergence: Blind Final Round + Stalled-Batch Recovery

Session 2026-08-09, hermes-opencode-plugin wiki audit (rounds 1-4).
Extends the "Repeated Recon-Verify-Fix Loops" section of SKILL.md.

## Blind final round (user-mandated, catches verified-in errors)

The user's convergence instruction for the last round was: **"one last
round, dont report previous findings to the sub agent."** Rounds 1-3 had
been briefed with per-round lists of already-fixed items; round 4 was sent
fully blind (fresh audit, no fix list, "NO NEW FINDINGS is a valid terminal
answer").

Why it matters — the tirith inversion:
- Round 3's Hermes-side agent reported allowlist persistence as "`always`
  on a tirith warning persists permanently". That reading is INVERTED:
  `tools/approval.py:3893-3896` does `if choice == "session" or (choice ==
  "always" and is_tirith): approve_session(...)` — so tirith + `always` is
  **session-only** ("pure-tirith findings are session-max by design"); the
  non-tirith `elif choice == "always"` branch is the one that persists
  permanently (:3897-3900).
- The parent "verified" the claim by running `sed` on those exact lines and
  still wrote the inverted version into the wiki — confirmation bias: the
  code was read through the subagent's lens instead of re-deriving the
  branch table.
- Briefed rounds could not catch it: agents told "prior corrections were
  applied, don't re-report unless WRONG" were pointed away from the very
  row that was wrong.
- The blind round 4 agent (independent read) flagged the inversion; a
  direct re-read of the code confirmed it and the wiki row was fixed.

Rule: briefed rounds accelerate convergence on NEW gaps, but the FINAL
round must be blind so claims a previous round "verified" get re-examined.
A blind round returning only already-fixed items is a strong convergence
signal; a blind round catching a fixed row is a regression that would
otherwise ship.

## Stalled batch recovery (#60203 wedge)

A 3-agent batch "stalled: the detached subagent stopped making progress,
did not respond to interruption, and never produced a completion event"
(known failure mode of long-lived gateway processes, #60203). The framework
never wrote `subagent-summary-*.txt` for that batch.

Salvage procedure (worked 2026-08-09):
1. `ls ~/.hermes/cache/delegation/` — confirm no summary files for the
   batch timestamp; `ls live/deleg_<id>/` for the task logs + manifest.
2. `wc -l` + read the TAIL of each `task-<n>.log`. An agent that finished
   its work leaves a line like:
   `22:27:50 final | status=completed duration=715.54s summary: <first ~200 chars>`.
   The in-log `summary:` is truncated at write time — a visible finding
   fragment may be ALL you recover; verify any such fragment against ground
   truth and apply it before re-dispatching (this recovered one real wiki
   bug: the tirith inversion).
3. Distinguish completed tasks (log ends with a `final` line) from cut-off
   ones (log ends mid-tool-call). Re-dispatch the WHOLE batch either way —
   truncated fragments are not the full report — but treat the fragments as
   real findings, not lost work, and re-dispatch identical briefs.
4. The wedge is a delivery failure, not agent failure: all three agents may
   have completed their audits; only the summary delivery died.

## Verification rubber-stamp pitfall

"Confirmed the cited lines exist" is not verification of a semantic claim.
For if/elif persistence/allowlist/approval semantics: translate the code
into your own branch table (`if X → session-only; elif Y → permanent`)
BEFORE comparing to the subagent's claim. The tirith row was verified
against the right lines and still written inverted.