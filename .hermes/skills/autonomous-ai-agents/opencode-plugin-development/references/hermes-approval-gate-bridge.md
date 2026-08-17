# Hermes approval gate as the opencode permission router (Hermes v2026.8.3)

The Hermes-side half of the bridge: route opencode `permission.asked` asks through
Hermes' OWN human-approval machinery so the user gets the IDENTICAL approval UX
as dangerous shell commands, not a plugin-custom prompt. Every symbol below was
read from the clone at `.slim/clonedeps/repos/NousResearch__hermes-agent`
(hermes-opencode-plugin workspace, v2026.8.3). The opencode-side surfaces of the
same bridge live in `references/bridge-surfaces-question-commands-permissions-v1-18-13.md`.

## The single escalation function

- `tools.approval.request_tool_approval(tool_name, reason, *, rule_key="", approval_callback=None)`
  (tools/approval.py:3299) — docstring: "asks the SAME human gate that Tier-2
  dangerous shell patterns use". Returns `{"approved": bool, "message": str|None,
  "pattern_key", "description", ...}`.
- A plugin `pre_tool_call` hook escalates by returning
  `{"action": "approve", "message": "...", "rule_key": "..."}` (hermes_cli/plugins.py:2136-2290);
  blocking = `{"action": "block"}`. Deny/block results are returned to the agent
  as the tool result.
- All entry points converge on ONE core: `_run_approval_gate(...)` (approval.py:2979) —
  yolo bypass -> session-cache short-circuit -> interactive/gateway/cron branch ->
  prompt -> deny/session/always persistence.

## Gate semantics and choice mapping to opencode

| Hermes gate result | opencode reply | Notes |
|---|---|---|
| approved (ANY branch: once, session-cache hit, always, yolo) | ALWAYS `{reply: "once"}` | the gate's return value is INDISTINGUISHABLE across approved branches (`{"approved": true, "message": null}` everywhere, approval.py:3033-3038, 3146-3152, 3212) — the bridge cannot know "always" was chosen, so it never forwards "always" to opencode. Hermes' own allowlists are the persistence layer; opencode re-asks in new sessions and Hermes auto-approves |
| deny / timeout / `approval_required` / no human | `{reply: "reject", message: <reason>}` | reason ALWAYS attached (R3b) |

## Gate semantics audit corrections (2026-08-09 subagent audit + manual re-verification)

- `[o]nce` = one call. `[s]ession` = in-memory ONLY (per Hermes process,
  `approve_session`, approval.py:2386) — NOT persisted anywhere. `[a]lways` =
  `approve_session` + `approve_permanent` + `save_permanent_allowlist` →
  persisted to the top-level `command_allowlist` config key (approval.py:2546-2554)
  with a `plugin_rule`-prefixed pattern. Persistence lives at Hermes, never
  "opencode session patterns".
- **NO smart-aux-LLM branch exists on the plugin path**: `_smart_approve`
  (approval.py:2886) is wired to `check_all_command_guards` (:3749) and
  `check_execute_code_guard` (:4117) ONLY. `request_tool_approval` →
  `_run_approval_gate` resolves yolo → session cache → cron → gateway → CLI →
  fail-closed, full stop. The default `approvals.mode: "smart"`
  (config_defaults.py:2044) does NOT make an aux LLM review opencode asks via
  the bridge — never design that in.
- `display_target` is HARDCODED to `f"<{tool_name}> (plugin approval rule)"`
  (approval.py:3360). The bridge cannot put its own marker there — the only
  bridge-controlled surface is `reason` (rendered verbatim as `description`).
- **Third return shape**: gateway branch with no notify callback QUEUES the
  request and returns `{"approved": false, ..., "status": "approval_required"}`
  (approval.py:3156-3171). Not a deny — handle explicitly. For the bridge
  (rarely has a gateway human present at ask time): fail closed and `reject`
  the opencode ask with an "awaiting human review" reason; the later gateway
  resolve cannot reach the already-rejected opencode request.
- **subagent contexts AUTO-DENY**: inside `delegate_task` worker threads a
  deny-callback is installed (delegate_tool.py:70-111; picked up by the gate
  via `_get_approval_callback`, approval.py:3040-3046). Any bridge approval
  call made from inside a subagent thread fails closed instantly — run gate
  calls from the plugin's main thread / dedicated thread with the interactive
  callback, or opt into `delegation.subagent_auto_approve` only where acceptable.

`[o]nce/[s]ession/[a]lways/[d]eny` are the CLI choices; `timeout` is fail-closed
("Silence is not consent"). `smart_approve`/`smart_deny` exist but ONLY on the
terminal/execute_code guard paths — never on `request_tool_approval` (see
audit corrections above). `always` = `approve_permanent(pattern_key)` +
`save_permanent_allowlist`, persisted under config `command_allowlist`.

## Deny-with-reason (R3b)

- Hermes gateway path carries an optional user-typed reason: `decision["reason"]`
  surfaces as "Reason given by the user: ..." inside the gate's return message
  (approval.py:3121-3132).
- CLI path is single letters only (no free-text reason input).
- opencode side: `reply: "reject"` + `message` fails the ask with
  `CorrectedError({feedback})`; reject WITHOUT `message` gives a bare
  `RejectedError`. Bridge policy: ALWAYS set opencode `message` — the user
  reason when present, else the gate's full fail-closed text ("BLOCKED: User
  denied ... Do NOT retry...") which is itself a valid reason for the subagent.

## Allowlist grain

`rule_key` controls the `[a]lways` allowlist grain. **CORRECTED (Round-2
audit, 2026-08-09): the reason-hash default only exists for DIRECT
`request_tool_approval(...)` calls with `rule_key=""`** (`approval.py:3349-3353`
derives `plugin_rule:<tool>:<sha256(reason)[:12]>`). On the pre_tool_call plugin
path this derivation NEVER fires: `resolve_pre_tool_block` calls
`request_tool_approval(tool_name, msg, rule_key=details.rule_key or tool_name)`
(hermes_cli/plugins.py:2284), and the non-empty `tool_name` always satisfies
`if rule_key:` (approval.py:3349). Effective default grain on the plugin path
is therefore **`plugin_rule:<tool>` — per-TOOL, coarse**: one `[a]lways` on
any approve-rule for `write_file` permanently allows every future
approve-rule on `write_file`. Consequence: **an explicit `rule_key` is
MANDATORY for per-permission grain** — use `rule_key="opencode:<permission>:<patterns>"`
so the Hermes permanent allowlist entries mirror opencode's own pattern rules
one-to-one; never rely on the documented default on the pre_tool_call path.

## Surfaces & context plumbing (implementation must-haves)

- CLI prompt needs the per-thread approval callback (`tools.terminal_tool.set_approval_callback` /
  `_get_approval_callback`); without it the gate denies fast (prompt_toolkit guard,
  approval.py:2608-2633) — the bridge event-handler thread MUST install it or
  route via gateway notify.
- Gateway: `submit_pending` + `_await_gateway_decision` when a notify callback is
  registered (blocking round-trip); with no callback the action is queued for
  `/approve` `/deny` review and the caller receives `{"status": "approval_required"}`.
- Cron mode honors `approvals.cron_mode` (deny/approve). Non-interactive
  non-cron: the plugin path opts in to FAIL-CLOSED (`fail_closed_when_no_human`)
  so a plugin-flagged action never runs ungated without a human.
- Context is contextvar-based, not env: `set_current_session_key` /
  `set_current_observability_context(turn_id, tool_call_id)` /
  `set_hermes_interactive_context(interactive)`. Bind per thread/async task,
  NEVER `os.environ`. Per-project scoping:
  `set_current_session_key(f"opencode:<dir>")` keeps session approvals per project.

## Observability hooks (fire from approval.py:96)

- `pre_approval_request` (observer): command, description, pattern_key, pattern_keys,
  session_key, surface `cli|gateway|smart` (+turn_id, tool_call_id).
- `post_approval_response`: adds `choice` (once/session/always/deny/timeout/
  smart_approve/smart_deny) and `decided_by: "aux_llm"` on smart path.

## Round-2 Hermes-side audit additions (2026-08-09, v2026.8.3)

New findings from the second HERMES-side wiki audit (the rule_key correction
above is the headline). All line refs re-read at the vendored tag.

- **Three DIFFERENT "no human present" shapes — one per entry point.** Do not
  assume the `approval_required` third shape everywhere:
  - `request_tool_approval` no-callback → `{"approved": false, ..., "status":
    "approval_required"}` (approval.py:3156-3171).
  - `check_execute_code_guard` no-callback → `{"approved": false, "status":
    "pending_approval", "approval_pending": true, "command"/"description"/
    "message"}` — payload ALREADY redacted via `redact_sensitive_text`
    (approval.py:4154-4157, :4163-4189); adds `smart_denied=True,
    allow_permanent=False` when a smart-deny fell through to the human
    (:4172-4173, :4187-4188).
  - `request_elicitation_consent` no-callback → plain string `"decline"`
    (approval.py:4293-4299).
  Key the bridge's pending/denied mapping off the entry point used.
- **`request_elicitation_consent` is a fifth gate entry point with its own
  contract** (approval.py:4263): returns `"accept"|"decline"|"cancel"` — NOT
  the `{"approved": ...}` dict; default `surface="mcp-elicitation"` (:4268);
  pattern_key hardcoded `"mcp_elicitation"` (:4304-4305); CLI path forces
  `allow_permanent=False` (:4333); timeout maps to `"cancel"`, not `"deny"`
  (:4343-4346). Relevant if the bridge answers opencode memory/skills-write
  consent asks.
- **Permanent allowlist is load-at-import ONLY**: `load_permanent_allowlist()`
  runs once at module import (approval.py:4350-4351). Runtime edits to
  `command_allowlist` in config.yaml do NOT take effect in a live process;
  only `approve_permanent`/`save_permanent_allowlist` keep memory+file in
  sync. A bridge relying on `[a]lways` persistence must not expect external
  config edits to apply mid-process.
- **`unregister_gateway_notify(session_key)` signals ALL blocked threads for
  that session** (approval.py:2325-2335: pops the callback, pops every queued
  entry, `.event.set()` on each) so agent threads don't hang. The bridge must
  register AND unregister its notify callback on shutdown; unregister is
  Hermes' own hang-prevention on session end.
- **messages-table schema in the wiki was partial** (hermes_state_common.py:
  252-276 also has `reasoning, reasoning_content, reasoning_details,
  codex_reasoning_items, codex_message_items, platform_message_id, observed,
  active, compacted` beyond the documented list). Watch `observed`/`active`
  defaults when writing rows directly.

## v2 client method names for the routes the bridge uses

operationIds in `packages/sdk/openapi.json` ARE the hey-api client method paths
of the generated v2 SDK (verified at v1.18.13):

- `command.list` -> GET /api/command (slash-command discovery)
- `question.request.list` -> GET /api/question/request (pending asks)
- `session.question.list|reply|reject` -> GET/POST /api/session/{id}/question[...]
- permission routes are NOT in openapi.json at this tag: call
  POST /api/session/{id}/permission/{requestID}/reply directly.

The legacy js SDK at v1.18.13 only generates `command` (POST /session/{id}/command)
and `tui.executeCommand`; sdk-next is a stub. The bridge should CRUD the v2
routes over HTTP (fetch/curl), not rely on a generated client.

## Settled design decisions (user decisions 2026-08-09)

All formerly-open questions were resolved in the spec review; implement these:

- **No bridge-side approval cache / scoping.** Use the ambient Hermes session
  key; do NOT bind a per-project key for caching. The gate's own
  session/permanent allowlists ARE the persistence mechanism, by design.
- **Concurrent asks: one FIFO queue per opencode server**, gate calls
  serialized. Per-session sibling bursts already collapse via opencode's
  sibling fan-out (replying one ask resolves its siblings); only cross-session
  asks genuinely queue up.
- **NO smart-mode on the plugin gate path (audit-corrected).** The aux-LLM
  smart branch is NOT reachable from `request_tool_approval`; do not design
  around it, do not promise "the guardian reviews opencode asks". If the
  user wants LLM-reviewed asks, that is a Hermes upstream change.
- **Ask must surface its origin — via `reason` ONLY.** `display_target` is
  hardcoded (approval.py:3360), so format `reason` = "opencode subagent
  (session <id>) requests permission: <permission>" — it renders verbatim as
  `description` for the user, observers, and gateway. The old
  `display_target`-marker design is impossible; never write it.
- **Timeout sharing:** inherit `approvals.timeout` (default 300 s,
  `_get_approval_timeout()` approval.py:2798) for opencode-sourced asks as
  well — no custom timeout. On expiry the bridge rejects the opencode ask
  with the gate's "Silence is not consent" reason, unblocking the subagent
  (opencode asks have no timeout of their own).
- **CLI deny reason: Option A.** Ship the gate's generic fail-closed message
  ("User denied ... Do NOT retry...") as the opencode `message`. Zero Hermes
  changes; no upstream PR needed. (A free-text deny reason in the CLI prompt
  was explicitly rejected to keep Hermes unpatched.)

Also captured as wiki pages in the repo: `wiki/concepts/plugin-requirements.md`
(R3/R3b mapping + questions), `wiki/concepts/hermes-approval-route.md` (gate anatomy).