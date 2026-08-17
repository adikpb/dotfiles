---
name: residual-version-surface-audit
description: Audit a codebase for residual old-version API surface.
version: 1
author: hermes-curator
license: MIT
metadata:
  hermes:
    tags: [audit, code-review, api-versioning, migration, verification]
    related_skills: [documentation-audit, requesting-code-review, systematic-debugging]
---

# Residual API-version surface audit

## When to use
- A parent task asks you to confirm a repo is "100% v1-ONLY / zero residual v2 surface" (or equivalent) after a version migration.
- You are auditing SOURCE + TESTS + README + WIKI for leftover old-version API usage, event types, wrappers, or contradictory prose.
- The deliverable is a machine-validated JSON finding list (`{findings:[...], summary}`).

## Methodology
Treat the audit as a set of explicit, SCOPED checkpoints. For each, GREP the actual source rather than trusting the prior round's "fixed" claim — re-verify independently.

1. **Model/shape normalization (source).** Locate the constructor/request builder (e.g. `create_session`). Confirm it attaches the normalized shape ONLY when all required keys are present — no pass-through branch that can emit a null/missing key or a bare partial object.
2. **Routes (code/tests/scripts).** Grep for the old prefix (e.g. `/api/`). Confirm client code calls only root-path v1 routes. Docs/wiki MAY still list `/api/` routes as *server reference* — that is out of scope unless the task names those files. Respect the explicit scope: a `/api/` check scoped to "code/tests/scripts" does NOT flag wiki reference tables.
3. **Envelope / event types / wrappers / rationale prose (code/tests/scripts).** Grep for `{data:}` unwraps, old-version event type names, wrapper keywords (e.g. `resume`), and v2-rationale prose. Distinguish the SSE `data:` frame *prefix* (standard, allowed) from a v2 `{data: ...}` JSON *envelope* (disallowed).
4. **Docs/wiki version annotations.** For named wiki files, confirm any "live version X.Y.Z" reference is annotated as historical/vendored with the current verified target (e.g. "(vendored audit clone; live verified target is v1.18.16 per README)"). Un-annotated live-version references are findings.
5. **Green gate.** Run the linter + test suite (`ruff check .`, `pytest -q`). Report the pass count verbatim.

## Pitfalls
- **read_file dedup false-positive (fresh subagent).** When running as a subagent, `read_file` may refuse with "File unchanged since last read — refer to the earlier read_file result" even though you never read that file THIS turn (its dedup hashes off the parent/earlier conversation). Do NOT loop re-requesting it — retrieve content via `search_files` (content mode, regex) or `terminal` grep instead. This occurred repeatedly in a round-3 re-audit and `search_files` resolved it immediately.
- **Machine-validated JSON output contract.** If the task specifies a JSON Schema and a validator parses your response, return ONLY the JSON object (a ```json fence is allowed). Any leading/trailing prose makes the validator throw "Response is not valid JSON: Expecting value: line 1 column N". Put all narrative in the JSON `summary` field. A prior round of this audit was rejected for exactly this — the rejected response had prose before the JSON.
- **Scope creep.** Don't flag reference documentation that explicitly disclaims use (e.g. "the /api/ question routes are NOT used by the plugin"). The audit scope is the plugin's actual behavior, not the server's full documented surface.

## Output
Return `{"findings": [], "summary": "0 findings"}` when clean (verify each checkpoint first). Each finding: `{file, line, issue, severity, fix}`.

## references
- `references/v1-only-audit-checklist.md` — concrete grep commands + the 4-checkpoint template from a real v1-only re-audit (168 pytest passing, ruff clean).
