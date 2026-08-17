# Behavioral audit — ROUND 2 RESTART (2026-08-12)

Re-verification of 10 behavioral findings from a rate-limited prior batch against the
CURRENT working tree of hermes-opencode-plugin, plus a new-bug hunt. Read-only audit.

## Moving-target audit method (the headline lesson)

The maintainer was editing the tree **concurrently with the audit** (bridge.py, events.py,
client.py, tools.py, read.py mtimes moved at 07:13–07:16, i.e. during verification). This
will recur — the installed plugin is a symlink to the dev repo, so fixes land continuously.

1. **Snapshot mtimes first and re-check between read batches**:
   `stat -f "%m %N" hermes_opencode/*.py | sort -rn` (macOS) + `git status`/`git diff HEAD`.
2. **Line-number mismatch between grep and an earlier read_file = the file changed under
   you.** Re-read the file before judging anything. (events.py went 200 → 212 lines mid-audit.)
3. **A transient pytest failure mid-run can be the file changing under the runner.**
   `test_reconnect_after_stream_closed` failed once while events.py was being rewritten,
   then passed in isolation AND on full re-run. Re-run before reporting; verify in isolation.
4. **Report against the FINAL observed state and state the edit window** in the report so
   the parent knows the verdicts are time-stamped.
5. **Evidence drift is itself a signal**: brief expected 153 passed; final tree = 155 passed
   (2 new regression tests for the forget() fix). ruff is a tripwire for freshly-landed
   text fixes — the finding-9 schema-text fix landed as one 149-char line → the sole E501.
6. Expected-vs-actual on the brief's line numbers: every briefed line had moved or been
   rewritten by audit time; verify by SEMANTICS (what the finding claims the code does),
   not by line number.

## The 10 briefed findings → all VERIFIED-FIXED by audit close

| # | Finding | Fix verified in tree |
|---|---|---|
| 1 | wait_for_complete resolved instantly on a STALE `_last_status` idle from a PREVIOUS turn of a reused session (busy event lands ~1s after prompt_async 204) | `EventRouter.forget(session_id)` (events.py:108-118) pops `_last_status` + `_waiters`; `bridge._wait_idle` calls it before `wait_for_complete` (bridge.py:464); regression test added |
| 2 | wait=false returned running=False for a just-forked turn | `running = True` unconditionally after the 204 (bridge.py:437) — the 204 IS the fork confirmation; status-map busy entry lags ~1s |
| 3 | stop-then-start broken in spawned mode (client/serve_handle survived stop) | `_owns_client = client is None`; stop() nulls `_serve_handle` and, when owned, `_client` (bridge.py:148-154) → restart re-runs `ensure_serve`; attached servers still never stopped |
| 4 | events.py docstring claimed x-opencode-directory header MUST be sent | rewritten to document the `?directory=` query form + the v1.18.13+ header stall |
| 5 | read.py unused logging import/logger | removed (read.py now imports only `typing.Any`) |
| 6 | prompt_async omitted `session_scoped=True` (404 → generic OpenCodeError) | `session_scoped=True` added (client.py:271) → `SessionNotFoundError` |
| 7 | shape_message flat fallback missed top-level time.created; non-dict info crashed | `isinstance(raw_info, dict)` guard; created chain: info.time.created → flat `msg['time']` dict → flat `msg['created']` |
| 8 | reconnect log claimed server.instance.disposed for any StreamClosed | `except StreamClosed as exc` → `logger.info("opencode event stream closed: %s", exc)` |
| 9 | tools.py schema said timeout 'default 600' while wiring uses config prompt_timeout | text now "defaults to the bridge prompt_timeout config, 600 unless set" — landed as a 149-char line → ruff E501 (see residual R1) |
| 10 | `_delegated` 'prompt' key dead payload | registration is `{"last_fp": ""}` only |

## Residual NEW findings (open)

- R1 (cleanup, tools.py:77): `ruff check .` fails — E501 149>120 on the finding-9 text fix. Wrap it.
- R2 (cleanup, tools.py:33): `_INT` dead constant (all schemas inline the dict).
- R3 (cleanup, bridge.py:70-71): `_delegated` / `_injected_questions` never pruned;
  `_pending_tails` buffers tails for EVERY idle session in the directory incl. FOREIGN
  sessions (other clients/TUI sharing the server) — foreign tails are consumable via the tail tool.
- R4 (nit, bridge.py:94-119): `_down_reason` never cleared on a later-successful start().
- R5 (nit, events.py:186): `(props.get("status") or {}).get("type")` crashes on a truthy
  non-dict status; `_dispatch` runs outside `_safe`, so the generic except tears down the
  stream → full reconnect.
- R6 (nit, tools.py:212): `bool(args.get("wait", False))` — agent passing `"false"` string
  coerces True → blocking call. Use a config-style `_as_bool`.
- R7 (nit, bridge.py:463-469): wait=true with a directory ≠ router directory never sees the
  session's events → always blocks the full prompt_timeout, resolved only by the final
  status-map re-read (which also carries the bridge directory).
- R8 (nit, read.py:64): non-list `parts` iterates keys → crash; add the same isinstance
  guard as the info fix.

## Live facts re-confirmed (same as prior live run)

prompt_async 204 in ~0.04-0.15s; status-map busy entry ~1s later; idle deletes the entry;
MessageV1 = `{info: {...}, parts}`; e2e smoke 6/6; `load_bridge_config()` takes no args
(pass a cfg dict to Bridge in probes, like the tests do).
