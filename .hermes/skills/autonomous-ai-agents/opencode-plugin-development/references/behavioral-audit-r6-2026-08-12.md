# Behavioral ROUND-6 verification (2026-08-12, convergence round)

7/7 briefed R5 fix groups VERIFIED-FIXED; 5 NEW (3 bug / 2 nit); zero
STILL-PRESENT. Suite: **167 passed + 1 subtest** (full `uv run pytest -q`),
88 passed + 1 subtest (bridge/events/read/tools targeted) — matches the
briefed count. ruff clean. mtimes static across the run (no moving target).

## Briefed R5 fix groups — verification with file:line (CURRENT tree)

1. Fork-time baseline — `_tail_fp` bridge.py:56-58; wait=false registration
   bridge.py:476-497 reads the tail FIRST (`out = read_session(...)` :480)
   and sets `entry["last_fp"] = _tail_fp(out["entries"])` :490 (was `''`);
   `_on_turn_complete` dedup bridge.py:236 `if fp and fp == entry.get("last_fp","")`
   → empty fp ALWAYS proceeds. Tests test_bridge.py:290-303
   (test_zero_row_completion_delivers_and_reaps), :305-326
   (test_delayed_prior_idle_not_misattributed_to_fork).
2. forget-before-fork — bridge.py:468-473 `router.forget(session_id)` BEFORE
   `client.prompt(...)` :474; `_wait_idle` (bridge.py:507-530) no longer forgets.
3. events.py stop() prunes — events.py:94-108 clears `_needs_busy` :103,
   `_saw_busy` :104, `_last_status` :105.
4. Fake directory recording — test_bridge.py:51/:70, test_tools.py:50/:68
   (`status_dirs.append(directory)`); test_wait_idle_cross_directory_polls_status_map
   test_bridge.py:328-345 asserts all polls == "/other".
5. Fake protocol fidelity — `permission_reply(self, rid, reply, message=None,
   directory=None)` test_bridge.py:94, test_tools.py:89, test_approval.py:39 =
   AskSurface protocol approval.py:51-53 = client.py:324-326.
6. messageID — client.py:269-272 `payload["messageID"] = message_id`
   (comment: pattern ^msg, additionalProperties:false); test_client.py:61-70
   asserts `messageID` == "msg-call-123" :65 and `"id" not in payload` :66.
7. Comment nit — bridge.py:75 `# wait=false sessions: {"last_fp", "in_flight"}`
   (brief cited :70; line drifted — content right).

## NEW findings (reproduced by replaying event sequences against the REAL
Bridge/EventRouter classes with a scripted in-memory fake client; sim script
pattern from R4/R5)

### N1 [bug] Overlapping wait=false forks: fork#2's baseline consumes turn-1's completion
bridge.py:236-246 + :484-491. Two forks before ANY completion, fork#2's
baseline read after turn-1 rows committed: idle#1's tail == fork#2 baseline
→ skipped as "duplicate" → turn-1 completion NEVER delivered, in_flight stuck
≥1 forever (permanent `_delegated` leak; compounds with each further fork).
**Regression vs pre-R5** (last_fp reset `''` delivered both idles).
The pinned test test_overlapping_wait_false_prompts_both_notify
(test_bridge.py:347-361) covers only the LUCKY ordering (fork#2 sees the
pre-fork tail); the common real-world ordering (fork#2 comes seconds later,
turn-1 rows already committed) leaks. Sim A: 2 forks → 1 injection → entry
present after both idles.

### N2 [bug] Zero-row completion with a NON-EMPTY baseline never delivers
bridge.py:236. R5's "empty fp ALWAYS delivers" covers only the empty-tail
case (test_zero_row... pins it). Session with prior history whose turn adds
zero shaped rows (reasoning-only parts): fp == baseline, non-empty → skipped
→ missed + permanent leak. **Regression vs pre-R5** (non-empty fp != reset
`''` delivered). Sim B: baseline `user:prior q\nassistant:prior a`, idle → 0
injections, entry stays.

