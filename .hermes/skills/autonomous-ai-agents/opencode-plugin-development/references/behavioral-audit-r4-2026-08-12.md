# Behavioral ROUND-4 verification — 2026-08-12 (convergence round)

Subagent dispatch: verify the 6 briefed Round-3 fix groups, then hunt NEW behavioral bugs in the bridge/events/read/tools surface. READ-ONLY audit (no repo edits); report to /tmp/v2_audit_r4_2_behavior.md; machine-validated JSON-only final response.

Test run: `uv run pytest tests/test_bridge.py tests/test_events.py tests/test_read.py tests/test_tools.py -q` → **82 passed, 1 subtest passed (26.09s)**. Round-3 fixes live in the uncommitted working tree — diff `git diff HEAD -- hermes_opencode/*.py` to see exactly what changed before verifying.

## Briefed Round-3 fix groups — all 6 VERIFIED-FIXED

| Fix | Evidence |
|---|---|
| 1. `_poll_status_idle` polls at 0.1s (was 0.5s) | `bridge.py:528` `time.sleep(0.1)`; `test_wait_idle_cross_directory_polls_status_map` passes |
| 2. Per-session `in_flight` counter | `bridge.py:459-463` (increment + `last_fp` reset on wait=false) + `:226-239` (decrement, pop at 0, keep entry + update `last_fp` on overlap); `test_overlapping_wait_false_prompts_both_notify` passes |
| 3. `_on_idle` delegated-membership guard hoisted above the tail read | `bridge.py:174-180`; `test_on_idle_ignores_foreign_sessions` passes |
| 4. `_dispatch` non-dict `properties` guard | `events.py:177-178` `raw_props if isinstance(raw_props, dict) else {}` + status-is-dict at `:190`; `test_dispatch_tolerates_non_dict_properties` passes |
| 5. Tail handler slices buffered rows to requested limit (B5) | `tools.py:266` on both buffered and live paths — code verified, **not test-pinned** |
| 6. `stop()` clears `_delegated`/`_injected_questions`/`_pending_tails` | `bridge.py:152-157` under the lock — code verified, **not test-pinned** |

## NEW findings (all reproduced by simulation, not just code reading)

### BUG-1 (medium) — stale-idle-after-forget race: `wait_for_complete` resolves on the PREVIOUS turn's idle
- **Where:** `events.py:124-146` (`wait_for_complete`) + `bridge.py:499-506` (`_wait_idle` calls `forget()` then waits).
- **Reproduction (real classes, in-memory fakes):** `router.forget("s1")` → dispatch a stale `session.status idle` frame → `wait_for_complete("s1", 5)` returned **True in 0.000s**.
- **Why it fires in practice:** `forget()` clears only *already-recorded* state. On a reused session, `prompt_async`'s 204 returns BEFORE the previous turn's idle frame is dispatched (the fork is async, ~1s busy lag), so a wait=true prompt submitted while the session is busy (or whose prior idle is in-flight in the SSE stream) resolves instantly on the PRIOR turn's idle — the new turn may not have started. Returned tail = previous turn's rows.
- **Fix:** require a `busy` observation AFTER `forget()` before accepting `idle` as completion (per-session `_needs_busy` flag cleared on the first busy post-forget), or capture a pre-turn tail fingerprint and reject any resolve whose tail did not advance past it.
- **Generalizes to:** any "reset-then-wait" pattern in event-driven code — a cleanup call protects only against already-recorded state; in-flight events dispatched after the cleanup still satisfy the wait.

### BUG-2 (low–medium) — content-fingerprint dedup defeated by tail advancement between duplicate idle deliveries
- **Where:** `bridge.py:220-239` (`_on_turn_complete` fp guard).
- **Reproduction (real Bridge + FakeCtx):** two overlapping wait=false prompts on one session (in_flight=2). Turn 1's idle delivers (fp = turn-1 rows, in_flight→1, `last_fp` set). Turn 2's USER row is then persisted while turn 2 still runs. A duplicate/reconnect-resend of turn-1's idle arrives → fp now differs (`...\nuser:second`) → **re-injects a false "turn complete" mid-turn-2** AND decrements in_flight→0 → **pops the entry** → turn 2's real idle finds `_delegated` empty → **turn 2's completion never notifies** (2 injections total, the 2nd spurious). The code's own docstring claim "reconnect re-sends never re-inject" is FALSE under tail advancement.
- **Fix:** dedup on the idle event's turn identity (`properties.messageID` when the v1 frame carries it), falling back to fp only for single-turn sessions; only decrement/pop when `in_flight == 1` at delivery time.
- **Generalizes to:** fingerprint dedup over a whole evolving stream fails when the stream advances between duplicate deliveries; dedup on event/turn identity when available.

