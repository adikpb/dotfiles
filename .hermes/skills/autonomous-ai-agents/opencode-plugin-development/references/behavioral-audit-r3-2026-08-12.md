# Behavioral ROUND-3 audit (2026-08-12) — 7/7 fix groups VERIFIED-FIXED, 5 NEW findings

Round 3 of the audit loop after Round-2R. State: 157 tests green (`uv run pytest -q`),
ruff clean, targeted `tests/test_bridge.py test_events.py test_read.py test_tools.py` = 78 passed.
All 8 round-2R residual findings landed as the 7 briefed fix groups.

## Fix-group verification (all VERIFIED-FIXED)

1. `EventRouter.forget(session_id)` pops `_last_status` + `_waiters` under lock
   (events.py:110-120); `Bridge._wait_idle` calls it before `wait_for_complete`
   (bridge.py:486). Pinned: `test_forget_clears_stale_idle_record` (test_events.py:163).
2. `_wait_idle(client, session_id, timeout, directory=None)` (bridge.py:469-512):
   router + same-directory → event path (forget + wait_for_complete + ONE final
   status-map re-read); else `_poll_status_idle` with saw_busy semantics.
   `client.session_status(directory=None)` (client.py:202-217; directory as query
   param only when non-None). Both test fakes accept the kwarg. Pinned:
   `test_wait_idle_cross_directory_polls_status_map` (test_bridge.py:269).
3. `_on_idle` buffers tails ONLY for `_delegated` sessions (bridge.py:181-185);
   `_on_turn_complete` pops the registration after successful delivery
   (bridge.py:228); `stop()` clears `_delegated`/`_injected_questions`/`_pending_tails`
   (152-157); `start()` resets `_down_reason` (99). Pinned: foreign-ignore
   (test_bridge.py:171), re-register-reinject (test_bridge.py:230).
4. Non-dict status guarded in `_dispatch` (events.py:189: `isinstance(status, dict)`).
   GAP: no unit test pins the guard (probe-verified only).
5. read.py: non-list `parts` guarded (64-65); default limit 40→8 (143-144);
   created fallback chain info.time.created → flat msg["time"] → flat msg["created"]
   (56-61). Pinned: `test_tail_default_limit`.
6. tools.py: `_INT` deleted; `_as_bool()` (35-39) fixes the `bool("false")` trap;
   timeout schema wording says "defaults to the bridge prompt_timeout config, 600
   unless set" (81-87); handler default follows config (220).
7. `text_msg` fakes are real MessageV1 `{info:{id,role,modelID,sessionID,time:{created}},parts}`
   in test_bridge.py/test_tools.py/test_read.py; flat fallback kept + tested.
   Config test for new keys (test_config.py:52-56).

## NEW findings

### N1 — bug — `_poll_status_idle` 0.5s granularity → false timed_out on fast turns (bridge.py:505-512)
The initial `saw_busy` read runs right after the prompt_async 204, BEFORE the documented
~1s busy-entry lag, so it cannot seed saw_busy for a fresh fork. A turn whose busy window
(entry appears when execution starts, deleted on idle) is shorter than ~0.5s can sit entirely
between two polls: saw_busy stays False → loop runs to deadline → returns True (timed_out)
for a COMPLETED turn. This is the ONLY path for cross-directory wait=true turns.
Analytic poll-schedule simulation (entry at ~1.0s post-fork, 0.5s polls, phase jitter):
busy window 0.2s → 3/5 alignments false-timeout; 0.4s → 1/5; ≥0.6s → 0/5.
Fix: `time.sleep(0.1)` (POLL_STOP granularity); keep saw_busy semantics (queued overlapping
turns legitimately delay the busy entry, so absence-grace alone would misreport those).

### N2 — bug — pop-on-delivery drops a second overlapping turn's completion (bridge.py:224-228 × 181-185)
Two wait=false prompts on the SAME session before the first completes: prompt 2 overwrites
`_delegated[s]` (448-449). Turn 1 idle → buffer + inject + POP. Turn 2 idle → not in
`_delegated` → no inject, no buffered tail. Completion notification silently lost (tail
tool's live-read fallback still works). Empirically confirmed: injections 1 == 1.
Fix: per-session in-flight COUNTERS (increment on register, decrement on delivery, pop at zero).

### N3 — cleanup — `_on_idle` reads the tail BEFORE the delegated guard (bridge.py:176 vs 181)
Every foreign-session idle triggers a full discarded `read_session` server round-trip
(probe: 1 discarded read per foreign idle), plus read-error log noise for foreign sessions.
Fix: hoist the membership check above the read.

### N4 — nit — non-dict `properties` unguarded in `_dispatch` (events.py:177)
`props = event.get("properties") or {}` — a truthy non-dict properties raises
AttributeError at `props.get(...)` → escapes into `_run`'s blanket except → full SSE
re-subscribe for one malformed frame. Same family as the fixed status guard.
Fix: `props = props if isinstance(props, dict) else {}`.

### N5 — nit — tail tool limit ignored when a buffer exists (tools.py:112 × 241-253)
Schema promises "Max messages (default tail_size, cap 100)" but buffered rows are returned
unmodified; limit applies only to the live-read fallback. Fix: slice the buffer or reword.

## Probe-method lesson (reusable)

For timing-granularity claims, prefer an ANALYTIC poll-schedule simulation over wall-clock
trials: simulate the exact poll times (t=0, +0.5, ...) vs the busy window [entry_delay,
entry_delay+window) across phase jitters and count false outcomes. The first probe attempt
(200 real trials × 0.5s sleeps × 5s deadline) TIMED OUT at 240s; the deterministic schedule
analysis + 4 short live trials (timeout=2) settled the question in seconds. Also: staticmethod
probes need `Bridge._poll_status_idle` (class attr), not a module-level import.

Full report with the 12-finding table: the round-3 session report (12 findings: 7 VERIFIED-FIXED,
5 NEW — 2 bug / 1 cleanup / 2 nit).
