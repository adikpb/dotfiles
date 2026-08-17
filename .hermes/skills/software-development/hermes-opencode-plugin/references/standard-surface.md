# Standard Hermes + OpenCode surfaces (verified against source)

Condensed from the pinned clones at their latest tags
(`.slim/clonedeps/repos/NousResearch__hermes-agent` = **v2026.8.13**,
`.slim/clonedeps/repos/anomalyco__opencode` = **v1.18.18**). The live
server this repo drives is often one tag BEHIND the clone (e.g. 1.18.16) —
always curl-probe a wrapped endpoint live (see bottom).

## Hermes `PluginContext` registration surface (v2026.8.13)

All on `ctx` inside `register(ctx)`. Source: `hermes_cli/plugins.py`.

- `register_tool(name, toolset, schema, handler, *, check_fn=None,
  requires_env=None, is_async=False, description="", emoji="", override=False)`
  — the canonical tool registration. `schema` is
  `{"name","description","parameters":{type/properties/required}}`.
- `register_hook(hook_name, callback)` — `hook_name` must be in `VALID_HOOKS`
  (v2026.8.13 has 26: pre_tool_call, pre_llm_call, transform_*, on_stream_*,
  on_session_start/end/finalize/reset, on_skill_lifecycle, subagent_start/stop,
  pre_approval_request, post_approval_response, pre_command, kanban_*,
  gateway_platform_event, …). Unknown names warn but still store.
- `register_system_prompt_section(id, content, *, position="after_memory",
  max_chars=…)` — bounded context frozen into each new session prompt.
  `id` must match `^[a-z0-9._-]{1,128}$`; duplicate id raises. `content` is a
  str or a callable `(session_info_mapping) -> str`. **Capability-discovery
  pattern**: announce your tools here so the model knows they exist.
- `register_approval_transport(name, present_fn)` — registers a NAMED, OWNED
  approval-presentation transport. **Inactive until the operator sets
  `security.approval.transport: <name>`** in config.yaml (separate consent
  step from enabling the plugin). `present_fn(request)` may be sync/async;
  `request` is a host-created redacted `ApprovalRequest` with `.command`,
  `.description`, `.respond(choice)`; return `request.respond(choice)` where
  `choice` ∈ once/session/always/deny. Cannot invent a scope the host did not
  offer. The transport is a PRESENTATION surface only — command policy and
  persistence stay host-owned; delegate to `tools.approval.request_tool_approval`
  (signature `request_tool_approval(tool_name, reason, *, rule_key="",
  approval_callback=None) -> {"approved": bool, "message": …}`) if you want the
  same human gate.
- `call_mcp(server, tool, arguments=None, timeout=30)` — capability-gated MCP
  call. **Default-off**: operator must list the server under
  `plugins.entries.<id>.mcp_allowlist` or it raises `PermissionError`. Returns
  `{"ok": True, "result": …}` / `{"ok": False, "error": …}`.
- `has_capability(cap)` — probe a gated host surface; fail-closed (False) on
  unknown/unreadable. Use to degrade gracefully instead of crashing on older
  hosts.

### Back-compat guarding pattern (for additive upgrades)
When adding a newer registration (e.g. `register_system_prompt_section`),
guard with `register = getattr(ctx, "register_system_prompt_section", None);
if not callable(register): return`. Wrap the call in try/except so an older
host (AttributeError / reserved-name / duplicate) silently skips — the
existing tool set must still register.

## OpenCode v1 instance HTTP surface (v1.18.18 clone; live may differ)

Stdlib `OpenCodeClient` in `hermes_opencode/client.py` wraps these. The plugin
uses the **v1 root-path routes** (no `/api` prefix) because the v1 runtime
resolves runtime/plugin-registered agents.

- `POST /session` → `{id, …}` (create). Model body is `{id, providerID}`, NOT
  the prompt `{providerID, modelID}` shape.
