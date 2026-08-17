# SSE `/event` location-filter root cause

## Symptom (one verification reported A/B/C all FAILING)

A live-tool verification of the plugin's three event-driven pillars reported:
- A) turn-complete injection — never appeared
- B) question ask — `que_` id minted but `opencode_question_reply` 404'd
- C) permission routing — no ask surfaced

All three "failed" at once. The verifier concluded a fix regression. It was
not — it was a single SSE subscription defect that starved the event router.

## Root cause

opencode location-filters the v1 `/event` stream on the **CANONICAL directory
path**. On macOS `/tmp` is a symlink to `/private/tmp`. The event router
subscribed `/event` with the RAW configured directory (`/tmp`), so every
location-scoped event (`session.status`, `question.asked`, `permission.asked`,
`session.idle`, `session.diff`) was dropped. The router received ONLY
`server.connected` and `server.heartbeat`.

Meanwhile the REST endpoints (`session_status`, `question_list`,
`permission_list`) use a DIFFERENT (non-location-exact or loosely-scoped) filter
and kept working. That is why:
- turn-complete only landed via the **status-map watcher** (REST poll), never
  via the SSE idle event;
- questions/permissions were never surfaced (their events never reached the
  bridge).

## Debug technique that cracked it (reusable)

The "router sees only connected/heartbeat" symptom is easy to misread as an
inject-sink or harness problem. Pin it down with a **singleton comparison**:

1. Temporarily write the router's subscription directory to a file at the top
   of `EventRouter._run`:
   `open("/tmp/router_dir.txt","a").write(f"ROUTER_DIR={self._directory!r}\n")`
2. In the same probe, open a SECOND `client.iter_events(directory=<known-good>)`
   connection on another thread and capture the `type`s it receives.
3. Compare: if `ROUTER_DIR` is a *different* (e.g. symlinked or cwd) path than
   the known-good connection — even though both call the identical
   `client.iter_events(directory=...)` — the bridge is subscribing the wrong
   directory. Concretely observed: `ROUTER_DIR='/Users/.../plugin'` (the cwd,
   because the bridge fell back to `os.getcwd()` when config had no
   `directory`) while the raw connection with the real dir got the full
   manifest. The cwd fallback in the probe masked the realpath fix until the
   probe was forced to pass `directory="/tmp"` explicitly.
4. Once `ROUTER_DIR` equals the canonical realpath, add an event counter in
   `_dispatch` (or dump each `event.get("type")`) and confirm
   `question.asked`/`permission.asked`/`session.status` now arrive. Assert the
   bridge's internal held state directly (`bridge._approval.held_question_ids()`
   should return the live `que_*` id) rather than inferring from a missing
   injected message.

This singleton comparison isolates "subscription directory wrong" from
"events on wire but dropped" from "events arrive but inject sink missing" —
three different failure classes with the same surface symptom.

## Post-fix architecture note

After `fa1628b` the SSE path is corrected. Separately, the question handling
was extracted from `approval.py` into `hermes_opencode/questions.py`
(commit `88cd624`) so question diagnostics log under
`hermes_opencode.questions`, not `hermes_opencode.approval`. If a verification
report shows `question ... held for agent reply` under the `.approval` logger,
the running code is PRE-fix — restart/reload to pick up the module split and
the canonical-dir SSE fix.

## Fix (commit `fa1628b`)

- `bridge.py`: `self._directory = os.path.realpath(self._directory)` so the
  subscription matches opencode's canonical-path filter.
- `client.py` `iter_events`: send the directory on the **`x-opencode-directory`
  HEADER**. On this opencode build the `?directory=` query form alone yields
  only `server.connected`/`heartbeat` and starves the router; the header form
  delivers the manifest. (The events.py docstring was corrected to say header,
  not query.)

After the fix, the router receives the full manifest and `question.asked` is
held with a real `que_` id (verified: `bridge._approval.held_question_ids()`
returned the live `que_example_sse`).

## Why this is distinct from the inject-sink limitation

The inject-sink issue (deferred tools have no cli_ref/session_key, so
`_inject_text` returns False) means events reach the bridge but the message
cannot be delivered. Here the events NEVER reach the bridge — a routing/subscription
defect, fixed by the realpath + header. Both can co-exist: fix the subscription
first (so events arrive), then use the recording-ctx probe (`scripts/probe_live.py`)
to prove the inject logic lands even without an interactive TUI.
