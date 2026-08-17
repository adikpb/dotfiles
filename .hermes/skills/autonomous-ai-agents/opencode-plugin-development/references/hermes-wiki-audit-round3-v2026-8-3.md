# Hermes-Side Wiki Audit — ROUND 3 (v2026.8.3)

Audited 2026-08-09 against the vendored clone `.slim/clonedeps/repos/NousResearch__hermes-agent`
(tag v2026.8.3, release 0.20.0). Scope: `entities/hermes-plugin-surface.md`,
`entities/hermes-tool-registry.md`, `entities/hermes-agent-runtime.md`,
`concepts/hermes-plugin-hooks.md`, `concepts/hermes-approval-route.md`,
`concepts/message-injection.md`.

## Round-audit method (proven across R1-R3)

1. Read every wiki page fully; verify EVERY cited `path:line` with `grep -n`/sed
   (expect ~1-3% drift; identical content = NOT a finding).
2. Sweep for UNDOCUMENTED surfaces — public module functions/classes/config keys
   with no wiki mention (`grep -n "^def \|^class \|^    def "`, then
   `grep -rn` callers to find hidden consumers). On later rounds, missing
   coverage outnumbers wrong claims.
3. Classify findings: CONTRADICTS code / INCOMPLETE coverage / line-drift /
   still-correct. Re-verify prior-round fixes; do NOT re-report them unless
   still wrong.
4. Cite `path:line` for every finding plus the wiki page the fix belongs in.

## Missed plugin surfaces

- **Thread tool whitelist** — `set_thread_tool_whitelist`/`clear_thread_tool_whitelist`
  (hermes_cli/plugins.py:2108-2118). Checked at the TOP of
  `_get_pre_tool_call_directive_details` (plugins.py:2140-2143), BEFORE
  `pre_tool_call` hooks run: any non-whitelisted tool gets a hard `block` and the
  plugin `approve` escalation NEVER fires. Only consumer:
  `agent/background_review.py:903` (review forks restricted to memory/skills
  tools; cleared in `finally` :935). Bridge relevance: tool dispatch from a
  whitelisted thread = silent hard block, no approval gate involved.
- **Plugin kind taxonomy** — `_VALID_PLUGIN_KINDS = {standalone, backend,
  exclusive, platform, model-provider}` (plugins.py:283); unknown kind falls
  back to standalone (:1602-1610). `kind: model-provider` ALSO skips
  `plugins.enabled` (recorded enabled=True, loaded lazily by
  providers/__init__.py, plugins.py:1427-1435); `kind: exclusive` (memory
  providers) is NOT auto-loaded — requires `<category>.provider` config
  (plugins.py:1411-1420). Bundled top-level `skip_names` includes `platforms/`
  and `model-providers/` (plugins.py:1353-1356), not just memory/context_engine.
  Wiki's "backend vs standalone + platform auto-load" is incomplete.
- **register_platform "deferred lazy load" conflation** — `ctx.register_platform`
  (plugins.py:950-1005) registers EAGERLY (`platform_registry.register(entry)`);
  lazy loading is the separate manifest-level `_register_deferred_platform`
  (plugins.py:1726-1765) reserved for bundled `kind: platform` plugins (adapter
  module imported only when gateway/cron/setup/send_message first asks).
- **registry.register extra params** — `max_result_size_chars` +
  `dynamic_schema_overrides` (tools/registry.py:521-534) are NOT exposed through
  `PluginContext.register_tool` (plugins.py:410-468); plugin tools cannot set
  result-size caps or dynamic schema overrides via ctx.

## Approval-gate edge cases

- **`pending_approval` shape is NOT execute_code-only.** `check_all_command_guards`'
  no-callback fallback returns the identical `{"approved": False, "status":
  "pending_approval", "approval_pending": True, command/description redacted}`
  (approval.py:3905-3927; redaction :3907-3909; smart-deny owner override adds
  `smart_denied=True, allow_permanent=False` :3918/:3928). The in-code comment at
  :3904 even says "Return approval_required for backward compat" while the code
  returns `pending_approval`. Shape matrix: `request_tool_approval` →
  `approval_required`; BOTH command guards → `pending_approval`; elicitation →
  plain string.
- **`[a]lways` persistence is pattern-dependent on the dangerous-command path**:
  gateway branch — tirith warnings get SESSION-only even on "always"; non-tirith
  "always" → permanent (`approve_session`+`approve_permanent`+
  `save_permanent_allowlist`, approval.py:3893-3900); CLI hides `[a]lways` when
  no permanent-capable warning (`allow_permanent=has_permanent_capable and not
  smart_denied_for_owner`, approval.py:3942-3947). Wiki choices table holds ONLY
  for the plugin path (single pattern_key through `_run_approval_gate`).
- **Consecutive-denial breaker** — after `approvals.denial_breaker_threshold`
  (default 3) smart-guardian DENYs in a row within a session, deny messages
  escalate to a hard-stop instruction (approval.py:2228-2275, :3755-3763, :3864);
  any approval resets the tally.

## Config namespaces (approvals.*) missing from wiki

Wiki documents only `approvals.mode` + `approvals.cron_mode`. Also live
(config_defaults.py:2043-2075):

- `approvals.timeout` (default 300) — CLI prompt AND gateway wait timeout
  (`_get_approval_timeout`, approval.py:2798-2809); also governs the elicitation
  CLI path. Bridge-relevant: a gateway approval blocks the agent thread up to
  this long.
- `approvals.smart_policy` (:2052-2055) — operator text appended to the smart
  guardian's SYSTEM prompt (trusted channel).
- `approvals.denial_breaker_threshold` (:2054-2057).
- `approvals.deny` (:2068-2075) — user fnmatch deny rules matched BEFORE the
  yolo bypass.

## Contradictions / drift

- cronjob tool actions are `create|list|update|pause|resume|remove|run`
  (tools/cronjob_tools.py:1051 schema, dispatch :739-1020) — wiki printed
  "create/edit/list/delete/run" (edit≈update, delete≈remove).
- Line drift only (content identical; not worth a wiki fix): registry singleton
  `tools/registry.py:911` (wiki said 910); `AIAgent.chat` `run_agent.py:7723`
  (wiki said 7710).

## Re-verified CORRECT (do not re-report)

Round-2 hermes-side fixes all still accurate: coarse `plugin_rule:<tool>` on the
pre_tool_call path (plugins.py:2284; finer hash derivation only on direct
`request_tool_approval` with empty rule_key, approval.py:3349-3357);
execute_code `pending_approval` shape + display redaction (approval.py:4154-4157,
4163-4189); elicitation `accept|decline|cancel` + timeout→cancel
(approval.py:4343-4346) + CLI `allow_permanent=False` (:4333); allowlist
load-at-import (approval.py:4351); `unregister_gateway_notify` unblocks ALL
queued threads (approval.py:2325-2335); messages-table columns incl.
reasoning/codex_*/platform_message_id/observed/active/compacted
(hermes_state_common.py:252-277). All PluginContext line citations
(plugins.py:339-1217), all 23 VALID_HOOKS (plugins.py:135), approval entry-point
lines (approval.py:3229/3299/4023/4263, `_run_approval_gate` :2979, `_smart_approve`
only at :3749/:4117), and the `approvals.mode: "smart"` default
(config_defaults.py:2044) verified exact.
