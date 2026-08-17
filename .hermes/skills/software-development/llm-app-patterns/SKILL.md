---
name: llm-app-patterns
description: "Build agentic LLM apps: JSON, UI cards, tools."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [llm, json, dashboard, agentic, ui, fastapi]
    related_skills: [sub-agent-verification]
---

# LLM application patterns

Class-level patterns for shipping LLM features in a product: schema-valid JSON replies, structured dashboard cards, upgrading a static prompt to a tool-calling loop, and debugging the JS that renders those UIs.

Absorbed from: `machine-validated-json-output`, `structured-llm-display`, `static-to-agentic-llm-upgrade`, `web-ui-debugging`.

## When to Use

- Final answer MUST be one JSON object that an external validator will parse
- A dashboard shows raw LLM JSON in a `<pre>` and needs a readable card
- A single-shot LLM call should become a tool-using agentic loop
- Clicks/modals in a Python-served inline-JS dashboard do nothing

Don't use for: generic code review, or researching third-party SOC architectures (`security-tool-analysis`).

## Machine-validated JSON output

Never hand-assemble JSON around a large markdown document. Quotes, backticks, em dashes, and newlines break the object (`Expecting ',' delimiter`).

1. Write the payload as a file (`write_file` `/tmp/<name>_report.md`). Edit that file with `patch`.
2. Serialize with `json.dumps(..., ensure_ascii=False)` via a Python heredoc.
3. Validate the file with the schema/`json.loads` before emitting. The chat reply is the file contents, nothing else.

Full recipe: `references/machine-validated-json-output.md`.

## Structured dashboard cards

Replace a raw JSON `<pre>` with an IIFE that parses the verdict and builds HTML sections (verdict badge, summary, evidence list, recommended actions, confidence). The pattern usually lives inside a JS-in-HTML-in-Python template literal — escape carefully.

Layout and escaping rules: `references/structured-llm-display.md`.

## Static prompt → agentic loop

Three commits, in order:

0. **Ledger first.** Log every LLM call, tool execution, and decision before any tool code. Write-only from the agent's perspective (post-hoc analysis only).
1. **Fixed enrichment.** Python decides which tools to call from available fields. `TOOL_REGISTRY` + `run_tool`. One LLM call on the enriched prompt.
2. **Agentic loop.** LLM chooses tools via function calling. Iteration + stop condition. Same ledger.

Do not jump to Phase 2 without the ledger and the deterministic enrichment path — you lose the ability to compare agent vs pipeline.

Full pattern + local-queue discipline: `references/static-to-agentic-llm-upgrade.md`, `references/local-llm-queue-discipline.md`.

## Web UI debugging (inline JS templates)

Silent JS errors are the #1 cause of "nothing happened" in FastAPI/Flask dashboards that serve JS as template strings.

1. Count `<script>` blocks; compile-check with `new Function(script.textContent)`.
2. Binary-search the failing line if parse fails.
3. `browser_console(clear=false)` after the click. Empty-message errors are often a prior parse error that prevented later code from running.
4. `browser_vision` to confirm the DOM actually changed.

Inline-JS template pitfalls: `references/debugging-inline-js-templates.md`. Full write-up: `references/web-ui-debugging.md`.

## Pitfalls

- Hand-typed JSON around markdown will fail the validator. Always `json.dumps`.
- Template-literal escaping (`\\`, backticks, `${`) is the usual card-render bug, not the model.
- Skipping the ledger makes agent-vs-pipeline regressions undiagnosable.
- Do not ask the vision model to "estimate" a JS bug — compile-check first.

## Verification

- JSON: `json.loads` + schema pass; no prose around the object.
- Card: badges/lists render; no `<pre>` dump.
- Agentic: ledger rows exist for tools + LLM; loop stops on the declared condition.
- UI: `new Function` succeeds; the click changes the DOM.
