# Behavioral / concurrency audit checklist (Python, read-only recon)

Companion to `smell-checklist.md`. Structural smells catch shape; these catch
*behavior that is wrong or fragile at runtime* — the class of finding a fresh
re-audit is most likely to surface. Scan this AFTER the structural list. Each
item: what to look for, where it hides, minimal fix.

## 1. Eager init-capture vs lazy re-resolution
Pattern: a value only valid at *use* time is read once in `__init__`/`start()`.
- Hides in: ContextVars (session/request key set per turn), CLI refs set after
  discovery, callbacks installed on a worker thread.
- Tell: the code already fixed one sibling lazily (`_capture_cli_ref()`,
  `get_current_session_key()` resolved at call time). The unfixed siblings are
  the same bug.
- Fix: re-resolve at the call site (mirror the lazy helper). Low-risk; does not
  break tests that pin the value post-construction.

## 2. Shared-resource teardown idempotency
Pattern: one worker/queue/fifo is shared by two owners (e.g. two bridges pass the
same FIFO). Each owner's `stop()` calls `fifo.stop()`; if `stop()` has no guard
and joins with a timeout, teardown blocks N×timeout and may return while the
worker is still mid-task.
- Fix: guard `stop()` so the second call is a no-op (`if self._stopped.is_set(): return`).
- Bonus: confirm no reply is dispatched against a client that teardown nulled.

## 3. Double-delivery / double-accounting dedup correctness
Pattern: two paths can signal the "same completion" (an idle SSE event AND a
status-watcher poll, or a question SSE event AND a message-part fallback). A
reg-pop on `counter <= 0` is the usual safety net — verify both paths converge
on the same pop so neither can deliver/reap twice. Also verify the held-registry
excludes already-held ids before re-enqueueing.
- Fix: a single `should_deliver()` decision + one pop; don't rely on two
  independent "busy observed" flags unless both feed the same dedup.

## 4. FIFO serialization vs a slow blocking call
Pattern: a long blocking call (human approval gate, up to minutes) runs on the
shared worker, stalling every other family that shares the queue.
- Verify: the blocking call is intentional and serialized; if a fast path must
  not wait on it, it needs its own queue.

## 5. Reconcile vs live-handled race
Pattern: a startup/attach reconcile re-lists pending asks and replies to orphans.
If it acts on an ask the live stream is *currently* handling, you double-reply.
- Verify: reconcile snapshots the live-handled set under lock, then clears its
  sibling bookkeeping; and both run on the SAME single worker (serialized), so
  they cannot interleave. If they run on different threads, add the lock.

## 6. Transport duplication for location-scoping
Pattern: a request sends the same scoping value as BOTH a query param AND a
header (`?directory=` + `x-opencode-directory`). One form may be ignored or
starve the route (a documented opencode gotcha: the query form drops
location-scoped events). Inconsistent forms also create symlink/canonical
mismatches.
- Fix: pick the header (canonical realpath) and use it everywhere.

## 7. Misleading variable names hide intent
Pattern: a local named `delegated` that actually holds the per-session *entry*,
or `status` that holds a type string. Harmless but makes the logic unreadable
and invites wrong edits.
- Fix: rename; flag LOW.

## 8. Test fakes masking real ordering
Pattern: a unit test constructs the object then sets a private attribute the
real `__init__` could not populate (e.g. `_session_key` set after construction).
The test passes; production still captures `None`.
- Fix: when a test pins a value post-construction, check whether the production
  path can actually reach that value — treat as a smell, not evidence of
  correctness.
