# Reply-route directory exactness — `POST /question/{id}/reply` & `/permission/{id}/reply`

The opencode v1 **reply** routes are directory-scoped AND directory-EXACT. This bit the
live `opencode_question_reply` tool this session (HTTP 404 on a valid, held `que_` id).

## Reproduction (live server, opencode v1.18.16)

Project dir where the question lives:
`DIR=$HOME/src/hermes-opencode-plugin`

```
QID=que_example_reply   # any live pending ask

# EXACT realpath, NO trailing slash -> HTTP 200 true  (answer accepted)
curl -s -m5 -X POST "http://127.0.0.1:4096/question/$QID/reply" \
  -H "x-opencode-directory: $HOME/src/hermes-opencode-plugin" \
  -H 'Content-Type: application/json' -d '{"answers":[["<label>"]]}' ; echo

# parent dir -> HTTP 404  Question request not found
curl -s -m5 -X POST "http://127.0.0.1:4096/question/$QID/reply" \
  -H "x-opencode-directory: $HOME" \
  -H 'Content-Type: application/json' -d '{"answers":[["<label>"]]}' ; echo

# trailing slash -> HTTP 404
curl -s -m5 -X POST "http://127.0.0.1:4096/question/$QID/reply" \
  -H "x-opencode-directory: $HOME/src/hermes-opencode-plugin/" \
  -H 'Content-Type: application/json' -d '{"answers":[["<label>"]]}' ; echo

# absent header -> HTTP 404
curl -s -m5 -X POST "http://127.0.0.1:4096/question/$QID/reply" \
  -H 'Content-Type: application/json' -d '{"answers":[["<label>"]]}' ; echo
```

Body: `{"answers":[["<option label>"]]}` — answers is a **list of lists**; a flat
`["fish"]` 400s with `Expected QuestionAnswer, got "fish"`.

## The plugin bug this exposed

`OpenCodeClient.question_reply` (`hermes_opencode/client.py`) sends **no directory**:
```python
def question_reply(self, rid, answers):
    self.request("POST", f"/question/{rid}/reply", body={"answers": answers})  # directory NOT forwarded
```
The sibling `permission_reply` (same file) **does** forward it:
```python
def permission_reply(self, rid, reply, message=None, directory=None):
    self.request("POST", f"/permission/{rid}/reply", body=body, directory=directory)
```
`request()` only adds the `x-opencode-directory` header when a `directory` is passed —
otherwise it falls back to `self.directory` (bridge cwd realpath). If that does not
**byte-match** the opencode-serve project dir, the live `opencode_question_reply`
returns `HTTP 404 Question request not found`, even though the `que_` id is valid and
correctly held by the bridge.

**Fix (APPLIED in commit `5a9c2ac`):** `question_reply(rid, answers, directory=None)`
forwards `directory` (mirrors `permission_reply`); `bridge.answer_question` passes
`self._directory` (canonical realpath); `approval._reply_question` passes
`self._directory`. The bridge resolves the right dir as `self._directory` =
`realpath(cfg.get("directory") or os.getcwd())` — which is now also the canonical
path the SSE subscription uses (see `sse-location-filter-root-cause.md`), so the
reply and the event subscription agree on the directory. Live
`opencode_question_reply(question_id='que_…')` now succeeds against a held id.

## Diagnostic sequence when a reply 404s

1. Capture the live `que_` id: `GET /question?directory=$DIR` (header or query both work for GET).
2. Reproduce the reply with curl, varying the `x-opencode-directory` header (matrix above)
   to find the **exact** string the server accepts.
3. Compare to the bridge's `self._directory`. If they differ, the plugin is sending the
   wrong directory. If they match but the live tool still 404s, the running bridge
   instance was built with a stale/mismatched dir — **restart Hermes to reload the plugin**
   (the module is already imported in the running process; a patch alone won't take effect).
