---
name: docx-pandoc-pipeline
description: "Use for markdown to docx+PDF via pandoc and LibreOffice."
version: 1.0.0
license: Proprietary
platforms: [macos]
metadata:
  hermes:
    tags: [docx, pdf, pandoc, libreoffice, citations]
    category: productivity
---

# Markdown → DOCX → PDF pipeline (pandoc + soffice)

Proven path on macOS for a "single script produces both .docx and .pdf" report. Verify output at both XML and rendered-PDF text level.

## Pipeline
```bash
pandoc "$SRC" -o "$BASE.docx"           # markdown → Word
soffice --headless --convert-to pdf --outdir . "$BASE.docx"   # Word → PDF
```
Post-render verify with pypdf: page count, key strings present, no literal `###`, no credentials. (`uv venv /tmp/pdfvN && uv pip install --python /tmp/pdfvN/bin/python pypdf`.) On macOS rasterize single PDF pages with `sips -s format jpeg -Z 1100 page.pdf --out page.jpg` and inspect with vision_analyze.

## Pitfalls (all hit in production)

1. **Word citation FIELDS do not survive LibreOffice→PDF.** Microsoft's ODT/DOCX compat table converts bibliography fields to plain text, and LibreOffice cannot read Word citation fields. For citations that must render in the PDF, use **real Word footnotes** (pandoc `[^n]` refs + `[^n]: text` defs), which DO render at page bottom in soffice output. Verify `word/footnotes.xml` exists in the docx zip.

2. **Footnotes are NOT allowed inside Word table cells.** Keep plain `[N]` pointer text in table cells; the Sources/bibliography section carries the full refs. Pandoc footnotes inside a table produce broken docx.

3. **pandoc collapses consecutive non-blank lines into one paragraph.** A Sources/references list written `[1] ... \n[2] ...` renders as one run-on block. Insert a blank line between each list entry so each renders on its own line.

4. **Page-per-major-heading:** insert a raw OpenXML page break before each `## ` heading so each section starts on a fresh page (user preference). Before each heading insert:
   ```` ```{=openxml} <w:p><w:r><w:br w:type="page"/></w:r></w:p> ``` ````

5. **Markdown headings need a blank line before them**, else `###` renders literally (the leading `###` shows up as text in the PDF). Ensure a blank line precedes every heading.

6. If a renderer/script rewrites the tail of the file (e.g. a Sources-block renderer `--replace-in`), lines appended AFTER it (like a trailing "no credentials" banner) get wiped. Re-append after rendering.

## Pitfalls inherited from bundled docx skill
- LibreOffice headless PDF export ignores `VerticalAlignSection.CENTER` on section properties; use a manual spacer paragraph (before: N twips) for cover-page vertical centering.
- Pandoc: don't round-trip OOXML through `xml.etree.ElementTree`; use `defusedxml.minidom`. Zip from INSIDE the unpacked dir and `rm` the target first.