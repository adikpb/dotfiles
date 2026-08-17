---
name: hermes-opencode-plugin
description: "Develop, upgrade, and verify the hermes-opencode plugin (Hermes <-> headless opencode bridge) against live opencode and the pinned Hermes/opencode clones. Covers the standard Hermes plugin registration surface (register_tool, system_prompt_section, approval_transport, call_mcp) and the opencode v1 HTTP/SSE surface."
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [OpenCode, hermes-opencode, plugin, verification, e2e, development]
    related_skills: [opencode, opencode-team, opencode-plugin-development]
---

# Hermes-OpenCode Plugin — End-to-End Driving

## When to use

- A user asks to exercise / test / verify the hermes-opencode plugin ("run it like a
  user would", "smoke test the plugin", "confirm the approval and question paths").
- You need to drive `opencode_prompt` / `opencode_session_tail` /
  `opencode_session_read` / `opencode_question_reply` / `opencode_command` against a
  live server, not the repo's pytest suite.
- A delegated turn is stuck `busy` and you must determine whether a permission ask was
  denied or a question ask is pending.

## What the plugin is

A Hermes plugin (`~/.hermes/plugins/hermes-opencode`) that delegates work to a headless
`opencode serve` on `127.0.0.1:4096` on the **v1 surface** (verified against opencode
v1.18.16). `auto_serve=true` by default: on load it probes `127.0.0.1:4096` and
**attaches to a healthy server already there** instead of spawning its own. Two ask
paths run on the event stream:

- **Permission asks** (`permission.asked`, v1) ride Hermes' own approval gate. The
  reason string carries the `[opencode]` origin marker; approved → reply `once`,
  denied/timeout/no-human → reply `reject` with a message.
- **Question asks** (`question.asked`, v1) are injected into the conversation (or held)
  and answered via `opencode_question_reply` (`question_reply_mode=tool` default).

**Design intent — the plugin is meant for COMPLETE event-driven usage.** Three
pillars must each hold; a failure of any is a DEFECT, not expected behavior (do not
wave these off as "headless quirks" — see references/event-driven-verification.md):
1. **Tail-on-idle injection**: when a delegated session goes idle, the bridge
   injects a turn-complete notification so the agent reads the tail without polling.
2. **Question + id injection**: a structured `question.asked` is injected as a
   `[opencode] question` message carrying a real request id, so
   `opencode_question_reply` has something to answer.
3. **Permission routing through Hermes**: permission asks route through Hermes'
   own approval subsystem (with the `[opencode]` reason) so an interactive human can
   approve/reject — not just fail-close.
Note: the plugin is **always non-blocking** — `opencode_prompt` returns immediately
with `running: true`; there is no `wait` flag (blocking `wait=true` / `timeout` /
`_wait_idle` were deleted). Completion is delivered via the event stream, never by
blocking the caller.

## Invoking the plugin tools from Hermes (deferred catalog)

The opencode tools are **not** in Hermes' base toolset. They live in the **deferred
plugin catalog** (`source: plugin`). Calling them by bare name inside a tool block
(for example `opencode_prompt(...)`) fails with `Tool 'opencode_prompt' does not
exist. Available tools: ...`. Invoke them through the deferred tool path instead:

1. `tool_search(query="opencode prompt")` confirms the tool exists and shows its
   one-line description.
2. `tool_describe(name="opencode_prompt")` returns the exact parameter schema. The
   plugin params (`wait`, `session_id`, `directory`, `agent`, `timeout`) are not
   obvious from the description alone, so describe before calling.
3. `tool_call(name="opencode_prompt", arguments={"prompt": "..."})` runs it.
   `tool_call` is the bridge to deferred/tools; bare tool-name calls are rejected.

This applies to every tool in this skill: `opencode_prompt`, `opencode_session_tail`,
`opencode_session_read`, `opencode_question_reply`, `opencode_command`.

## The end-to-end flow

1. `opencode_prompt(prompt=...)` → returns
   `{"session_id": "ses_...", "running": true, "tail": [...]}`. **Capture the real
   `session_id`.** The call is always non-blocking (no `wait` flag); the turn runs in
   the background and completion is injected event-driven. Delegate, then answer, then
   read.
2. Wait a few seconds for the turn to reach its gates, then read:
   - `opencode_session_tail(session_id=..., limit=40)`
   - `opencode_session_read(session_id=..., scope="range")`
3. If a question ask fired, answer it:
   `opencode_question_reply(question_id="que_...", answers=["<option label>"])`.
   - The `question_id` comes from the injected `[opencode] question` message. If that
     message did NOT surface in your context (gateway / tool-only-mode fallback),
     recover the id from the live server — see `references/rest-debugging.md`.
4. Confirm completion: `GET /session/status?directory=<DIR>` returns `{}` (idle
   sessions are deleted from the map) once the turn finishes.
5. `opencode_command()` (no name) lists server-registry commands; `/init` is the first
   entry (`source: command`).

## Building / upgrading the plugin to the Hermes plugin-development standard

When a task is "update the plugin to latest capability / SOTA, the standard
way" (not just e2e-verify it), drive the work from the **official plugin docs**
(`developer-guide/plugins` + `user-guide/features/plugins` on
hermes-agent.nousresearch.com), cross-checked against the pinned clones — not
from this skill's prose or memory. Verified contract for this plugin:

- **`register()` must be lightweight and fail-soft.** Do NOT do network or
  spawn I/O inside `register()`. Starting the bridge (spawning/attaching
  `opencode serve`, opening the SSE socket) belongs in `Bridge.start()` and
  MUST be wrapped so a down/unreachable server cannot abort registration. If
  `register()` raises, Hermes disables the plugin and registers **0 tools**.
  Verify with `hermes plugins doctor . --ci` (below) — its network sandbox
  turns any registration-time network call into a 0-tool failure.
- **`hermes plugins doctor . --ci` is the authoritative build check.** It runs
  the same discovery → manifest parse → import → `register(ctx)` → tool/hook
  registry Hermes uses, in a temp `HERMES_HOME`, and blocks direct network
  access during registration. A clean run prints `registrations: N tool(s), M
  hook(s)` and exits 0; `-ci` makes it non-zero on error for CI. ALWAYS run it
  after changing `register()`, the manifest, or any tool wiring. Recipe + the
  fail-soft `register()` pattern in `references/build-to-standard.md`.
- **Manifest v2, not v1.** `plugin.yaml` should carry `manifest_version: 2`,
  `api_version: 1`, `license`, `homepage`, `tags`, an accurate `description`
  (it lies if it lists surfaces you removed), and a `config_schema` block
  (types `str/int/float/bool/list/dict`) validating every setting under
  `plugins.entries.<id>.settings`. `config_schema` mismatches log an actionable
  warning at load — never a load failure. Keep `provides_tools` in sync with
  what `register()` actually registers.
- **Don't gate optional-auth tools with `requires_env`.** `requires_env` in the
  manifest (or per `register_tool`) **disables the whole plugin** when the var
  is missing. This plugin's auth is optional (localhost bind needs no password),
  so gating every tool on `OPENCODE_SERVER_PASSWORD` broke the no-auth default.
  Let the bridge fail-soft at start time instead; only `requires_env` a var that
  is genuinely required.
- **Require a minimum version; document it — don't host-guard.** The user
  prefers `ctx.on_unload(...)` (Hermes >= v2026.8.13) called directly with NO
  `getattr` fallback, and a README "Requirements" table stating the floor
  (Hermes >= v2026.8.13 for `on_unload`; opencode >= v1.18.18 for the v1
  abort route). Dropping the host-guard keeps the code honest: an older
  Hermes raising at load is the intended signal, not a bug to swallow.

Surfaces deliberately NOT used by this plugin (and why): `register_system_prompt_section`
— the model already discovers the bridge through the tool registry, so the
section is redundant; `register_approval_transport` — its `present_fn` calling
`request_tool_approval` recurses (see the recursion footgun in Pitfalls) and is
redundant because the bridge already escalates via the gate. Prefer the simplest
registration that works; add a richer surface only when it earns its place.

## Pitfalls

- **Source of truth is the CLONE + LIVE SERVER, never this skill's prose.** A user
  correction this session: *"Look it up online/source, don't trust the skills."*
  Skill summaries (including this one) are secondary interpretations and drift.
  Before implementing against a Hermes/opencode API, grep the pinned clones
  (`.slim/clonedeps/repos/NousResearch__hermes-agent` and
  `anomalyco__opencode`) for the actual `def`/`register_*` signature and the
  live handler, and — critically — **probe the live opencode server with curl**
  for any endpoint you wrap. The clone (latest tag) can declare a route that is
  BROKEN on the live server's older tag: in this session `GET /session/list`
  returned `{"name":"UnknownError",...}` 500 on the live `1.18.16` while the
  `v1.18.18` clone declared it cleanly, and `POST /session/{id}/abort` returned
  `true` live. A route that 500s on the running server is a real defect for the
  tool that wraps it even if the clone looks fine. Verify endpoints live, not
  just in source. See `references/standard-surface.md` for the verified Hermes
  registration signatures and the live-probe recipe.
- **Verify in source before claiming a path \"works\".** A tool-level report (e.g.
  "denied → reject") only shows the *outcome*; it does not prove the ask actually
  traversed the routing. Read the plugin source (`events.py` dispatch →
  `approval.py` `_handle_permission`/`_handle_question` → `bridge.py` inject) to
  confirm the event fired and the right handler ran. A fail-closed reject with
  `status: "approval_required"` is the *correct* headless outcome, but only proves
  the gate was reached — it does NOT prove permission routing reaches a human in an
  interactive TUI (see the lazy-callback fix below). User correction: never summarize
  a path as working from the report alone.
