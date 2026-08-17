# Turn-complete injection + non-blocking delegation (2026-08-10)

Settled design for `opencode_prompt` + turn-completion delivery in the
hermes-opencode bridge. Companion to `question-gate-answer-v1-18-13.md`.

## Design principle (user directive)

A BLOCKING delegate prompt is wrong: while the tool call blocks the agent's
loop, incoming questions and events are invisible (gate auto-answers still
work, but `tool`-mode held asks and anything agent-side stall; the event-
driven spirit dies). Rule: **delegate prompts are fire-and-monitor by
default**; blocking is an explicit opt-in.

## Layering: tool default ≠ bridge default

- `Bridge.prompt(..., wait: bool = True)` keeps its blocking contract
  (active-set poll + `timed_out`), so its existing tests stand unchanged.
- The TOOL handler passes `wait=args.get("wait", False)` — the agent-facing
  default is NON-blocking. Return shape: `wait=false` → `{session_id,
  running, entries, tail_size}` (no `timed_out` key); `wait=true` →
  `{session_id, timed_out, entries, tail_size}`. The handler must emit keys
  conditionally (tool_result kwargs built per-mode) so the wrong-mode key
  never appears as `null`.

## Completion triggers (per engine)

- v1-driven sessions: `session.status` idle — rides the existing E2E-verified
  tail-on-idle path; `_on_idle` now also feeds the injector.
- v2 sessions: `session.next.stop` with `state.kind == "complete"` — NEW
  `EventRouter` route (`on_turn_complete` callback). session id resolved from
  `properties.sessionID`, falling back to `durable.aggregateID`;
  error/cancelled/missing-state stops are ignored.
- Honest caveat: the v2 trigger is unit-tested with a scripted router, NOT
  yet E2E-verified against a live v2-core server. If the subscribed stream
  does not publish `next.stop` for a core, that session never auto-injects
  and the tail/read tools remain the fallback (design is lossless, not
  lossy). v1 idle injection IS E2E-verified.

## Scoping + dedup

- Only sessions registered by `prompt(wait=false)` are injected
  (`self._delegated[sid] = {"last_fp", "prompt"}`). `wait=true` never
  registers; undelegated sessions are skipped (tail tool still buffers).
- Dedup = **content fingerprint** over the shaped rows
  (`\n`.join(f"{role}:{content}")). NOT `durable.seq`: `read.py` shapes to
  Hermes rows and DROPS `durable`, so a seq-based check is always 0 vs 0 and
  silently never fires. Fingerprint is engine-agnostic (v1 legacy rows have
  no durable either) and matched opencode's actual variance (v2 tails carry
  the `prompted/step.started` family, v1 carries message pages — both just
  shape to rows).
- `last_fp` advances ONLY on a successful injection, so a refused inject
  (gateway mode, `inject_message` returns False) leaves retry open for a
  later event.

## Injection semantics + config

- Format: header `[opencode] turn complete | session <sid>` + shaped
  `role: content` lines via `PluginContext.inject_message` (user role).
- Quirk: agent IDLE → queued as next input (wakes the agent); agent running
  → interrupt. The wake is desired for delegation continuation; the config
  escape hatch is `inject_turn_complete` (default `true`).
- **Config keys are WHITELIST-filtered by `load_bridge_config`** — a new key
  must be added to the returned dict and covered by
  `load_bridge_config()[key] == default`, or it is dead (same trap as
  `question_reply_mode`; see `question-gate-answer-v1-18-13.md`).

## Test recipe (10 tests added)

- FakeCtx (`inject_message` recording, returns True) + Bridge(ctx=FakeCtx()).
- Cases: inject once per delegated turn; re-inject when tail CONTENT
  advances (use a different prompt text, not just a higher seq — identical
  content fingerprints as equal); skip undelegated; flag-off skips;
  v1 `_on_idle` path injects; `wait=True` never delegates; ctx=None is
  silent (no crash, tail tool still works).
- Event routing: complete stop dispatches; error / missing-state ignored;
  durable-only sid resolution.
- Pyright gotcha: `Bridge._ctx` is typed Optional — assert via
  `assertIsInstance(ctx, FakeCtx)` (narrows) or a `ctx()` helper, never
  `self.bridge._ctx.injected` bare.

## Test-authoring pitfalls (patch hygiene)

Inserting a new test before an existing method: old_string must be ONLY the
target `def ...:` line (plus minimal unique context) — never include the
following body lines you are about to duplicate; three accidental body
deletions + one README table row-swap happened this session from over-long
old_strings. Each was caught by immediate lsp_diagnostics/failed asserts and
restored before the suite run; re-read the file before retrying a patch.

## Verification tracker pattern

The external reviewer re-fires per edit-turn and wants evidence IN the turn
of the edit: targeted `pytest` on the changed modules + one focused temp
script (`hermes-verify-` prefix, system tempdir via tempfile.mkstemp,
unlinked after) that exercises the changed behavior with stubs. When it
re-fires with ZERO new edits, close it with `git status --porcelain` empty +
HEAD proof + a fast temp-script re-run; do not burn another full-suite
cycle, and do not claim verification that was never run (the full
`pytest tests/ -q` + `ruff check` stay green per commit, ~45s).