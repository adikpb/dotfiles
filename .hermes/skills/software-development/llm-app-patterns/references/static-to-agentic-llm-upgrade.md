---
name: static-to-agentic-llm-upgrade
description: Upgrade static-LLM prompts to tool-calling agentic loops.
---

# Static-LLM → Agentic Pipeline Upgrade

A repeatable three-phase pattern for converting a single-shot-LLM system into a tool-using agentic loop. Works best when the existing system already has a database, Pydantic models, and an LLM client — just no tools or iteration.

## The Pattern

### Phase 0 — Schema & Foundation (commit 1)

- **Audit trail first.** Every LLM call, tool execution, and decision gets logged before any tool code is written.
- Pattern: AiSOC's investigation ledger (3 tables: `investigation_runs`, `investigation_events`, `investigation_artifacts`).
- Create a `Ledger` class with: `start_run(alert_id)` → `record_event(run_id, kind, agent, summary)` → `record_artifact(event_id, name, content)` → `complete_run(run_id)`.
- The ledger is write-only from the agent's perspective — the agent never reads it during execution. It exists purely for post-hoc analysis and debugging.

### Phase 1 — Fixed Enrichment Pipeline (commit 2)

- **Deterministic tool calls before any LLM call.** Python code decides which tools to call based on available data fields (sender, domain, recipient, IP, etc.).
- Create a `TOOL_REGISTRY` dict mapping tool names to functions, plus a `run_tool(name, conn, **kwargs)` dispatcher.
- Organize all tools in a single module (`src/tools/<domain>.py`). Each tool is a function that takes a `conn` and returns a serializable dict.
- Collect every tool result, build an enriched prompt, then make exactly one LLM call.
- Every tool call + LLM call gets recorded in the ledger from Phase 0.

### Phase 2 — Agentic Tool-Calling Loop (commit 3)

- **LLM chooses tools via function calling.** Replace the single enriched prompt with an iterative loop.
- Add `build_tool_definitions()` that generates OpenAI-compatible tool definitions from the registry. Each definition needs: `name`, `description`, `parameters` (JSON Schema with `type`, `properties`, `required`).
- Core loop (≈60 lines):
  ```python
  while iteration < max_iterations:
      response = client.chat.completions.create(messages=messages, tools=tool_defs, tool_choice="auto")
      if response.choices[0].message.tool_calls:
          for tc in response.choices[0].message.tool_calls:
              result = run_tool(tc.function.name, conn, **json.loads(tc.function.arguments))
              messages.append({"role": "tool", "tool_call_id": tc.id, "content": json.dumps(result)})
      else:
          verdict = parse_json(response.choices[0].message.content)
          if valid_verdict(verdict): break
  ```
- Add nudge-retry for non-JSON responses from the LLM.
- Fall back to deterministic enrichment if LLM is unavailable entirely.
- Wire up a new API endpoint alongside the old one so both can be compared.

### Phase 2.5 — Dashboard Integration (commit 4)

- **New API endpoint for ledger data:** `GET /api/alerts/{alert_id}/investigations` — returns runs with nested events and artifacts from the investigation ledger. Gives the dashboard a read-only window into agent activity.
- **Single endpoint, single button:** Merge both paths into one: `POST /api/alerts/{alert_id}/analyze` calls the agentic loop directly. No separate `/analyze-agentic` endpoint. In the UI, replace the old "Analyze" and "Deep" pair with a single "🔍 Deep" button in the table row and "🔍 Deep Investigate" in the modal. Everything uses one unified `analyzeAlert()` JS function.
- **No phase badges:** Do not display "Phase 1" or "Phase 2" labels anywhere. The investigation report heading is "Investigation Report", not "LLM Analysis". Investigation run summaries in the history list show run ID, status, model, and timestamps — no per-run "Agentic" vs "Standard" label since every run is now agentic. Remove all conditional badge logic at both the analysis-card level and the run-list level.
- **Agentic flag (internal only):** Still add `final_findings["agentic"] = True` in the agentic loop's verdict dict before saving (`src/agent.py`). This allows the backend to distinguish agentic from deterministic-fallback runs if needed for future logic, but the dashboard does not expose it visually.
- **Investigation history section:** Add below the investigation report in the alert detail modal. Use HTML `<details>` elements for collapsible runs — avoids needing JS accordion logic. Each run shows: run ID, model, status, timestamps, iteration count, and a list of tool calls with kind, agent, summary, duration, and linked artifacts.
- **Async data loading:** Fetch investigation history after the modal renders via `setTimeout(() => loadInvestigations(a.id), 0)` — the modal body must be in the DOM before the async call completes. IMPORTANT: use `a.id` here (plain JS variable reference), NOT `${a.id}` (template literal syntax) — the setTimeout call is OUTSIDE the backtick template literal that builds the modal HTML, so `${...}` is invalid JS and causes a silent script parse failure, preventing ALL modal functions from loading.
- **Inline dashboard caveat:** In single-file dashboards (HTML string in api.py), every edit requires careful escaping. JS template literals (backticks) inside Python f-strings clash — use string concatenation or escape backticks. Test every dashboard change by running the server and loading the page, not just by inspecting the string.
- **Retroactively patching existing records:** When adding the `agentic` flag after the fact (e.g., because a run completed before the flag was introduced), patch the DB directly with SQL rather than re-running the analysis:
  ```sql
  UPDATE alerts SET agent_analysis = json_set(agent_analysis, '$.agentic', json('true')) WHERE id = ?;
  ```

