---
name: security-tool-analysis
description: "Extract patterns from open-source AI SOC codebases."
version: 1.0.0
author: Hermes Agent
tags: [security, SOC, AI-agents, pattern-extraction, open-source-research]
---

# Security Tool Analysis — Pattern Extraction from Open-Source AI SOCs

## When to Use

- User asks to research an open-source AI SOC or security tool and extract what's useful
- You need to evaluate whether a project's patterns transfer to your stack
- You're comparing multiple open-source AI SOC solutions for architecture decisions
- User says "look at this project" and you need to produce structured findings

## Methodology

### Step 1: Understand the target's architecture at the right level

Read the README and architecture docs first. Get the big picture before diving into source code. Identify:

- **Language stack** — Python vs Go vs TypeScript vs polyglot
- **Infrastructure dependencies** — Kafka, Postgres, Neo4j, ClickHouse, Redis, Qdrant?
- **Deployment model** — single binary, Docker Compose, Kubernetes, microservice mesh?
- **Agent architecture** — single LLM call, LangGraph DAG, custom state machine, multi-agent?

### Step 2: Identify the core pattern vs. infrastructure wrapper

For each feature, ask: "Is this a transferable design pattern or a wrapper around their specific infrastructure?"

| Looks like infrastructure | Looks like a pattern |
|---|---|
| Uses Kafka for event spine | Uses a 3-table ledger for audit trail |
| Writes to Postgres with RLS | State machine with typed Pydantic state object |
| Uses Neo4j attack graph | Blast-radius calculation from adjacency data |
| Reads from ClickHouse event lake | Tool-based query interface for event search |
| Qdrant RAG over MITRE STIX | Local MITRE technique lookup from JSON map |

### Step 3: Extract the 5 critical patterns

For any AI SOC investigation agent, look for these:

1. **Agent orchestrator** — How does the agent decide what to do? (LangGraph DAG? Sequential loop? One-shot?)
2. **Tool definitions** — How are tools defined and dispatched? (Function-calling? Custom router? Fixed pipeline?)
3. **Audit trail / ledger** — Are agent decisions logged? At what granularity? (Per-prompt? Per-tool-call? Per-step?)
4. **State management** — How does state flow between steps? (Mutable dict? Pydantic model? SQL-backed?)
5. **Grounding mechanism** — How does the agent cite evidence? (Tool call IDs? Query references? Free text?)

### Step 4: Map findings to your stack

Create a transferability matrix:

| Pattern from X | Port to our stack | Effort | Value |
|---|---|---|---|
| Ledger schema | Port schema + writer | Low | High |
| Tool module structure | Mirror file layout | Low | High |
| LangGraph DAG | Async loop w/ state machine | Medium | High |
| Neo4j attack graph | Defer — needs Graph DB | High | Low |

### Step 5: Save the research

Write a reference file under this skill with the analysis. Include:
- What was extracted (with source code references)
- What was skipped and why
- Specific file paths in the source project for future reference
- Transferability matrix

## What to Skip (always)

- **Infrastructure scaffolding** — Docker files, CI/CD, deployment configs for OTHER architectures
- **Multi-tenant RLS** — irrelevant for local/SQLite deployments
- **Cloud-specific connectors** — not applicable unless you're integrating those services
- **Vendor-specific APIs** — Sentinel, GuardDuty, CloudTrail parsers

## Guard Against

- **Assuming their stack = best practice** — a 22-microservice mesh may solve problems you don't have
- **Infrastructure FOMO** — "they use Neo4j so we need a graph DB" is almost always wrong for SQLite-scale
- **Pattern over-extraction** — just because they have an MCP server doesn't mean you need one

## Reference

`references/aisoc-pattern-extraction.md` — detailed analysis of the AiSOC (wunitb/AiSOC) project, with specific file paths, extracted patterns, and the full transferability matrix for a SQLite-based stack.
