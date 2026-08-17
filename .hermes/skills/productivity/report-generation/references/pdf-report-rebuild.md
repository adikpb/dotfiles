---
name: pdf-report-rebuild
description: "Use when regenerating exported report PDFs, same layout."
version: 1.0.0
author: Nous Research
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [PDF, report, reportlab, pdfplumber, regeneration, layout]
    category: productivity
    related_skills: [pdf, macos-vision-ocr]
---

# PDF Report Rebuild

Regenerate exported data-grid PDFs (attendance monthly reports, timesheets, log sheets) with changed values while preserving the original visual layout: letterhead, grid, shading, fonts, cell geometry. REBUILD with reportlab rather than editing content streams in place: exported reports often use CID/subset fonts and contain stale duplicate text layers, which make in-place text edits unreliable.

## When to use
- "Update this [report PDF] for [new period]", "keep the working time the same", "mark days X-Y as absent", "change these values but keep the look".
- Any request to change values inside a generated grid-style PDF while keeping its appearance.

## Workflow
1. **Recon (pdfplumber)**: page size from the mediabox (e.g. A3 landscape 1190.98 x 841.97), `page.lines` (grid), `page.rects` (cell shading: white/yellow fills), `page.images` (letterhead is often ONE background image, sometimes squished/stretched), `page.chars` (font names + sizes per region, e.g. ArialMT 9.9, Arial-BoldMT 12).
2. **Decode cells**: naive `extract_words()` interleaves strings when the exporter draws overlapping copies or per-glyph offsets (common with subsetted fonts). Reconstruct per cell: filter chars by column window (midpoints between column-header centers) and row band (top-origin y range), cluster chars into lines by `top` (tolerance ~3 pt), join each line by x0. Reusable tool: `scripts/extract_pdf_grid_cells.py`.
3. **Resolve ambiguous values with pixel truth**: render at scale >= 4 (pypdfium2) and OCR crops using the `macos-vision-ocr` skill. Pick readings that also satisfy derived checks (attended minutes ~= checkout - checkin, rounded).
4. **Rebuild (reportlab)**:
   - `canvas.Canvas(OUT, pagesize=(W, H))` with the ORIGINAL mediabox.
   - `drawImage(background, x0, y0, w, h, preserveAspectRatio=False)` at the image's exact displayed bbox. Replicate the source's stretch exactly (do not fix the aspect ratio).
   - Replay `page.rects` (fills, in order) then `page.lines` (strokes) from the source for identical shading and grid.
   - Draw text at ORIGINAL char positions: baseline = H - (top + 0.72*size), where top is pdfplumber's top and H is page height. Center cell values with `drawCentredString` at column centers (from the column-header word positions).
   - Helvetica/Helvetica-Bold are metric-equivalent stand-ins for ArialMT/Arial-BoldMT.
   - Narrow time cells: the source often renders HH:MM:SS as three stacked segments (HH: / MM: / SS) because the exporter wrapped the text. Replicate the stacking (segment top offsets ~ [5.2, 16.6, 28.0] pt relative to the row top) to match the source look.
5. **Recompute summary numbers so they are internally consistent**: period days = normal + weekend + absence + leave. Source exports are frequently buggy here (e.g. '#' marks on worked days while the summary claims a different Weekend count). Make table and summary agree, then TELL the user what you changed and why.
6. **Verify**: re-extract the new PDF's cells with the same extractor and diff against the intended data table; OCR the header band and key rows; confirm the background image actually rendered (pixel probe or OCR of the header band, since a mostly-white image can silently fail).

## Pitfalls
- Row labels can overflow the label column into the first data cell ("Check-out1" at 9.9 pt is ~50 pt vs a 46.5 pt label column). The source wraps it ("Check-" / "out1"); do the same or shrink the font. A single stray glyph in the first cell's audit is the tell.
- Stale duplicate text layers: "updated" exports can contain an old copy of some strings (double times on one day, two summary rows with different totals). The VISIBLE reading (OCR) is the current one.
- Don't invent the footer Date/Time stamp: keep the original export timestamp unless the user asks to change it.
- Keep the build script next to the output file so the user can regenerate with tweaks.
- Extract the background image with pypdf (`page.images[name].image.save(...)`); the pypdf ImageFile object itself has no .save() method.

## Support files
- `references/attendance-report-rebuild-2026.md` - worked example: June->July attendance report (geometry, full data table, decisions, pitfalls hit).
- `scripts/extract_pdf_grid_cells.py` - char-level per-cell extractor for grid PDFs (pass column centers + row bands).