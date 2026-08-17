# Serve lifecycle: probe-first auto_serve, spawn ownership, double-load (2026-08-11)

All findings E2E-verified 2026-08-11 on the hermes-opencode-plugin repo (opencode
1.18.16, hermes-agent v2026.8.3 runtime venv). The bug sequence, the fix, and the
durable rules that fell out of diagnosing a "bridge down" on a fresh hermes chat.

## The double-load collision

The TUI topology loads the plugin TWICE per Hermes process: the agent context and
the gateway context both run `register()`. Signature in `~/.hermes/logs/agent.log`:

- Two identical config warnings ~2s apart (e.g. 13:09:21,411 and 13:09:23,372)
- Then one `bridge down` ERROR from the second load's spawn: `opencode serve
  exited (rc=1) before printing its listening banner` with serve output:
  `Warning: OPENCODE_SERVER_PASSWORD is not set; server is unsecured.` +
  `Error: Unexpected error` + `ServeError`

Both warnings are NORMAL — do not read a single warning as a bug. The second
`ensure_serve` collided with the first on the port.

## Loser-crash signature (EADDRINUSE)

opencode serve prints its banner BEFORE the bind succeeds:

- The surviving process's log shows `opencode server listening on http://127.0.0.1:4096`
- The losing spawn prints the password warning, then `Error: Unexpected error`
  and `ServeError`, rc=1, with NO listening line in ITS log

So a spawn that prints a listening banner can still fail. The banner is not
proof of bind.

## Probe-first ensure_serve contract (user-approved, strict mode)

`ensure_serve` under auto_serve probes the CONFIGURED endpoint first:

1. Health check + auth probe (`_health_ok`).
2. 200 with matching auth -> `{"mode": "attached", "handle": None}` — concurrent
   loads (agent+gateway, or two Hermes instances) share one server.
3. 401 (`AuthRequired`) -> `ServeAttachError` at startup, hard fail. User chose
   strict mode: "fail hard when the probe passes and auth mismatches". Never
   attach blind, never spawn into a guaranteed EADDRINUSE.
4. Unreachable (`OpenCodeError`) -> spawn.
5. Non-200, non-401 status -> treated as unreachable -> spawn.

README contract ("start opencode serve on load when the configured port is
free") now matches the code.

## Spawn ownership: never stop a server you did not start

- `ServeHandle` (serve.py) is constructed ONLY in `spawn_serve`; it registers
  `atexit.register(self.stop)` at construction and owns the process group kill.
- Every attach path (probe-attach AND `auto_serve=false`) returns
  `handle: None` — no handle object exists to stop.
- `bridge.stop()` (bridge.py): router.stop(), approval.stop(), then
  `if self._serve_handle is not None: self._serve_handle.stop()`.
- Regression guard added (test_bridge.py): attach mode, patch
  `ServeHandle.stop` with `side_effect=AssertionError(...)`, call
  `bridge.stop()` — must not fire. The plugin reaps only what it sowed
  (user directive 2026-08-11).

## Evidence traps when diagnosing serve failures

1. **The crashed spawn's serve log is UNLINKED.** `spawn_serve`'s
   banner-failure exception path unlinks the NamedTemporaryFile log before
   raising. A surviving `hermes-opencode-serve-*.log` in TMPDIR
   (`ls -t /var/folders/*/*/T/hermes-opencode-serve-*.log`) likely belongs to
   an EARLIER spawn — reading it as the crashed run's output misleads.
2. **The real opencode traceback** is in opencode's own logs:
   `ls -t ~/.local/share/opencode/log/*.log` — that's where "Unexpected error"
   gets its stack.
3. **The bridge's error text embeds the serve-output tail as read at failure
   time**; the on-disk log can differ afterwards. Don't diff the two.
4. **Reconstruct ownership, don't guess**: `lsof -nP -iTCP:<port>` (LISTEN pid
   + ESTABLISHED client), `ps -o pid,ppid,lstart,command -p <pid>` (ppid is the
   Hermes process that spawned it; lstart tells you which session), and
   `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:<port>/api/health`
   (200 with no creds = unauthenticated server alive).
5. A 2ms gap between the config warning and the bridge-down error means NO
   spawn was attempted — the failure came from the probe/attach path, not the
   spawned process.

## Exception-layering rule

- Low-level helpers propagate RAW exceptions (`AuthRequired`, `OpenCodeError`);
  call sites wrap into user-facing types (`ServeAttachError`,
  `ServeStartupError`) with distinct messages.
- The bug this session: `_health_ok` WRAPPED connection errors into
  `ServeAttachError`. The new probe caught `OpenCodeError` — which never
  surfaced, because the helper had already swallowed it into the wrapper type.
  Result: `ServeAttachError` escaped `ensure_serve` -> "bridge down: cannot
  reach opencode server at ...: connection error ... Connection refused" 2ms
  after the config warning, with NO spawn attempt, on a FREE port.
- Fix applied: `_health_ok` propagates raw; the three call sites handle
  dispatch: spawn ready-loop tolerates exceptions (retry), `attach_serve`
  wraps with friendly text, `ensure_serve` probe dispatches
  AuthRequired -> strict fail / OpenCodeError -> spawn.

## Docs and manifest surface sync (user directives 2026-08-11)

- A README rewrite must ALSO update `plugin.yaml` `description` AND pyproject
  `[project] description` — both are user-facing (the manifest one renders in
  `hermes plugins list`) and they drift with stale framing. Check all three
  surfaces after any docs pass.
- README style for this repo: "more user-facing but for power users; avoid
  negative ontologies". No "no polling", "never gated or queried", "TUI only",
  "refused", "fail closed". Say what each mode DOES: "the full experience is
  the Hermes CLI/TUI: completion notices and questions land in the
  conversation as they happen. In gateway and desktop sessions the same events
  stay on the event stream and the tools." Keep the config/tool tables intact;
  drop stale test counts rather than let them drift (they rot).
- Verification scan after a docs rewrite: `grep -c` for em dashes and the
  negative-ontology words (`never`, `refused`, `fail clos`, `\bonly\b`).

## Removed-shim-test policy

- User directive: "why does the shim require test, its a local only thing
  right? get rid of it". The shim is NOT local-only (directory installs from
  GitHub use the same load path) — state the correction in one line, then
  comply fully. The committed `tests/test_shim.py` was removed; verify the
  directory load path with a one-shot loader replication (subprocess, scrubbed
  sys.path, fake ctx with the REAL `register_tool` API) instead of a committed
  test.
- History: the amended commit never reached origin, so the push was a plain
  fast-forward — no force needed. `git push --force-with-lease` is only
  required when rewriting commits already on origin.
