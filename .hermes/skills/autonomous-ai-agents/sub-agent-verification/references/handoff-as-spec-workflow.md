# Handoff-as-Spec Workflow (Aegis SOC Session)

This reference documents a concrete session where a detailed handoff document was written as a markdown spec, then fed to opencode as a build brief for a multi-file implementation.

## The Patterns

### 1. Write a detailed spec first

The handoff document (`agentic-llm-handoff.md`) included:
- **Current state** — what exists, file map, key decisions
- **Existing solutions research** — AiSOC, Google Agentic SOC, SOC Copilot
- **Extractable knowledge** — what patterns we can take from AiSOC
- **Phased migration plan** — Phase 0 (schema/ledger) → Phase 1 (tools/models/agent rewrite)
- **File-by-file breakdown** — exact paths for new files and what each should contain
- **Guardrails and constraints** — max iterations, timeout, local-first, SQLite backend
- **Gotchas** — learned from prior sessions (function calling with Qwen, token limits, etc.)

### 2. Feed spec to opencode

```bash
opencode run "Build Phase 0 and Phase 1 from the spec" -f .hermes/plans/agentic-llm-handoff.md
```

What opencode did automatically:
- Read the spec and built a todo list from it
- Mapped the codebase (read all source files, globbed test files)
- Created tasks: Phase 0 → Phase 1 in order
- Detected and fixed LSP errors (type annotations, import paths)
- Attempted to run tests (blocked by permission — known limitation)

### 3. Post-opencode verification

After opencode finished:
- **Run existing tests**: `npm run test` (but `package.json` had a placeholder — fixed it)
- **Write a smoke test**: imported new modules, tested lifecycle end-to-end
- **Check git state**: `git diff --stat` and `git status --short`

### 4. The verification caught

| Issue | How caught |
|---|---|
| `package.json` test script was a placeholder | Manually ran `npm run test`, got the error |
| FK constraint error on `investigation_runs.alert_id` references `alerts(id)` | Smoke test hit it |
| `source_type NOT NULL` on events table | Smoke test needed full column list |
| `migrate()` takes path, not connection | First smoke test attempt failed |

## Key insight

The handoff document does double duty: it's both the specification (for you to review/approve) and the build brief (directly fed to opencode). This avoids the "translation loss" of summarizing a spec into a prompt — the orchestrator reads the full document, including constratins and gotchas.
