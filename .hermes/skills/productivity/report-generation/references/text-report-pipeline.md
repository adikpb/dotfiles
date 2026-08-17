# Text-only reports: markdown → docx → PDF

For reports **without screenshots/images** (research briefs, provider comparisons, policy docs), the docx-js screenshot machinery in the main SKILL.md is overkill. The fast, reliable path is a two-step conversion with tools already on the machine:

```
markdown file  --(pandoc)-->  docx  --(LibreOffice headless)-->  pdf
```

This pipeline produced a clean, verified text report (privacy-providers-final: markdown → 16-page docx + 16-page PDF) with this exact chain.

## Exact commands

```bash
SRC=report.md
BASE=report

# 1) markdown -> docx
pandoc "$SRC" -o "$BASE.docx"

# 2) docx -> pdf (LibreOffice headless)
soffice --headless --convert-to pdf --outdir . "$BASE.docx"
```

Both tools are commonly present: `pandoc` and `soffice` via Homebrew on macOS. Verify with `which pandoc soffice`.

- **pandoc** handles markdown tables, headings, inline code, and citation `[n]` markers as-is. It is the single source of truth for the doc.
- The docx is a faithful styled Word copy; the PDF is the share/sign version. One script produces both, matching the user's "single script produces both" convention.

## Each major section starts on its own page (raw OpenXML page break)

To make every `## ` section begin at the top of a new page in the docx AND the
PDF, insert a raw OpenXML page-break block immediately before each `## ` heading
in the markdown. Pandoc passes it through verbatim to the docx, and LibreOffice
honors it during PDF export. Use the packaged `scripts/text-report-fixes.py
pagebreaks <report.md>` (idempotent) rather than hand-editing.

```md
```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

## 2. The next section
```

Deal with the first section however you like: you can also page-break before it
(so page 1 is just the title/meta) or not. Do it with a Python script, not
hand-editing, and make the script **idempotent**: deleting every existing page-break block first, then inserting one fresh block before each `##`
heading, is far safer than conditionally adding to the previous 3–4 lines (a
fragile "is it there already?" check that double-inserts).

**A heading glued to the previous line is not parsed as a heading.** If markdown
was built by concatenating part files (`cat a b > final.md`) a `### X` heading
with no blank line before it renders as literal text (`### NEAR AI Cloud:` shows
up in the PDF verbatim). Headings need a preceding blank line. Normalize the
merged file so every `#`, `##`, `###` is preceded by a blank line, then convert.

## Verifying the rendered output (pypdf text + sips raster)

`pdftoppm` (poppler) is often NOT installed (only pandoc + soffice are). Two
text options for verification that need no rasterizer:

1. **Structural / presence check with `pypdf`** — see pitfall below on
   whitespace normalization, then assert sections start on expected pages:

```python
import pypdf, re
r = pypdf.PdfReader("report.pdf")
print("pages:", len(r.pages))
full = " ".join((p.extract_text() or "") for p in r.pages)
norm = re.sub(r"\s+", " ", full)          # collapse all whitespace BEFORE asserting
```

2. **Visual check via macOS `sips`** when you have a vision aux model (no
   pdftoppm/ghostscript needed). Extract a single page to its own PDF with
   pypdf, then rasterize with `sips`:

```bash
# single-page PDF:  index 3 = page 4
python3 -c "
import pypdf
from pypdf import PdfWriter
w = PdfWriter(); w.add_page(pypdf.PdfReader('report.pdf').pages[3])
w.write('/tmp/page4.pdf')
"
sips -s format jpeg -Z 1000 --setProperty formatOptions 60 \
     --out /tmp/page4.jpg /tmp/page4.pdf
```

