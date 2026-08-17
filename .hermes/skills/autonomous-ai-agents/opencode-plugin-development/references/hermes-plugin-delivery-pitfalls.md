# Hermes-plugin delivery pitfalls (bridge → opencode, replayed 2026-08-13)

These are NOT opencode-API issues — they are Hermes-core behaviors a bridge
plugin hits when it delivers opencode questions/permissions into the Hermes
agent. Both were found live in the hermes-opencode plugin and are easy to
mis-diagnose. They complement `v1-v2-api-surface.md` (which is about the
opencode side); this file is about the Hermes side.

## CRITICAL — `PluginContext.inject_message` can silently drop the message

`ctx.inject_message(content)` (hermes_cli/plugins.py:495) returns `False` in
several real states and the plugin MUST NOT treat `False` as "fall back to the
tail tool":
- `cli is None` → "no CLI reference (not available in gateway mode)".
- **`"gateway mode requires an existing session_key"`** → logged WARNING; the
  Hermes core guard fires when there is no active session_key at inject time
  (mid-turn, between turns, or a sub-state in TUI). It happens in TUI too — NOT
  only headless.
- Any `False` is logged at WARNING level in `agent.log` (search the phrase
  `inject_message: gateway mode requires an existing session_key`).

Symptom if mishandled: the bridge's question handler injects the ask, marks it
"injected", and HOLDS the ask in the registry — but the injected message never
reached the agent. The agent then has no way to learn the pending `question_id`
(except shelling out to `GET /question` with the right `x-opencode-directory`
header — the v2 `/api/question/request` returns the server's DEFAULT dir, not the
session dir, so it is WRONG for this). The ask is a silent dead end.

FIX PATTERN (v1-only, no v2):
1. Never mark an ask "injected" unless `inject_message` returned True.
2. When inject returns False, STILL register the held ask AND log a WARNING that
   includes the `rid` + `directory`, so the failure is never silent.
3. Expose a discoverable fallback for pending ids: add a v1
   `client.question_list(directory)` → `GET /question` with the
   `x-opencode-directory` header, and a tool (`opencode_question_list`) returning
   `held_question_ids()` ∪ the live list. Then `opencode_question_reply` is usable
   without the injected message having landed.

## Permission gate fail-closes to DENY (correct-by-design, not a bug)

A bridge mapping opencode `permission.asked` → Hermes' approval gate:
- The interactive approval callback is captured at construction from
  `tools.terminal_tool._get_approval_callback()`, which lives in `threading.local`
  and is populated ONLY on the interactive/main thread. The FIFO worker thread
  calls `set_approval_callback(self._approval_callback)` in `_run`.
- If the worker has NO callback (headless, or the registering thread lacked one),
  `request_tool_approval` → `prompt_dangerous_approval` FAIL-CLOSES WITH DENY.
- The plugin surfaces this as `permission_reply(rid, "reject", "awaiting human
  review")` or a denial message; opencode then says "The user rejected
  permission" — that is opencode's wording for ANY `reject`, NOT a human deny.
- This is intended: there is no human approval surface in a headless runtime.
  The fix is OPERATIONAL (run where an approval channel exists), not a code
  change to the gate. Do NOT "fix" the fail-closed path — it is the safety
  property.

## Workflow the user enforced (replay on future similar tasks)

- **Live-spike-gate before adopting any endpoint.** Recon summaries + vendored
  source reading MISSED both the wrapped v2 envelope and the v2-session-store
  split. Spawn the real `opencode serve` via the plugin's own `serve`/`client`
  (auth + base URL match production) and curl the candidate routes against a real
  session BEFORE writing code.
- **Recon split by subsystem** (read, prompt/handoff, ask/reply, transport) via
  parallel subagents — each owns a distinct plugin surface, reports
  adopt/keep/hybrid per candidate endpoint with file:line refs.
- **"One branch only"** — the user explicitly rejected v1/v2 fallback dual code.
  If a capability is non-functional with the chosen transport, drop it.

## Repro / verification recipe (live spike)

Spawn a real server and probe both sides:
```python
import os, sys, time, json
sys.path.insert(0, "<repo>")
os.environ["OPENCODE_SERVER_USERNAME"] = "opencode"
os.environ["OPENCODE_SERVER_PASSWORD"] = "spike-secret"
from hermes_opencode.serve import ensure_serve
from hermes_opencode.client import OpenCodeClient
served = ensure_serve({"auto_serve": True, "hostname": "127.0.0.1", "port": 0,
                       "username": "opencode", "password": "spike-secret", "timeout": 10})
client = OpenCodeClient(served["hostname"], served["port"], username="opencode",
                        password="spike-secret", timeout=15)
# v1-prompted session -> v2 read EMPTY:
sid = client.create_session(); client.prompt(sid, "say PONG")
time.sleep(6)
st, _, h = client.request("GET", f"/api/session/{sid}/history", {"after":0,"limit":8})
print(st, json.dumps(h))   # expect {"data":[]}
# same session via v2 prompt -> v2 read POPULATED:
st, _, c = client.request("POST", "/api/session", body={})
vsid = (c.get("data") or c).get("id")
client.request("POST", f"/api/session/{vsid}/prompt",
               body={"prompt": {"text": "say PONG"}, "resume": True})
time.sleep(6)
st, _, h2 = client.request("GET", f"/api/session/{vsid}/history", {"after":0,"limit":8})
print(st, json.dumps(h2))  # expect real session.next.* events with durable.seq
served["handle"].stop()
```
For the Hermes-side pitfalls: trigger a question in a TUI session, then grep
`~/.hermes/logs/agent.log` for `inject_message: gateway mode requires an existing
session_key` to confirm the silent-drop path; the fix is the discoverable-id
fallback above, not a change to `inject_message`.
