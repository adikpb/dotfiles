# Round-Loop Residue Sweep — Method Deltas from Round 2 (2026-08-11)

Companion to the hermes-opencode v1-only audit loop. Round 2 of the
residue sweep ran with the round-1 findings ALL fixed; it produced 2 NEW
STALE_DOC findings and three method deltas worth reusing in any
round-loop docs-vs-code audit.

## Delta 1 — a behavior fix's doc fallout extends beyond the files it touched

Round 1 fixed client.prompt() to use `POST /session/{id}/prompt_async`
(was the blocking `POST /session/{id}/message`) and edited the
specifically-NAMED doc files (R7 table, permissions banner, index
one-liner, README). It never swept the docs that *claim* the plugin's
route: round 2 found plugin-requirements.md R1:76 ("V1 (what the plugin
drives): ... then `POST /session/{id}/message`") and R5:242-244
("`prompt` ... via `POST /session` / `POST /session/{id}/message`") still
prescribing the OLD route.

Rule: **after any route/endpoint change, grep the docs for the OLD route
token AND for "what the plugin (drives|uses|implements)" phrasing.** A
"what X does" claim is the highest-drift doc type — it survives even when
the file that used to contain the route is fully rewritten.

## Delta 2 — grep-token false positives are a classification class, not noise

A residue token like `v2` matches version strings (`v2026.8.3`),
commit refs, and vendored-clone pins (`.slim/clonedeps.json:27`). In
round 2 these hits (approval.py:11, serve.py:8, README.md:17, three wiki
entity pages, the clonedeps pin) were the MAJORITY of raw matches.
Classify them explicitly in the ledger ("FALSE POSITIVE — version
string") instead of silently ignoring them: an explicit class proves the
sweep examined them, and prevents a later round re-reporting the same
non-findings. Also: count-only grep output truncates at the limit — when
a file's count is suspicious, re-grep that file with content mode.

## Delta 3 — verify fixed docs on DISK, not via git

The wiki/ directory is git-ignored in this repo: `git status` and
`git log -- wiki/` show NOTHING for it, so round-1 doc fixes never
appear in git state. Audits of git-ignored workspace content must read
the files directly; do not conclude "fix absent" from git. (Corollary:
`git diff` vs HEAD shows only code files — the doc fixes live purely in
working-tree state.)

## Delta 4 — machine-validated contract: recover from a bounce by re-emitting ONLY the JSON

The round-2 subagent response was bounced once with
`Extra data: line 14 column 1 (char 1259)` — prose or a trailing report
after the JSON object. Recovery is a full re-emit of ONLY the JSON
object (a ```json fence is tolerated; anything else is not). The
human-readable report goes to the /tmp file the task named; it is never
part of the final message. If a re-emit must happen, keep the JSON
byte-identical to what validated, minus the extraneous trailing content.
