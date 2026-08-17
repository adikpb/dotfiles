# v1-Migration Audit: Convergence Rounds 5-7 (2026-08-12)

hermes-opencode-plugin v2→v1 migration audit. Extends SKILL.md items 9-10
("Fix-introduces-bug convergence", "Live-probe complement") with the exact
bug sequence and the design that ended it. The loop: 3 parallel READ-ONLY
agents per round (residue sweep / behavioral review / surface consistency),
each briefed with prior-round fix groups to VERIFY (exact line anchors) +
focused areas for NEW findings, each writing a full report to /tmp and
returning a `{findings[], total_findings}` JSON schema; parent fixes, runs
ruff + pytest + live e2e, then re-dispatches until ALL agents report 0.

## The bug sequence (why each "fix" needed re-auditing)

All in the delegated-fork completion delivery: v1 `session.status` idle
events carry NO turn identity (`{sessionID, status:{type}}` only), one idle
per transition, live-only stream with no replay. The bridge dedups idle
deliveries by a tail fingerprint. Every dedup refinement broke a different
case:

- R4: stale-idle-vs-forget race → `needs_busy`/`saw_busy` gating in the
  router (idle resolves a wait only if a busy was seen since forget()).
- R5: delayed prior-turn idle misattributed to a new fork → fork-time tail
  baseline (`last_fp` initialized to the tail at fork; delivery requires
  the fingerprint to have advanced; empty-fp "always deliver" exemption).
- R6 found the R5 fix's own bugs:
  - N1 overlapping forks: fork#2's baseline read happens AFTER turn-1's
    rows commit → turn-1's completion tail EQUALS fork#2's baseline →
    swallowed → missed notification + permanent `in_flight` leak.
  - N2 zero-row completion with a NON-empty baseline: a turn that adds
    only reasoning parts shapes to the pre-fork tail → `fp == last_fp`
    → never delivered → leak (the empty-fp exemption only covered the
    empty-baseline case).
  - N3 wait=true: a stale prior-turn busy+idle PAIR still in the stream
    pipeline after forget() re-armed resolves the fresh wait early
    (sub-ms window on the real wire; reproduced by manual dispatch).

## The orthogonal-observation design (the fix that stuck)

The lesson: with identity-free events, do not refine the same ambiguous
signal — add an independent observation and gate on the combination.

- Router gained an `on_busy` callback; bridge records `entry["busy_seen"]`
  when a session.status busy frame arrives for a registered fork.
- Delivery gate: `if fp == last_fp: deliver only if busy_seen` (a busy
  proves a turn RAN; an unchanged-fp idle after a busy is that turn's real
  zero-row completion; without a busy it's a duplicate replay). busy_seen
  is consumed (reset) on every delivery. This single gate replaced BOTH
  the empty-fp exemption AND the fork-baseline rule — it subsumes N1, N2
  and the original delayed-idle case (a stale idle's turn produced no busy
  after the fork).
- Wait path (N3): pre-fork tail baseline captured before `client.prompt`;
  after `wait_for_complete` resolves, re-read the tail — if the
  fingerprint did not advance past the baseline, the resolution was a
  stale prior-turn idle → fall back to `_poll_status_idle` (status-map
  busy→deleted cycle is the ground truth for the fresh turn).
- Forget re-arm moved BEFORE the fork (a busy landing ~1s after the 204
  must not be discarded by a later forget) and gated to the router's
  directory scope (cross-directory waits never reach the router's stream;
  an ungated forget just leaks `_needs_busy` entries).

## Convergence-round brief anatomy (what worked)

- "ROUND N: verify the M briefed fix groups (state exact file:line anchors
  checked), then find NEW findings, focusing on areas (a)-(e)" + the full
  wire-shape ground truth + the vendored-source paths. State-machine
  simulation against the REAL classes was explicitly encouraged and
  produced the R6 findings (a sim script replayed event sequences).
- "Take two mtime snapshots of the repo before and after your review and
  report both" — kills the moving-target excuse.
- "Run the targeted unit tests yourself first."
- Convergence is PER-AGENT: R6 residue returned 0 while behavioral
  returned 3 bugs + 2 nits and surface returned 2. 0 from one vantage does
  not close the loop.

## Live probes for what e2e misses

e2e smoke (6 stages: spawn/health/prompt/tail/commands/SSE) never covers
`wait=true` or the delegated-fork reap. Temp `scripts/_*.py` probes:
- Pass the cfg dict DIRECTLY to `Bridge(ctx=None, cfg={...})` — never
  `load_bridge_config()` (reads Hermes' own config, not the probe's).
- Assert the internal state that proves the fix: after a wait=false fork
  completes, `bridge._delegated` entry is popped (reaped) and
  `_pending_tails[sid]` holds the buffered rows; a wait=true outcome has
  `timed_out: False` and the expected rows.
- Run once, then DELETE the probe (repo hygiene; the R5 round flagged
  stray `scripts/_*.py` artifacts as findings).

## Test-fake fidelity (surface findings this round)

- Fakes must record kwarg calls: `FakeClient.session_status` gained a
  `status_dirs` list and the cross-directory test asserts the forwarding —
  a regression dropping `directory=` otherwise passes the suite.
- Fake param NAMES must match the real protocol: client.py's
  `permission_reply(request_id, ...)` was renamed to `rid` to match the
  AskSurface protocol + fakes; a keyword call written against the real
  signature would TypeError against mismatched fakes.
- Fake wire shapes must match the server: per-option `{"type": "custom"}`
  options were replaced by the real `[{label, description}]` + per-question
  `custom` boolean (the server can never emit a per-option type).
- When code captures a fork-time baseline, fakes must advance
  `message_pages` AFTER the fork read (in the finish thread, before the
  idle dispatch) — a pre-advanced page makes the baseline capture the
  completed turn and the baseline verification rejects the real resolution
  (the R6 `test_prompt_waits_for_idle_event` fix).

## Net result

170 passed (+3 net tests vs R5), ruff clean, e2e 6/6, live probes green,
residue agent at 0 findings for the first time (R6); R7 re-audit in
flight. The `busy_seen` gate + pre-fork baseline + poll fallback together
cover every reachable ordering of busy/idle/tail events the wire can
produce.
