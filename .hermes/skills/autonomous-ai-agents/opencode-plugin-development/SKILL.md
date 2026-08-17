---
name: opencode-plugin-development
description: "Use when building OpenCode plugins or SDK integrations."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [OpenCode, Plugin-API, SDK, Sessions, Bridge]
    related_skills: [opencode, hermes-agent, llm-wiki]
---

# OpenCode Plugin & SDK Development (source-level bridge)

Use when building a bridge, plugin, or programmatic integration with OpenCode: authoring a plugin (npm package or local `./plugin.ts`), driving a running opencode server from a Node client via `@opencode-ai/sdk`, injecting messages into a session, or mapping the opencode source (e.g. a Hermes Agent ↔ OpenCode bridge). This is the DEVELOPMENT twin of the `opencode` skill (CLI/TUI only). The user's oh-my-opencode-slim plugin repo (fork `adikpb/oh-my-opencode-slim`, local path `~/dotfiles/.config/opencode/plugins/oh-my-opencode-slim/`) is covered here — config architecture, disk-read invariants, RuntimeConfig: `references/oh-my-opencode-slim-dev.md` and `references/plugin-config-audit.md`.

## v1/v2 API surface recon — integration pitfalls

> Full detail + the v2-session-store-split gotcha + live-probe technique: **`references/v1-v2-api-surface.md`** (read it before adopting any v2 endpoint).

Condensed knowledge bank of the opencode HTTP API surface split and where v2
genuinely helps vs regresses a bridge (v2 `event?after=<seq>` replay fixes
reconnect loss but carries NO `session.status` idle/busy and NO
`session.next.start/stop`; `/api/session/{id}/wait` is a 503 stub; v2 interrupt
is the one real win; v2 `GET /api/session/active` is process-local/
foreground-only/restart-emptying and NOT directory-scoped). Read
`references/opencode-v1-v2-api-surface.md` before any v2-adoption work.

## Iterative multi-agent v1-consistency audit loop (v2-surface migration)

When migrating the plugin (or auditing a finished migration) to confirm it is
fully v1-ONLY with ZERO residual v2 surface, run the audit as a looped
delegated fan-out rather than one pass. Subagents self-report and can miss
cross-cutting residue, so re-dispatch until 0 findings.

- Use `delegate_task` with `tasks=[...]` and 3 LEAF s

