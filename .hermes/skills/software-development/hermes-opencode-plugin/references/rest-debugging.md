# hermes-opencode plugin — REST debugging recipes

When the plugin's own tools don't expose what you need (raw tool-call `state`, the
`que_` question id when no `[opencode] question` message surfaced, confirmation that an
ask fired), hit the opencode server directly. The plugin attaches to an existing
`opencode serve` (default `127.0.0.1:4096`).

## Server + auth

```
export BASE=http://127.0.0.1:4096
# No auth with OPENCODE_SERVER_PASSWORD unset + 127.0.0.1 bind.
# If a password is set, add -u "opencode:$OPENCODE_SERVER_PASSWORD".
TD="$(pwd)"   # the bridge/plugin directory — used as x-opencode-directory
```

## Directory gotcha (critical)

The v1 `/question` route is **directory-scoped**. Without the `x-opencode-directory`
header it returns `[]` even when an ask is live. Always send the header.

The v2 `GET /api/question/request?directory=$TD` is unreliable for this: in the verified
session it reported the **server's default** directory (a different repo entirely) and
returned `[]`. Prefer the v1 route + header.

## Recipes

**Session status (idle = `{}`):**

```
curl -s --max-time 8 "$BASE/session/status?directory=$TD"
# {"ses_...":{"type":"busy"}}  while running; {} when idle/complete
```

**Permission asks (v1, directory-scoped):**

```
curl -s --max-time 8 -H "x-opencode-directory: $TD" "$BASE/permission"
# [] once the plugin resolved (denied) an ask — empty != "no ask fired"
```

**Question asks (v1, directory-scoped) — recover the que_ id here:**

```
curl -s --max-time 8 -H "x-opencode-directory: $TD" "$BASE/question"
# [{"id":"que_...","sessionID":"ses_...","questions":[...],"tool":{...}}]
```

**Raw messages (shows raw tool-call `state`: status running/error, `[opencode]` reason,
reasoning text — the plugin's shaped read tools HIDE these):**

```
curl -s --max-time 8 "$BASE/session/$SID/message?limit=50" -o /tmp/opencode_msgs.json
python3 - <<'PY'
import json
for m in json.load(open("/tmp/opencode_msgs.json")):
    info=m["info"]; print(info.get("role"), info.get("id"), info.get("finish"))
    for p in m.get("parts",[]):
        if p.get("type")=="tool":
            print("  tool=", p.get("tool"), "state=", json.dumps(p.get("state"))[:600])
        elif p.get("type") in ("text","reasoning"):
            t=p.get("text") or ""; print("  ", p.get("type"), t[:200])
PY
```

**Health / version:**

```
curl -s --max-time 8 "$BASE/global/health"   # {"healthy":true,"version":"1.18.16"}
```

## Reply routes (what the plugin calls internally)

- Question reply: `POST /question/<que_id>/reply` body `{"answers":[["<label>"]]}`
- Permission reply: `POST /permission/<rid>/reply` body `{"reply":"once"|"reject","message":...}`

## Reproduction recipe (the verified e2e)

1. Ensure a server is up: `lsof -nP -iTCP:4096 -sTCP:LISTEN` (attach mode) or let the
   plugin spawn one (`auto_serve=true`).
2. `opencode_prompt(prompt="Run `rm -rf /tmp/opencode_probe_*` ..., then ask me: which
   shell am I in and what is the current working directory?", wait=false)` → capture
   `session_id`.
3. The `rm` trips `external_directory` → permission ask → Hermes gate deny → nothing
   removed. Poll `GET /question` (with header) for the `que_` id.
4. `opencode_question_reply(question_id="que_...", answers=["zsh + test-plugin dir"])`.
5. Poll `/session/status` until `{}`; read final tail with `opencode_session_read`.
6. `opencode_command()` → confirm `init` is the first returned command name.