Then hand `/tmp/page4.jpg` to `vision_analyze`/`browser` to confirm footnotes,
hyperlinks, tables, and headings render cleanly. The vision provider may though
The vision provider may fail intermittently ("Internal Server Error", or "Model only supports text
input" if the aux vision slot is off) — retry or fall back to the pypdf text
check, which is authoritative for content presence anyway.

## Critical pitfall: line-wrapping breaks substring checks

`pypdf.PdfReader.extract_text()` inserts a newline at every PDF text-line wrap. A claim present in the document but rendered mid-paragraph will therefore NOT match a plain `in full` substring check, because the string is split as `not \nhardware-isolated`.

- A naive `"hardware-isolated" in full` returns False even though the PDF is correct.
- **Fix: normalize whitespace first** — join pages, replace `\n` with spaces, collapse runs of whitespace via `re.sub(r"\s+"," ", full)`, THEN run substring assertions.

Whitespace-normalized substring checks are authoritative (true positives, no false negatives). Do NOT conclude "content missing / conflated" from a raw `extract_text()` miss — re-run on the normalized text before trusting it.

## Citation ledger integration (grounded reports)

See the `grounded-citations` skill for the ledger contract; the pipeline notes
below are what the user's actual reports require in practice.

1. Rendering is done in `<skill_dir>/scripts/sources.py render --cited-in report.md --replace-in report.md` to append the Sources block mechanically (URLs from the ledger, never retyped).
2. Run `python3 sources.py verify report.md` after edits and before converting — it flags broken citations and reports blank provenance coverage.
3. Per source, attach verbatim quotes to the ledger from the fetched page text (see the `grounded-citations` SKILL.md), never reconstructed from memory. The user's "no em dashes in any writing" rule applies to your own prose, NOT to verbatim quotes or to the `—` separators and source titles rendered by `sources.py` into the Sources block; changing those breaks the verbatim evidence match or the mechanically-rendered format. After editing and re-rendering, re-run `sources.py verify` before converting.

### The user's preferred citation style: inline clickable markers, NOT footnotes

This user finds Word-footnote citations ugly ("the footnotes make things ugly").
Never convert inline `[n]` markers into Word footnotes (`[^n]`). Two hard facts
shape the right choice:

- Word citation **fields** (Zotero/EndNote "Insert Citation") are the standard
  "real Word" mechanism, but they are NOT PDF-safe through this pipeline:
  Microsoft's ODT↔DOCX compat table and Zotero's docs both confirm LibreOffice
  cannot read Word citation fields, so they flatten to plain text on export.
- Word **footnotes** do survive LibreOffice PDF export — `[^n]` markdown renders
  as true `word/footnotes.xml` entries, and they appear at the page bottom in
  the PDF. But the user rejected them as visually cluttered.

**Chosen style: keep the inline `[n]` marker, make each a live hyperlink.**

- In pandoc markdown write the marker as `[[n]](https://source.url)`. The outer
  brackets are link syntax; the inner `[n]` is the visible marker text.
- Pandoc emits a genuine Word external hyperlink: visible text `[n]`, target in
  `word/_rels/document.xml.rels`, requiring the visible body text `[n]`. Verify:
  `<w:hyperlink` count in `document.xml` equals your citation count, and the
  rels target holds the URL.
- LibreOffice carries these hyperlinks through to the PDF, so citations are
  clickable in BOTH the docx and the PDF, with zero visual clutter.
- Keep the `## Sources` block as the bibliography page at the end.

### Source-table cells: footnotes are NOT allowed inside Word table cells

If the report has a price/comparison table that cites sources, leave those as
plain inline `[n]` bracket pointers even when the rest of the doc uses rich
citations. Word disallows footnotes inside table cells, so `[^n]` (and any
footnote-based mechanism) breaks there. A plain `[n]` pointer in the table tying
to the Sources block is both legal and cleaner than a footnote in a cell.

### Pitfall: converting `[n]` → `[^n]` footnotes breaks the ledger's `--cited-in`

`sources.py verify` and `render --cited-in <draft>` detect citations by the
literal `[n]` pattern. Once you rewrite inline `[n]` into `[^n]` footnote
markers, the ledger no longer recognizes them, the Sources block silently drops
those sources, and numbering develops gaps. If you must move citations to
footnotes, keep the footnotes but re-render the Sources block after — and since
this user prefers clickable inline markers anyway (`[[n]](url)`), the ledger
still reads the `[n]` inside the link and everything matches. Prefer the
hyperlink form over the footnote form for ledger hygiene as well as aesthetics.

## Pitfall: `render --replace-in` clobbers everything after `## Sources`

`sources.py render --replace-in report.md` rewrites the file from the `## Sources` heading to end-of-file. Any footer You appended after the Sources block with `cat ... >> report.md` (e.g. a closing `**No API keys...**` line, an author note, a page footer) is **silently deleted** by the renderer. Symptom: the footer vanishes from the markdown and from the rendered PDF, but `sources.py verify` still passes (it only checks the citation block).

Fix: append the footer BEFORE the Sources block, or re-append it AFTER the final `render --replace-in` (and re-verify + re-convert). Confirm the footer survived with a `grep -c` on the markdown (and a pypdf substring check on the rendered PDF), not by assumption.

## Checking the docx has the expected image/media count

Text-only reports have no embedded media (no `word/media/`). Verify you did not accidentally embed screenshots:
```bash
python3 -c "
import zipfile; z=zipfile.ZipFile('report.docx')
print([f for f in z.namelist() if f.startswith('word/media/')] or 'no media (text-only, correct)')
"
```