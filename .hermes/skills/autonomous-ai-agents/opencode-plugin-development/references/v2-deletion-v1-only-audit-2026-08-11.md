# v2-deletion v1-only audit (2026-08-11) — round 6 of the audit loop

Behavioral review (READ-ONLY) of the migration that deleted the opencode v2 surface from
hermes-opencode-plugin and made it v1-only. Round 1 did the deletion+rename; this round
checked signatures, routes, SSE terminal handling, idle semantics, dead code, threading, and
v1-only intent. Evidence: `uv run pytest -q` -> 151 passed; `uv run ruff check .` -> clean.

## Settled state (current client surface)

- `session_status()` (was `active_sessions()`): `GET /session/status` -> `{sessionID: {type:
  "busy"}}`; the status service DELETES a session's entry on idle, so **absence = idle**.
- `create_session(agent, model, directory)`: `POST /session` -> bare `{id, ...}` — NO `data`
  envelope (do NOT unwrap); body `{agent?, model?}`; directory via BOTH `?directory=` query and
  `x-opencode-directory` header.
- `prompt(session_id, text, message_id, agent, model, directory)`: `POST /session/{id}/message`
  with the PARTS body `{parts: [{type: "text", text}], agent?, model?, id?}` — the v2
  `{prompt: {text}, resume}` wrapper is gone.
- `messages(session_id, before, limit) -> (list, next_cursor)`: `GET /session/{id}/message?
  before=&limit=`; bare list; next page via `Link` header `<...>; rel="next"` (X-Next-Cursor
  also advertised in the docstring but NOT parsed — only Link).
- `commands()` -> `GET /command` (`[{name, template}]`); `health()` -> `GET /global/health`.
- `permission_list` -> `GET /permission`; `permission_reply` -> `POST /permission/{id}/reply`
  `{reply, message?}`; `question_reply` -> `POST /question/{id}/reply` `{answers: [[...]]}`;
  `question_reject` -> `POST /question/{id}/reject` body `{}`.
- SSE `GET /event`: frames are `data: {id, type, properties}\n\n`; terminal frame
  `server.instance.disposed` -> raise StreamClosed (NOT yielded); EOF without terminal ->
  StreamBroken (distinct); 10s heartbeat. Directory as `?directory=` query: current
  WorkspaceRoutingMiddleware `defaultDirectory()` =
  `searchParams.get("directory") || headers["x-opencode-directory"] || cwd` (query wins; both
  accepted — the round-2 "header stalls the body" docstring in client.py:346-349 is stale for
  the current server).
- v2 rationale (client.py module docstring): v2 sessions resolve only config-document agents
  and deny every tool for plugin-registered agents (omo-slim's orchestrator); the v1 runtime
  resolves them.

## Findings (all fixed in follow-up work, or fix-recommended here)

- BUG `scripts/e2e_smoke.py:115` — `CLIENT.active_sessions()` (deleted) -> AttributeError in
  stage s03. Fix: `CLIENT.session_status()`.
- BUG `scripts/e2e_smoke.py:125,134` — `read_session(..., engine="v2")` (param deleted) ->
  TypeError, and `out['engine']` -> KeyError in stage s04. Fix: drop both.
- CLEANUP `client.py:287-288` — unreachable `if status == 404` in `messages()` (request with
  `session_scoped=True` already raises SessionNotFoundError).
- CLEANUP `read.py:138-141` — no-op `except SessionNotFoundError: raise`.
- CLEANUP `config.py:90,129` — `prompt_timeout` loaded but never consumed (bridge.prompt
  hardcodes 600; tools default 600).
- NIT `client.py:409-424` — `_parse_sse_frame` dropped the `isinstance(dict)` guard; a valid
  non-object JSON frame -> AttributeError at `.get("type")` instead of a frame skip.
- NIT `client.py:292-299` — pagination parses Link only; docstring promises X-Next-Cursor.
- NIT `bridge.py:92-96,115-133` — `start()` not idempotent (double-start leaks daemon
  router+worker threads; stop() joins 5s/10s while SSE read can block 30s).
- NIT `approval.py:148-150` — `question_registry_get` test-only.
- Verified-clean: ALL in-package call sites match the new client signatures; idle semantics
  (pre-check, event wait, post-timeout re-read) consistent; thread lifecycle has no
  join-on-self / swallowed shutdown exceptions.

## Audit method (transferable to any deletion/rename migration)

1. Read ALL files incl. test fakes first; kick off pytest + ruff in the BACKGROUND while
   reading the rest.
2. Classify every suspicious item pre-existing vs migration-introduced with `git diff` and
   `git show HEAD:<file>` — the e2e bugs were NOT new code: the call sites existed at HEAD and
   worked because the methods existed; the DELETION broke them. "Pre-existing but broken by
   the deletion" is still a migration bug.
3. Whole-repo grep for every deleted name (`active_sessions`, `engine=`, `V2Collapser`,
   `prompt_legacy`, `/api/`, `.v2.asked`, `session.next`) — the ONLY hits were in
   `scripts/e2e_smoke.py`. **PITFALL: pytest passing does NOT cover scripts/; CI-green is not
   e2e-green.** Unit-test fakes (FakeBridgeClient etc.) were updated by the migration; the
   e2e script was not.
4. Signature matrix: every client method vs every call site (bridge/tools/approval/serve/
   events + tests + scripts). In-package all matched; scripts did not.
5. Verify server-side claims against upstream source, not docs (workspace-routing middleware
   settled the header-vs-query question).
6. Finding rule: severity (bug/cleanup/nit) + verified file:line + description + concrete
   fix; a finding without file:line is not a finding.