### CLEANUP-3 — in_flight bookkeeping gated behind inject success → entries never reaped
- `bridge.py:206-208` returns before the decrement when `inject_turn_complete=False`; `:224` returns before it when `_inject_turn` fails (gateway mode). Reproduced: two completed turns with injection disabled left `{'last_fp': '', 'in_flight': 2}`; entry never popped until `stop()`.
- **Fix:** decouple bookkeeping from delivery — decrement/pop unconditionally; gate only the notification on the inject flag/result.
- **Generalizes to:** counter/registry bookkeeping must not be gated behind the side-effect it tracks, or disabled/unavailable delivery leaks the state.

### CLEANUP-4 — the non-dict-properties guard is asymmetric: consumers still crash-and-drop malformed question frames
- `bridge.py:304-305` (`_on_question`) and `approval.py:169-170` (`enqueue_question`) use `event.get("properties") or {}` without an isinstance dict check → a list `properties` raises AttributeError (swallowed by the router's `_safe`), and the ask is **silently dropped**: never injected/held in tool mode, never rejected in reject mode → the opencode session wedges forever (asks have no server-side timeout).
- Reproduced: `_dispatch({"type":"question.asked","properties":["junk"]})` → 0 held, 0 injected, 0 replies, no error surfaced.
- **Fix:** mirror the `events.py:177-178` isinstance guard in `_on_question`/`enqueue_question` with a warn-level log.
- **Generalizes to:** when a defensive-guard fix lands at the dispatcher, sweep ALL consumers of the same payload shape — the same bug class sits one layer down.

### NITs
- `run_command` (bridge.py:559) silently switched wait=True → wait=False; `OPENCODE_COMMAND_SCHEMA` still describes blocking semantics with no mention of the `running` key.
- Buffered tails never upgrade to a live read when the requested limit > tail_size (caller asking limit=50 on a buffered session gets ≤8 rows). **consume_tail by-reference concern: checked OK** — `pop()` removes the only bridge reference and the handler slices a fresh list (`entries[:limit]`), so no mutation path into bridge state exists.
- Round-3 fixes 5 and 6 are un-pinned: no test asserts the buffered-tail limit slice, none asserts `stop()` empties the three dicts.

## Checked-OK items (briefed focus areas that did NOT pan out)

- **`_poll_status_idle` seed timing:** the saw_busy seed read runs immediately after `prompt()` returns (post-204); the 0.1s loop catches the ~1s-lagged busy entry when it lands. Correct as designed; the only residual (busy window <0.1s landing entirely between two polls on the poll-fallback path) is theoretical — the event path is primary and unaffected.
- **wait=false with an existing session_id:** the in_flight increment sits after the create-skip block (`bridge.py:454-463`), so it applies identically to new and reused sessions — correct, and `test_turn_complete_reinjects_when_turn_advanced` pins the reuse path.

## Method lesson for this round: SIMULATE, don't just read

Concurrency/state-machine claims (counters, dedup guards, cleanup-before-wait) are weakly settled by code reading — both bugs below were "maybe" from reading and *proven* by simulation. Recipe that worked, zero repo edits:

```python
import sys; sys.path.insert(0, repo_root)
from hermes_opencode.bridge import Bridge
from hermes_opencode.events import EventRouter
# scripted in-memory fakes: FakeClient (create_session/prompt/session_status/
# messages/iter_events), FakeCtx (inject_message records) — copy from tests/
# 1) stale-idle race: router.forget(s) -> dispatch idle -> wait_for_complete -> time it
# 2) duplicate-idle re-inject: 2 wait=false prompts, deliver idle 1, advance the
#    fake message page (turn-2 user row), replay idle 1, then idle 2; count ctx.injected
# 3) disabled-inject leak: cfg["inject_turn_complete"]=False, complete turns, dump _delegated
```

Each suspected race became a ~10-line experiment; all three hypotheses confirmed (instant-resolve True in 0.000s; spurious 2nd injection + missed turn-2 delivery; in_flight 1→2). Complements the earlier analytic poll-schedule method (behavioral-audit-r3) — use phase-jitter analysis for *timing* claims, live simulation for *state-machine* claims.

## Report discipline

- Full report: `/tmp/v2_audit_r4_2_behavior.md` (markdown: verification table, findings with reproduction notes, checked-OK items, JSON appendix).
- Final response to the parent must be a SINGLE JSON object matching the briefed schema (`findings[]` with status/severity/file/line/description/fix + `total_findings` counting only NEW/STILL-PRESENT). VERIFIED-FIXED entries may be included in `findings` for traceability — `total_findings` excludes them. No prose before/after the JSON.