- **Permission ask denied in headless runs is correct, not a bug.** With no human
  approver in the loop, the Hermes gate fail-closes to `reject`. A denied
  `external_directory`/`bash` ask means the command (e.g. `rm -rf /tmp/...`) **never
  executed**. The raw tool part shows `state.status="error"` with an `error` string
  containing `BLOCKED: Tool 'external_directory' requires approval ([opencode] session
  <sid>: ...)`.
- **`GET /question` returns `[]` unless you send the `x-opencode-directory` header.**
  The v1 pending-question route is directory-scoped; without the header it yields
  nothing even when an ask is live. The v2 `GET /api/question/request?directory=<DIR>`
  is unreliable here — it reported the SERVER's default directory (a different repo)
  and returned `[]`. Use the v1 route with the header. (Recipes in references.)
- **A question ask may never reach `opencode_question_reply` if the headless model
  paraphrases it.** Under server-assigned free models, such as the
  `deepseek-v4-flash-free` model used in this session, the model can satisfy an "ask
  me" by writing the question as plain assistant prose (for example `Your turn: Which
  shell am I in?`) instead of emitting a structured `question.asked` event. No
  `[opencode] question` user message surfaces in your context and no `que_...` id is
  recoverable, so `opencode_question_reply` has nothing to answer. Detect this by
  reading the session tail. If the assistant text contains the question but there is no
  injected `[opencode] question` message, the ask was paraphrased rather than routed.
  Do not issue a `question_reply` call against a missing id. See
  `references/headless-ask-repro.md`.
- **Structured `tool{}` question ask stalls without becoming an inline `[opencode] question`.**
  A second failure shape: the headless model emits the **legacy AskUserQuestion v1
  tool-call** — a `tool` tool-call with **empty arguments `{}`** — and then the turn
  FREEZES. The session tail stops at that single `tool` call with no following assistant
  message, no `[opencode] question` user message is injected into your context, and no
  `que_...` id is ever produced. `opencode_question_reply` therefore has nothing to
  answer, and the session wedges (`running` stays `true`, no idle event). This is
  distinct from the paraphrased-prose case (which yields a *completed* assistant turn) —
  here the turn is genuinely stuck. **Diagnostic tell:** read
  `opencode_session_tail`/`opencode_session_read` repeatedly; if the tail is stable at a
  lone `tool` call with `arguments: "{}"` and no subsequent content, the ask is stalled,
  not pending. Do not wait for an idle event that will never come. Evidence and
  reproduction in `references/tool-call-stall-repro.md`
  (session `ses_example_stall_a`).
- **Always non-blocking: the `wait` flag is gone.** `opencode_prompt` never blocks;
  there is no `wait=true`/`timeout`. Completion is delivered event-driven
  (tail-on-idle inject + question inject). A verification that relied on `wait=true`
  to observe completion must instead read the injected turn-complete message or poll
  `opencode_session_tail`.
- **Permission routing must reach a human in interactive mode — capture the
  approval callback on the REGISTERING (main) thread, NOT the worker.** Approval
  callbacks live in `tools.terminal_tool._callback_tls = threading.local()`,
  populated ONLY on the main thread (the CLI's `set_approval_callback` runs on
  main). The old code captured `_get_approval_callback()` inside
  `ApprovalBridge._on_started` — which runs on the FIFO WORKER thread — so it
  read an EMPTY thread-local, got `None`, called
  `set_approval_callback(None)`, and every interactive permission ask hit
  `request_tool_approval(approval_callback=None)` and **silently fail-denied**
  (verified against `tools/terminal_tool.py:260-268` +
  `tools/approval.py:3040-3045` via a dedicated source-reading subagent — do NOT
  trust the code's own design doc, which claimed the worker capture was
  correct). Correct fix: `Bridge._wire` calls `_capture_approval_callback()` on
  the main/registering thread and passes `approval_callback=` into
  `ApprovalBridge.__init__`; `_on_started` only INSTALLS it on the worker
  (`set_approval_callback(self._approval_callback)`). A "lazily capture on the
  worker" approach is WRONG — the worker local is always empty. If permission
  asks fail-close in a TUI with a human present, check the callback was captured
  on the main thread, not the worker.
- **Permission ask can fail-closed INSIDE opencode, before reaching Hermes' gate.** The
  documented `state.status="error"` BLOCKED denial is one path; the other is opencode's
  *own* internal permission system auto-denying (e.g. `external_directory /tmp/*`) and
  returning a **completed assistant turn** that reports "blocked before execution" — no
  Hermes approval prompt surfaces in your conversation. In that case the command never
  reached Hermes' approval gate at all, so there is no approval message to act on. Either
  way the destructive command did NOT run; the difference is whether the denial came from
  Hermes (tool error, BLOCKED reason) or from opencode (prose denial inside a normal
  assistant turn). Treat a *completed* assistant turn that says "blocked" as a silent
  fail-closed, not as a real interactive approval prompt. See
  `references/tool-call-stall-repro.md` (session `ses_example_stall_b`).
- **Empty `/permission` does NOT mean no ask fired.** Once the plugin resolves (denies)
  an ask, the pending list clears. To confirm an ask fired, read the session messages
  and look for the `[opencode]` reason marker in the tool part's `error`/`state`.
- **Shaped tail vs raw messages.** The plugin read tools give role/content rows. To see
  the raw tool-call `state` (status `running`/`error`, the `[opencode]` reason,
  reasoning text), hit `GET /session/<sid>/message?limit=N` directly — `read.py`
  collapses parts into role/content and hides `state`.
- **Auth.** With `OPENCODE_SERVER_PASSWORD` unset and a `127.0.0.1` bind, opencode auth
  is disabled — no credentials needed ("auth not required" works). A `0.0.0.0` bind with
  an empty password is refused at startup.
- **Model is server-assigned** unless pinned via plugin config `model`/`agent`. Don't
  assume a specific provider; this session got `deepseek-v4-flash-free`.
- **Event-driven injections silently no-op when the tools are driven OUTSIDE an
  interactive TUI.** A verification that calls `opencode_prompt` /
  `opencode_question_reply` through the deferred tool catalog (`tool_call`) — not a
  human sitting in the TUI — has no live `cli_ref` / `session_key` bound on the
  background watcher / router threads. Every `_inject_text` then returns `False`
  ("inject unavailable: no plugin ctx", or no `cli_ref` + no `session_key`) and the
  source falls back to "tail tool remains the fallback". Observed this session: across
  4 delegated turns, **none** of the three pillars fired — no `[opencode] turn
  complete`, no `[opencode] question`, and the permission ask never surfaced — while
  every direct read (`opencode_session_tail`, `GET /session/...`) worked. **Calibration:
  if a task asserts "an injected message must arrive unprompted," that assertion can
  ONLY pass in a real interactive TUI.** In a tool-driven verification, "nothing
  injected" is the EXPECTED artifact of missing inject delivery, NOT proof the fix is
  broken. Report it as "inject delivery unavailable in this harness; completion
  confirmable only via the tail/read tools," and use direct reads + REST probes to
  verify everything else. Do NOT conclude the fix regressed until you've established
  whether you're in an interactive TUI (recipes in `references/inject-silent-noop-repro.md`).
- **Question ask emitted as a structured `question` tool-part but NEVER registered in
  `GET /question` → no `que_` id, reply 404s, session wedges.** A third distinct
  failure shape, separate from paraphrased-prose and `tool{}`-stall. Observed: opencode
  returned a real `question` tool call (`tool_name=question`, `callID=call_...`, full
  `questions` payload) AND a `tool` row for it, but `GET /question` returned `[]` and no
  SSE `question.asked` injection surfaced. The fix's `_route_question_parts` resolves
  the real `que_*` id ONLY from the pending `GET /question` list, so with an empty list
  it `continue`s — no `[opencode] question` is injected and no id is held.
  `opencode_question_reply(question_id='que_<callID>')` then returns **HTTP 404
  "Question request not found"** (the `callID` is not a server `que_` id), and opencode
  stays blocked forever waiting on an answer it never exposed as a resolvable request
  (no server-side timeout — exactly the "held ask blocks the session" risk in the
  source). **Diagnostic recipe:** read the tail; if a `question` tool-part with a
  `callID` exists but `GET /question` is `[]`, the ask is unresolvable — do NOT attempt a
  `question_reply` against the `callID`. Repro in `references/inject-silent-noop-repro.md`
  (session `ses_example_ask_wedge`).
- **Verify `approvals.mode=smart` with `hermes config get`, not by grepping
  config.yaml.** The global `~/.hermes/config.yaml` carries an `approval:` (model-provider)
  block, NOT an `approvals.mode` key; grepping for `approvals.mode` finds nothing. The
  effective mode resolves through the CLI: `hermes config get approvals.mode` returned
  `smart` this session. Use that to confirm the Scenario C precondition rather than
  editing config.
- **`opencode_question_reply` 404s with a valid `que_` id if the reply omits the
  exact `x-opencode-directory` header.** The `POST /question/{id}/reply` (and
  `/permission/{id}/reply`) routes are directory-EXACT: the header must byte-match the
  opencode-serve project dir with NO trailing slash (`.../hermes-opencode-plugin` works;
  `.../hermes-opencode-plugin/` and `$HOME` both 404). The plugin's
  `OpenCodeClient.question_reply` (`client.py`) forwards **no directory** (unlike the
  sibling `permission_reply`, which does), so if the bridge's `self.directory` doesn't
  exactly match, the live reply returns `HTTP 404 Question request not found` even though
  the id is correctly minted and held. Reproduction matrix + fix (forward `directory`,
  like `permission_reply`) in `references/reply-route-directory.md`. Diagnostic tell:
  `curl` with the exact realpath header returns `200 true` while the live tool 404s →
  the running bridge is sending the wrong/absent directory; restart Hermes to reload the
  patched module (the imported module won't pick up an in-place edit).
- **Scenario C can be INCONCLUSIVE if opencode auto-approves the command.** The fix
  under test routes permission asks through Hermes' smart-approval gate, but opencode
  itself may approve a `bash`/file action server-side (no `permission.asked` event) and
  just run it. This session: `opencode_prompt("echo hello-from-opencode")` executed and
  printed output with `/permission` staying `[]` and no approval prompt surfacing — the
  Hermes gate was never exercised. To truly test Scenario C you must provoke an ask
  opencode will NOT auto-approve (e.g. a write to a protected path under an opencode
  permission policy), and watch for `request_tool_approval` / a `permission.asked`
  event reaching the Hermes gate. A clean "command ran, no prompt" is NOT evidence the
  routing works — it may mean opencode skipped the gate entirely.
- **`register_approval_transport` `present_fn` must NOT call `request_tool_approval` (recursion footgun).** A transport's `present_fn(request)` is the *presentation* surface the approval gate invokes when `security.approval.transport` names this plugin. If `present_fn` calls `request_tool_approval(...)` (the gate) again, it recurses: `request_tool_approval` → `_present_with_selected_transport` (`tools/approval.py:3720`) → `invoke_approval_transport(your_present)` → `your_present` → `request_tool_approval` → … It either stack-overflows or runs until the transport worker's timeout, then fail-closes `deny`. With the *default* config (`transport: builtin`) the transport is never selected, so it's just dead weight; but if an operator sets `security.approval.transport: <your-name>`, it **wedges**. A transport is only correct when the plugin owns a **novel human-facing surface** (web UI, phone push, gateway DM) that presents `request` and waits for `request.respond(choice)`. If the plugin just wants the *existing* Hermes gate (CLI/TUI/gateway) to handle the human prompt, it should NOT register a transport at all — call `request_tool_approval` directly from the bridge (that escalates to the built-in gate). This plugin registered and then **removed** a transport for exactly this reason (commit `395e8f8`): the `present_fn` called `request_tool_approval` (circular + redundant, since the bridge already escalates via the gate). Before writing any `present_fn`, grep `tools/approval.py` for `_present_with_selected_transport` to confirm the selected-transport wiring and avoid the loop.
- **Question diagnostics live in `hermes_opencode.questions`, not
  `approval.py`.** If a review of plugin logs shows `question ... held for
  agent reply` / `opencode question ...` under the `hermes_opencode.approval`
  logger, the running code is PRE-refactor (pre-commit `88cd624`, which
  extracted the question path into `questions.py` with its own logger so
  question logs stop bleeding into the approval-gate log stream). A user
  complaint like "why are question logs coming from the approval file" means
  the module split is missing. Final architecture (commits `88cd624` →
  `f09a995`): `questions.py` owns the question path as free functions
  (`enqueue_question`/`handle_question`/`_reply_question`/`_reject_question`/
  `question_mode`) with its OWN logger; `ApprovalBridge` holds NO question
  methods at all (no thin delegating wrappers). The shared single-worker FIFO
  lives in its own module `fifo.py` (generic, no opencode/approval knowledge);
  `ApprovalBridge` owns a `Fifo` instance and `enqueue_permission`/
  `enqueue_question` submit task callables. `router.py` (was `events.py`)
  dispatches via a register-based route table — `router.register("permission.asked", h)`
  and `register("session.status:idle", h)` / `register("session.status:busy", h)`
  with `type:subtype` keys — NOT a static `if etype ==` chain. `bridge._wire`
  registers the routes. Module map in `references/architecture.md`.

- **Refactor preferences (user corrections this session — durable style
  rules, embed them rather than re-learning):** When restructuring this
  plugin, the user rejected three patterns:
  1. **No thin back-compat wrappers.** Extracting functionality into a new
     module must NOT leave delegating methods on the old class
     (`_handle_question(self, e): questions.handle_question(self, e)`) "for
     back-compat." Migrate the call sites AND the tests to call the new module
     directly. A pure-forwarding wrapper is dead weight that rots. (This
     session: the first extraction commit left such wrappers; the user said
     "No need for thin delegating wrappers on ApprovalBridge, migrate tests
     too properly" — they were removed and tests repointed to `questions.*`.)
  2. **One concern, one module, one logger.** A concern that never touches a
     subsystem's logic shouldn't log under that subsystem's namespace. The
     user flagged questions logging under `hermes_opencode.approval` even
     though questions NEVER hit the gate. Extract into its own module with
     `logging.getLogger(__name__)` so diagnostics stay separable.
  3. **Register-based dispatch + extract infrastructure.** Don't hard-code
     routing in a static `if etype == "x":` branch; use a register table
     (`register(type, handler)`, `type:subtype` keys) so the router carries no
     domain semantics. Shared machinery (a single-worker FIFO task queue)
     belongs in its own generic module (`fifo.py`), not embedded in a domain
     class. The user: "Have the fifo as well as the router moved to another,
     dont have the routes be defined statically, instead have a route and
     callback register thing."
  4. **Deep extraction kills cross-cutting — move the WHOLE concern, not just
     the state.** A follow-up refactor showed moving only `QuestionRegistry`
     state out of `ApprovalBridge` while leaving the question *state machine*
     (`_question_mode`, `_clarify_active`, `_ask_question_default`,
     `_route_question_parts`, `_resolve_question_id`, inject-once/route-once
     dedup) on `Bridge` was still a cross-cut: `Bridge` injected itself into
     `QuestionBridge` via the `ask_question=` callback and held question dedup
     state. The user: "lets aim for a deeper extraction so we dont have cross
     cutting of concerns." Final shape: `QuestionBridge` owns the ENTIRE
     question path (mode/clarify/asker/route/id-resolve/dedup + the held
     registry); `Bridge` keeps ONLY genuinely orchestrator-level concerns and
     passes them in as **wired callbacks** (`inject=` for text delivery,
     `clarify_callback=` for the TUI resolve) plus `ask_question=` for the
     default asker. The injection direction matters: `QuestionBridge` *decides
     when* (mode/clarify/dedup logic); `Bridge` *performs* the delivery. A
     "move X into a new module" done halfway leaves back-references — extract
     the full concern so neither side reaches into the other beyond the wired
     callbacks. See `references/architecture.md` for the module map.
  5. **Don't submit one-time worker setup in a base `__init__` (race).** The
     shared `AskBridge` base previously called `self._fifo.submit(self._on_started)`
     inside `__init__`. With an injected, already-running FIFO, the worker can
     run `_on_started` before the subclass finishes setting its own attributes
     (`ApprovalBridge` sets `_approval_callback` AFTER `super().__init__`),
     and the swallowed `AttributeError` silently leaves setup undone (e.g. the
     approval callback never installs → every ask fail-denies). Fix: move the
     submit into an explicit `AskBridge.start()` called by the orchestrator
     (`bridge._wire`) AFTER both bridges are constructed. A regression test
     (`StartHookTestCase`) pins "init does not run setup; start() does." This
     was a HIGH-severity race the FIRST read-only recon missed and an
     INDEPENDENT fresh re-audit caught — run the recon→implement→re-audit loop
     (see `code-review-recon`) so a second fresh pass catches what the first
     missed.

- **SSE `/event` subscription location-filters on the CANONICAL directory — this
  was the root cause of a verification reporting A/B/C all failing.** On macOS
  `/tmp` is a symlink to `/private/tmp`. The event router subscribed `/event`
  with the RAW configured dir (`/tmp`), but opencode location-filters the v1
  manifest (`session.status`, `question.asked`, `permission.asked`) on the
  **canonical** path, so every location-scoped event was dropped — the router
  received ONLY `server.connected`/`server.heartbeat`, while a raw
  `client.iter_events` connection got the full manifest. The REST endpoints
  (`session_status`, `question_list`, `permission_list`) use a different filter
  and kept working, which masked it: turn-complete only landed via the
  status-map watcher (REST), and questions/permissions never surfaced. **Fix
  (commit `fa1628b`):** `bridge._directory = os.path.realpath(...)` and
  `client.iter_events` sends the directory on the `x-opencode-directory`
  **HEADER** (the `?directory=` query form alone starves the router on this
  build). **Diagnostic:** if the router's `_dispatch` only ever sees
  `server.connected`/`server.heartbeat` but a separate `client.iter_events`
  call gets `question.asked`/`permission.asked`/`session.status`, the
  subscription directory/header is wrong — the events are on the wire but the
  router filters them out. This is distinct from the inject-sink limitation
  below: here the events never reach the bridge at all. Recipe in
  `references/sse-location-filter-root-cause.md`.
- **Each ask family needs SYMMETRIC lifecycle handling — a reconcile for one
  family must exist for the other.** Question asks (`question.asked`) and
  permission asks (`permission.asked`) share the same risk: an opencode ask has
  **no server-side timeout**, so an orphaned ask left over from before a
  reconnect blocks the session forever. `ApprovalBridge` had a `reconcile()`
  (fetch pending, reject orphans) but `QuestionBridge` had NONE for a long
  stretch — a fresh audit subagent flagged it as HIGH. If you add recovery /
  reconcile / reconnect handling to one ask family, add the symmetric handling to
  the other, or an un-recovered family will strand sessions. The question
  reconcile must reject only asks NOT already held/injected (live asks the agent
  will answer), mirroring the permission logic.
- **A reconcile that blocks the worker during a quiescence wait can REJECT a live
  ask.** `ApprovalBridge.reconcile` waits `QUIESCENCE_DELAY` on the shared FIFO
  worker, then snapshots `_pending`. An ask that streams in DURING that wait
  isn't in the snapshot, so reconcile wrongly REJECTED it and the later live gate
  reply 404'd. Fix: stamp each live ask with a reconnect **epoch** (`_pending_epoch[rid] = self._epoch`, epoch bumped in `reconcile()` under lock) and skip any ask whose epoch >= the current one (post-reconnect live ask). Reconcile only rejects pre-reconnect orphans. Don't let a "clean up orphans" pass nuke asks that arrived during the drain.
- **The audit discipline for this plugin is its own skill (`codebase-audit-loop` +
  `python-audit-baseline`).** Two non-obvious traps bit this repo repeatedly:
  (a) a green `pytest` count can hide a test module that failed COLLECTION
  (an import break drops the module silently, the rest still "pass"); (b) `ruff
  --fix` prunes a backward-compat re-export it thinks is unused, re-breaking
  importers. After ANY refactor that moves a symbol, re-export it at the old
  location AND re-run the FULL suite (grep for `ERROR collecting`). See those
  skills before declaring a refactor "done."
- **You CAN verify inject logic end-to-end without an interactive TUI** (corrects
  the "inject is unknowable outside TUI" calibration). The limitation is that
  the deferred *tools* (`tool_call`) have no live `cli_ref`/`session_key`, so
  `_inject_text` returns `False`. But you can drive the **real `Bridge`** with a
  recording context double that returns a valid `session_key` from
  `inject_message(...)` — then injects actually land and you can assert on the
  recorded content. This proves the fix logic (tail-on-idle, question inject,
  permission routing) independent of the harness sink. A deterministic probe
  wiring `RecCtx` + the real `Bridge` + a raw `client.iter_events` reader
  thread + internal held-state inspection is in `scripts/probe_live.py`. Use it
  to confirm an injected `[opencode] question` message and a held `que_` id from
  the running bridge, rather than inferring from "no message appeared."

## Maintaining the plugin's LLM wiki (the `wiki/` KB)

The plugin ships a `wiki/` LLM knowledge base (Karpathy-style interlinked
markdown) that documents the surfaces this plugin consumes — opencode's **v1
HTTP/SSE API** and the **Hermes plugin/approval contract** it implements. It is
a primary artifact, maintained by the same standards as the code. Governing
skill: `llm-wiki` (trim-to-scope + version-pin discipline live there).

- **Trim by consumption, not topic.** The plugin is a *consumer* of opencode's
  API, not a builder of opencode plugins. Keep pages about the HTTP/SSE
  surfaces it calls (`opencode-http-api`, `opencode-event-streams`,
  `opencode-session-reading`, `opencode-question-api`, `opencode-permissions`,
  `opencode-commands`, `opencode-agent-registry`) and the Hermes contract it
  implements (`hermes-plugin-surface`, `hermes-plugin-hooks`,
  `hermes-tool-registry`, `hermes-approval-route`, `message-injection`,
  `hermes-plugin-example-spotify`). Drop pages about *building* opencode
  plugins, opencode's internal agent loop, or two-sided hook comparisons —
  those aren't relevant to this plugin's dev/usage.
- **Re-verify against the pinned clones.** The wiki is sourced from
  `.slim/clonedeps/repos/{NousResearch__hermes-agent, anomalyco__opencode}`
  (release-tag pinned). When you bump those clones, diff the relevant source
  files between tags and refresh only the pages that changed. Prefer **symbol
  names** in citations over `file.py:1234` line anchors — line numbers shift
  every release but `display_target`, `register_hook`, `request_tool_approval`
  do not. Full recipe in `references/wiki-maintenance.md`.
- **THE WIKI IS GITIGNORED** (a `.gitignore` block: `# BEGIN hermes-opencode-plugin
  wiki`). All page edits are **on-disk only** and never committed to the plugin
  repo. The only tracked clone-bump artifact is `.slim/clonedeps.json`. Do NOT
  claim "committed the wiki" — `git status` stays clean because the files are
  ignored. Tell the user the KB is local-only and offer to un-ignore + commit
  if they want it tracked. (Verification: `git check-ignore wiki` returns the
  path.)

## Reporting (evidence, not paraphrase)

When verifying the plugin, paste the real artifacts: the actual `session_id`, the
assistant/question text read back, the permission outcome (denied/approved) with the
`[opencode]` reason, the question outcome with the answer you supplied, and the command
names. **Do not paraphrase success and do not summarize away tool errors — paste real
tool output and real errors verbatim.** This is the whole point of an e2e exercise:
success is demonstrated by raw evidence, not by a summary claim.

## References

- `references/rest-debugging.md` — exact curl recipes (permission/question pending
  lists, raw message read, status map) with the directory-header gotcha, and the
  reproduction recipe.
- `references/headless-ask-repro.md` — observed headless repro
  (ses_example_headless): permission ask fail-closed on external dir, and
  question ask paraphrased as model prose with no recoverable id.
- `references/tool-call-stall-repro.md` — observed headless repro:
  structured `tool{}` AskUserQuestion stall (no inline question, no `que_` id, wedged
  turn) and an opencode-internal fail-closed permission denial surfacing as a completed
  assistant turn with no Hermes approval prompt.
- Plugin source is self-documenting: `README.md`, `wiki/` (entities/opencode-http-api.md,
  concepts/opencode-question-api.md), and `hermes_opencode/{bridge,approval,serve,client,tools,read}.py`
  under `~/.hermes/plugins/hermes-opencode/`.
- `references/event-driven-verification.md` — code-level routing chain, the three
  event-driven pillars, the always-non-blocking contract, and the lazy
  approval-callback fix (verified against source).
- `references/inject-silent-noop-repro.md` — observed tool-driven repro: all three
  event-driven pillars silently no-op outside an interactive TUI; the
  structured-`question`-part-without-`que_`-id shape (reply 404, wedged session);
  `hermes config get approvals.mode` recipe; the REST probe set used to verify
  completion independently of injections.
- `references/reply-route-directory.md` — the `POST /question/{id}/reply` &
  `/permission/{id}/reply` routes are directory-EXACT; the plugin `question_reply`
  omits the `x-opencode-directory` header (unlike `permission_reply`) so the live
  `opencode_question_reply` 404s on a valid `que_` id; reproduction matrix + fix.
- `references/sse-location-filter-root-cause.md` — the `/event` subscription
  location-filters on the CANONICAL directory (`/tmp` → `/private/tmp` on macOS);
  the router received only `server.connected`/`server.heartbeat` while a raw
  connection got the full manifest. This starved all three event-driven pillars
  in one verification. Symptoms, root-cause proof, and the realpath + header fix.
- `references/architecture.md` — final module map (`bridge`/`router`/`fifo`/`approval`/`questions`/`client`), the register-based dispatch pattern, and the tests to repoint when refactoring. Read before any structural change to the plugin.
- `scripts/probe_live.py` — deterministic live probe: wires a recording `RecCtx`
  (valid `session_key`) + the real `Bridge` + a raw `client.iter_events` reader
  thread + internal held-state inspection to prove inject logic (tail-on-idle,
  question → held `que_` id) works even without an interactive TUI.
- `references/wiki-maintenance.md` — how to bump the pinned `.slim/clonedeps`
  clones to latest tags, diff what actually changed, refresh only the affected
  wiki pages (symbol-name citations over brittle line anchors), and the
  gitignored-wiki verification pitfall. Read before any "update the wiki to
  latest" task.
- `references/standard-surface.md` — verified Hermes `PluginContext`
  registration signatures (v2026.8.13: register_tool, register_hook,
  register_system_prompt_section, register_approval_transport, call_mcp,
  has_capability) + the opencode v1 instance endpoint catalog (v1.18.18 clone)
  + the **live curl-probe recipe** to confirm a wrapped endpoint before
  claiming it works. Read before any "upgrade the plugin to latest capability"
  task — and remember: clone-declared routes can 500 on the live (older-tag)
  server, so probe live.
- `references/build-to-standard.md` — the "upgrade to latest capability / SOTA,
  the standard way" recipe set: `hermes plugins doctor . --ci` (the authoritative
  build check that catches registration-time network I/O), the fail-soft
  `register()` pattern, manifest v2 + `config_schema`, the optional-auth
  `requires_env` trap, and the minimum-version-documents-not-host-guards rule.
  Read before any build/upgrade task.
