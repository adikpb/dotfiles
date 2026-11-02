# Markdown → PDF legibility fixes (pandoc + LibreOffice)

Two user-visible rendering bugs hit when a Markdown report is converted
`pandoc → docx → soffice --convert-to pdf`. Both produce a "looks fine in
Markdown, garbled in PDF" complaint. Fix BOTH before delivering a PDF.

## Bug 1 — paragraphs collapse into one line

Markdown treats a bare newline as a space. When the source is written with
intentional line breaks (lists, addresses, multi-line table cells, or any
hand-authored break), pandoc/CommonMark joins them — the PDF shows one run-on
line where the author meant several.

Fix (belt and suspenders):
1. Ensure every non-blank line in the `.md` ends with TWO trailing spaces
   (the Markdown hard-break / `<br>` syntax). Blank lines stay blank.
2. Render with the `hard_line_breaks` extension so even lines without the
   suffix break:
   `pandoc -f markdown+hard_line_breaks "$SRC.md" -o "$SRC.docx"`

Python helper to add the two-space suffix to a file:
```python
with open(path, encoding="utf-8") as f:
    text = f.read()
out = []
for ln in text.split("\n"):
    if ln.strip() == "":
        out.append(ln)
    else:
        if not ln.endswith("  "):
            ln = ln.rstrip() + "  "
        out.append(ln)
with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out))
```

## Bug 2 — tables squished / columns crushed

Pipe tables in pandoc default to auto-fit widths. LibreOffice applies
"auto fit" and crushes wide tables (e.g. a 7-column build spec) into thin
columns that wrap badly. `ColWidth` Lua constructors are NOT reliably exposed
across pandoc builds — don't fight the Lua API. Instead, post-process the docx
XML to force fixed layout with balanced column widths.

Reusable pattern (see `data/fix_docx_tables.py` in the VRS seo repo): for each
`<w:tbl>` set `<w:tblLayout w:type="fixed"/>`, set table width to 100%
(`w:tblW` pct 5000), and give every grid column + cell a balanced `dxa` width
(usable A4 width ≈ 9026 twips, split evenly across N cols).

Pipeline:
```bash
pandoc -f markdown+hard_line_breaks "report.md" -o "report.docx" \
  && python3 data/fix_docx_tables.py "report.docx" \
  && soffice --headless --convert-to pdf --outdir . "report.docx" \
  && rm -f "report.docx"
```
Verify: unzip the docx, confirm `w:type="fixed"` appears on every table and
`<w:gridCol w:w="...">` widths are non-zero and roughly equal.

## When to apply
Any time you hand a Markdown-derived PDF to a human — reports, invoices,
implementation orders. The two-space suffix is harmless to plain-Markdown
readers too, so applying it unconditionally is safe.
