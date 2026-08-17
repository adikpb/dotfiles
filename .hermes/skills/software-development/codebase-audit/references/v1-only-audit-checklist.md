# v1-only / residual v2-surface audit — concrete checklist

Derived from a hermes-opencode-plugin round-3 re-audit (168 pytest passing, `ruff` clean, 0 findings).

## Grep probes (run from repo root, adapt prefixes to your version pair)
- Routes in source: `search_files` pattern `/api/|@app\.(get|post)|route\(` on `hermes_opencode/`.
  Expected: zero `/api/` hits in client code; only root-path routes (`/session`, `/global/health`, `/event`, `/command`, `/permission`, `/question`).
- Model shape: read `client.py` `create_session`; confirm `if model_id and provider_id: body["model"] = {"id": model_id, "providerID": provider_id}` and NO other branch (no null/missing `providerID`, no bare `{id}`).
- Event types / wrappers / prose: pattern `session\.status|server\.instance|session\.message|session\.question|event_type|v2|resume|unwrap|data\.get|\[.data.\]` on `hermes_opencode/` and `tests/`.
  Expected: only v1 types (`session.status`, `server.instance.disposed`, `server.connected`, `server.heartbeat`); no `resume` wrapper. NOTE: "v2026.8.3" mentions are the Hermes version, not opencode v2 — not findings.
- Wiki version refs: pattern `1\.18\.13|1\.18\.16|live|vendored|historical|annotat` on `*.md`.
  Expected: every `1.18.13` "live" reference annotated (e.g. opencode-event-streams.md frontmatter + E2E note carry "(vendored audit clone; live verified target is v1.18.16 per README)" / "(historical — current README verified target is v1.18.16)").
- v2 surface in docs: pattern `/api/|v2|resume|rationale|unwrap` on `*.md` — inspect NAMED wiki files only; reference tables that say "NOT used by the plugin" are acceptable, not findings.

## Green gate
```
uv run ruff check .
uv run pytest -q
```

## Scope discipline (critical — prevents false-positive findings)
- `/api/` check = code/tests/scripts ONLY (task-scoped). Wiki `opencode-http-api.md` listing `/api/` routes is server reference, out of scope.
- Named wiki files for the version-annotation check: `opencode-question-api.md` + `opencode-event-streams.md` (task-specific — adapt to your task's named files).
- The plugin's actual client routes were ALL root-path v1; the v2 `/api/` surface exists only in wiki reference docs that disclaim plugin use.

## Tooling note
If `read_file` refuses with "File unchanged since last read" for a file you have NOT read this turn (common for fresh subagents), use `search_files` (content mode) or `terminal` grep to fetch the content instead of re-requesting `read_file`.
