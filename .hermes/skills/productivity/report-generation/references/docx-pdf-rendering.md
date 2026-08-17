---
name: docx-pdf-rendering
description: Use when rendering markdown reports to docx + PDF.
---

# Markdown → docx → PDF report rendering

## When to use
User asks to "render it in pdc" (PDF + companion docx) or produce a report document from markdown. Standing user style: ONE chain produces BOTH docx and PDF; each major section starts on a fresh page; sequential numbering; **no em dashes in prose** (use commas/colons/restructure; keep em dashes only inside verbatim quotes for evidence integrity and in machine-rendered Sources separators).

## Pipeline
1. Author the report in markdown with inline citations `[n]` backed by the grounded-citations ledger (`~/.hermes/skills/research/grounded-citations/scripts/sources.py`):
   - `add <url> --title "..."` then `quote <id> --text "..." --from page.txt` to bind verbatim evidence
   - `render --style markdown --cited-in report.md --replace-in report.md` writes the Sources block (only cited ids)
   - `verify report.md` must end "citations OK"; `--evidence` flag lists ids lacking quotes
2. `pandoc report.md -o report.docx` (add `--reference-doc="$HOME/.pandoc/ref.docx"` if that file exists).
3. `soffice --headless --convert-to pdf --outdir . report.docx`.
4. Verify the PDF with `scripts/verify_pdf.py` (pypdf in a throwaway venv: `uv venv /tmp/pdfv && uv pip install --python /tmp/pdfv/bin/python pypdf`).

## Word-native citations (footnotes, not fields)

When the user asks for "citations in Word" that survive the LibreOffice PDF conversion: **use real Word footnotes, never citation fields.**

- Word citation *fields* (the Zotero/EndNote "Insert Citation" mechanism) do NOT survive LibreOffice: Microsoft's ODT↔DOCX compat table lists Bibliography as "converted to plain text", and Zotero's docs confirm LibreOffice cannot read Word fields. **Footnotes/endnotes are fully supported in both** and render at the page bottom in the PDF.
- Conversion recipe (markdown source-of-truth → footnotes):
  1. Run `sources.py verify report.md` on the markdown BEFORE conversion.
  2. In prose only, rewrite each `[n]` → `[^n]`; append one definition per cited source before the `## Sources` block: `[^n]: <url> — <title>` (pull url/title from the Sources block; ~35 defs for a report is normal).
  3. **Leave `[n]` plain inside table cells** — Word disallows footnotes in table cells. A source cited only in a table (e.g. a pricing footnote) correctly gets NO footnote definition.
  4. `pandoc` then emits real `word/footnotes.xml` elements; LibreOffice PDF keeps them.
- Verify: `unzip -p out.docx word/footnotes.xml | grep -c '<w:footnote '` (2 separators + real notes), and PDF text extraction shows the URL at the bottom of the citing page.
- Pitfall: after `[n]` → `[^n]`, `sources.py verify` reports most sources "uncited" because its parser only counts `[n]` markers. That is expected — provenance moved into footnotes; verify on the markdown source-of-truth BEFORE conversion, and don't chase the post-conversion warnings.

## Page breaks: one major section per page
Insert this raw OpenXML fenced block on its own lines immediately BEFORE each `## ` heading:

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

- Expect page 1 to hold title/meta alone; first section starts on p2. That is the intended outcome, not a bug.
- Re-application MUST be idempotent: strip ALL existing pagebreak blocks first, then re-insert one per heading. Blindly re-inserting doubles them (9 headings → 18 breaks) and creates blank-page artifacts.

## Pitfalls (all hit in production — check before re-rendering)
1. **Consecutive markdown lines collapse into ONE paragraph** in pandoc. A Sources block of `[1] url …`, `[2] url …` lines renders as a run-on paragraph. Blank-line separate every source entry (`re.sub(r"(\n\[\d+\]) ", r"\n\n\1 ", block)`).
2. **A heading needs a blank line before it.** `### X` immediately after a paragraph renders as literal "### X" TEXT (pandoc fails to parse it as a heading). Ensure a blank line precedes every `##`/`###`.
3. **`render --replace-in` rewrites the whole Sources tail and silently deletes anything appended after it** (e.g. a final "no credentials" disclaimer). Append post-render lines AFTER running the renderer, or re-append afterward and re-convert.
4. **pypdf extraction gives false negatives:** line-wrap splits words mid-token (`not \nhardware-isolated`) and converts quotes to curly ("…"). Normalize whitespace + quotes before substring checks; a MISS is usually a wrap artifact, confirm against the source markdown before declaring content missing.
5. **Large write_file calls time out** (content beyond ~8K tokens per call). Write long documents as several small part files (`part_a.md`, `part_b.md`, …) then `cat part_*.md > final.md`. Keep each write_file under ~8K tokens.
6. **Em-dash audit:** after final edits run `awk '/^## Sources/{s=1} !s' report.md | grep -c '—'`; any prose hit (outside verbatim quotes) must be rewritten.
7. **Numbering gaps in the Sources block (e.g. `[1]…[5]` then `[7]`):** `render --cited-in` emits only ids the draft cites, so a gap means a ledger id is registered but never cited (typically a source used only in a table that later got trimmed). Fix by citing it in prose where it belongs (e.g. a price-map cross-check line); never renumber the ledger to close the gap.

## Verification
`python3 scripts/verify_pdf.py report.pdf --require "Chutes" --drop "x402" --section "3. Tier 2" --section "Sources"` checks required strings present, dropped strings absent, each section's page, and total page count. See the script's `--help`.