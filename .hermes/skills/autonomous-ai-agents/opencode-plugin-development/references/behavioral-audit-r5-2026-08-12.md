# Behavioral ROUND-5 verification (2026-08-12)

Round 5 of the behavioral audit loop (convergence round). Briefed: verify the 4
Round-4 fix groups + hunt NEW bugs in the needs_busy/saw_busy lifecycle, the
decoupled `_on_turn_complete` bookkeeping, the tail upgrade path, and any R4
regression. All R4 fixes were UNCOMMITTED working-tree changes (git status
showed 19 modified files; git log head = cc47714).

## Test run
`uv run pytest tests/test_bridge.py tests/test_events.py tests/test_read.py tests/test_tools.py -q`
→ **86 passed + 1 subtest** (suite grew +4 since R4's 82+1). `uv run ruff check` clean.
Moving-target check: source mtimes static across the run; line numbers re-grepped after every read.

## Briefed fix groups — all VERIFIED-FIXED (exact lines)
1. **needs_busy/saw_busy lifecycle (events.py)**: sets :75-76; forget() re-arms
   `_needs_busy` + discards `_saw_busy` + pops `_last_status`/`_waiters` :125-129;
   fast path only accepts idle when NOT in `_needs_busy` :147-151; final check
   `not needs_busy or saw_busy` :161-163; dispatch busy→saw_busy :212-213, stale
   idle guard :215-220, qualifying idle discards + sets waiter :221-226. Pinned by
   `test_stale_idle_after_forget_does_not_resolve_until_busy` (test_events.py:178-191)
   and `test_prompt_waits_for_idle_event` (test_bridge.py:395-419) which dispatches
   busy at +0.1s then idle at +0.3s — real wire order, prompt already inside the wait.
2. **Decoupled `_on_turn_complete` bookkeeping (bridge.py:225-240)**: fp-guard :229,
   last_fp update :231, in_flight decrement :232, pop at zero :233-236 — ALL before
   the inject_turn_complete gate :237-240 and `_inject_turn` :239. Fork registration
   :461-465 (per-session in_flight counter, last_fp reset). No leftover refs to the
   removed `on_turn_complete` router callback or `_delegated["prompt"]` key.
3. **isinstance guards**: `_on_question` bridge.py:305-306, `enqueue_question`
   approval.py:170-171 (both coerce non-dict properties to {}, not `or {}`).
4. **tools.py + tail + guard hoist**: OPENCODE_COMMAND_SCHEMA non-blocking note
   :170-179; tail upgrade `if not entries or len(entries) < limit:` → live read
   :264-276 (pinned by test_tail_handler_upgrades_short_buffer_to_live_read,
   test_tools.py:144); `_on_idle` foreign guard hoisted above the tail read
   bridge.py:174-183.

## NEW findings (all reproduced via SIMULATION against the real Bridge/EventRouter with scripted in-memory fakes — zero repo edits)

### B1 (bug) — zero-row completion dedup'd as duplicate: missed delivery + permanent `_delegated` leak
- `bridge.py:229` `if fp == entry.get("last_fp", ""): return` interacting with the
  fresh-fork reset `bridge.py:464` (`entry["last_fp"] = ""`).
- Reproduced: delegated wait=false turn completes with an EMPTY shaped tail →
  `fp == ""` → equals `last_fp == ""` → early return. injected=0 (completion NEVER
  notified), in_flight stays 1, entry never pops. Next fork inflates counter to 2,
  decrements to 1 → **leak is permanent**. Consequences: (a) silent missed
  notification; (b) session stays in `_delegated` forever → defeats the R3
  foreign-idle guard hoist (bridge.py:174-180) → every future idle triggers a
  server tail read; (c) unbounded growth.
- Trigger: any completion with no shaped rows — empty session, reasoning-only
  parts (shape_message skips reasoning from content), agent-resolution failure
  before any message row. read.py shapes an empty page to `entries: []` without
  raising (verified).
- Fix: apply the fp dedup only when fp is non-empty (empty tail = nothing to
  compare → always deliver + decrement), or decrement/pop on every delivered idle.

### B2 (bug) — stale idle STILL fires `_on_idle`: spurious turn-complete + premature pop; real completion never notified
- `events.py:227-228` fires `_on_idle` for EVERY idle, including frames the stale
  guard :215-220 classified as stale.
- Reproduced (real Bridge + real EventRouter, scripted dispatch): wait=false turn B
  registered (last_fp="", in_flight=1); `router.forget()` re-armed needs_busy (a
  concurrent wait=true prompt on the same session). The PREVIOUS turn's idle frame
  dispatches → wait path correctly ignores it, but `_on_idle` runs → tail read
  (previous rows, B still running) → `_on_turn_complete` sees fp ≠ "" ≠ last_fp ""
  → spurious "[opencode] turn complete" while B runs, in_flight 1→0, pop. B's real
  idle later → `_delegated` empty → B's completion NEVER notified. Sim: injected=1
  after stale idle, still 1 after B's real idle.
- **This re-opens R4's "unreachable on the wire" claim**: R4's argument covered
  DUPLICATE idle frames (live-only stream, one idle per busy→idle, reconnect
  replays current state). A single DELAYED frame suffices because the fresh-fork
  `last_fp=""` reset discards the delivery baseline — any first idle with any
  non-empty tail passes the dedup.
- Trigger realism: moderate-low (agent re-forks the same session before the
  previous idle dispatches — polling-based observation, gateway mode — plus a
  wait=true call on the same session), but failure is silent and permanent.
- Fix: replace the "" reset with a fork-time tail baseline — snapshot the pre-fork
  fp at registration and require `fp != fork_fp` (tail ADVANCED) before
  delivering/decrementing; combine with B1's empty-tail handling.

### B3 (nit) — fork-then-forget ordering: forget() discards a fresh-turn busy
- `bridge.py:458` forks (`client.prompt`) then `bridge.py:502` calls forget();
  forget() discards `_saw_busy` at `events.py:129`. A fresh busy landing in the
  window is destroyed → fresh idle classified stale → event wait burns its full
  budget (sim: 0.41s of a 0.4s wait for a turn that completed at t=0); the
  status-map re-read at bridge.py:507 masks the RESULT, but the event path is dead.
- Wire realism: window is microseconds (busy lands ~1s after the 204), but the
  ordering is wrong by construction. Fix: call forget() BEFORE client.prompt().

### B4 (nit) — `_needs_busy`/`_saw_busy` never pruned
- Only shrunk on a qualifying idle (events.py:222-223). 5 forgets for never-running
  sessions → 5 ids retained for the router's lifetime; a lone busy sits in
  `_saw_busy` forever. Same never-pruned class as the R2R2 `_delegated`/`_pending_tails`
  finding (fixed elsewhere); the R4 sets were added without a reap story.
- Fix: prune on reconnect or cap with oldest-first eviction; at minimum clear on stop().

### B5 (nit) — fake `session_status` drops the directory kwarg
- test_bridge.py:68 / test_tools.py:66 accept `directory` but don't record/assert
  it; the real client (client.py:202) is directory-scoped and the bridge forwards
  it at bridge.py:507/521-523. A forwarding regression passes the suite
  (test_wait_idle_cross_directory_polls_status_map exercises behavior only).
- R3 surface finding #1 class ("fakes that accept kwargs but record a subset"),
  fixed for prompt/create but not swept to session_status. Fix: record the kwarg
  and assert it in the cross-directory test.

## Method lessons (generalize to future rounds)
1. **Attack a prior round's "unreachable on the wire" claim at its ASSUMPTIONS,
   not its conclusion.** R4 proved duplicate idle frames can't occur; B2 reached
   the same failure shape with ONE delayed frame. Enumerate the claim's
   preconditions (duplicate? replay? per-transition count?) and vary each.
2. **A fix that RESETS a dedup key to "" (fresh-fork last_fp) must be checked in
   BOTH directions**: empty-tail (fp=="" now equal → miss/leak) and unchanged-tail
   (delayed/stale frame now passes → spurious deliver). Dedup keys that conflate
   "no data" with "same data" are the bug class.
3. **Verification of a "bookkeeping decoupled from delivery" fix must test the
   REAP guarantee, not just the delivery**: B1 shows the entry can still leak
   through a legit dedup hit; assert `_delegated` is empty after every
   completion shape (empty rows, identical rows, advanced rows).
4. Simulation remains the fastest proof: import the REAL Bridge/EventRouter, drive
   `_dispatch`/`_on_idle`/`forget` directly with scripted frames, assert on
   `injected`/`_delegated`/`_needs_busy`/`_saw_busy`.

## Round-5 summary table
10 findings: 5 VERIFIED-FIXED (the 4 briefed groups, split 5 ways) + 5 NEW
(2 bug / 3 nit), zero STILL-PRESENT. Full report: /tmp/v2_audit_r5_2_behavior.md.
