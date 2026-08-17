# opencode v1/v2 API surface — integration pitfalls (condensed)

Proved live against opencode **v1.18.16** (`/opt/homebrew/bin/opencode`) on 2026-08-13 during the hermes-opencode-plugin migration.

## CRITICAL — v2 read stores are only populated for v2-prompted sessions

A session driven through the **v1** `prompt_async` surface returns EMPTY from the v2 read endpoints even after a completed turn:
- `GET /api/session/{id}/history?after=0&limit=8` → `{"data": []}`
- `GET /api/session/{id}/context` → `{"data": []}`
- `GET /api/session/active?directory=…` → `{"data": {}}`

The **same** session driven through the **v2** surface (`POST /api/session` + `POST /api/session/:id/prompt` with `{"prompt":{"text":…},"resume":true}`) returns real data:
- `history` → durable `session.next.*` events, each with `durable.seq` (e.g. `session.next.prompt.admitted`, `prompted`, `step.started`, …).
- `context` → the active message window (`{id, type:"user"|"assistant", text|content, …}`).
- `active` → `{"<sessionID>": {"type":"running"}}` **mid-turn** (empty `{}` when idle).

**Consequence:** a "read=v2, prompt=v1" hybrid is NON-FUNCTIONAL. You cannot mix transports across the session lifecycle. Either stay fully v1, or go fully v2 (v2 prompt + v2 read + v2 idle detection via `active`/event-replay). No partial adoption.

## Envelopes differ: v2 wraps, v1 is bare

- v1 responses are bare JSON: `GET /session/status` → `{sessionID: {type:"busy"}}`, `GET /session/:id/message` → list, `POST /session/:id/prompt_async` → 204.
- v2 read/command responses are WRAPPED: `{"data": …}`. A client that does `isinstance(parsed, list)` (as `client.commands()` did for v1) silently breaks on v2 — returns `[]`. **Unwrap `parsed["data"]` for v2 routes.**
- v2 `context` → `{"data": [messages]}`. v2 `/api/command` → `{"data":[…]}` and returns ONLY server-registry (non-TUI) commands (v1 returned builtin `init`).
- v2 `/api/health` → `{"healthy":true}` — a STRICT DOWNGRADE from v1 `/global/health` which includes `"version":"1.18.16"`. Keep v1 health.

## Where v2 genuinely helps (vs v1) — recon consensus

- **v2 `POST /api/session/{id}/interrupt`** — the one clean win; v1 has no interrupt.
- **v2 `event?after=<seq>` replay** — fixes reconnect loss (v1 `/event` has no replay, which forced the bridge's tail-fingerprint dedup). But carries NO `session.status` idle/busy and NO `session.next.start/stop`; v2 coordinator sessions lack `session.status`, so idle detection must stay on v1.
- **v2 `/api/session/active`** — cleaner active-set than v1 `GET /session/status` (which deletes idle sessions) — BUT only works for v2-prompted sessions (see split above).
- **v2 `history`/`context`** — durable seq + `hasMore`, survives compaction (v1 `before`-cursor is invalidated mid-pagination) — BUT only for v2-prompted sessions.

## Where v2 does NOT help

- **Ask/reply event families** `permission.v2.asked` / `question.v2.asked`: the omo-slim orchestrator on v1.18.16 emits ONLY v1 events; subscribing is dead dispatch + double-handling risk. Reply bodies (`{reply,message?}`, `{answers:string[][]}`) are identical v1/v2.
- **Transport** (`/command`, `/global/health`): keep v1 (wrapped envelope + downgraded health).
- **SDK `@opencode-ai` (PyPI alpha `v0.1.0a36`, httpx-based)**: kills the plugin's deliberate zero-dep `dependencies = []`; pins an alpha against a server pinned to v1.18.16 (version-drift); v2-tilted. Keep the hand-rolled stdlib `http.client` client.
- **`/api/session/{id}/wait`** = 503 stub.

## Technique: LIVE-PROBE before adopting any v2 endpoint

Recon summaries + vendored-source reading MISSED both the wrapped envelope and the v2-session-store split. Before committing to a v2 adoption, spawn the real `opencode serve` via the plugin's own `serve`/`client` (so auth + base URL match production) and curl each candidate route against a real session. This caught both gotchas that recon did not.

## Single-branch rule (user, 2026-08-13)

"No v1/v2 fallback dual-branch code." If a v2 capability is non-functional with the plugin's chosen transport, DROP it — do not keep a v1 fallback path. The live probe decides; if split, drop rather than hybridize.
