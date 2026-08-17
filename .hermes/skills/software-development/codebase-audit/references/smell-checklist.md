# Refactor smell checklist (Python, read-only recon)

Use as the systematic scan list in step 3 of the recon workflow. Each item:
what to look for, where it usually hides, and the minimal restructure.

## 1. Repeated error-handling blocks -> shared helper
Pattern: the same `try: call(); except Exception: log + fail-closed/ fallback`
repeated across modules/methods.
- Look: `_handle_permission` inner try + a separate `_fail_closed_*` helper;
  `_reply`/`_reject` each wrapping their client call; a sibling path that
  calls the same client method with **no** guard (inconsistent discipline).
- Fix: one `def _reply_fail_closed(callable, *a, **kw): try: callable(*a,**kw)
  except Exception: log` and route every reply through it.

## 2. Unguarded call in a "fail-closed" path
Pattern: a function is explicitly built to never crash the worker/router, but
one of its sibling calls (e.g. the initial reconcile, vs the live-stream path)
is unguarded and can raise out of startup.
- Look: a method whose "live" call is wrapped but whose "initial"/"reconnect"
  call is not, and which is invoked outside any `_safe` wrapper.
- Fix: wrap the unguarded call with the same fail-closed helper, or move it
  under the existing `_safe` wrapper.

## 3. Thin delegating wrappers (violates "no thin wrappers" rule)
Pattern: `def f(x, *a): return x.g(*a)` with a docstring justifying it.
- Look: module-level wrappers that the only caller (which already holds the
  concrete type) could call directly.
- Fix: inline the call at the single call site; delete the wrapper.

## 4. Duplicated config/state resolution
Pattern: the same derived value computed in 3 places (config, bridge,
submodule), with one version reaching into another module's `_private`
attribute.
- Look: `question_reply_mode`, timeouts, host/port — resolved in config +
  orchestrator + submodule; submodule reads `_cfg` it doesn't own.
- Fix: compute once (config), read the key downstream; delete the
  private-reaching accessor.

## 5. Functions >60 lines mixing concerns
Pattern: one method does fetch + parse + dedup + accounting + inject + reap.
- Look: `*_turn_complete`, `*_on_idle`, `_inject_*`, big `*_handle_*` methods.
- Fix: extract a pure decision fn (`_should_deliver(entry, fp, busy) -> bool`)
  and keep the side-effecting wrapper thin.

## 6. Scattered concern that a module was meant to own
Pattern: a module's docstring claims ownership of a whole path, but the
orchestrator holds most of the logic while the module holds only the
primitive (FIFO enqueue / registry).
- Look: routing, resolution, asker-default, and glue living in the
  orchestrator while the "owner" module just stores state.
- Fix: move routing/resolution/asker logic into the owner module; leave the
  orchestrator only its explicit jobs (injection, clarify, watch).

## 7. Leaky / inconsistent transport surface
Pattern: a client returns a 3-tuple `(status, headers, parsed)` that most
callers discard with `_, _, parsed = ...`; or the same header logic built by
hand in two places instead of one `_headers()` helper.
- Fix: a `request_json()` that returns parsed + raises; keep raw `request`
  only for the one caller needing headers.

## 8. Per-call param skips canonicalization the default got
Pattern: `__init__` canonicalizes a value (e.g. `os.path.realpath(directory)`)
but a per-call override parameter is used raw, creating a filter/lookup
mismatch (symlinked `/tmp` vs `/private/tmp`).
- Fix: canonicalize the override the same way before use.

## 9. Stale / contradictory docstrings
Pattern: docstring describes the opposite of the code, especially around
critical design points (canonical directory, fail-closed, serialization order).
- Fix: correct the docstring; flag as MED — future maintainers will trust it.

## 10. Triplicated "invoke callable, swallow + log"
Pattern: `Fifo._run`, `AskBridge._safe`, `EventRouter._safe` each re-implement
"run cb, log on fault, don't propagate".
- Fix: one shared module-level `_safe_call(fn, *a, label=...)`.
