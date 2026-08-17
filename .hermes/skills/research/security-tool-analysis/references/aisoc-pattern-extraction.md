# AiSOC (wunitb/AiSOC) — Pattern Extraction Analysis

Extracted from session 20260728, live codebase at v7.3.1/v8.0. Source: https://github.com/wunitb/AiSOC

## Project Profile

- **Stack**: Polyglot microservice mesh (Python, Go, TypeScript, Next.js, ~22 services)
- **Infrastructure**: Kafka, PostgreSQL, ClickHouse, Neo4j, OpenSearch, Qdrant, Redis
- **Agent framework**: LangGraph (~600-line orchestrator)
- **License**: MIT — fully readable and forkable
- **Maturity**: Production-grade, CI-gated eval harness

## Extracted Patterns (transferable to Aegis SOC)

### 1. Investigation Ledger (3-table design) — HIGH VALUE

**Source files:**
- `services/api/migrations/008_investigation_ledger.sql` — schema
- `services/agents/app/investigator/ledger.py` — writer (~200 lines)

**Schema summary:**
- `investigation_runs` — one row per investigation (id, case_id, model_used, status, iterations, started_at, completed_at)
- `investigation_events` — append-only, one row per agent step (run_id, seq, kind, agent, summary, payload, input_hash, output_hash, duration_ms)
- `investigation_artifacts` — large blobs (llm_prompt, llm_response, tool_input, tool_output, report)

**Why it's a pattern (not infrastructure):** The 3-table design is protocol-agnostic. No Kafka, no Postgres-specific features beyond RLS (which we skip). The writer pattern (`start_run → record_event → record_artifact → complete_run`) is a pure logic concern. Ported directly to SQLite in ~100 lines.

**Our adaptation:** Replaced UUID PKs with TEXT, removed RLS, added `alert_id` foreign key to `alerts`. Writer uses synchronous sqlite3 instead of asyncpg. Everything else stays.

### 2. LangGraph Workflow DAG — MEDIUM VALUE

**Source file:** `services/agents/app/graph/workflow.py` (~90 lines)

**Node flow:**
```
auto_triage ─┬─ (FP/benign high-confidence) ──► END
             └─ (else) ──► triage ──► enrichment ──► investigation ──► attack_path ──► END
```

**Why it's a pattern:** The DAG structure (conditional routing, early exit, sequential steps) is general-purpose. The LangGraph dependency is incidental — the same logic works as an async Python state machine with a `switch/case` on state status.

**Our adaptation:** Replace `StateGraph(dict)` with an async `while` loop that checks `state.status` after each node. Node functions remain identical: they take `InvestigationState`, return `InvestigationState`.

### 3. Pydantic InvestigationState — HIGH VALUE

**Source area:** `services/agents/app/models/state.py` (deduced from usage)

**Key fields (from usage across agents):**
- `incident_id`, `case_id`
- `status: AgentStatus` (running, completed, failed, cancelled)
- `iteration_count`, `max_iterations`
- `findings: list[str]` — what the agent found
- `proposed_actions: list[ProposedAction]`
- `threat_intel: dict`
- `tool_results` (inferred)

**Why it's a pattern:** Typed state eliminates the ad-hoc dict wrangling that causes 90% of bugs in agent loops. Every node function knows exactly what it reads and writes.

### 4. Tool-per-file module structure — HIGH VALUE

**Source area:** `services/agents/app/tools/`

- `graph.py` — wraps Neo4j graph API for agent use
- Other tool files per domain

**Why it's a pattern:** Clean separation of concerns. Each tool is a standalone async function with explicit parameters and return types. The agent imports only the tools it needs.

### 5. Auto-triage with early exit — MEDIUM VALUE

**Source file:** `services/agents/app/agents/auto_triage_agent.py`

Runs before the main investigation. If LLM classifies alert as FP/benign with high confidence, closes it immediately. Saves downstream tool calls and LLM costs.

### 6. Evidence grounding — MEDIUM VALUE

Enforced across the system: every LLM claim must cite a tool call or query result. System prompts explicitly require `evidence_cited` to reference specific tool call IDs. Test harness asserts this.

## What We Skipped (and why)

| Feature | Why skip |
|---|---|
| Neo4j entity graph (17 node labels, 14 edge types) | Needs a graph DB. SQLite JOINs suffice at our scale |
| Apache Kafka event spine | Our events are CSV-ingested, not streaming |
| Qdrant vector RAG over MITRE ATT&CK | Local MITRE map = one JSON file, no vector DB needed |
| 22-microservice mesh | We're a single FastAPI process. Keep it that way. |
| Playbook engine with blast-radius gating | Defer to v0.3 |
| Attack-path agent (walks Neo4j) | Needs Neo4j — defer until needed |
| React/Next.js console with Investigation Rail | Our dashboard is embedded HTML. Extend existing modal. |
| MCP server (13 tools for IDE agents) | Cool but not needed. Defer. |

## Key Source Files for Reference

| File | What it teaches |
|---|---|
| `services/api/migrations/008_investigation_ledger.sql` | Clean 3-table design with append-only enforcement |
| `services/agents/app/investigator/ledger.py` | Ledger writer pattern (~200 lines, ~50% is error handling) |
| `services/agents/app/graph/workflow.py` | How to wire a multi-agent DAG (5 nodes, conditional routing, early exit) |
| `services/agents/app/tools/graph.py` | Tool-as-function pattern calling an external service |
| `packages/aisoc-sandbox/src/aisoc_sandbox/` | Simulated offline agent funnel — useful eval pattern |

## Transferability Matrix

| Pattern | Port effort | Value | Priority |
|---|---|---|---|
| Investigation Ledger (3 tables + writer) | Low (~100 lines) | High | P0 |
| Pydantic InvestigationState model | Low (~50 lines) | High | P0 |
| Tool-per-file module | Low (~30 lines scaffolding) | High | P0 |
| LangGraph DAG → async state machine | Medium (~150 lines) | High | P1 |
| Auto-triage with early exit | Low (~80 lines) | Medium | P1 |
| Evidence grounding in prompts | Low (~10 lines per prompt) | Medium | P1 |
| Cross-alert AlertHistoryStore | Medium (~200 lines) | Medium | P2 |
| Threat intel tools (AbuseIPDB, MITRE map) | Medium (~150 lines) | Low | P2 |

## Google Cloud Agentic SOC Validation

Google's Agentic SOC (https://cloud.google.com/solutions/security/agentic-soc) uses the same core pattern:
- **Triage & Investigation agent** — exactly our target
- **Hybrid: deterministic playbooks + AI agents** — validates Phase 1 → Phase 2 progression
- **Human-in-the-loop for critical actions** — aligns with our guardrails design
- **"30 min → 60 sec"** — useful benchmark target for measuring improvement