## Key Design Decisions

| Decision | Default | Reasoning |
|---|---|---|
| **Framework** | None (custom 60-line loop) | No existing framework saved more code than it cost in complexity for a single-agent loop. Consensus across all 2026 framework comparisons: "start without one." |
| **Tool definition format** | OpenAI function-calling (`tool_choice="auto"`) | Universal format supported by OpenAI SDK, LiteLLM, and most local model servers. Qwen 3.5 may produce XML-style `<tool_call>` instead — handle via `finish_reason == "tool_calls"` on the response, not content parsing. |
| **Ledger storage** | SQLite same DB as alerts/events | Simple, zero-dependency, consistent with existing schema. SQLite WAL mode: on delete must rm `.db-wal` and `.db-shm` too. |
| **Iteration limit** | 8 | Enough for typical SOC investigation (2-3 tools → analyze → final verdict). Prevents runaway loops. |
| **Fallback** | Deterministic enrichment (same tool queries, no LLM) | When LLM is down, the deterministic pipeline produces a reasonable result. Never silently return an error. |

## Model-Specific Handling

- **Qwen 3.5 (7-9B):** At the edge of reliable function calling. May emit malformed JSON — always wrap `json.loads(tc.function.arguments)` in try/except with empty `{}` fallback. Use 120s+ timeout for reasoning models; they spend 200-500 tokens reasoning before generating content, so a 60s timeout causes silent fallback to deterministic responses.
- **Code-generation models (Smolagents/CodeAct approach):** Write Python instead of JSON tools. Works better with smaller models. Consider if Qwen 3.5 function-calling is unreliable enough to justify the sandboxing cost.
- **Timeout config:** Put model-specific timeouts in `config.yaml` — the LLM call builder reads it from there.

## User Preferences (Aegis SOC project)

- Look up framework/library decisions online before recommending. Don't answer from cached knowledge — research first.
- Clean incremental commits: Phase 0 (schema+ledger), Phase 1 (tools+pipeline), Phase 2 (agentic loop) — each a separate commit.
- `npm run test` should run the actual test suite, not a placeholder.
- Interactive OpenCode TUI may stall on first startup (plugin loading) — use `opencode run` one-shot for first invocation.

## Pitfalls

- **Stale function-calling format:** The OpenAI SDK `tool_choice="auto"` format changes across library versions. Pin `openai>=1.30.0` and test with `finish_reason == "tool_calls"`.
- **Tool result truncation:** Tool responses can grow large (100+ events). Always truncate before appending to messages — 4000 chars per tool result is a safe ceiling.
- **Missing `requirements.txt` after uv migration:** When switching from `requirements.txt` to `pyproject.toml`, committing the deletion separately avoids confusing git bisect.
- **Clean reset:** Deleting `aegis.db` without also deleting `aegis.db-wal` and `aegis.db-shm` restores old data from the WAL on next connection. Also delete `ingestor_state.json` to force a fresh re-ingest. Full reset: `rm -f aegis.db aegis.db-wal aegis.db-shm ingestor_state.json`.
- **OpenCode first startup:** First `opencode` TUI session takes time ("Loading plugins…"). Use `opencode run` (one-shot) for first run to avoid frustration, then switch to interactive TUI for iteration.
- **LM Studio queue pile-up:** When testing agentic loops against a local LLM, never fire multiple deep-analysis calls concurrently. Each call queues at the LLM server and runs sequentially. See `references/local-llm-queue-discipline.md` for detection, workflow, and avoidance patterns.

## Related Skills

- `uv-python-project-init` — Python project setup
- `systematic-debugging` — Debugging agentic loops
- `spike` — Throwaway experiments for validating tool definitions

## Verification

```bash
# After each phase:
npm run test                    # Existing tests must still pass
.venv/bin/python tests/smoke_phase1.py  # Smoke test new modules
.venv/bin/python -c "from src.agent import investigate_alert_agentic; print('OK')"  # Import check

# Full end-to-end (requires running server + LLM):
curl -X POST http://localhost:8090/api/alerts/1/analyze
```
