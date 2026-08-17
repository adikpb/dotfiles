---
name: machine-validated-json-output
description: "Use when a task's single-JSON reply must match a schema."
version: 1.0.0
author: Hermes Agent
related_skills: [sub-agent-verification, structured-llm-display, hermes-source-development]
category: software-development
---

# Machine-Validated JSON Output

For tasks whose final answer MUST be one JSON object that passes an external validator — e.g. subagent contracts worded "Reply with ONLY the corrected JSON object matching the OUTPUT CONTRACT schema", "No prose before or after", "your FINAL response must be a single JSON object that validates against this JSON Schema". The schema usually has one required top-level key holding a large markdown string (e.g. `{"report": "..."}`).

## Core rule

Never hand-assemble the JSON payload. Hand-typing JSON around a large markdown document is a recurring failure: markdown carries quotes, backticks, em dashes, newlines, and backslashes, and one missed escape breaks the whole object (typical validator error: `Expecting ',' delimiter: line 2 column 21468`). Escaping is the interpreter's job — let it do the escaping.

Workflow that reliably passes:

1. **Write the content payload first, as a file.** `write_file` the markdown/text report to `/tmp/<BASENAME>_report.md`. Edit THAT file with `patch` when wording changes — never fix up the published JSON blob.
2. **Serialize with `json.dumps`** (heredoc keeps shell quoting a non-issue):
   ```bash
   python3 - <<'EOF'
   import json
   md = open('/tmp/BASENAME_report.md', encoding='utf-8').read()
   payload = json.dumps({"report": md}, ensure_ascii=False)
   open('/tmp/BASENAME_final.json', 'w', encoding='utf-8').write(payload)
   print(len(payload))
   EOF
   ```
   `ensure_ascii=False` keeps unicode (em dashes, arrows, emoji) readable while remaining valid JSON.
3. **Round-trip before submitting:** `python3 -c "import json; d=json.load(open('/tmp/BASENAME_final.json')); print(sorted(d.keys()))"` — confirms parse + required keys. If a jsonschema validator is available, run it too.
4. **Emit the exact bytes:** `cat /tmp/BASENAME_final.json` and submit that output verbatim. A ```json ``` fence around it is fine if the contract allows; any other prose violates "No prose before or after".

## Pitfalls

- **Validator rejection → regenerate, don't hand-repair.** A failed parse means the source md (or dict shape) needs fixing; then re-run steps 2–3. Surgical edits into a multi-KB escaped string multiply errors.
- **One editing round = one re-serialization.** Any wording change to the report invalidates the old JSON. Never submit a doc eyeball-edited by hand.
- **Watch output size caps.** Escaped JSON is larger than the md (`\n`, `\"`, unicode → `\uXXXX`). Under a ~50 KB tool-output cap a big report breaks; keep reports compact or write to a file and read it back instead of `cat`.
- **Keep the source of truth in files, not chat state.** If context is compacted mid-task, the report file and serializer survive; a JSON blob in the transcript may not be reconstructible from memory.
- **Verify before claiming compliance.** "Validates against the schema" needs an actual `json.loads` (or jsonschema) run — never assert it on eyeballed output.
- **Fact-check the payload BEFORE serializing.** Line references, symbol names, quotes inside the report — if they need fixing afterward you re-serialize anyway; cheaper to get them right first (draft, patch the .md, then serialize once).

## Session-derived evidence

A contract-mandated report was first hand-written as one JSON string and rejected twice with `Expecting ',' delimiter` at a large column offset because embedded markdown quotes/backticks/em dash/backslash sequences were unescaped. The identical markdown, serialized as `json.dumps({"report": md}, ensure_ascii=False)`, passed on the first re-submission.