**Pitfall — never poll the fan-out with `terminal(sleep …)` + transcript
tail.** A `delegate_task` fan-out re-enters as ONE consolidated message when
all children finish; do not `sleep` and tail the live logs to "wait". Stop
calling tools and let the result wake the session automatically. (User
correction, 2026-08-13: "do not call shell commands like sleep to wait, just
stop calling things, you will be waken automatically.")
ubagents, one per lens:
  1. **Source & tests** — grep `hermes_opencode/*.py tests/*.py scripts/*.py`
     for any `/api/` route, `{data:}` envelope unwrap, v2 event types
     (`permission.v2.*` / `question.v2.*`), `resume` wrapper, or "v2 registry
     never sees" prose; confirm every `client.py` endpoint hits only root v1
     routes; run `uv run pytest -q` inside the child to prove green.
  2. **Docs** — README + `wiki/**.md`: no line may state the plugin DRIVES a
     `/api/` v2 route (v2 is OK only as "reference / deferred / historical"
     server surface); README tool/config tables must match `tools.py`
     schemas + `config.py` defaults; version stamps consistent (README says
     the live verified target, e.g. v1.18.16; cloned-source tag refs are fine).
  3. **Wire-shape correctness** — per `references/v1-wire-surface-audit.md`:
     create-vs-prompt Model/ModelRef split, no stray payload keys,
     `messageID` (not `id`), `/event` `?directory=` query; plus the latent
     guards: `messages()` must never emit `before` without `limit`, and
     `create_session` must never emit a null `providerID`.
- Each child returns JSON `{findings:[{file,line,issue,severity,fix}], summary}`;
  fix every finding, then RE-DISPATCH all 3 with the fix summary in `context`.
- STOP when a round returns 0 findings across all 3 lenses. Real result from
  this session: round 1 found 6 (2 wire-shape latent, 4 doc), all fixed,
  round 2 returned 0.

## Pitfall: awaiting async delegation — do NOT poll with sleep

`delegate_task` (background fan-out) re-enters the conversation automatically
when ALL children finish. **Do not** shell out to `sleep`/`tail -f` loops to
wait for it, and do not re-call tools just to "check". The user explicitly
corrected this: stop calling things and wait for the wake. You may read the
live transcript files for a progress glance, but never block the session on
`sleep`. If you genuinely need to do other independent work meanwhile, do it,
then wait for the consolidated result — do not busy-loop.

> Verified v1 wire-surface facts (route-by-request shapes, the
> create-vs-prompt Model/ModelRef trap, QuestionOption shape, SSE envelope) and the
> consistency-audit checklist live in `references/v1-wire-surface-audit.md` — read it
> before touching any client payload, test fake, or docs table in this plugin.

## 2026-08-11: the plugin is V1-ONLY — v2 API dropped (no fallbacks)

User decision: the opencode v2 surface (AgentV2 registry, `/api/*` routes,
`session.next.*` events, `permission.v2.*`/`question.v2.*`, v2 history/
context/engine reads) is DELETED from hermes-opencode, not kept with
fallbacks; one API surface only (v1), v2 re-migration deferred. Name
changes: `create_session_v1` -> `create_session`, `prompt_legacy` ->
`prompt` (parts body + agent/model/directory), `active_sessions` ->
`session_status()` (GET /session/status map; absence = idle). Deleted
machinery (DO NOT resurrect): V2Collapser, detect_engine/_event_seq/engine
routing, `scope=context`, `_last_stop`, `_fallback_v1`, `_deny_locked_out`,
deny-lockout detection, `fallback:"v1"`, family-keyed ask routing, the
`session_id` param on opencode_question_reply. The wiki keeps v2 as
server-surface REFERENCE (banner-marked "V1-ONLY / reference only / dropped
2026-08-11" on plugin-requirements.md, opencode-session-reading.md,
opencode-agent-registry.md); wiki pages WITHOUT such a banner that still
prescribe v2 plugin behavior are STALE (round-1 residue audit found one:
opencode-permissions.md:47-48 prescribing the deleted v2-first reconcile).

**Post-migration residue audit method (round 1, 2026-08-11)** — when a
migration deletes API surface, sweep for residue as a distinct step: grep
the DELETED names (methods, params, routes, event families, output fields)
across ALL files incl. `scripts/` — the unit suite is a blind spot
(`pytest -q` green does NOT cover scripts/e2e_smoke.py, which needs a live
server; it shipped with `engine="v2"` + `active_sessions()` calls that
TypeError/AttributeError on every run). Prove staleness statically
(`inspect.signature(fn)`, `hasattr(cls, name)`) instead of running e2e.
Classify every mention: CODE_PATH (executable, bug) / STALE_DOC (doc CLAIMS
v2 usage, bug) / EXPLANATORY (doc explains v2 is NOT used, banner-marked
reference pages, dated changelog entries, negative tests asserting v2
families are ignored — allowed). Filter noise dirs (`.slim/clonedeps`
vendored clones, `.venv`, caches) out of recursive greps. Details + the
residue checklist + findings: `references/v1-only-migration-residue-audit-2026-08-11.md`.

## Ground truth = source, not docs

The plugin contract is code-first. Always read the repo sources at the exact tag you target:

- Verify the tag first: `git describe --tags`. This skill's reference is pinned to **v1.18.13** (commit a105350812f05, tag v1.18.13).
- Key packages in the monorepo:
  - `packages/plugin` → `@opencode-ai/plugin` (the plugin author's API: `src/index.ts`, `src/tool.ts`, `src/v2/…`)
  - `packages/sdk/js` → `@opencode-ai/sdk` (generated client: `src/client.ts`, `src/server.ts`, `src/v2/…`)
  - `packages/protocol` → Effect HttpApi wire groups (server routes)
  - `packages/schema` + `packages/core` → wire contracts (Permission, Session, Event unions)
  - `packages/opencode/src` → host runtime: `src/plugin/*` (loader + trigger), `src/session/*`, `src/tool/registry.ts`, `src/permission/index.ts`, `src/config/*`
- **Generated API spec is endpoint ground truth**: `packages/sdk/openapi.json` at the tag lists every real route (162 paths at v1.18.13). Dump `sorted(paths.keys())` and diff intended wire calls against it BEFORE trusting any wiki/table — it catches v1/v2 path drift (`prompt-async`-vs-`prompt_async`, `/event`-vs-`/events`). Check three levels: route DECLARATION (protocol group) ≠ HANDLER implementation ≠ SERVICE wiring (that's how `wait`/`compact` were found to be 503 stubs).
- Repo-root `AGENTS.md` carries conventions: regenerate legacy JS SDK with `./packages/sdk/js/script/build.ts`; after protocol changes run `bun run generate` from `packages/client`.
- The hermes-opencode-plugin workspace also carries a requirements wiki IN the repo at `<repo>/wiki/` (SCHEMA.md, index.md, log.md; gitignored, `WIKI_PATH` unset — not `~/wiki`). The design distillation for this bridge lives there: `concepts/plugin-requirements.md`, `concepts/hermes-approval-route.md`, `concepts/opencode-permissions.md`, `concepts/opencode-commands.md`, `concepts/opencode-question-api.md`, `entities/opencode-http-api.md`. Orient with SCHEMA+index+log before editing.

## Quick contract (v1.18.13)

- A v1 plugin is a FUNCTION: `type Plugin = (input: PluginInput, options?: PluginOptions) => Promise<Hooks>`. No name/setup/config object fields; identity comes from the default-exported module shape `{ id?, server, tui? }` (or legacy: any exported function).
- `PluginInput = { client, project, directory, worktree, experimental_workspace: { register }, serverUrl, $: BunShell }` — `client` is an `OpencodeClient` for the running server (plugins can push messages via `client.session.prompt`).
- Returned `Hooks` fields: `tool`, `config`, `event`, `auth`, `provider`, `chat.message`, `chat.params`, `chat.headers`, `command.execute.before`, `tool.execute.before/after`, `shell.env`, `tool.definition`, plus `experimental.*` hooks — all `(input, output) => Promise<void>` with a mutable `output` object.
- Local (path) plugins MUST export `id` (`Path plugin ${spec} must export id`); npm plugins get the package name.
- Current prompt bodies are PARTS-BASED: `client.session.prompt({ path: {id}, body: { parts: [TextPartInput|FilePartInput|AgentPartInput|SubtaskPartInput] } })` on `POST /api/session/{id}/message`. There is no `prompt: string` anymore.
- Message injection: session.prompt / promptAsync endpoints > plugin-injected `client` > `tui.appendPrompt`.

## Pitfalls

- The multi-line `trigger` call: `plugin.trigger("hook.name", …)` — the hook name is usually on the NEXT line. A single-line grep of `trigger("` misses it; use two-line context or read the code.
- `plugin.trigger` runs hooks in load order over a shared mutable `output`; later plugins see earlier plugins' writes. Order is deterministic (built-ins first, then config-plugin array order).
- `permission.ask` plugin hook is DECLARED in the Hooks interface but has NO trigger call-site in v1.18.13 — the permission surface is the `permission.asked` / `permission.replied` events plus `ctx.ask()`. Don't build on it.
- **Idle trigger = modern `session.status` (`type: "idle"`), NOT `session.idle`**
  (deprecated in-schema, still emitted — v1.18.13 publishes BOTH on idle).
  **DO NOT rely on `POST /api/session/:id/wait`: it is a declared-but-stubbed
  route that ALWAYS 503s** (`OperationUnavailableError`, core/src/session.ts) —
  blocking handoffs must watch `session.status idle` client-side.
- **Replay stream path is SINGULAR**: `GET /api/session/:sessionID/event?after=`
  (NOT `/events`). The global/instance streams (`/event`, `/global/event`,
  `/api/event`) are live-only, emit NO SSE-level `id:` field, and have NO
  `after` replay — reconnect = reconcile via REST lists
  (`GET /api/permission/request`, `GET /api/question/request`, session-scoped
  variants). Event wire shape is `{id, type, properties}` — flat payloads like
  `permission.asked {sessionID, permission, patterns}` are NESTED under
  `properties`.
- **v2 prompt body has NO `parts`**: `POST /api/session/:id/prompt` takes
  `{prompt, resume?, delivery?, id?}` where `prompt = {text, files?, agents?}`;
  legacy `/session/{id}/message` takes `parts`. `resume: false` = ADMIT-ONLY
  (input durably recorded, execution NOT woken — core/src/session.ts:382);
  legacy `promptAsync` (path `/session/{id}/prompt_async`, UNDERSCORE) DOES
  start the turn. Reused prompt `id` = exact-retry reconciliation, mismatch →
  ConflictError: use caller-generated ids for idempotent delegation.
- **Pending `permission.asked` / `question.asked` have NO server-side timeout**
  (block on a Deferred until replied or instance disposed). A bridge crash
  strands the opencode turn forever — on startup reconcile pending REST lists
  and reject leftovers with a reason. Rejecting one requestID only fans out to
  SAME-session siblings (`always` fan-out skips siblings whose patterns aren't
  all newly allowed — they stay pending).
- **V1 and V2 permission surfaces are SEPARATE stores — never mix them.**
  Runtime tools emit `permission.asked` / `permission.replied` from the V1
  service (`packages/opencode/src/permission/index.ts`) with V1 payloads
  `{permission, patterns, always, tool?}`. The `/api/...` permission routes
  (`/api/permission/request`, `/api/session/:sid/permission/:rid/reply`) are
  backed by a DIFFERENT service `PermissionV2` (`packages/core/src/permission.ts`)
  emitting `permission.v2.asked`/`permission.v2.replied` with
  `{action, resources, save[], source}` — its pending map cannot see V1 asks,
  so replying to a V1 requestID there is a guaranteed 404. To answer a V1
  `permission.asked`, POST `{reply, message?}` to the LEGACY instance route
  `POST /permission/:requestID/reply` (directory-scoped via header), NOT the
  v2 session route. Wire table lives in
  `references/http-api-surfaces-audit-v1-18-13.md`.
- **Three distinct SSE surfaces, three different schemas**:
  1. `GET /event` (instance): directory-scoped, raw `{id,type,properties}`,
     full legacy manifest incl. `session.status`; emits `server.connected`
     first, `server.heartbeat` every 10s, closes on `server.instance.disposed`.
     **Send the directory as `?directory=` QUERY — the `x-opencode-directory`
     HEADER form returns 200 but the body never starts (no `server.connected`,
     no heartbeat; WorkspaceRoutingMiddleware workspace-routing.ts:87 reads
     the query first). E2E-verified 2026-08-10.**
  2. `GET /api/event` (protocol): ALL locations, schema-encoded against
     `ServerDefinitions` — which EXCLUDES `session.status`/`session.idle`/
     `permission.asked`/`question.asked` (they live only in the legacy
     manifest); bounded 256-event dropping queue → slow consumers get the
     stream FAILED with `EventV2.SubscriberOverflow`.
     **The "exclusion" is NOT a filter — it is a stream-killer.** `allBounded`
     subscribes to EVERY publish with no type filter (core/src/event.ts:152-160,
     `listen` :606-613), then `Schema.encodeUnknownSync(OpenCodeEvent)` THROWS
     on any type outside `ServerDefinitions` (server/src/handlers/event.ts:16).
     The first `session.status`/`permission.asked`/`question.asked` crossing
     the shared EventV2 bus kills the whole SSE response with no terminal
     frame (heartbeat is merged `haltStrategy:"left"`, so it dies too). Only
     subscribe `/api/event` where v1 publishers are absent; otherwise treat it
     as best-effort + reconnect/reconcile.
  3. `GET /api/session/:sessionID/event?after=` : the ONLY replay stream
     (durable events, per-session aggregate seq).
  **`session.status` is published only by the V1 prompt/runtime loop**
  (`session/status.ts`, `run-state.ts`); the v2 SessionV2 executor emits no
  status (unchanged TODO). So idle detection for v1-driven sessions watches
  the legacy stream; v2-only flows must watch `GET /api/session/active`
  (empty = idle; a `step.failed` run still leaves the set) or the last
  durable event (`step.completed`/`step.failed`) — NEVER
  `POST /api/session/:id/wait` (503 stub). The v1.18.13 v2 durable family
  has **NO `session.next.start`/`stop`**: real events are
  `session.next.prompt.admitted` → `prompted` (same messageID, both carry
  `data.prompt.text` — shape the user row ONCE), `step.started`
  (`data.model.id`, `assistantMessageID`), `delta` (state.kind text|tool),
  `tool.called/success/failed`, `step.completed`/`step.failed`
  (`data.error.message`). Wire shape `{id, type, durable:{aggregateID, seq,
  version}, data}`; `after=` cursors are `durable.seq`. A shaper built for
  start/delta/stop yields EMPTY tails on a live server (E2E-verified
  2026-08-10, details in `references/session-reading-tail-ranges-v1-18-13.md`).
- **Auth seam when `OPENCODE_SERVER_PASSWORD` is set**: ALL HttpApi routes incl.
  SSE require `Authorization: Basic <base64("opencode":<pw>)>` (username default
  `opencode`, override via `OPENCODE_SERVER_USERNAME`); `?auth_token=` query
  credential also accepted (leak risk). The SDK's `createOpencodeServer` passes
  NO password option and attaches no auth header — put the password in the
  process env before spawning. Edge: `OPENCODE_SERVER_PASSWORD=""` (empty
  string) DISABLES auth entirely (instance httpapi middleware/authorization.ts:90
  `ServerAuth.required`) — treat empty as unset/error, not "secured".
- **ROUND-2 audit corrections (2026-08-09) — wiki pages still drifted**:
  - `GET /api/session/active` is **GET, not POST** (protocol/src/groups/session.ts:146
    `HttpApiEndpoint.get`). Two wiki pages printed POST — that 405s the
    blocking-handoff loop.
  - Replay path is `/api/session/:sessionID/event` **SINGULAR**; the SDK method
    is named `Session3.events` but its URL is `/event` (v2/gen/sdk.gen.ts).
    Four wiki pages still printed `/events` — wire truth = openapi.json paths,
    never the operationId/method name.
  - v2 prompt reply `SessionInput.Admitted` has field **`id`** (the message id),
    NOT `messageID` (schema/src/session-input.ts:15-23) — idempotent-delegation
    code must read `admitted.id`.
  - Question tool INPUT schema has **no `custom` field** — `custom` is
    response-side only (`Info`); `Prompt` = `{question, header, options,
    multiple}` (schema/src/question.ts:28-44, tool/question.ts:6-8).
  - v2 `/api/event` has **NO `server.instance.disposed` terminal** and only a
    15s SSE-comment keepalive `": heartbeat\n\n"` (server/src/handlers/event.ts:37);
    only the v1 `/event` stream ends with a disposed frame + 10s
    `server.heartbeat` event. Reconnect detection on the v2 stream = socket
    close/error, nothing else.
  - `POST /api/session/:id/interrupt` is a **no-op when the session is idle**
    (protocol/src/groups/session.ts:355) — fine for cancel, useless as a wake.
  - `opencode plugin <module>` CLI lives in `src/cli/cmd/plug.ts:178-179`
    (registered src/index.ts:102), NOT in `src/config/`.
  - v1 status reconciliation: status map **deletes the entry on idle** and
    `get()` defaults absent ⇒ `{type:"idle"}` (opencode/src/session/status.ts:32,42-47);
    legacy `GET /session/status` is the v1 counterpart to v2 `GET /api/session/active`.
  - Legacy session list query params (`scope=project|path|roots|start|search|limit`,
    instance httpapi groups/session.ts:30-38) and v2 list cursor pagination remain
    undocumented in the wiki endpoint table.
  Full wiki page:line contradiction list: `references/wiki-audit-round2-v1-18-13.md`.
- **Tail-on-idle race**: durable history rows commit asynchronously AFTER
  `session.status idle` fires ("Newly committed events may appear on later
  pages") — retry the tail read until `hasMore:false`/sequence stable.
- **Bridge consumer transport (E2E-verified 2026-08-10)**: Python
  `http.client` chunked `read(n)` aggregates WHOLE chunks until `n` bytes
  accumulate (`_read_chunked` loops) — `resp.read(4096)` on a quiet SSE
  stream blocks ~forever because the only traffic is ~90-byte 10-second
  heartbeat chunks. Use `resp.read1(4096)` (per-chunk read): `server.connected`
  arrives instantly, heartbeats keep the loop alive. With the wrong read
  call, every SSE probe appears to hang and even curl-vs-python A/B tests
  look like a server bug. See the probe methodology + `/event` query-vs-header
  finding in `references/session-reading-tail-ranges-v1-18-13.md`.
- **Questions NEVER ride the approval gate (settled 2026-08-10, SUPERSEDES
  the earlier gate design)**: the user rejected gate routing outright ("the
  permission aux agent has very different instructions"; the main agent must
  answer). `question_reply_mode` default is `tool`: SSE `question.asked` ->
  `Bridge._on_question` injects the ask into the main agent's conversation
  via `PluginContext.inject_message` (formatted `[opencode] question | session
  <sid> | id <rid>` + numbered questions with non-custom/custom option labels
  + "Answer with opencode_question_reply(question_id=...)", ONCE per rid,
  deduped in `_injected_questions`) then holds it in the FIFO worker's
  `_questions` registry; the agent answers by id via `opencode_question_reply`
  WITHOUT querying a list. **Only `reject` and `tool` exist (2026-08-10, later directive): `auto_first`
  and `auto_answer_questions` were DELETED (config valid set, approval.py
  `auto_first_answers`, tests, docs); `reject` never injects (test-pinned).
  `gate` is invalid -> falls back to `tool` with a warning. Questions are
  NEVER queried or listed: the `opencode_questions` tool, client
  `question_list*` methods, and the reconcile `GET /question` catch-up were
  all REMOVED; `opencode_question_reply` is the ONLY question tool and
  `attach_reconcile` reconciles permission asks only. Unanswerable asks (custom-only options, or any empty answer entry) fail
  closed to `/reject` in EVERY mode — the handler-level guard in
  `_handle_question` (replaced the gate-branch guard). Kept from the gate era:
  config keys are WHITELIST-filtered by `load_bridge_config` — a
  documented-but-unwired key is DEAD; add every new key to the returned dict +
  test `load_bridge_config()[key] == default`. Details + test recipe:
  `references/question-gate-answer-v1-18-13.md`.
- **Human relay via the Hermes clarify panel (`question_clarify`, 2026-08-10)**:
  opt-in (default `false`), tool mode only. The bridge calls the CLI's
  `_clarify_callback` DIRECTLY from the FIFO worker, outside the agent loop,
  so NO tool-call row, NO tool-result row, NO message enters the session
  (one dim scrollback line only, cli.py `_persist_prompt_summary`,
  disable via `display.persist_prompts`). Resolve the callback via the same
  ref `inject_message` uses: `getattr(ctx, "_manager", None)` -> `_cli_ref`
  -> `_clarify_callback` (TUI-only; gateway mode -> None -> fallback).
  Map non-custom option labels to panel choices (clarify caps at 4; overflow
  reachable via its auto-appended Other input); custom-only asks ->
  `choices=None` open-ended prompt. Timeout sentinel: callback returns
  `"The user did not provide a response within the time limit..."` (match
  with `startswith`); on timeout, panel exception, or no callback, fall back
  to inject+hold. Serializes in the FIFO worker like permission asks (a slow
  human holds the question queue). Detail + tests:
  `references/question-clarify-relay-2026-08-10.md`.
- **Hermes plugin packaging: pip entry-point format (2026-08-10, verified
  against docs + loader)**: directory plugins (plugin.yaml + `register(ctx)`
  in the root `__init__.py`) need NO pyproject; pip plugins need
  `[project.entry-points."hermes_agent.plugins"] name = "package"` and the
  entry MODULE must expose `register(ctx)` (`ep.load()` then
  `getattr(module, "register")`, plugins.py:1890). The loader imports
  directory plugins as `hermes_plugins.<slug>` (plugins.py:1873) — no
  self-import collision, so share one implementation: `register()` lives in
  the package, the root `__init__.py` is a lazy shim that delegates inside
  `register()`. **CRITICAL (2026-08-10): the loader NEVER puts the plugin
  dir on `sys.path`** — it imports via
  `spec_from_file_location("hermes_plugins.<slug>", dir/__init__.py,
  submodule_search_locations=[plugin_dir])` (plugins.py:1873) and no
  sys.path insert exists anywhere in hermes_cli, nor is the package in the
  runtime's site-packages. So top-level absolute self-imports
  (`from hermes_opencode.x import y`) FAIL with ModuleNotFoundError in a
  directory install — in the root shim AND inside the package
  (`hermes_opencode/__init__.py:28` had one; all package imports must be
  RELATIVE). The shim must be relative-first with absolute fallback:
  `try: from .hermes_opencode import register as _register
  except ImportError: from hermes_opencode import register as _register`
  (pytest imports root `__init__.py` as a bare top-level module when
  `tests/` has `__init__.py` — relative raises ImportError there, fallback
  handles it; a bare `from .sub import ...` at top level = 158 collection
  errors). **Failure is SILENT**: the loader catches register() exceptions,
  `hermes plugins list` still shows the manifest, agent.log shows nothing —
  tests pass (pytest has repo root on sys.path via cwd) while the live
  plugin never loads. `hermes plugins list` is NOT proof of load.
  PEP 639: setuptools REJECTS `license = "MIT"` together with a
  `License :: ...` classifier ("superseded by license expressions") — keep
  exactly one. Editable installs leave `*.egg-info/` in-tree (committed
  once) — gitignore + `git rm -r --cached`. `plugin.yaml` `provides_tools`
  must match `TOOL_REGISTRY` exactly. Verify with: `uv pip install -e .` ->
  `importlib.metadata.entry_points()` group check -> `ep.load()` callable ->
  uninstall; temp verify scripts in TMPDIR need
  `sys.path.insert(0, repo_root)` (script dir, not cwd, is sys.path[0]).
  Detail: `references/hermes-plugin-packaging-entry-point.md`.
- **Hermes-runtime questions: consult the `hermes-agent` skill FIRST** (user
  redirect 2026-08-10: "get via hermes skill"). The vendored-clone source
  dig is slow; the skill's routing table points at the right reference and
  the docs site. Use the clone only for file:line verification.
- **Delegation is fire-and-monitor, never blocking (settled 2026-08-10)**: a
  blocking delegate prompt wedges the agent's tool loop so incoming
  questions/events become invisible. `opencode_prompt` defaults `wait=false`
  (submit + return `running` immediately; completion observed via the
  tail/read tools) while `Bridge.prompt` keeps `wait=True` as its own
  blocking contract — tool default ≠ bridge default; the handler emits
  `running` vs `timed_out` conditionally, never both as null. Turn
  completion is DELIVERED, not polled: `_on_idle` (v1 `session.status`)
  feeds `_on_turn_complete` — the v2 `session.next.stop`-complete route
  existed briefly and was DELETED in the 2026-08-11 v1-only migration;
  idle is the ONLY completion signal now (wait_for_complete resolves on
  `session.status idle` only, with one status-map re-read as the
  stream-down fallback),
  which injects a SHORT NOTIFICATION once per turn via
  `PluginContext.inject_message` for delegated (wait=false) sessions only:
  `[opencode] turn complete | session <sid> | N rows | opencode is done, check it out
  via opencode_session_tail or opencode_session_read` — the tail ROWS are
  NEVER injected (user directive 2026-08-10: "tell opencode is done, check
  it out"; the agent fetches via the tail/read tools). Dedup stays by
  CONTENT fingerprint, not `durable.seq` (shaped rows drop durable; seq
  checks silently never fire); the fingerprint BASELINE is captured at fork
  time — `last_fp` is set to the fp of the tail read prompt() already
  performs (bridge.py:490), so a delayed idle of a PRIOR turn equals the
  baseline and is skipped, and EMPTY fingerprints always deliver
  (`if fp and fp == last_fp: return` — a zero-row completion with an empty
  shaped tail would otherwise leak the `_delegated` registration at
  in_flight forever); never reset `last_fp` to `""` at fork — that
  re-opens the delayed-idle misattribution window (R5 bug 2);
  `inject_turn_complete` (default true) gates it and must be added to the
  `load_bridge_config` whitelist or it is dead. TUI-only: gateway mode
  returns False and the tail tools stay the fallback; idle-agent quirk =
  the inject wakes it as next input. Design + 10-test recipe + the full
  Hermes injection-surface map: `references/turn-complete-injection-v2026-8-3.md`
  and `references/hermes-message-injection-surfaces.md`.
- **Plugin repo release prep (2026-08-10)**: scrub iteration-marker comments
  (`R*`/`F*`/`P2`/`t1*`/`round-N audit`) from SHIPPED code only — the in-repo
  wiki KEEPS its R-tags (internal contract, gitignored, never pushed). Author
  rewrite on unpushed history: commit first (rebase needs a clean tree), then
  `git rebase --root --exec 'git commit --amend --no-edit --author="N <n@users.noreply.github.com>"'`;
  **the installed plugin is now a SYMLINK to the repo
  (`~/.hermes/plugins/hermes-opencode -> <repo>`, user directive 2026-08-10),
  so there is NO refresh/sync step after pushes — the loader reads the dev
  tree directly; `git fetch origin && git reset --hard origin/main` through
  the symlink would DESTROY dev work. Verify load effects with the
  shim-loader replication test, not a sync. Pitfalls: ruff
  lints Python only — `plugin.yaml` passed to `ruff check` floods E501/syntax
  noise; subprocess pytest MUST inherit the env (a stripped env drops
  PYTHONPATH → spurious `No module named 'tools'` failures); `od -c` trailing-
  newline checks are ambiguous — read the last byte in Python instead.
  Details: `references/repo-release-prep-2026-08-10.md`.
- **Serve lifecycle: probe-first auto_serve, spawn ownership, double-load
  (2026-08-11)**: the TUI loads the plugin TWICE per Hermes process (agent +
  gateway contexts) — two `config` warnings ~2s apart in agent.log are
  NORMAL, not a crash. `ensure_serve` under auto_serve must PROBE the
  configured endpoint before spawning: healthy (200 + auth match) -> attach;
  auth mismatch (401) -> fail hard at startup (strict, user choice; never
  attach blind, never spawn into EADDRINUSE); unreachable -> spawn. The
  losing spawn of a port collision dies with opencode's "Error: Unexpected
  error" / "ServeError" (rc=1) AFTER printing its "listening on" banner
  (banner prints BEFORE the bind succeeds). Ownership: `ServeHandle` is
  created ONLY by spawn_serve (atexit.stop registered at construction);
  every attach path returns handle=None, and bridge.stop() stops only a
  non-None handle — the plugin NEVER stops a server it did not spawn (user
  directive; regression-guarded by patching ServeHandle.stop with
  side_effect=AssertionError — must not fire for an attached bridge).
  Evidence traps: the crashed spawn's serve log is UNLINKED on the
  banner-failure path, so a surviving `hermes-opencode-serve-*.log` in
  TMPDIR likely belongs to an EARLIER spawn; the real opencode traceback is
  in `~/.local/share/opencode/log/`. Reconstruct ownership via
  `lsof -nP -iTCP:<port>` + `ps -o pid,ppid,lstart,command` + `curl /api/health`
  (200 = unauthenticated winner alive, its python client = SSE stream).
  Exception-layering rule that broke once: a helper that WRAPS raw errors
  (`_health_ok` -> ServeAttachError on connection failure) defeats callers
  catching the RAW type (OpenCodeError) — helpers propagate raw
  `AuthRequired`/`OpenCodeError`; call sites wrap into user-facing types
  with distinct messages. Detail + fix timeline:
  `references/serve-lifecycle-ownership-2026-08-11.md`.
- **Docs and manifest surfaces (2026-08-11, user directives)**: a README
  rewrite must ALSO update `plugin.yaml` `description` and pyproject
  `[project] description` — both are user-facing surfaces (the manifest one
  shows in `hermes plugins list`) and they drift with stale framing. README
  style for this repo: user-facing but for power users; AFFIRMATIVE framing
  — avoid the negative ontology ("no polling", "never gated or queried",
  "TUI only", "refused", "fail closed"): say what each mode DOES ("the full
  experience is the Hermes CLI/TUI: completion notices and questions land
  in the conversation as they happen"), keep the config/tool tables intact,
  drop stale test counts rather than let them drift. The shim load-path
  regression test was REMOVED on directive ("why does the shim require
  test... get rid of it") — verify the directory load path with a one-shot
  loader replication instead of a committed test; when the user questions a
  test, comply after one line of correction; a rewritten commit that never
  reached origin amends + plain fast-forward pushes (no force needed).
- **Surface-consistency audit after an API migration (2026-08-11, four
  layers)**: beyond the residue sweep (above), verify cross-layer
  consistency: (1) TOOL surface — registry names+schemas vs plugin.yaml
  provides_tools vs README Tools table vs test schema asserts; schema params
  documented nowhere are findings (README opencode_prompt row dropped
  `directory?`/`agent?`). (2) CONFIG surface — trace each key read site →
  returned dict → consumer. Three failure classes: DEAD = read+documented but
  never consumed (`prompt_timeout` was in config.py AND the README table yet
  tools.py:211/bridge.py:389 hardcode 600); UNDOCUMENTED = consumed but in no
  table (`agent`/`model`); DEAD READ = `cfg.get()` that load_bridge_config
  never produces (`directory` — always os.getcwd() in production). Note the
  internal rename: config key `rule_key` is returned as `rule_key_prefix`;
  check consumers use the dict key, docs use the config-file key. (3)
  DOCS-vs-code — sweep the ENTIRE repo incl. scripts/ for deleted surface
  (old method names, old params, old routes, old events); e2e_smoke.py still
  called `active_sessions()` + `engine="v2"` while the changelog claimed it
  was converted — log entries are NOT evidence. (4) TEST-FAKE fidelity —
  diff fake signatures AND return shapes vs the real client; fakes MISSING
  methods real code calls are masked by test config (`attach_reconcile=False`
  skips reconcile's `permission_list`). Also: Hermes `requires_env` only
  feeds toolset requirements display (registry.py:865-868, no hard gate) —
  flagging the optional password as required is a nit, not a blocker.
  Method + full 13-finding report:
  `references/surface-consistency-audit-v1-only-2026-08-11.md`.
  Parallel-dispatch deltas merged into that report: +2 nits —
  wiki/log.md:34-35,74,82 dated changelog entries still describe
  pre-migration v2 behavior as current (superseded by the 2026-08-11
  migration entry; add a "superseded" pointer), and README.md:114-115
  "asks that carry a question id resolve through the question route,
  others through the reject route" wording (code DROPS id-less question
  events with a warning, approval.py:173-181; the reject route is for
  unanswerable asks, approval.py:280-283); also the index.md cite is
  :34, not :35. Reporting discipline: when the task mandates a
  machine-validated JSON output contract, the FINAL response must contain
  ONLY that JSON object — trailing prose bounces the whole response
  (validator: "Extra data: line N column 1 (char M)").
- **Behavioral round of the v1-only audit (2026-08-11, round 2 —
  signatures/SSE/idle)**: beyond residue + surface consistency, verify
  BEHAVIOR: (1) signature matrix — every client method vs EVERY call site
  incl. test fakes and scripts/ (all in-package call sites matched; the only
  breaks were scripts/). (2) SSE terminal contract — `server.instance.disposed`
  → StreamClosed (never yielded), EOF without terminal → StreamBroken
  (distinct); KEEP the `isinstance(dict)` guard in frame parsers when
  rewriting them — a valid non-object JSON frame (e.g. `data: [1,2]`) raises
  AttributeError at `.get("type")` and reads as a router crash, not a skipped
  frame (client.py:409-424 regression vs the old `_parse_frame`). (3)
  `POST /session` returns the BARE session object `{id, ...}` — NO `data`
  envelope; create_session must NOT unwrap (the v1 prompt route takes the
  PARTS body; the status map deletes entries on idle, absence=idle). (4)
  docstring-vs-code on pagination: `messages()` parses only the `Link`
  header while the module docstring promises `X-Next-Cursor`. (5) dead-branch
  sweep: unreachable `if status == 404` after `session_scoped=True` already
  raises in request() (client.py:287-288); no-op
  `except SessionNotFoundError: raise` (read.py:138-141). (6) lifecycle:
  `bridge.start()` is not idempotent — double-start leaks daemon
  router+approval worker threads. - **V1 LIVE runtime semantics (2026-08-11, post-migration live e2e — the
 findings static review missed)**: (1) **`POST /session/{id}/message`
 BLOCKS until the turn completes** (streams one final JSON); the
 non-blocking fork route is `POST /session/{id}/prompt_async` (204 No
 Content; body = same PromptPayload `{parts, agent?, model?, id?}`).
 client.prompt MUST use prompt_async or the HTTP call hangs past any
 sane timeout while the model works (live: 10s client timeout tripped;
 the turn still completed server-side, so it looks like a server bug).
 (2) **`GET /session/status` map lifecycle**: the entry appears when the
 forked turn STARTS (~1s after the prompt_async 204, `{type:"busy"}`)
 and is deleted on idle — absence at FIRST check = "not started yet",
 NOT "already done" (refines the older absence=idle claim). Blocking
 waits must be event-primary (`session.status idle`) with a saw-busy-
 gated map poll fallback; a naive early `absent ⇒ done` return resolves
 before the turn starts. (3) **MessageV1 shape**: `GET /session/{id}/message`
 returns `{info: {id, role, sessionID, time:{created}, modelID|model:
 {providerID, modelID}}, parts}` — flat `msg.get("role")` yields None so
 EVERY message shapes as "assistant" with no model/timestamp; shape from
 `info` (keep a flat fallback for fakes; user msgs nest `info.model`,
 assistant msgs carry flat `info.modelID`). (4) **SSE close mid-chunk**:
 `http.client.IncompleteRead` (HTTPException, NOT OSError) escapes read
 loops → the event router's blanket except logs a "router crashed;
 reconnecting" traceback on EVERY normal shutdown; map it to
 StreamClosed in the read loop for the quiet "event stream ended" path.
 (5) **e2e token matching**: prompt_async returns before the turn starts
 and the USER's own prompt contains the expected token — wait for an
 ASSISTANT row containing it (user row = false positive). (6) **live
 probes beat source reading** for shape/semantics: one-off scripts
 (status-map lifecycle timing, raw message JSON dump, bridge wait=True
 against a spawned server) — remember `load_bridge_config()` takes NO
 args (reads hermes_cli config); pass a cfg dict to Bridge directly like
 the tests do. Detail + live timings: `references/live-v1-runtime-verification-2026-08-11.md`.

- **Behavioral ROUND-2-RESTART verification (2026-08-12) — all 10 prior
  findings VERIFIED-FIXED, plus the moving-target audit pitfall**: the
  re-verification batch caught the maintainer fixing CONCURRENTLY with the
  audit (file mtimes moved 07:13-07:16, mid-run). Generalizing method
  lessons: (1) snapshot mtimes (`stat -f "%m %N" hermes_opencode/*.py`) and
  `git diff HEAD` BEFORE and DURING verification; a grep line-number
  mismatch against an earlier read = the file changed under you — re-read
  before judging. (2) A transient pytest failure mid-run can be the file
  changing under the runner (test_reconnect_after_stream_closed failed
  once, passed isolated + re-run; final 155 passed vs the briefed 153 — 2
  new regression tests). (3) ruff is a tripwire for freshly-landed text
  fixes: the finding-9 schema-text fix landed as one 149-char line → the
  sole E501. Resolved lifecycle fixes now in the tree: stale `_last_status`
  idle from a PREVIOUS turn of a reused session makes `wait_for_complete`
  resolve instantly — `EventRouter.forget(session_id)` (pops
  `_last_status`+`_waiters`) before each new turn's wait; wait=false
  reports `running=True` right after the 204 (status-map busy entry lags
  ~1s); stop() tracks `_owns_client` and nulls `_serve_handle` + owned
  `_client` so restart re-runs ensure_serve; `prompt_async` needs
  `session_scoped=True` (404 → SessionNotFoundError); shape_message guards
  non-dict info AND non-list parts with a created fallback chain
  info.time.created → flat msg['time'] → flat msg['created']; StreamClosed
  logging must not claim server.instance.disposed for mid-chunk closes.
  Residual new findings: `_INT` dead constant; `_delegated`/
  `_injected_questions`/`_pending_tails` never pruned (foreign-session
  tails buffered); stale `_down_reason` after later-successful start;
  `_dispatch` crash on a non-dict status (→ full reconnect); the
  `bool("false")` wait-coercion trap; cross-directory wait=true always
  blocks the full prompt_timeout (router sees only bridge-directory
  events). Full 18-finding table + the moving-target method:
  `references/behavioral-audit-r2r2-2026-08-12.md`.
- **Behavioral ROUND-3 verification (2026-08-12) — 7/7 fix groups VERIFIED-FIXED
  (157 tests green, ruff clean), 5 NEW (2 bug / 1 cleanup / 2 nit)**: all 8
  round-2R residuals landed (forget-before-wait, cross-directory `_wait_idle`
  branch + `session_status(directory)`, delegated idle guard + pop-on-delivery +
  stop/start clears, non-dict status guard, read.py parts/limit/created guards,
  `_INT` deleted + `_as_bool` + timeout text, MessageV1-shaped test fakes + 6
  regression tests). NEW: (1) **`_poll_status_idle`'s 0.5s poll granularity
  false-times-out fast turns** — the busy window (entry appears ~1s after the
  fork 204, deleted on idle) can slip entirely between two polls, and the first
  saw_busy read runs BEFORE the lag so it never seeds; analytic phase-jitter
  sim: 0.2s window → 3/5 false-timeout, 0.4s → 1/5; fix = 0.1s polls, KEEP
  saw_busy semantics (queued overlapping turns legitimately delay the entry).
  (2) **pop-on-delivery drops a SECOND overlapping wait=false turn on the same
  session** — single-slot `_delegated[s]` registration: first idle delivers +
  pops, second turn's idle hits the delegated guard → no inject, no buffer;
  fix = per-session in-flight counter, pop at zero. (3) `_on_idle` reads the
  tail BEFORE the delegated guard → discarded server read per foreign idle
  (hoist the guard). (4) non-dict `properties` unguarded in `_dispatch` →
  AttributeError → full reconnect (same family as the fixed status guard).
  (5) tail tool `limit` ignored when a buffered tail is consumed. Probe-method
  lesson: for timing-granularity claims prefer an ANALYTIC poll-schedule
  simulation (phase jitter over entry-delay/window) over wall-clock trials —
  real 0.5s×200-trial×5s-deadline runs time out at 240s; the schedule analysis
  + 4 short live trials settled it in seconds; staticmethod probes need
  `Bridge._poll_status_idle`, not a module import. Full 12-finding table:
  `references/behavioral-audit-r3-2026-08-12.md`.
- **Surface ROUND-3 verification (2026-08-12) — all 6 briefed fix groups
  VERIFIED-FIXED (ruff clean; 157 passed + 1 subtest; mtimes static, no
  moving target this round), 3 NEW findings + 1 STILL-PRESENT**: the
  briefed groups were the Round-2R NEW surface findings (text_msg fakes now
  real MessageV1 `{info:{id,role,modelID,sessionID,time:{created}},parts}`
  + session_status directory kwarg in test_bridge/test_tools; test_config
  defaults+overrides covering prompt_timeout/inject_turn_complete/
  directory/agent/model/question_reply_mode/question_clarify; e2e_smoke
  PROJ/tempfile removal; read_session default limit 8 + every tail_size
  fallback on 8 (bridge.py:175/213/446, tools.py:248/271, read.py:144);
  wiki port/requires_env/prompt_async/no-idempotency-key/no-retry-backoff/
  MessageV1-primary; read.py logging import gone). NEW findings generalize
  the four-layer method: (1) TEST-FAKE RECORDING fidelity — fakes that
  accept kwargs but record only a subset (FakeBridgeClient.prompt records
  just (session_id, text), dropping agent/model/directory; create_session
  drops directory) blind the suite to payload-forwarding regressions;
  record the full kwargs and assert the forwarding. (2) Schema params with
  bare types and NO description (opencode_command name/args/directory =
  `_STRING`) leave agents unguided — every param needs a description,
  directory params especially. (3) Directory-scope behavior must be ON the
  tool surface: wait=true for a directory != bridge directory polls the
  status map (the router never sees that session's idle event) and can
  hold the full prompt_timeout — schema + README still claim purely
  STILL-PRESENT: wiki/log.md [2026-08-10] entries still describe v2
  session.next.stop / v2-first permission_list as current with no
  superseded pointer. Full 11-finding table + clean-sweep
  confirmations: `references/surface-consistency-audit-round3-2026-08-12.md`.
- **Surface ROUND-4 verification (2026-08-12) — all 6 briefed R3 fix
  groups VERIFIED-FIXED (ruff clean; 161 passed + 1 subtest — suite grew
  +4 since R3; mtimes static, no moving target), 4 NEW + 3
  STILL-PRESENT**: briefed groups verified with file:line (opencode_command
  schema descriptions incl. cross-directory wait text tools.py:172-183/88-97;
  README prompt row matches README.md:87 + no other row drift; log.md
  superseded banners on both [2026-08-10] v2 entries log.md:34-35/:85-86;
  diag2_e2e.py citation annotated opencode-session-reading.md:72-73; fakes
  record full kwargs + test_prompt_forwards_config_agent_model_and_directory
  test_bridge.py:300-323; tail_size 8 across read/bridge/tools/config, test
  CFGs still inject 40). NEW: (1) the R3 bare-param fix covered ONLY
  opencode_command — 3 more schema params still bare `_STRING` (tail/read
  session_id, reply question_id, tools.py:114/131/154) — when a finding is
  a CLASS, sweep the whole class next round, not just the cited instance.
  (2) README prompt signature order (session_id? before the required
  prompt) drifts from schema property order — the one row that doesn't
  match. (3) the R3 cross-directory fix landed on schema+README but the
  wiki R1 blocking bullet (plugin-requirements.md:98-101) stayed
  event-only — same claim fixed on 2 of 3 surfaces; re-grep sibling
  surfaces for the OLD text after fixing one. (4) opencode-session-reading
  MessageV1 summary (:92-94) shows nested model only while the live v1
  wire carries flat info.modelID on assistant rows (user msgs nest
  info.model); the page's own :108 table covered both — summary lines lag
  the tables. STILL-PRESENT (all R1 findings, never in any briefed list —
  re-check PRIOR rounds' unfixed findings; the brief only covers the last
  round's groups): plugin-requirements.md:329-331 `GET /question` in the
  reconnect reconcile recipe (R1 #7, contradicts the page's own R2:142-143);
  __init__.py:42 requires_env password mislabel (R1 #13, optional secret
  shown as required); bridge/tools fakes still lack permission_list/
  permission_reply masked by attach_reconcile=False in both CFGs (R1
  #11/12, partially fixed — flipping the flag would AttributeError).
  In-page contradiction rule: a "Resolved questions" bullet that
  contradicts the page's own updated R-section is stale regardless of its
  section header — the header is history, the recipe is prescription.
  Full 13-finding table:
  `references/surface-consistency-audit-round4-2026-08-12.md`.
- **Surface ROUND-5 verification (2026-08-12) — 6/6 briefed R4 fix groups
  VERIFIED-FIXED (ruff clean; 165 passed + 1 subtest — matches the briefed
  count exactly, +4 since R4; mtimes static), 2 NEW (1 bug / 1 nit), zero
  STILL-PRESENT**: briefed groups verified with file:line (3 bare-_STRING
  schema params gained descriptions tools.py:114-117/134-137/160-163; README
  prompt row signature order README.md:87; plugin-requirements.md
  cross-directory caveat + GET /question dropped :102-104/:145-146;
  opencode-session-reading MessageV1 flat-modelID note :92-96; __init__.py:42
  requires_env lists BOTH username+password; fakes gained permission_list/
  permission_reply/question_reject/commands + test_reconcile_attached_rejects
  _stale_asks test_bridge.py:85-96/:337-350). NEW: (1) **client.prompt sends
  `payload[\"id\"]` but the real v1 prompt_async body field is `messageID`**
  (prompt.ts:1501 PromptInput; openapi.json:7173-7176 pattern `^msg` +
  additionalProperties:false → an `id` key 400s or is stripped) — and the
  unit test PINTS the wrong field + pattern-invalid value (test_client.py:61-68
  asserts `id`=="call-123"): a fake echoing the client's own payload can lock
  in a wire shape the real server rejects; re-derive asserted body field
  names from openapi.json/schema, and note the wiki was RIGHT here
  (opencode-http-api.md:31) while the code was wrong. Latent — no production
  call site passes message_id (bridge.py:458, tools.py:239-244). Do NOT
  confuse with the v2 REPLY `Admitted.id` (opposite surface, opposite field).
  (2) fake `permission_reply` param names drift (`decision`/`reason` in
  test_bridge.py:92/test_tools.py:87 vs real client + AskSurface protocol
  `reply`/`message` client.py:322-324/approval.py:51-53) — works
  positionally, but a keyword call would break tests-only; the TEST-FAKE
  fidelity layer must diff param NAMES, not just signatures/return shapes.
  Full 8-finding table: `references/surface-consistency-audit-round5-2026-08-12.md`.
- **Surface ROUND-6 verification (2026-08-12) — 2/2 briefed R5 fix groups
  VERIFIED-FIXED (ruff clean; 167 passed + 1 subtest), 2 NEW (both bug), zero
  STILL-PRESENT**: F1 verified (client.py:272 `payload["messageID"]` vs the
  real PromptPayload `{messageID pattern ^msg, model {providerID, modelID},
  agent, noReply, tools, format, system, variant, parts}` required [parts],
  additionalProperties:false) and F2 verified (all three fakes'
  permission_reply now `(rid, reply, message=None, directory=None)` matching
  AskSurface; wire reply bodies `{reply, message?}` / `{answers}` /
  no-body-reject all match groups/permission.ts + question.ts). NEW: (1)
  **create_session sends `model: {providerID, modelID}` but the v1 POST
  /session body requires Model.Ref `{id (required), providerID (required),
  variant?}`** (openapi.json requestBody; schema/src/model.ts:14-18;
  additionalProperties:false) — the create 400s whenever the bridge config
  `model` is set, while prompt_async legitimately wants the OTHER shape
  `{providerID, modelID}` (PromptInput ModelRef, prompt.ts:1494-1497):
  **one logical value, two wire shapes — shape per endpoint, never reuse
  one dict across routes**. (2) **read.py tool-part shaping reads top-level
  `name`/`input`/`output` but the real SessionV1.ToolPart is
  `{type:"tool", callID, tool, state:{status, input, output, error}}`**
  (schema/src/v1/session.ts:315-322; message-v2.ts page items carry stored
  parts verbatim) — live tool rows shape to tool_name="tool", arguments
  "{}", content None; the test fake test_read.py:24-36 encodes the SAME
  wrong shape so the suite cannot catch it — **a fake that mirrors the code
  under test's assumptions instead of the real wire contract locks in wire
  bugs; re-derive fake part shapes from schema/src/v1/session.ts, not from
  the shaper**. Full 4-finding table:
  `references/surface-consistency-audit-round6-2026-08-12.md`.
- **Residue ROUND-4 (2026-08-12) — CONVERGENCE: 11/11 briefed fix groups
  VERIFIED-FIXED (161 passed + 1 subtest, mtimes static, no moving
  target), ZERO CODE_PATH / ZERO STALE_DOC residue left** in code,
  scripts, tests, plugin.yaml/pyproject, README, or any of the 21 wiki
  pages. Every remaining v2 mention classifies EXPLANATORY (comment
  explaining v2 is unused; intentional negative test like
  test_read.py:151 asserting `scope="context"` RAISES; banner-marked
  reference pages; opencode-server-surface docs) or HISTORICAL-LOG
  (dated append-only log entries — accept as history unless they read as
  current; the two round-3 STILL-PRESENT log.md entries now carry the
  superseded banners, closing that finding). One nit: fix 2 landed the
  `_delegated` `in_flight` counter but left the inline shape comment at
  `{"last_fp"}` — **a fix that changes a structure must update the
  comment that DESCRIBES it; comment-drift is a fix-surface class, check
  it during verification** (bridge.py:70). Convergence-round discipline:
 'NO NEW FINDINGS is a valid result'; run the full deleted-name grep
 list and classify EVERY hit into the four buckets before declaring
 clean. Full verification table + classification:
 `references/residue-sweep-r4-2026-08-12.md`.
 - **Residue ROUND-5 (2026-08-12) — convergence HELD: 2/2 frontmatter bumps
 VERIFIED (`updated: 2026-08-11` on plugin-requirements.md and
 opencode-permissions.md), ZERO CODE_PATH / ZERO STALE_DOC again across
 code, scripts, tests, plugin.yaml/pyproject, README, all 24 wiki pages**;
 prior STILL-PRESENT items re-verified fixed (permissions.md:53
 reference-only, plugin-requirements.md:146 no-`GET /question`, fakes
 implement permission_list/permission_reply). Two open items: (1) the R4
 report-file nit (bridge.py:70 `_delegated` comment says `{"last_fp"}`
 while entries carry `in_flight` :232/:463) is STILL PRESENT — the R5
 brief claimed R4 found "exactly 2 findings" and omitted it, so **the
 round's reference FILE is ground truth, not the brief; re-check
 report-file items the brief drops**; (2) __init__.py:42 requires_env
 password mislabel stays a surface-loop item. New method lessons: (1) a
 terminal rg pattern containing a single quote SILENTLY returns 0 hits
 (shell-quoting break) — run deleted-name greps via tool-level ripgrep
 (search_files) and sanity-check 0-hit results against a must-match
 pattern; (2) the per-file hit-count sweep (`rg -i -c 'v2|/api/' …`) is
 the completeness check — classify every listed file, files absent are
 provably clean; (3) disambiguate Hermes version-string hits (`v2026.8.3`
 in README/wiki sources) from v2-API mentions before bucketing; (4)
 non-v2 findings still must fit the mandated JSON bucket enum — pick the
 least-wrong bucket and label "non-v2" in the description. Full table:
 `references/residue-sweep-r5-2026-08-12.md`.
 - **Residue ROUND-6 (2026-08-12) — convergence HELD, 3rd round; the R4 bridge.py
   nit is VERIFIED-FIXED at :75**: the `_delegated` shape comment now reads
   `# wait=false sessions: {"last_fp", "in_flight"}` — R5's "still present"
   report-file item is CLOSED. ZERO CODE_PATH / ZERO STALE_DOC again across code,
   scripts, tests, plugin.yaml/pyproject, README, all 24 wiki pages; all 528 raw
   `v2|/api/` hits classify EXPLANATORY / HISTORICAL-LOG / Hermes version string
   (`v2026.8.3`) or sit in excluded vendored-clone noise (`.slim/clonedeps`).
   New method lesson — **briefed file:line references go STALE as fix work grows
   the file**: the brief said bridge.py:70 but the comment now lives at :75
   (bridge.py gained ~5 lines of fix work since R4). Verifying by the briefed
   line number alone would false-FAIL a correctly-landed fix; re-locate by
   CONTENT (grep the comment text), confirm semantics, then report the CURRENT
   line so the next round re-verifies a live number. Line-number drift ≠
   regression. Also re-confirmed: mtime snapshot before/after the sweep is the
   moving-target guard, and uncommitted fix work on top of the last commit
   (19 modified files + `uv.lock`) is the NORMAL mid-audit state, not a failure.
   Full table: `references/residue-sweep-r6-2026-08-12.md`.

 - **Audit ROUND-3 fixes landed; ROUND-4 convergence dispatch (2026-08-12)**:
  the 8 round-3 findings fixed + verified (161 passed, ruff clean, e2e 6/6
  live). Fix patterns worth reusing: (1) OVERLAPPING async turns on one
  session -> per-session `in_flight` counter in the notification registry
  (increment on register, decrement on delivery, pop at zero, keep the
  fingerprint while a sibling turn runs) - a single-slot registration drops
  the second turn's completion notification; (2) status-map busy-window
  phase jitter -> poll at 0.1s, never >=0.5s (the busy entry lags ~1s after
  the prompt_async 204 and a fast turn can slip entirely between polls;
  keep saw_busy semantics - queued overlapping turns legitimately delay the
  entry); (3) hoist foreign-session guards ABOVE the speculative read (an
  idle event for a non-delegated session must cost zero server
  round-trips); (4) a tool's `limit` must slice BUFFERED rows too, not just
  live-read fallbacks, or the schema over-promises; (5) audit convergence:
  `__pycache__` regenerates on EVERY test run - purge after the final
  verification pass, and de-list it in audit briefs (gitignored, not a
  finding). Test-cascade trap: extending a fake's recorded tuple shape
  (adding agent/model/directory to `.prompts`/`.created`) breaks EVERY
  assertion comparing the recorded list - grep all assertion sites first;
  and the test harness CFG's `directory` key ("/proj") flows into the
  recorded kwargs, so expectations must carry it (2 red runs: 5 then 2
  failures). Detail + the round-4 verification-first brief:
 `references/audit-round3-fixes-and-round4-dispatch-2026-08-12.md`.
 - **Behavioral ROUND-4 verification (2026-08-12) — 6/6 briefed R3 fix groups
 VERIFIED-FIXED (82 passed + 1 subtest on the 4-file targeted suite), 7 NEW
 (2 bug / 2 cleanup / 3 nit), zero STILL-PRESENT**: verified with file:line
 (0.1s poll bridge.py:528; in_flight counter :459-463/:226-239 pinned by
 test_overlapping_wait_false_prompts_both_notify; hoisted delegated guard
 :174-180; non-dict properties guard events.py:177-178; buffered-tail limit
 slice tools.py:266; stop() clears :152-157). NEW: (1) **stale-idle-after-
 forget race** — `forget()` clears only RECORDED state; an idle frame
 dispatched AFTER forget resolves wait_for_complete instantly (reproduced:
 0.000s True): a wait=true prompt on a reused/busy session returns
 "completed" on the PREVIOUS turn's idle with a stale tail; require a busy
 observation after forget (or tail advancement vs a pre-turn fingerprint)
 before accepting idle as completion. (2) **fp dedup defeated by tail
 advancement** — a reconnect-resend/duplicate of an already-delivered idle
 re-injects a FALSE turn-complete while a second overlapping turn runs AND
 pops in_flight to 0, so the second turn's completion never notifies
 (reproduced: 2 injections, 2nd spurious, turn-2 delivery missed); dedup on
 the idle's turn identity (properties.messageID when present), decrement/
 pop only at in_flight==1. (3) in_flight bookkeeping is gated behind inject
 success → entries never reaped when inject_turn_complete=False or gateway
 mode (decouple bookkeeping from delivery). (4) the non-dict-properties
 guard is ASYMMETRIC — _on_question/enqueue_question still `or {}` a list →
 AttributeError swallowed → ask silently dropped (reject mode never rejects
 → session wedges); sweep all consumers when a dispatcher guard lands.
 Probe-method lesson: **SIMULATE, don't just read** — import the REAL
 Bridge/EventRouter with scripted in-memory fakes and replay the event
 sequences (duplicate idle, stale frame after forget, message page
 advancing between deliveries); each suspected race became a ~10-line
 experiment and all hypotheses reproduced with zero repo edits (use the
 analytic phase-jitter method from r3 for timing claims, live simulation
 for state-machine claims). Full 13-finding table:
 `references/behavioral-audit-r4-2026-08-12.md`.
 - **Behavioral ROUND-5 verification (2026-08-12) — 4/4 briefed R4 fix groups
 VERIFIED-FIXED (86 passed + 1 subtest on the 4-file suite, +4 tests since R4;
 mtimes static), 5 NEW (2 bug / 3 nit), zero STILL-PRESENT**: verified with
 file:line (needs_busy/saw_busy lifecycle events.py:75-76/125-129/147-151/
 161-163/210-228 pinned by test_stale_idle_after_forget + the real-wire-order
 test_prompt_waits_for_idle_event; _on_turn_complete bookkeeping BEFORE the
 inject gate bridge.py:225-240/461-465; isinstance guards bridge.py:305-306 +
 approval.py:170-171; command-schema note + tail upgrade + hoisted foreign guard
 tools.py:170-179/264-276 + bridge.py:174-183). NEW: (1) **zero-row completion
 dedup'd as a duplicate** — the fresh-fork last_fp reset to "" (bridge.py:464)
 makes fp=="" (empty shaped tail: empty session, reasoning-only parts) equal to
 last_fp, so _on_turn_complete returns early: missed delivery + PERMANENT
 `_delegated` leak + the session permanently defeats the foreign-idle guard
 hoist; (2) **stale idle still fires `_on_idle`** — the wait path's stale guard
 (events.py:215-220) does not gate the :227-228 callback, so a previous turn's
 DELAYED idle frame (no duplicate needed — R4's "unreachable" claim covered
 DUPLICATE frames only) is misattributed to a fresh wait=false turn (the last_fp
 reset re-opens the dedup window): spurious turn-complete + premature pop, real
 completion never notified; (3) fork-then-forget ordering (bridge.py:458 then
 :502) lets forget() discard a fresh-turn busy that lands in the microsecond
 window — event path dead, full timeout burn, result masked by the status
 re-read; (4) _needs_busy/_saw_busy never pruned for sessions that never
 complete; (5) fake session_status drops the directory kwarg (recording-fidelity
 class unswept). Method lessons: attack a prior round's "unreachable on the
 wire" claim at its ASSUMPTIONS (duplicates? replay? per-transition count?), not
 its conclusion — one delayed frame reached the same failure shape; a fix that
 RESETS a dedup key to "" must be checked in BOTH directions (empty tail =
 miss/leak, unchanged tail = spurious deliver); verify a decoupled-bookkeeping
 fix by asserting the REAP guarantee (`_delegated` empty after every completion
 shape), not just the delivery. Full 10-finding table + reproduction recipes:
 `references/behavioral-audit-r5-2026-08-12.md`.
- **Behavioral ROUND-6 verification (2026-08-12, convergence) — 7/7 briefed R5
 fix groups VERIFIED-FIXED (167 passed + 1 subtest full suite, 88 + 1
 targeted, ruff clean, mtimes static), 5 NEW (3 bug / 2 nit), zero
 STILL-PRESENT**: verified with file:line (fork-time baseline
 bridge.py:56-58/:480-491/:236 + tests test_bridge.py:290-303/:305-326;
 forget-before-fork bridge.py:468-474; events.py stop() prunes :100-105;
 fake status_dirs test_bridge.py:51/:70 + test_tools.py:50/:68 + cross-dir
 poll pin :328-345; permission_reply (rid, reply, message=None, directory=None)
 on all 3 fakes = AskSurface approval.py:51-53; client.py:269-272 messageID +
 test_client.py:61-70; bridge.py:75 comment). NEW: (1) **overlapping-fork
 baseline consumption** — fork#2's fork-time baseline read after turn-1 rows
 commit makes idle#1's tail == fork#2 baseline → skipped as duplicate →
 turn-1 completion never delivered + in_flight stuck >=1 forever (regression
 vs pre-R5 ''-reset; the pinned overlap test only covers the LUCKY same-tail
 ordering, while fork#2 seconds later reading already-committed rows is the
 COMMON one); (2) **zero-row fix incomplete** — "empty fp always delivers"
 covers only the empty-tail case; a zero-row completion with a NON-EMPTY
 baseline (session with history) is dedup'd as duplicate → missed + permanent
 leak (also a regression); (3) **stale-busy seeds _saw_busy** —
 forget-before-fork can't stop an in-flight prior-turn busy frame; it
 re-seeds saw_busy, so the prior turn's idle resolves wait_for_complete EARLY
 (timed_out=False with the prior tail while the fresh queued turn runs) —
 busy-side mirror of the R4 stale-idle race, window wider than it looks
 because the single router thread runs _on_idle (server round trip) inline
 and frames backlog; (4) zero-row overlapping duplicate idle pops in_flight
 to 0 → second turn's real completion never notifies (inherent: replay
 indistinguishable without a fingerprint); (5) cross-directory wait=true calls
 forget() on sessions the router never sees → _needs_busy residue until
 stop(). KEY INSIGHT: **the router clears _saw_busy on EVERY idle dispatch
 (events.py:228-229) — "busy observed since the last dispatched idle" is the
 signal that separates a genuine completion (fp == baseline, turn ran) from a
 duplicate replay (fp == baseline, no new busy); a has_busy_since_idle(sid)
 accessor fixes findings 1/2/4 at once and keeps test_delayed_prior_idle
 green (its delayed idle follows an idle dispatch that cleared saw_busy)**;
 finding 3 needs a forget-generation stamp instead. Method lessons: (a) a
 dedup-key fix must be checked in BOTH baseline directions — R5 checked
 empty-tail zero-rows but the non-empty-baseline unchanged-tail variant
 regressed (enumerate (empty/non-empty baseline) x (advanced/unchanged
 tail)); (b) a race-pinning test that only asserts the LUCKY interleaving
 passes while the realistic ordering leaks — ask which ordering the real
 wire produces and pin that too; (c) un-fixable overlap cases share an
 information-theoretic root: v1 idle/busy events carry no turn identity, so
 overlapping-turn accounting needs a side signal (busy-since-idle /
 forget-generation / per-fork messageID) — report the ambiguity and propose
 the signal, not a wishful fix. Full 12-finding table:
 `references/behavioral-audit-r6-2026-08-12.md`.
 - **Audit ROUND-5 fixes landed; ROUND-6 dispatch (2026-08-12)**: all Round-5
 findings fixed + verified (167 passed + 1 subtest, ruff clean, e2e 6/6 live,
 live wait=true + fork probe green). The dedup saga's SETTLED design: the
 fork-time tail baseline — `last_fp` starts at the fp of the tail read
 prompt() already performs (bridge.py:490), so a delayed prior-turn idle
 equals the baseline (skipped) and empty fingerprints always deliver
 (`if fp and fp == last_fp`), fixing BOTH the zero-row leak and the
 delayed-idle misattribution; a separate `fork_fp` key is redundant (the
 baseline subsumes it). Also: forget-before-fork re-arm ordering
 (bridge.py:468-473 — a fresh busy must land after the re-arm), events.py
 stop() prunes _needs_busy/_saw_busy/_last_status, fake status_dirs
 recording, permission_reply renamed to AskSurface `(rid, reply, message,
 directory)`, and `payload["messageID"]` (was "id") with a pattern-valid
 test pin. Test-conversion trap: with baseline semantics the fake page must
 advance BEFORE each completion but the FORK read must see the PRE-turn page
 (setting the advanced page before the prompt makes the fork capture it as
 baseline → completion skipped → 1 != 2). Detail + live probe evidence +
 the round-6 verification brief:
 `references/audit-round5-fixes-and-round6-dispatch-2026-08-12.md`.

 Verified v1 contract + full findings:
 `references/v2-deletion-v1-only-audit-2026-08-11.md`.
- `session.compact`, `session.shell`, `session.skill` v2 endpoints are likewise
  declared-but-stubbed (503) at this tag; `GET /api/health` exists for liveness.

  Full seam audit with file/line map and the wiki-contrast list:
  `references/integration-seams-v1-18-13-audit.md`.
- **ROUND-2B audit corrections (2026-08-09) — beyond the R2 list**: the v2
  `/api/event` stream dies on v1-only event types (see SSE pitfall above);
  opencode NEVER returns busy on prompt (v2 maps only NotFound/Conflict,
  server/src/handlers/session.ts:140-170; v1 `prompt`/`promptAsync` have no
  `mapBusy`, instance handlers/session.ts:295-329 — `mapBusy` only wraps
  shell/revert/deleteMessage) so overlapping prompts are admitted and queue
  invisibly — the bridge's wait-loop is the ONLY serializer; instance dispose
  fails pending asks silently (question service `addFinalizer` rejects
  deferreds without publishing `question.rejected`, question/index.ts:74-81 —
  treat stream-close as reject-all-pending + REST reconcile); v1 `/event`
  stream drops events with UNDEFINED location even on "global" subscriptions
  (instance handlers/event.ts:36-38 `event.location?.directory ===
  instance.directory`) and uses `Queue.unbounded` (:31); Hermes v2026.8.3 has
  NO plugin unload/dispose/atexit hook (hermes_cli/plugins.py) — the bridge
  must own subprocess teardown itself; `plan_exit` is question-backed
  (tool/plan.ts:30-44) so plan-mode completion emits `question.asked`.
  Full details: `references/seam-audit-round2b-v1-18-13.md`.
- **Hermes plugin user config**: no `ctx.config`/`get_config` helper exists —
  read `plugins.entries.<plugin_id>.*` from config.yaml via `load_config()` +
  `cfg_get` (hermes_cli/config.py:2886); users set keys via
  `hermes config set plugins.entries.<id>.<key> <value>`; secrets via
  manifest `requires_env:` + `.env` (`references/hermes-plugin-user-config.md`).
- **Hermes-side ROUND-2 audit (2026-08-09)**: the plugin-path `rule_key`
  default is per-TOOL (`plugin_rule:<tool>`), NOT the documented
  reason-hash default — `resolve_pre_tool_block` passes
  `rule_key=details.rule_key or tool_name` (plugins.py:2284), so the
  `approval.py:3349-3353` sha256 derivation never fires from pre_tool_call.
  Plus: three distinct "no-human" shapes per entry point
  (`approval_required` / `pending_approval`+redacted payload /
  `"decline"`), `request_elicitation_consent` fifth entry point
  (`accept|decline|cancel`, `allow_permanent=False` on CLI), permanent
  allowlist is load-at-import only (approval.py:4350-4351), and
  `unregister_gateway_notify` unblocks ALL queued threads.
  Details+citations: `references/hermes-approval-gate-bridge.md`.
- **Hermes-side ROUND-3 audit (2026-08-09)** — new gaps beyond R2:
  - **Thread tool whitelist** (`set_thread_tool_whitelist`/`clear_thread_tool_whitelist`, plugins.py:2108-2118) is a hard per-thread gate checked BEFORE `pre_tool_call` hooks (plugins.py:2140-2143) — non-whitelisted tools block outright, the plugin `approve` escalation never fires; only consumer is background_review.py:903 (memory/skills-only review forks).
  - `pending_approval` is NOT execute_code-only: `check_all_command_guards`' no-callback fallback returns the same shape (approval.py:3905-3927; the in-code comment at :3904 even says "approval_required" while the code returns `pending_approval`).
  - `[a]lways` persists permanently only for non-tirith warnings on the dangerous-command path (approval.py:3893-3900); CLI hides it when no permanent-capable warning (:3942-3947). Plugin path (request_tool_approval) unaffected.
  - `approvals.*` namespace also carries `timeout` (default 300, approval.py:2798-2809), `smart_policy`, `denial_breaker_threshold` (3), `deny` (config_defaults.py:2052-2075) — wiki documents only mode/cron_mode.
  - Plugin kinds beyond backend/standalone: `exclusive` (needs `<category>.provider`) and `model-provider` (skips plugins.enabled) (plugins.py:283, :1411-1435).
  - cronjob actions are `create|list|update|pause|resume|remove|run` (cronjob_tools.py:1051), not create/edit/list/delete/run.
  Full findings + citations: `references/hermes-wiki-audit-round3-v2026-8-3.md`.
- **Integration-seam ROUND-3 (2026-08-09)** — contract gaps, not regressions:
  - `GET /api/session/active` tracks the **v2 coordinator's active set only**
    (server handlers/session.ts:81-88 → core/session/execution/local.ts:31-36,
    `active: coordinator.active`) — a v1-run session NEVER appears, so the
    blocking handoff "works for both surfaces" overclaims; for v1 sessions
    consume `session.status idle` or event quiescence + client timeout.
  - Resolving `"always"` makes the **server** resolve same-session siblings
    itself and publish `permission.replied {reply:"always"}` for each
    (permission/index.ts:160-164) — the bridge never sends `"always"` but the
    fan-out publishes it. Across a reconnect gap the bridge saw neither the
    sibling asks nor their replies; reconcile must treat same-session asks
    that are no-longer-in-pending as auto-approved `once` (never re-ask,
    never reject) — else Hermes' allowlist diverges from opencode's.
  - Startup stale-ask rejection races that fan-out: order reconcile AFTER
    stream quiescence (one heartbeat/idle cycle with no permission events).
  - Bound port is not the configured port: `serve` defaults `--port 0` and
    silently rebinds via a 4096-first fallback (server.ts:117-121); the
    stdout banner `opencode server listening on http://…`
    (cli/cmd/serve.ts:20) is the only reliable signal — auto-serve must
    parse it, like the JS SDK spawner does.
  - Round-3 opencode-side = **CONVERGENCE**: zero actionable findings (all
    prior fixes verified correct; only line-range nitpicks). The round-2
    mid-verification item was closed: v1 `GET /event` DOES declare
    `WorkspaceRoutingQuery` (groups/event.ts:19-25) + InstanceContext +
    WorkspaceRouting + Authorization middlewares — `?directory=` on the v1
    SSE stream is valid.
  Full detail + verification cites: `references/seam-audit-round3-v1-18-13.md`.
- **ROUND-4 audit (2026-08-09) — fresh 10-page re-verification**: round-3
  convergence held, but 2 NEW substantive contradictions surfaced:
  - **`ReplyInput` has NO `sessionID`** — the permissions wiki claims
    `{sessionID, requestID, reply}`; the schema is `{requestID, reply,
    message?}` (schema/src/v1/permission.ts:56-58). `sessionID` lives only on
    the `permission.replied` EVENT payload (same file :62-65, published
    permission/index.ts:115-119). Never expect sessionID on the reply input.
  - **`GET /api/session/{id}/message` (plural) does not exist on the V2
    surface** — only SINGULAR `session.message`
    `/api/session/:sessionID/message/:messageID` (protocol/groups/session.ts:360);
    the plural read is V1-only (`GET /session/:sessionID/message`, instance
    httpapi groups/session.ts:85,179). A wiki row claiming a v2 plural
    message-list route must be deleted/relabeled.
  - Precision slips: dispose-finalizer cite off (permission/index.ts:54-61,
    not :74-81), full-manifest cite (event-manifest.ts:70/76 not 63-74),
    `system?` omitted from the legacy prompt-body enum
    (types.gen.ts:2588-2601), and **`GET /experimental/tool` requires
    `provider`+`model` query params** (400 without, groups/experimental.ts:57-61).
  Full per-finding cites + verified-clean matrix + audit method:
  `references/wiki-audit-round4-v1-18-13.md`.
- **Integration-seam ROUND-5 (2026-08-09) — fresh 9-page contract audit, 1 NEW
  substantive finding**: the v2 durable read surfaces (`GET /api/session/:id/
  history`, `/context`, `/message/:id`, `/event?after=`) return **EMPTY
  (200, `{data:[],hasMore:false}` — never 404) for sessions run by the v1
  classic runner** — the exact population whose idle signal is the v1
  `session.status` event. Durable events are written ONLY by v2-core modules
  (`durable:` exists only on session-event.ts:39,45; all SessionEvent
  publishers live in packages/core/src/session/*), and `SessionMessageTable`
  is written only by the v2 projector; v1 persists to legacy `message`/`part`
  tables, readable solely via cursor-paginated `GET /session/{id}/message`
  (instance handlers/session.ts:106-145) — a tail/range mechanism the wiki
  never specifies. A shared `SessionTable` masks the emptiness as a 200, not a
  404. **Route tail/range reads by engine; never feed v2 history/context with
  v1-idle sessions.** Documented proof chain:
  `references/seam-audit-round5-v1-18-13.md`.
- v2 plugin API (`@opencode-ai/plugin/v2/promise` and `v2/effect`) is experimental: `interface Plugin { id; setup(ctx) }` with per-domain registries (agent/aisdk/catalog/command/integration/reference/skill) and `Registration.dispose()/reload()`. Use the v1 hooks for stable deliverables.
- SDK directory routing: pass `directory` to `createOpencodeClient` → sets `x-opencode-directory` header; GET requests are rewritten to carry it.
- The `tui` export is a separate surface (renderer/keybinds); a module can export `server` or `tui`, not both.

## References

- `references/opencode-plugin-api-v1-18-13.md` — the verified source map: full type quotes, hooks catalog with fire sites, tool/schema, config & opencode.json registration, permission model, SDK client+server annotated example, message-injection APIs, v1.18.13 version-specific notes, key-file table, and the recon commands used.
- `references/bridge-surfaces-question-commands-permissions-v1-18-13.md` — serve mode, question tool, permission deny-with-reason, slash-command registry over HTTP (the non-TUI set), v2 plugin fragments.
- `references/session-reading-tail-ranges-v1-18-13.md` — session reading for the bridge: idle signals (modern `session.status` vs legacy; `wait` is a 503 stub — active-poll is the handoff), v2 history/context endpoints, Hermes-row shaping, the E2E-verified v1.18.13 durable family (`prompt.admitted`/`prompted` dedupe, `step.*` — no `start`/`stop`), `/event` `?directory=` query-vs-header stall, Python chunked `read(n)` → `read1(n)` pitfall, and the file-logged/raw-socket probe methodology.
- `references/hermes-approval-gate-bridge.md` — the Hermes-side half: route opencode `permission.asked` through Hermes' OWN approval gate (`tools.approval.request_tool_approval` / `pre_tool_call` `{"action": "approve"}` directive), gate result → opencode `once/always/reject` mapping, deny-with-reason, allowlist grain, contextvar plumbing, v2 operationId method names, and the SETTLED design decisions (no approval cache, FIFO queue, smart-mode + origin marker, shared 300s timeout, deny reason Option A).
- `references/repo-wiki-maintenance.md` — editing the in-repo requirements wiki (`<repo>/wiki/`): evidence-first rule, log.md append-merge pitfall, chunked writes, patch-over-rewrite, lint-before-finish.
- `references/question-gate-answer-v1-18-13.md` — the settled question design (2026-08-10, gate REMOVED): `question_reply_mode=tool` default (ask injected into the main agent's conversation once, held, answered by id via `opencode_question_reply`), mode table (`tool`/`auto_first`/`reject`; `gate` invalid → falls back to `tool`), bridge `_on_question`/`_inject_question` + approval `_handle_question` implementation map, fail-closed guard for unanswerable asks, the whitelist-filtered-config-key dead-key pitfall, and the test recipe (7 gate tests replaced by 12 tool/auto_first/reject tests, plus FakeCtx + pyright-narrowing patterns). NOTE: `auto_first` was DELETED later the same day (see the questions pitfall in SKILL.md) — the mode table here predates that.
- `references/question-clarify-relay-2026-08-10.md` — human relay via the Hermes clarify panel (`question_clarify`, opt-in): how the bridge reaches `cli._clarify_callback` through `ctx._manager._cli_ref`, calls it outside the agent loop (zero transcript rows), maps option labels to panel choices (cap 4, custom-only → open-ended), the timeout-sentinel fallback to inject+hold, FIFO-worker threading constraints, and the test recipe.
- `references/hermes-plugin-packaging-entry-point.md` — pyproject/pip entry-point plugin format: `[project.entry-points."hermes_agent.plugins"]`, entry module must expose `register(ctx)`, directory plugins load as `hermes_plugins.<slug>`, the lazy import-free root-shim pattern (pytest imports root `__init__.py` bare when `tests/` has `__init__.py`), PEP 639 license-conflict, `*.egg-info/` gitignore, plugin.yaml/registry sync, and the editable-install round-trip verification.
- `references/hermes-plugin-loader-symlink-2026-08-10.md` — the loader contract for DIRECTORY plugins (2026-08-10): spec_from_file_location import, no sys.path, SILENT register() failure, the verified relative-first shim + relative package imports, the scrub-sys.path subprocess regression test (fake ctx must implement the REAL `register_tool`; `config={"auto_serve": False}` to avoid a serve spawn; f-string `{{}}` pitfall), and the symlink install (no sync ritual, no fetch/reset through the symlink). (2026-08-11 UPDATE: the committed regression test was REMOVED on user directive — run the loader replication as a one-shot probe instead; see the serve-lifecycle reference.)
- `references/repo-release-prep-2026-08-10.md` — GitHub release prep for the plugin repo: marker-comment scrub (wiki keeps its R-tags), author + LICENSE, dropping scratch diagnostics, `rebase --root --exec` author rewrite (commit-first order), installed-plugin refresh via fetch+reset (not pull) after SHA rewrites, and the ruff/inherited-env/od-c verification pitfalls. (2026-08-10 UPDATE: the installed copy is now a symlink to the repo, so the refresh step is GONE — see the loader/symlink reference.)
- `references/serve-lifecycle-ownership-2026-08-11.md` — serve lifecycle (2026-08-11): TUI double-load (agent+gateway, two config warnings), probe-first auto_serve contract (attach if healthy / strict-fail on auth mismatch / spawn if unreachable), spawn ownership (ServeHandle only on spawn; attached servers never stopped), the EADDRINUSE loser crash signature, serve-log unlink evidence trap + `~/.local/share/opencode/log/` tracebacks, process/port reconstruction commands, the exception-layering rule (_health_ok propagates raw), the doc/manifest surface-sync directives (affirmative framing, keep tables, drop stale counts), and the removed-shim-test policy (one-shot loader replication instead).
- `references/surface-consistency-audit-v1-only-2026-08-11.md` — surface-consistency audit (2026-08-11, round 3): the four-layer method (tool surface registry↔manifest↔README↔test asserts; config read↔consumed↔documented with the dead/undocumented/dead-read key classes; docs-vs-code incl. scripts/ residue; test-fake signature+shape fidelity and config-masked missing methods), the verified v1-only surface inventory (client methods, 5 tool schemas, config dict keys, banner-marked wiki pages), and the 13 findings (4 bug / 3 cleanup / 6 nit) with file:line.
- `references/v1-only-migration-residue-audit-2026-08-11.md` — the v1-only migration + round-1 residue audit (2026-08-11): what was deleted (client routes, event families, read engines, ask routing) and what was renamed (create_session/prompt/session_status), the v2-residue grep checklist (deleted method/param/route/event names), the unit-suite blind spot (scripts/e2e_smoke.py not covered by pytest), static staleness proof (`inspect.signature`/`hasattr`), the CODE_PATH/STALE_DOC/EXPLANATORY classification, the banner-vs-stale-wiki rule, and the 3 findings with fixes (e2e_smoke.py:115 active_sessions→session_status, e2e_smoke.py:125/134 engine="v2" removal, opencode-permissions.md:47-48 v2-first reconcile claim).\n- `references/v2-deletion-v1-only-audit-2026-08-11.md` — the v1-only migration
  BEHAVIORAL audit (2026-08-11, round 2): verified v1 contract (POST /session
  bare `{id}` no envelope, parts-body prompt, `GET /session/status` absence=idle,
  `GET /command`, `/global/health`, SSE disposed→StreamClosed vs EOF→StreamBroken,
  WorkspaceRoutingMiddleware `defaultDirectory()` = query || header || cwd), the
  10 findings with fixes (2 bugs in scripts/e2e_smoke.py, dead 404 branch,
  no-op except, `_parse_sse_frame` dict-guard regression, Link-only pagination,
  `prompt_timeout` dead key, `start()` non-idempotency, `question_registry_get`
  test-only), and the signature-matrix + git-diff-classification audit method
  (pre-existing-but-broken-by-deletion call sites are still migration bugs).
- `references/behavioral-audit-r2r2-2026-08-12.md` — behavioral ROUND-2-RESTART verification (2026-08-12): the moving-target audit method (mtimes, grep-vs-read line mismatch = file changed under you, transient pytest failure = file changing under the runner, verify by semantics not line numbers), the 10-finding VERIFIED-FIXED table (forget-before-wait, running=True after 204, _owns_client stop/start, session_scoped prompt_async, shape_message guard chain, StreamClosed log wording, timeout-schema text), and the 8 residual NEW findings with line numbers.
 - `references/behavioral-audit-r3-2026-08-12.md` — behavioral ROUND-3 verification (2026-08-12): the 7 briefed fix groups VERIFIED-FIXED with file:line evidence (forget-before-wait, cross-directory _wait_idle + session_status(directory), delegated idle guard + pop-on-delivery + stop/start clears, non-dict status guard — with the missing test-pin gap, read.py guards, tools.py _INT/_as_bool/timeout text, MessageV1 fakes), 5 NEW findings (0.5s poll-granularity false timeout with the analytic phase-jitter simulation numbers, pop-on-delivery dropping an overlapping second turn, foreign-idle discarded tail read, non-dict properties → reconnect, tail limit ignored on buffer), and the analytic-schedule-over-wall-clock probe method.
- `references/behavioral-audit-r4-2026-08-12.md` — behavioral ROUND-4 verification (2026-08-12, convergence round): the 6 briefed R3 fix groups VERIFIED-FIXED with file:line evidence, 7 NEW findings (stale-idle-after-forget race — forget() protects only recorded state, reproduced 0.000s instant resolve on wait=true session reuse; fp dedup defeated by tail advancement between duplicate idle deliveries — false re-inject + premature in_flight pop so the overlapping turn never notifies; in_flight bookkeeping gated behind inject success; asymmetric non-dict-properties guard at the question consumers), the checked-OK items (poll seed timing, wait=false existing-session counter, consume_tail aliasing), and the SIMULATE-don't-just-read method (import the real Bridge/EventRouter with scripted in-memory fakes and replay event sequences to prove state-machine races with zero repo edits).
- `references/behavioral-audit-r5-2026-08-12.md` — behavioral ROUND-5 verification (2026-08-12): the 4 briefed R4 fix groups VERIFIED-FIXED with file:line evidence (needs_busy/saw_busy lifecycle, _on_turn_complete bookkeeping-before-gate, isinstance guards, command-schema note + tail upgrade + hoisted foreign guard), 5 NEW findings (zero-row completion dedup'd as duplicate, stale idle still fires _on_idle, fork-then-forget ordering, never-pruned needs_busy/saw_busy, fake session_status directory drop), and the method lessons (attack prior-round 'unreachable' claims at their assumptions, check a dedup-key reset in BOTH directions, assert the reap guarantee not just delivery).
- `references/behavioral-audit-r6-2026-08-12.md` — behavioral ROUND-6 verification (2026-08-12, convergence): the 7 briefed R5 fix groups VERIFIED-FIXED with file:line evidence (fork-time baseline, forget-before-fork, events.py stop() prune, fake status_dirs, permission_reply AskSurface names, messageID field, _delegated comment), 5 NEW findings (overlapping-fork baseline consumption — fork#2's baseline eats turn-1's completion → permanent in_flight leak; zero-row fix incomplete for non-empty baselines; stale-busy seeds _saw_busy → early wait resolve; zero-row duplicate-idle pop; cross-directory forget _needs_busy residue), the KEY INSIGHT (router clears _saw_busy on every idle dispatch → has_busy_since_idle(sid) separates genuine completions from duplicate replays and fixes findings 1/2/4 at once), and the method lessons (check a dedup-key fix in BOTH baseline directions — the non-empty-baseline unchanged-tail variant regressed; a race-pinning test asserting only the LUCKY interleaving passes while the realistic one leaks; un-fixable overlap cases share an info-theoretic root — v1 events carry no turn identity, propose a side signal not a wishful fix).
- `references/surface-consistency-audit-round3-2026-08-12.md` — surface ROUND-3 verification (2026-08-12): the 6 briefed fix groups VERIFIED-FIXED with file:line evidence (MessageV1-shaped fakes, session_status directory kwarg, config test coverage, e2e_smoke PROJ/tempfile cleanup, tail_size-8 unification, wiki port/requires_env/prompt_async/no-idempotency fixes, read.py import), 3 NEW findings (fake-recording fidelity, schema params without descriptions, undocumented cross-directory wait=true), 1 STILL-PRESENT (log.md superseded pointers), and the clean-sweep confirmations (no server_port / tail_size 40 / /message-route residue).
- `references/surface-consistency-audit-round4-2026-08-12.md` — surface ROUND-4 verification (2026-08-12, convergence round): the 6 briefed R3 fix groups VERIFIED-FIXED with file:line evidence (command schema descriptions + cross-directory wait text, README prompt row match + no other row drift, log.md superseded banners on both [2026-08-10] entries, diag2_e2e.py citation annotation, full-kwarg fakes + test_prompt_forwards_config_agent_model_and_directory pin, tail_size-8 unification with test CFGs still at 40), 4 NEW nits (bare-param class not swept beyond opencode_command, README prompt signature order vs schema property order, wiki blocking bullet still event-only after the schema/README cross-directory fix, MessageV1 summary missing the flat info.modelID assistant form), 3 STILL-PRESENT from R1 (GET /question in the reconnect reconcile recipe, requires_env password mislabel, bridge/tools fakes missing permission_list/permission_reply masked by attach_reconcile=False), and the method lessons (sweep the whole finding CLASS, re-check prior rounds' unfixed findings — the brief covers only the last round, in-page contradiction rule: Resolved-questions bullets that contradict the page's own R-section are stale).
- `references/surface-consistency-audit-round5-2026-08-12.md` — surface ROUND-5 verification (2026-08-12, convergence round): the 6 briefed R4 fix groups VERIFIED-FIXED with file:line evidence (schema param descriptions, README row order, wiki caveat/recipe fixes, dual requires_env, permission/question/command fakes + reconcile pin), 2 NEW findings (client.prompt sends `id` but the real v1 prompt_async body field is `messageID` pattern `^msg` — test_client.py:61-68 pins the wrong field; fake `permission_reply` param-name drift `decision`/`reason` vs `reply`/`message`), and the method lessons (suite-count corroboration vs the brief; a fake echoing the client's own payload can lock in a wrong wire contract — re-derive asserted body field names from openapi.json/schema; docs can lead code — the wiki had `messageID` right).
- `references/surface-consistency-audit-round6-2026-08-12.md` — surface ROUND-6 verification (2026-08-12, convergence round): the 2 briefed R5 fix groups VERIFIED-FIXED with file:line evidence (payload["messageID"] vs real PromptPayload field set incl. messageID pattern ^msg and additionalProperties:false; fakes' permission_reply AskSurface param names + wire reply/question bodies), 2 NEW bugs (create_session model {providerID, modelID} vs Model.Ref {id, providerID, variant} required+additionalProperties:false → 400 when model configured — while prompt_async wants the {providerID, modelID} shape; read.py tool shaping vs real ToolPart {type, callID, tool, state:{input, output}} — with the mirror-fake trap in test_read.py:24-36), the verified-checks list (permission.reply/question.reply/question.reject/reject no-body, /event frame contract, messages bare-list + Link/X-Next-Cursor), and the method lessons (per-endpoint wire schema from openapi.json; one-logical-value-two-wire-shapes; fake part shapes from schema/src, not the shaper). Note: this round's report file could not be written at audit time (tool-iteration cap) — the JSON summary was the deliverable.
- `references/residue-sweep-r4-2026-08-12.md` — residue ROUND-4 (2026-08-12, convergence): the 11 briefed fix groups VERIFIED-FIXED with file:line evidence (0.1s poll, in_flight counter + stop() clears, hoisted delegated guard, non-dict properties guard, buffered-tail limit slice, schema descriptions + cross-directory wait docs, README row, log.md superseded banners, diag2_e2e annotation, full-kwargs fakes + 4 new tests + /proj assertions), the four-bucket classification of every deleted-name grep hit (CODE_PATH/STALE_DOC = 0), the comment-drift nit (bridge.py:70 `_delegated` shape comment vs the new `in_flight` field), and the convergence-round method (NO-NEW-FINDINGS-is-valid; accept dated log entries as history).
- `references/residue-sweep-r5-2026-08-12.md` — residue ROUND-5 (2026-08-12, convergence held): 2/2 frontmatter bumps VERIFIED (updated: 2026-08-11), ZERO CODE_PATH / ZERO STALE_DOC re-confirmed, the R4 brief under-counted its own round (said "exactly 2 findings", omitted the bridge.py:70 nit — report FILE is ground truth), prior STILL-PRESENT items verified fixed (permissions.md:53, plugin-requirements.md:146, fakes permission_list/permission_reply), and the new method lessons: silent shell-quoting grep failure (terminal rg patterns with single quotes return 0 hits — use tool-level ripgrep + must-match sanity check), the per-file hit-count sweep as completeness check, version-string (`v2026.8.3`) vs v2-API disambiguation, and least-wrong-bucket reporting for non-v2 findings under a mandated JSON enum.
- `references/residue-sweep-r6-2026-08-12.md` — residue ROUND-6 (2026-08-12, convergence held 3rd round): the R4 bridge.py `_delegated` comment nit VERIFIED-FIXED at :75 (briefed :70 — line-number drift lesson: re-locate by CONTENT, report the current line), ZERO CODE_PATH / ZERO STALE_DOC re-confirmed (all 528 v2|/api/ hits EXPLANATORY / HISTORICAL-LOG / version-string / vendored noise), the live-surface inventory re-check (client methods, 5 tools, question_reply schema), and the per-file classification table.
- `references/audit-round5-fixes-and-round6-dispatch-2026-08-12.md` — ROUND-5 fix application + ROUND-6 dispatch (2026-08-12): the SETTLED fork-time tail baseline dedup design (`last_fp` starts at the fp of the fork's own tail read; empty fingerprints always deliver — fixes BOTH the zero-row registration leak and the delayed-prior-idle misattribution; a separate `fork_fp` key proved redundant), the five fix groups with file:line (forget-before-fork re-arm bridge.py:468-473, events.py stop() prune, fake status_dirs recording, permission_reply AskSurface names, `payload["messageID"]` + pattern-valid test pin), the baseline-semantics test-conversion trap (advance the fake page BEFORE each completion, but let the fork read see the PRE-turn page), live probe evidence (wait=true 9.8s/PONG; fork 0.0s running; `_delegated` reaped live), and the round-6 seven-group verification brief.
- `references/live-v1-runtime-verification-2026-08-11.md` — LIVE-verified v1 runtime semantics (2026-08-11): `POST /session/{id}/message` BLOCKS until the turn completes vs `prompt_async` (204 fork route); `/session/status` map lifecycle (entry appears ~1s after prompt_async, deleted on idle — absence at first check = not started, not done; assistant text appears while still busy); MessageV1 `{info:{...},parts}` shape (flat role reads → everything shapes "assistant"); `http.client.IncompleteRead` → StreamClosed on SSE close; e2e assistant-row token matching; one-off probe methodology (map lifecycle timing, raw JSON dump, live bridge wait=True; `load_bridge_config()` takes no args — pass a cfg dict to Bridge).\n- `references/integration-seams-v1-18-13-audit.md` — seam audit (2026-08-09): stubbed v2 endpoints (`wait`/`compact`/`shell`/`skill` → 503), v2 prompt body vs legacy `parts`, `resume:false` admit-only, prompt-`id` idempotency, SSE envelope `{id,type,properties}`, `/event` vs `/events` replay paths, no-server-side-timeout on asks + crash-recovery, auth Basic/`auth_token` seams, serve network defaults (port 0 / mdns 0.0.0.0), permission fan-out limits, and the wiki-vs-code contradiction list.
- `references/http-api-surfaces-audit-v1-18-13.md` — HTTP surface inventory (2026-08-09 wiki audit): the two mounted stacks (v1 instance roots vs v2 `/api`) and their SEPARATE service backends, openapi.json ground-truth dump (162 routes), full endpoint groups incl. `interrupt`/`switchAgent`/`switchModel` (live) vs stubs, session list cursor pagination + handler defaults (limit 50), v2 `session.create` location default = serve-process cwd, three-SSE-stream schema matrix, auth + `tool.definition`/`tool.ids` 400-when-missing-provider caveat.
- `references/wiki-audit-round2-v1-18-13.md` — ROUND-2 audit (2026-08-09): NEW gaps the R1 fixes missed — `/api/session/active` is GET (wiki said POST), replay path still `/events` in 4 pages, `Admitted.id` (not `messageID`), question input has no `custom`, v2 `/api/event` has no disposed terminal (15s comment heartbeat), empty-password disables auth, `opencode plugin` lives in cli/cmd/plug.ts, interrupt idle no-op, v1 `/session/status` absent=idle, undocumented v2 list/message/health/tool.ids surfaces. Per-finding source path:line + wiki page:line + suggested fix.
- `references/seam-audit-round2b-v1-18-13.md` — ROUND-2B audit (2026-08-09): v2 `/api/event` is FATAL on v1-only event types (encode throw, no terminal frame — the "exclusion" is not a filter), prompts NEVER return busy (admitted+queued invisibly; bridge wait-loop is the only serializer), instance dispose fails pending asks with no rejection event (treat stream-close as reject-all + REST reconcile), v1 `/event` drops undefined-location events even on "global" subs + unbounded queue, Hermes has no plugin unload hook, `plan_exit` is question-backed; plus verified non-findings (create-then-prompt race closed, `?after=` no gap, per-subscriber wakes).
- `references/hermes-wiki-audit-round3-v2026-8-3.md` — ROUND-3 hermes-side wiki audit (2026-08-09): thread-tool whitelist hard gate (checked before pre_tool_call hooks), plugin-kind taxonomy (exclusive/model-provider), `pending_approval` shared with check_all_command_guards, tirith-only `[a]lways` persistence, approvals.* namespace (timeout/smart_policy/denial_breaker_threshold/deny), cronjob action names, register_platform eager-vs-deferred, registry.register extra params, line drift; R2 items re-verified still correct; plus the round-audit method.
- `references/wiki-audit-round4-v1-18-13.md` — ROUND-4 fresh opencode-side re-audit (2026-08-09): 2 NEW substantive contradictions — `ReplyInput` has NO `sessionID` (schema/src/v1/permission.ts:56-58; sessionID only on the `permission.replied` event) and the v2 plural `GET /api/session/{id}/message` route does NOT exist (only singular `session.message`, protocol/groups/session.ts:360; plural is V1-only) — plus 4 precision slips (`GET /experimental/tool` requires `provider`+`model` query params (400 without), dispose-finalizer cite off, manifest cite off, `system?` omitted from prompt-body enum), a re-verified-clean matrix, and the claim-taxonomy audit method (endpoints→groups+handlers+openapi.json; defaults→handlers vs bounds→group schemas).
- `references/seam-audit-round5-v1-18-13.md` — ROUND-5 integration-seam audit (2026-08-09): the NEW finding that v2 durable reads (`history`/`context`/`message/:id`/`event?after=`) are EMPTY for v1-run sessions (durable events + `SessionMessageTable` written only by v2-core; v1 persists to legacy `message`/`part`, readable only via `GET /session/{id}/message`; shared `SessionTable` masks emptiness as 200) with the full proof chain and the engine-ownership audit method; everything else re-verified clean (R1-R4 spot checks).\n- `references/turn-complete-injection-v2026-8-3.md` — settled non-blocking delegation design (2026-08-10): `wait=false` tool default vs bridge blocking contract, v1-idle/v2-`session.next.stop` completion triggers (v2 trigger unit-tested, E2E-pending), delegated-session scoping, content-fingerprint dedup (shaped rows drop `durable.seq`), `inject_turn_complete` whitelist requirement, `inject_message` wake/idle semantics, the 10-test recipe + patch-hygiene and verification-tracker pitfalls.\n- `references/hermes-message-injection-surfaces.md` — every Hermes message-injection channel at v2026.8.3 with file:line cites: `PluginContext.inject_message` (plugins.py:495, TUI-only, interrupt-vs-queue), `pre_llm_call` ephemeral per-turn context (plugins.py:1177/1919), `agent.interrupt` (run_agent.py:3020), raw `_pending_input`/`_interrupt_queue` (cli.py:4633), `SessionState.append_message`/`append_messages_batch` (hermes_state.py:6060/6207), gateway platform pipeline, webhooks/cron as session-starters, and non-paths (ContextEngine, MCP).\n- `scripts/wiki-lint.py` — runnable wiki lint (broken wikilinks, orphans, index completeness) for the repo wiki; `python3 wiki-lint.py [WIKI_DIR]`.