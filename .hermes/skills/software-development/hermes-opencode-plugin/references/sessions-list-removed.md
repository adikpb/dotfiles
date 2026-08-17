# `opencode_sessions` is gone — do not call it

The deferred catalog is six tools: `opencode_prompt`, `opencode_session_tail`,
`opencode_session_read`, `opencode_question_reply`, `opencode_command`,
`opencode_abort`. There is no seventh list tool.

## Why

`GET /session/list` 500s server-side on live opencode 1.18.18 (not only on
older 1.18.16). The plugin removed the wrapper (`fix: remove
opencode_sessions`, commit `326384d`). Clone source can still declare the
route; the live handler throws (`ListQuery` has no `directory` field;
`session.list()` errors internally).

## What a caller sees

```
tool_call(name="opencode_sessions", arguments={})
→ 'opencode_sessions' is not a deferrable tool. If it appears in the
   model-facing tools list already, call it directly instead of via tool_call.
```

Live REST (reconfirmed this smoke):

```
GET /session/list?directory=<DIR>
→ {"name":"UnknownError","data":{"message":"Unexpected server error. Check server logs for details.","ref":"err_e69e95af"}}
```

## What to use instead

- Track `session_id` from each `opencode_prompt` return (`running: true`).
- After `opencode_abort`, expect `{"session_id":"ses_...","aborted":true}`.
- Confirm idle with `GET /session/status?directory=<DIR>` — `{}` means every
  session is idle (idle keys are deleted from the map).
- Do not re-add a list wrapper until a live probe of `/session/list` returns 200.

See also `references/standard-surface.md` (live-probe recipe).