### N3 [bug] wait=true: stale BUSY dispatched after forget() seeds _saw_busy → early resolve
events.py:131-135 (forget) + :218-219 (busy→saw_busy) + :167-169 (resolve
condition); bridge.py:468-473. forget() discards saw_busy but cannot stop an
in-flight prior-turn busy frame; it re-seeds `_saw_busy`, so the prior turn's
idle satisfies "in needs_busy AND in saw_busy" and resolves wait_for_complete
EARLY: prompt returns `timed_out=False` with the PRIOR turn's tail while the
fresh queued turn is still running; the fresh completion is orphaned.
Busy-side mirror of the R4 stale-idle race. Window is wider than "turn A
started ms ago": the single router thread runs `_on_idle` (a server round
trip) inline, so frames backlog in the socket buffer during slow callbacks.
Sim C2 reproduced.

### N4 [nit] Zero-row overlapping turns: duplicate/replayed idle pops in_flight to 0
bridge.py:241-246. Empty fp → EVERY idle delivers, so a replay of idle#1 pops
in_flight 2→1→0 and turn 2's REAL completion finds the entry gone → never
notifies. R4 duplicate-idle shape resurrected for fingerprint-free sessions.
Inherent: v1 idle events carry no turn identity ({sessionID, status.type}
only) and an empty tail has no fingerprint. Low frequency (replay + zero-row
+ overlap). Sim D.

### N5 [nit] forget() is directory-agnostic → _needs_busy residue
bridge.py:468-473 (no directory check) + events.py:75/:134. A cross-directory
wait=true prompt calls router.forget(sid) for a session the bridge-scoped
router never sees → `_needs_busy` entry persists until stop() (pruned only on
same-directory idle dispatch events.py:228 or stop() :103). Bounded,
self-healing on later same-directory use. Residual of the R5 group-3 "never
pruned" nit, which fixed only same-directory completions + stop().

## Key insight: `_saw_busy` cleared-on-idle-dispatch is the dedup signal
The router clears `_saw_busy` on EVERY idle dispatch (events.py:228-229). So
"busy observed since the last dispatched idle" separates a genuine completion
(fp == baseline but the turn ran → a busy was seen) from a duplicate replay
(fp == baseline, no new busy since the last idle). A `has_busy_since_idle(sid)`
accessor on EventRouter (or a mirrored per-entry flag in the bridge) fixes N1,
N2 and N4 in one move — and keeps test_delayed_prior_idle green because in
that test the delayed idle follows turn A's own idle dispatch, which already
cleared saw_busy. N3 needs a forget-generation stamp instead (a stale busy
must only seed its own generation).

## Method lessons (convergence-round additions)
- **A dedup-key fix must be checked in BOTH baseline directions, including
  the non-empty-baseline unchanged-tail variant.** R5 checked the empty-tail
  zero-row case ('' == '' skip → leak) but the flip side — a non-empty
  baseline with an unchanged tail (session with history, turn adds zero shaped
  rows) — also regressed (fp == baseline non-empty → skip). General rule: for
  a completion whose fingerprint equals the current key, enumerate every
  (empty/non-empty baseline) × (advanced/unchanged tail) cell.
- **A race-pinning test that asserts only the LUCKY interleaving passes while
  the common ordering leaks.** test_overlapping_wait_false_prompts_both_notify
  sets both forks' baseline reads against the SAME pre-fork tail; the real
  server commits turn-1 rows while turn-1 is still busy, so a fork#2 issued
  seconds later reads a tail that already includes them → the leak ordering is
  the realistic one. When a test depends on an interleaving, ask which
  ordering is more likely on the real wire and pin THAT one too.
- Suite-count corroboration held again (167+1 == brief; targeted 88+1).
- The un-fixable cases share an information-theoretic root: v1 idle/busy
  events carry no turn identity, so overlapping-turn accounting is ambiguous
  without a side signal (busy-since-idle, forget-generation, or per-fork
  messageID). Report the ambiguity honestly and propose the signal, not a
  wishful fix.

## Checked-OK (no finding)
- wait=true stale-IDLE-in-flight after forget (sim C1): correctly skipped;
  fresh busy→idle resolves — the R5 ordering fix works for its intended case.
- Empty-baseline zero-row completion: delivers + reaps (R5 pinned).
- `_on_turn_complete` bookkeeping runs before the inject gate (bridge.py:241-250)
  — reaping works with inject_turn_complete=False / gateway mode.
- Cross-directory status-map poll forwards directory on every poll.
