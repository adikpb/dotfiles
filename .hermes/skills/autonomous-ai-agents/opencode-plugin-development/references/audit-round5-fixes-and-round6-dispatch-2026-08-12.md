# Audit ROUND-5 fixes + ROUND-6 dispatch (2026-08-12)

Round 5 (deleg_966d3b57) closed: all findings fixed and verified — **167
passed + 1 subtest** (was 165; +2 net new tests), ruff clean, e2e 6/6 live,
live wait=true + fork probe green. Round 6 (deleg_dbade646) dispatched with
a 7-group verification brief (convergence round).

## The settled dedup design: fork-time tail baseline

The R4→R5 dedup saga (duplicate-idle false re-inject → delayed-idle
misattribution to a new fork → zero-row registration leak) has ONE
resolution, applied in this session:

- **At registration (wait=false fork), set `last_fp` to the fingerprint of
  the tail read that prompt() already performs** (bridge.py:490
  `entry["last_fp"] = _tail_fp(out["entries"])`) — NOT `""`. The pre-fork
  rows were already returned to the caller, so they must not re-notify; a
  DELAYED idle of a PRIOR turn has fp == this baseline and is skipped by
  the existing `fp == last_fp` guard.
- **Empty fingerprints always deliver**: `if fp and fp == last_fp: return`
  (bridge.py:236). A completion whose shaped tail is empty (reasoning-only
  parts, agent-resolution failure before any row) has nothing to compare —
  dedup-skipping it leaks the `_delegated` registration at in_flight
  forever AND permanently defeats the foreign-idle guard hoist.
- The two rules together fix BOTH Round-5 bugs:
  - zero-row completion → delivered + reaped
    (`test_zero_row_completion_delivers_and_reaps`)
  - delayed prior idle → fp == fork baseline → skipped
    (`test_delayed_prior_idle_not_misattributed_to_fork`)
- A separate `fork_fp` key proved REDUNDANT: `last_fp` starts at the
  baseline and only moves forward on deliveries, so the baseline check is
  subsumed by `fp == last_fp`.

## Round-5 fix application details

1. **forget-before-fork**: prompt() wait=true re-arms
   `router.forget(session_id)` BEFORE `client.prompt` (bridge.py:468-473);
   `_wait_idle` no longer forgets. A fresh-turn busy landing right after
   the 204 can no longer be discarded by the re-arm's saw_busy discard
   (which would burn the full event wait).
2. **events.py stop()** clears `_needs_busy`/`_saw_busy`/`_last_status`
   (prune-on-stop; the sets otherwise grow per abandoned session).
3. **Fake recording**: `session_status` records
   `self.status_dirs.append(directory)`; the cross-directory poll test
   asserts every poll forwarded `"/other"`.
4. **Fake protocol fidelity**: `permission_reply` renamed to the AskSurface
   protocol `(rid, reply, message=None, directory=None)` in both fakes.
5. **messageID field**: client.py sends `payload["messageID"] = message_id`
   (was `"id"` — the real v1 prompt_async body field, pattern `^msg`,
   additionalProperties:false); test_client.py asserts
   `messageID == "msg-call-123"` AND `"id" not in payload` (pattern-valid
   value; re-derive asserted body field names from openapi.json/schema,
   never from the client's own payload echo — a fake echoing the client
   locks in the wrong wire contract).

## Test-conversion trap (baseline semantics)

Converting completion tests to fork-baseline semantics: the fake message
page must ADVANCE BEFORE each completion, but the FORK read inside prompt()
must see the PRE-turn page. Setting the advanced page before the prompt
call makes the fork capture the advanced tail as its baseline → the
completion fp equals the baseline → skipped → assertion fails (1 != 2).
Sequence that works: page1 → prompt() → page2 → _on_turn_complete() →
page3 → prompt2() → page4 → _on_turn_complete() …

## Live probe evidence (fork probe)

- wait=true: 9.8s, `timed_out=False`, texts `[Reply with exactly PONG, PONG]`
- wait=false fork: 0.0s, `running=true`
- 3s later: `_delegated == {}` — the fork's turn completed, delivered, and
  the registration was REAPED live (in gateway mode ctx=None → no inject,
  but bookkeeping still popped); `_pending_tails` buffered (tail tool
  fallback intact).

## Round-6 brief (deleg_dbade646)

7 verification groups: fork-time baseline (bridge.py:476-497 / :230-250 +
  `_tail_fp` :56-58 + 2 new tests), forget-before-fork (:468-473), events.py
  stop() prune, fake status_dirs recording + assertion, fake permission_reply
  protocol names, messageID field + test pin, bridge.py:70 comment
  `{"last_fp", "in_flight"}`. NEW-findings focus areas: baseline ×
  overlapping forks (two wait=false forks before ANY completion), zero-row
  completions under overlap, wait=true with forget moved before the fork.
