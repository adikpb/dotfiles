# Hermes Approval Gate Internals — the plugin escalation path (verified v2026.8.3)

Verified line-by-line against the v2026.8.3 clone (release 0.20.0) while auditing
the hermes-opencode bridge wiki. Every claim below was checked in the source;
line numbers are clone-relative. This map is the ground truth for any plugin
that escalates tool calls to the human-approval gate (`request_tool_approval`).

## The plugin escalation entry point

- `request_tool_approval(tool_name, reason, *, rule_key="", approval_callback=None)`
  is at `tools/approval.py:3299`. It is THE plugin surface ("asks the SAME human
  gate that Tier-2 dangerous shell patterns use"). It delegates to
  `_run_approval_gate(...)` (:2979), passing `fail_closed_when_no_human=True`
  (:3377) — the plugin path fails CLOSED in headless/non-interactive contexts,
  unlike the dangerous-command path which keeps a historical fail-open default
  (:3081-3086).
- The `pre_tool_call` hook `{"action":"approve", ...}` directive is resolved by
  `resolve_pre_tool_block` (`hermes_cli/plugins.py:2247-2295`) → calls
  `request_tool_approval(rule_key or tool_name)`; gate errors/denials/timeouts
  fail closed to a BLOCK message.
- Default allowlist grain when no `rule_key`: `plugin_rule:<tool_name>:<sha256(reason)[:12]>`
  (approval.py:3349-3357). "Distinct reasons on one tool persist independently."
- **`display_target` is NOT settable.** `request_tool_approval` hardcodes
  `display_target = f"<{tool_name}> (plugin approval rule)"` (:3360). The only
  user-visible, bridge-controllable text is the `reason` string. (A wiki that
  recommends formatting a custom `display_target` to label the ask is wrong.)
- **The approved return value is ambiguous.** Every approved outcome — yolo
  bypass (:3033-3034), session-cache hit (:3036-3038), CLI `once` (:3212),
  `session`/`always` (:3146-3152, :3205-3210) — returns the identical dict
  `{"approved": True, "message": None}`. A caller cannot tell whether the
  decision was once/session/always/yolo/cache-hit from the return value. Denials
  are richer: `outcome: "timeout"|"denied"`, `user_consent: False`,
  `status: "approval_required"` (gateway queue), `smart_denied`.
  A bridge that needs to distinguish may pre/post-probe `approved` state, or
  just treat every approved as "once".

## 2. Smart (aux-LLM) approval does NOT apply to the plugin path

- `_smart_approve` (:2886) is invoked ONLY from `check_all_command_guards`
  (:3740-3776) and `check_execute_code_guard` (:4117). `request_tool_approval`
  → `_run_approval_gate` has NO smart branch: yolo → session-cache →
  gateway/cron/CLI → fail-closed. RecreationState:
  - default `approvals.mode` is `"smart"` (hermes_cli/config_defaults.py:2044),
    so a default config DOES smart-review dangerous shell commands but NEVER
    smart-reviews plugin-tool approvals.
  - Smart approval of "persist" also persists nothing: smart approve is
    one-command-only (:3751-3760), smart deny with interactive owner can be
    overridden once (smart_denied flag).
- `pre_approval_request` / `post_approval_response` hooks: observers only,
  return ignored (VALID_HOOKS comment, plugins.py:174-188). Smart-path observer
  payload is redacted first via `_prepare_smart_approval_observer` (:123-155).

## 3. Gate branching in order (plugin path)

1. yolo (`HERMES_YOLO_MODE` frozen at import — `_YOLO_MODE_FROZEN`; per-session
   gateway `/yolo`; `approvals.mode: off`) → approved (:3033, :2784-2788).
2. Session allow state `is_approved(session_key, pattern_key)` — checks BOTH
   in-memory `_session_approved` AND permanent `_permanent_approved` (:2460-2471).
3. `approval_callback` resolution: explicit arg, else per-thread callback from
   `tools.terminal_tool._get_approval_callback` (:3040-3045).
4. Context classification — `_is_interactive_cli()` (:84-93, ContextVar
   `hermes_interactive` first, then env `HERMES_INTERACTIVE`); `_is_gateway_approval_context`
   (:243-261, `HERMES_GATEWAY_SESSION` or `HERMES_SESSION_PLATFORM`); cron wins
   over gateway (:1452-262).
5. Branch: cron (`approvals.cron_mode` deny/approve, :3052-3060) → fail-closed
   block for plugin path when no human (:3061-3080) → gateway round-trip
   (:3088-3171) → CLI prompt (:3173).
6. CLI prompt `prompt_dangerous_approval` (:2561): `[o]nce/[s]ession/[a]lways/[d]eny`,
   timeout fail-closed with distinct `timeout` outcome. prompt_toolkit-guard:
   if a TUI owns stdin and no approval_callback is on this thread, it denies
   fast (:2619-2633) — any thread needing interactive approval MUST install a
   callback.

## 4. Persistence semantics (config namespace)

- `s)esson`: `approve_session(session_key, pattern_key)` → **in-memory only**
  (`_session_approved`, :2386-2390). Lost on process restart. NOT in config.
- `always`: `approve_permanent` + `save_permanent_allowlist` → writes the
  TOP-LEVEL `command_allowlist` key of config.yaml (approval_defaults
  :2546-2554; default key at config_defaults.py:187). The allowlist contains
  the synthetic `plugin_rule:...` keys, reloaded next boot via
  `load_permanent_allowlist` (:2528-2543).
- A wiki claiming `[s]ession` and `[a]lways` both "persist to config.yaml" is
  wrong; only ALWAYS does.
- `resolve_gateway_approval(session_key, choice, resolve_all, reason)` —
  the `/approve`/`/deny` handler surface (:2338-2371); `reason` relays
  "Reason given by the user: …" into the BLOCKED message (:3121-3132).
- `register_gateway_notify(session_key, cb)` (:2313) is the ONLY way to get
  interactive (bubble/button) gateway approvals; `unregister_gateway_notify`
  (:2325-2335) unblocks ALL pending waits — entries resolve as timeout →
  fail-closed BLOCK. `submit_pending` is single-slot per session (overwrites).

## 5. Thread binding checklist (plugin bridge threads)

For a plugin thread calling `request_tool_approval`, bind per thread/async
task, NEVER `os.environ`:
1. `set_current_session_key(session_key)` — returns a Token; reset after
   (approval.py:171).
2. `set_current_observability_context(turn_id=…, tool_call_id=…)` (:181) — feeds
   the approval hooks.
3. `set_hermes_interactive_context(True)` (:69-76) — REQUIRED but easy to miss:
   without it, a non-gateway process falls to "non-interactive non-gateway" →
   `fail_closed_when_no_human` → always BLOCKED for the plugin path (:3061-3080).
4. Pass `approval_callback=` explicitly to `request_tool_approval` to bypass the
   prompt_toolkit fast-deny guard (:2619-2633).

## 5. Subagent trap — `delegation.subagent_auto_approve`

- Subagent threads ALWAYS install a non-interactive approval callback: default
  auto-DENY with a `logger.warning` audit (:tools/delegate_tool.py:70-93);
  `delegation.subagent_auto_approve: true` (config_defaults.py:1718-1726) flips to
  auto-approve-"once". If a plugin's `request_tool_approval` call happens inside
  a delegated subagent, the gate picker `_get_approval_callback` picks up the
  auto-deny callback → every ask silently denies with NO prompt. Any design
  relying on human approval inside `delegate_task` contexts is broken on the
  default config.

## 6. Registry override-gate nuance (entry-point plugins)

- `tools/registry.py:472` `register_plugin_override_policy(namespace, allowed)`
  records policy under the `hermes_plugins.<slug>` module namespace
  (`hermes_cli/plugins.py:1776-1781`). `_plugin_owner_of` (:481-503) only
  recognizes modules in the policy map OR starting with `hermes_plugins.`.
- Pip/entry-point plugins (`hermes_agent.plugins` group) load under THEIR OWN
  module name (`ep.load()`, plugins.py:1889-1904) → `_plugin_owner_of` returns
  None → `register(override=True)` skips the gate (:547-562) → **a pip-installed
  plugin can override built-in tools without `allow_tool_override: true`.**
  Directory plugins are gated correctly. Archive this asymmetry when designing
  trust boundaries. Also `deregister` uses `sys._getframe(2)` ownership checks
  (:505-519, :605-670), not the register path.

## 7. Verified supporting facts (misc)

- `hrs_config cfg_get` lives at `hermes_cli/config.py:2886`; config defaults for
  `plugins.*` and `command_allowlist` at `hermes_cli/config_defaults.py`.
- Approval identity is ContextVar-based: `_approval_session_key`,
  `_approval_turn_id/_tool_call_id`, `_hermes_interactive_ctx` (:55-200).
- `check_execute_code_guard` (:4072) is the other gate entry (execute_code
  tool); it also lacks the smart path at 4117 but it IS the one that runs smart.