- `POST /session/{id}/prompt_async` → 204 (fire-and-forget; turn forked). Body
  `{"parts":[{"type":"text","text":…}], "agent"?,"model"?,"messageID"?}`.
- `GET /session/status?directory=` → `{sessionID: {type: busy}}` map; ABSENT
  key = idle (the bridge's turn-complete signal).
- `GET /session/{id}/message?before=&limit=` → cursor list (`Link` /
  `X-Next-Cursor` header). `before`+`limit` required together or 400.
- `GET /permission` / `POST /permission/{rid}/reply` (directory-exact header).
- `GET /question` / `POST /question/{rid}/reply` / `/reject` (directory-exact).
- `GET /command` → `[{name, template}]`.
- `POST /session/{id}/abort` → returns `true` (cancels running turn; live-verified).
- `GET /session/list?directory=` → directory-scoped session list. **BROKEN
  server-side at v1.18.18** — returns `UnknownError` HTTP 500 for ANY request
  (no params, `?scope=project`, and `?directory=` all 500 on live 1.18.18;
  `GET /session/status` works fine, so it's specific to the list route).
  Source: `ListQuery` (`groups/session.ts`) has NO `directory` field and the
  handler resolves the directory from the server's own CWD, while
  `session.list()` throws internally. There is NO working "list sessions"
  endpoint at this tag. **Do NOT wrap it** — the plugin removed
  `opencode_sessions` for exactly this reason (commit `326384d`). Track
  sessions by the `session_id` `opencode_prompt` returns; tail/read default to
  the most recent delegated session. This is the canonical "clone declares a
  route that is BROKEN on the live server" trap — pin the clone, but ALWAYS
  curl-probe a wrapped endpoint live before trusting it.
- `GET /event` (SSE) — location-filters on the CANONICAL directory (macOS
  `/tmp`→`/private/tmp`); directory MUST ride the `x-opencode-directory`
  HEADER, not just `?directory=`. Without the realpath header, only
  `server.connected`/`server.heartbeat` arrive.
- Auth: Basic (base64 `user:pass`) on every request when password set; empty
  password = no auth (config layer refuses wide binds in that case).
- `POST /api/session/{id}/wait` — **REMOVED** by v1.18.18 (was a 503 stub);
  do not use; poll `/session/status` instead.

## Live-probe recipe (run BEFORE claiming a wrapped endpoint "works")

```bash
DIR=$HOME/src/hermes-opencode-plugin
H=127.0.0.1:4096
curl -s -m 5 -H "x-opencode-directory: $DIR" "$H/global/health"        # liveness
curl -s -m 5 -H "x-opencode-directory: $DIR" "$H/session/status?directory=$DIR"  # {}
curl -s -m 5 -X POST -H "Content-Type: application/json" -H "x-opencode-directory: $DIR" \
  "$H/session?directory=$DIR" -d '{}'        # -> {"id":"ses_..."}
# create sid, then:
curl -s -m 5 -X POST -H "Content-Type: application/json" -H "x-opencode-directory: $DIR" \
  "$H/session/$SID/prompt_async?directory=$DIR" -d '{"parts":[{"type":"text","text":"hi"}]}'  # 204
curl -s -m 5 -X POST -H "Content-Type: application/json" -H "x-opencode-directory: $DIR" \
  "$H/session/$SID/abort?directory=$DIR" -d '{}'   # -> true
curl -s -m 5 -H "x-opencode-directory: $DIR" "$H/session/list?directory=$DIR"  # verify; may 500
```

Also drive the real `Bridge` in-process for a tool-level round trip:
```python
from hermes_opencode import tools
from hermes_opencode.bridge import Bridge
from hermes_opencode.config import load_bridge_config
cfg = load_bridge_config(); cfg["auto_serve"]=False; cfg["port"]=4096
b = Bridge(ctx=None, cfg=dict(cfg)); b.start()
b.prompt("hi"); b.abort(sid)
tools.set_bridge(b)   # required before _handle_* tools resolve
```
