---
name: report-generation
description: "Generate docx/PDF reports: screenshots, pandoc, rebuilds."
version: 1.0.0
author: Auto-generated from session
platforms: [macos, linux, windows]
tags: [reporting, screenshots, docx, documentation, web-capture, browser-vision]
---

# Report Generation with Web Screenshots

Create documents and reports that include web UI screenshots — dashboard states, modal dialogs, tabbed views, and filtered data — by combining JS patching, headless browser capture, and docx-js embedding.

## When to Use

Use this skill when the user asks to:
- "Create a report/docx with screenshots of the dashboard"
- "Document the UI with screenshots"
- "Capture the current state of the web app in a document"
- "Generate a visual walkthrough of the interface"
- "Render this report as docx/pdf" for a **text-only** document (no screenshots): use the fast pandoc → LibreOffice pipeline in `references/text-report-pipeline.md` instead of the docx-js machinery below. That reference also covers: **inline clickable hyperlink citations** (this user rejects footnotes), raw-OpenXML page-break-per-heading, blank-line-before-heading rule for merged files, pypdf whitespace-normalized verification, and macOS `sips` rasterization for vision checks when pdftoppm is absent.
- "Update this report PDF for a new period / keep the layout": rebuild the grid with reportlab (`references/pdf-report-rebuild.md`), do not edit content streams.

The workflow applies to **any web-based dashboard or application** that renders in a browser.

## Text-only markdown → docx + PDF (pandoc)

Proven macOS path: `pandoc "$SRC" -o "$BASE.docx"` then `soffice --headless --convert-to pdf --outdir . "$BASE.docx"`. Verify with `scripts/verify_pdf.py` (pypdf in a throwaway uv venv).

Production pitfalls (all hit): Word citation FIELDS die in LibreOffice→PDF — use real Word footnotes (`[^n]`) for citations that must survive, and leave plain `[N]` inside table cells (Word forbids footnotes there). pandoc collapses consecutive non-blank lines (blank-line-separate Sources). Headings need a blank line before them or `###` renders as literal text. Page-per-`##` via raw OpenXML break; strip existing breaks before re-inserting. `sources.py render --replace-in` wipes anything after `## Sources`. pypdf wraps lines — whitespace-normalize before substring checks.

Full recipes: `references/text-report-pipeline.md`, `references/docx-pdf-rendering.md`, `references/docx-pandoc-pipeline.md`.

## Grid PDF rebuild (reportlab)

Regenerate exported attendance/timesheet grid PDFs with new values while preserving letterhead, grid, shading, fonts, and cell geometry. Exported reports use CID/subset fonts and stale duplicate text layers — in-place stream edits are unreliable.

1. Recon with pdfplumber (mediabox, lines, rects, images, chars).
2. Decode cells with `scripts/extract_pdf_grid_cells.py` (do not trust `extract_words()` on overlapping copies).
3. Ambiguous values: rasterize at scale ≥ 4 and OCR via the `macos-vision-ocr` skill.
4. Rebuild with reportlab at the original mediabox; replay rects then lines; draw text at original char positions. Worked example: `references/attendance-report-rebuild-2026.md`.
5. Recompute summaries so table and totals agree; tell the user what changed.

Full write-up: `references/pdf-report-rebuild.md`.

## Prerequisites

```bash
# Docx generation
npm ls docx --depth=0 2>/dev/null | grep -q docx || npm install docx

# Image processing (required for cropping/resizing retina screenshots)
pip show pillow >/dev/null 2>&1 || pip install pillow

# Verification (optional)
which pandoc || brew install pandoc       # docx → text extraction
```

## Workflow

### Phase 1: Plan the report structure

Before writing any code, define the sections and which views each screenshot will show:

| # | Section | View state to capture |
|---|---------|----------------------|
| 1 | Dashboard overview | Default landing — KPI cards, alert table |
| 2 | Events browser | Events tab with data table |
| 3 | Detail views | Modal dialogs, expanded panels, tool call details |

### Phase 2: Capture screenshots via `browser_vision`

The Hermes `browser_vision()` tool captures page screenshots and returns a `screenshot_path` pointing to a PNG file.

### Step 0: Check the viewport meta tag

Before taking any screenshots, inspect the page's `<meta name="viewport">` tag. The `browser_vision()` tool captures the **entire browser viewport** at full device-pixel ratio (2-4x DPR). If the viewport meta sets a fixed width (e.g. `width=800`) that's narrower than the actual browser window (~1496px), the page content renders at that fixed width while the capture is still the full viewport size. **Result: the dashboard content fills only ~50% of the captured image, with the rest being empty dark background.** When this image is scaled to 780px in a docx, the actual UI gets stretched across twice its intended width — causing oversized text and warped proportions.

**Fix:** If the viewport meta is `width=800` (or any fixed value smaller than the browser), change it server-side to `width=device-width, initial-scale=1.0`:

```patch
-<meta name="viewport" content="width=800, initial-scale=1.0, maximum-scale=1.0">
+<meta name="viewport" content="width=device-width, initial-scale=1.0">
```

This lets the layout viewport match the actual browser width. After the change, restart the server so the new HTML is served. No CSS overrides needed beyond this.

**Verify the viewport width is correct before capturing:**

```js
// In browser_console — confirms width=device-width is working
window.innerWidth  // Should be ~1496 (full browser width), not ~800
```

**After switching to Events tab, also verify container fills the viewport:**

```js
var c = document.querySelector('.container');
var r = c.getBoundingClientRect();
( r.width / window.innerWidth * 100 ).toFixed(0) + '%';
// Should be 96%+, not 50% or less
```

Do NOT apply CSS font-size overrides (`font-size: 22px !important`) — they inflate text in the captured image but fail to compensate for the viewport-width mismatch, producing screenshots that are both oversized AND cramped.

**Procedure per view state:**

1. Navigate to the desired state with `browser_navigate` + `browser_click`
2. Call `browser_vision()` — it returns a `screenshot_path` in the response
3. Copy the screenshot file to your project's screenshots dir:

   ```bash
   cp /path/to/browser_screenshot_<hash>.png ./screenshots/screenshot_name.png
   ```

4. Repeat for each view state

**No JS patches, no headless Chrome, no server restarts needed.**

Tip: Pass `annotate=false` to avoid overlay labels on the screenshot.

**Expanding non-clickable disclosure triangles:** When modal content uses `<details><summary>` elements not shown as clickable `@ref` in the snapshot, toggle via `browser_console`: `allDetails[n].open = true`. See `references/modal-screenshot-technique.md` for the full technique, including event-row detail panels with broken onclick handlers.

**Viewport-only capture (preferred — eliminates post-processing):** `browser_vision()` captures the **entire scrollable page**, not just the viewport. A dashboard table with 100+ rows produces a 15,000+ px tall image — unusable when rendered. Instead of cropping/resizing the giant image afterwards, **prevent the page from being tall at capture time**:

**Technique A — limit displayed rows (data tables):** Before switching to the Events/table tab, override the rendering function to show only 10–15 rows. Combined with CSS constraints, this keeps the entire page within the viewport:

```js
// Patch BEFORE clicking the tab that triggers data load
window.renderEvents = function(events) {
  var e = events.slice(0, 15);
  var el = document.getElementById('events-table');
  var html = '<table><thead>...' + e.map(...).join('') + '...</table>';
  el.innerHTML = html;
};
```

Then constrain BOTH `documentElement` and `body` to the viewport height **before** taking the screenshot — this prevents any new elements (like expanded detail panels) from growing the page:

```js
document.documentElement.style.overflow = 'hidden';
document.documentElement.style.maxHeight = window.innerHeight + 'px';
document.body.style.overflow = 'hidden';
document.body.style.maxHeight = window.innerHeight + 'px';
```

**Technique B — constrain first, then expand (detail panels/modals):** For a screenshot showing an expanded row or modal section, limit rows to 5 (so the table header + a few rows + the expanded content all fit within one viewport), then constrain, then click to expand, then capture. The CSS constraint prevents the detail panel from pushing the page beyond the viewport.

**Result:** Screenshots are exactly one viewport tall (~3160 px at 4x retina), no cropping or resizing needed. Files stay small and text is legible at the docx render size.

**When to fall back to resize/crop:** If you cannot control the page content (e.g., external site, no JS hooks to limit rows), capture at full page height the old way then resize/crop with Pillow (see below).

**Retina / high-DPI fallback (if viewport constraint didn't work):** `browser_vision()` captures at full device-pixel ratio (2x–4x retina), producing 5000–6000 px wide images. At 600x377 render size in the docx, these compress to 12–15% of their original resolution — text becomes illegible and file sizes balloon. If you must post-process, batch-resize to ~1600 px wide:

```python
from PIL import Image
img = Image.open('screenshot.png')
w, h = img.size
img = img.resize((1600, int(h * 1600 / w)), Image.LANCZOS)
img.save('screenshot.png', optimize=True)
```

1600 px at render width 600 gives ~2.7x oversampling — sharp text at any output scale.

**Modal content capture (fixed-position overlays):** Many UI frameworks render modals with `position: fixed` and `overflow: hidden` on `.modal-content`. `browser_vision()` captures full page but modals often clip. To capture the full modal content, use `browser_console` to make the content scrollable:

```js
document.querySelector('.modal-content').style.overflowY = 'auto';
document.querySelector('.modal-content').style.maxHeight = '80vh';
document.querySelector('.modal-content').scrollTop = 1500;
```

Then call `browser_vision()`. Repeat with different `scrollTop` values (e.g., 0 → top section, 1500 → middle, 3000 → bottom) to capture each logical section as a separate screenshot. Each section becomes its own figure in the report.

### Phase 3: Embed screenshots in docx

Write a Node.js script using the `docx` npm package. Structure it with helper functions for clean code:

```js
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const {
  Document, Packer, Paragraph, TextRun, ImageRun, Table, TableRow,
  TableCell, HeadingLevel, AlignmentType, WidthType, ShadingType,
  PageBreak, BorderStyle, LevelFormat, PageOrientation,
  convertInchesToTwip,
} = require('docx');

const SCREENSHOTS_DIR = path.resolve(__dirname, '..', 'screenshots');

// Helper: read image → base64 data URI
function imageData(file) {
  const buf = fs.readFileSync(path.join(SCREENSHOTS_DIR, file));
  return `image/${path.extname(file).slice(1)};base64,${buf.toString('base64')}`;
}

// Helper: screenshot with heading + image + caption
function screenshotSection(title, filename, caption, opts = {}) {
  // Use 600x377 for landscape screenshots — this fits within a letter/A4 page's
  // 6.5-inch printable area (8.5" page minus 1" margins each side) at 96 DPI.
  // 780px (=8.125") overflows 6.5" and causes right-edge clipping in PDF export.
  // Override per-section for portrait or tall content.
  const { width = 600, height = 377 } = opts;
  const parts = [
    new Paragraph({
      children: [new TextRun({ text: title, bold: true, size: 24 })],
      keepNext: true,
      spacing: { before: 400, after: 100 },
    }),
  ];
  const imgPath = path.join(SCREENSHOTS_DIR, filename);
  if (fs.existsSync(imgPath)) {
    parts.push(
      new Paragraph({
        children: [new ImageRun({
          data: imageData(filename),
          transformation: { width, height },
          type: path.extname(filename).slice(1),
        })],
        keepNext: true,
        alignment: AlignmentType.CENTER,
        spacing: { before: 100, after: 100 },
      })
    );
  } else {
    parts.push(
      new Paragraph({
        children: [new TextRun({ text: `[Screenshot: ${filename} — not available]`, italics: true, color: '999999' })],
        keepNext: true,
        spacing: { before: 100, after: 100 },
      })
    );
  }
  if (caption) {
    parts.push(
      new Paragraph({
        children: [new TextRun({ text: caption, italics: true, size: 18, color: '666666' })],
        alignment: AlignmentType.CENTER,
        spacing: { after: 200 },
      })
    );
  }
  return parts;
}

// Helper: body paragraph
function body(text, opts = {}) {
  return new Paragraph({
    children: [new TextRun({ text, size: 22, ...opts })],
    spacing: { after: 120, line: 360 },
  });
}

// Helper: regular bullet
function bullet(text, opts = {}) {
  return new Paragraph({
    children: [new TextRun({ text, size: 22, ...opts })],
    spacing: { after: 80, line: 320 },
    numbering: { reference: 'default-list', level: 0 },
  });
}

// Helper: bold bullet (use for section headings within lists, or for
// short all-bold items. For longer items that need a bold label +
// regular description, use boldLabelBullet() instead.)
function boldBullet(text) {
  return new Paragraph({
    children: [new TextRun({ text, bold: true, size: 22 })],
    spacing: { before: 120, after: 40, line: 320 },
    numbering: { reference: 'default-list', level: 1 },
  });
}

// Helper: sub-bullet (regular weight, level 2 indent)
function subBullet(text) {
  return new Paragraph({
    children: [new TextRun({ text, size: 20, color: '444444' })],
    spacing: { after: 60, line: 300 },
    numbering: { reference: 'default-list', level: 2 },
  });
}

// Helper: mixed-format bullet with bold label + regular description.
// Use for lists where every item has a title and explanation
// (Limitations, Future plans, key terminology). Avoids the problem
// of boldBullet() making the entire sentence heavy.
function boldLabelBullet(label, description) {
  return new Paragraph({
    children: [
      new TextRun({ text: label, bold: true, size: 22 }),
      new TextRun({ text: description, size: 22 }),
    ],
    spacing: { before: 100, after: 60, line: 320 },
    numbering: { reference: 'default-list', level: 0 },
  });
}

// Build the document
const doc = new Document({
  title: 'Project Report',
  styles: { default: { document: { run: { font: 'Calibri', size: 22 } } } },
  numbering: {
    config: [{
      reference: 'default-list',
      levels: [
        { level: 0, format: LevelFormat.BULLET, text: '\\u2022', alignment: AlignmentType.LEFT },
        { level: 1, format: LevelFormat.BULLET, text: '\\u25E6', alignment: AlignmentType.LEFT },
        { level: 2, format: LevelFormat.BULLET, text: '\\u25AA', alignment: AlignmentType.LEFT },
      ],
    }],
  },
});

// Generate
const OUTPUT = path.resolve(__dirname, '..', 'Project_Report.docx');
const PDF_OUTPUT = path.resolve(__dirname, '..', 'Project_Report.pdf');
Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(OUTPUT, buf);
  console.log(`✅ Report written: ${OUTPUT} (${(buf.length / 1024).toFixed(0)} KB)`);

  // ── Generate PDF via LibreOffice headless ──
  try {
    const pdfOpts = [
      'SelectPdfVersion=2',
      'ExportFormulasAs=1',
      'EmbedStandardFonts=true',
      'UseLosslessCompression=true',
      'MaxImageResolution=600',
      'ReduceImageResolution=false',
    ].join(';');
    execFileSync(
      'soffice',
      ['--headless', '--convert-to', `pdf:writer_pdf_Export:${pdfOpts}`, OUTPUT],
      { cwd: path.dirname(OUTPUT), stdio: 'pipe', timeout: 120_000 }
    );
    const pdfSize = fs.statSync(PDF_OUTPUT).size;
    console.log(`✅ PDF generated: ${PDF_OUTPUT} (${(pdfSize / 1024).toFixed(0)} KB)`);
  } catch (err) {
    console.error('⚠️  PDF conversion failed (LibreOffice may not be installed):', err.message);
  }
}).catch(err => {
  console.error('❌ Failed:', err);
  process.exit(1);
});
```

**Key docx-js gotchas for images (see the `docx` skill for full details):**
- `ImageRun` requires `type:` explicitly (`'png'`, `'jpg'`)
- Images need `transformation: { width, height }` in pixels (the library converts to EMU at 96 DPI internally)
- For landscape screenshots (most dashboards), use `600×377` — this fits within the 6.5-inch printable area of a letter/A4 page at 96 DPI (600px = 6.25in, leaving 0.25in margin). Do NOT use 780px — that equals 8.125in, which overflows the 6.5in printable area and causes right-edge clipping in PDF export.
- For portrait modal sections or tall vertical content, override with e.g. `{ width: 520, height: 660 }` in the opts parameter.
- `convertInchesToTwip()` for page margins
- Table rows must be `TableRow` objects, not bare arrays
- Use `LevelFormat.BULLET` for numbering, never literal bullet characters
- Use `boldLabelBullet('Label: ', 'description')` for mixed-format items — avoids the problem of making every word in every bullet bold

**Page layout and pagination:**

- **Cover page vertical centering:** `VerticalAlign.CENTER` works in the docx file but does NOT survive LibreOffice headless PDF conversion — the text appears at the top of the page. Use a calculated manual spacer instead. The printable height is `page_height - top_margin - bottom_margin` (e.g., 11″ - 1.5″ - 1″ = 8.5″ = 12,240 twips). Estimate the total text-block height (title + subtitle + version + date + rule + confidential = ~4,120 twips for typical report typefaces), then set `spacing: { before: (printable_height - text_block_height) / 2 }`. Use twips (1″ = 1,440 twips; 1pt = 20 twips):

  ```js
  // ≈ 4400 twips = 3.06″ spacer pushes content to visual center
  // (tuned for 11″ page, 1.5″ top margin, 1″ bottom margin)
  new Paragraph({ spacing: { before: 4400 } }),
  ```

  No `verticalAlignment` property or `VerticalAlign` import needed. This is the reliable cross-format approach.

- **Page breaks before multi-figure groups:** Do NOT insert an explicit `PageBreak` before a multi-figure group. When preceding body text already fills the page, a `PageBreak` following it creates a **blank page** (the break forces content to skip past the current page, leaving it entirely empty). Instead, rely on two mechanisms that work correctly together:

  1. **Major sections use `pageBreakBefore: true`** on `section()` (HEADING_1) — this already ensures the section starts on a clean page.
  2. **Each figure is self-contained via `keepNext`** on heading→image only (caption has NO `keepNext`). Consecutive figures can page-break independently because the chain stops at each caption.

  If figures within a subsection get separated from their group, the fix is never an explicit `PageBreak` — fix the `keepNext` chain instead (ensure heading→image keepNext, caption has none). The explicit `PageBreak` approach is fragile and empirically produces blank pages.

### Phase 4: Convert to PDF (macOS)

```bash
# LibreOffice is often not in PATH on macOS. Use the full path:
/Applications/LibreOffice.app/Contents/MacOS/soffice --headless --convert-to pdf --outdir . report.docx

# Or symlink it for future use:
sudo ln -s /Applications/LibreOffice.app/Contents/MacOS/soffice /usr/local/bin/soffice

# Verify page count and size
file report.pdf     # expect "PDF document, version 1.7, N pages"
ls -lh report.pdf
```

If `soffice` is in PATH you can just run `soffice --headless --convert-to pdf report.docx`.

### Automate PDF generation in the script

Instead of running a separate shell command after generating the docx, add `execFileSync` directly into the generate script so a single `node generate_report.js` produces both files:

```js
const { execFileSync } = require('child_process');

// After Packer.toBuffer succeeds:
const OUTPUT = path.resolve(__dirname, '..', 'Project_Report.docx');
const PDF_OUTPUT = path.resolve(__dirname, '..', 'Project_Report.pdf');
Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync(OUTPUT, buf);
  console.log(`✅ Report written: ${OUTPUT} (${(buf.length / 1024).toFixed(0)} KB)`);

  // ── Generate PDF via LibreOffice headless ──
  try {
    const pdfOpts = [
      'SelectPdfVersion=2',
      'ExportFormulasAs=1',
      'EmbedStandardFonts=true',
      'UseLosslessCompression=true',
      'MaxImageResolution=600',
      'ReduceImageResolution=false',
    ].join(';');
    execFileSync(
      'soffice',
      ['--headless', '--convert-to', `pdf:writer_pdf_Export:${pdfOpts}`, OUTPUT],
      { cwd: path.dirname(OUTPUT), stdio: 'pipe', timeout: 120_000 }
    );
    const pdfSize = fs.statSync(PDF_OUTPUT).size;
    console.log(`✅ PDF generated: ${PDF_OUTPUT} (${(pdfSize / 1024).toFixed(0)} KB)`);
  } catch (err) {
    console.error('⚠️  PDF conversion failed (LibreOffice may not be installed):', err.message);
  }
}).catch(err => {
  console.error('❌ Failed:', err);
  process.exit(1);
});
```

**Always use `execFileSync` with an argument array** (the second parameter) instead of `execSync` with a shell string. This avoids shell-injection vectors when the file path or filter options contain special characters. The filter options `pdfOpts` are constructed from known constants — safe — but using `execFileSync` is the standard pattern.

**Filter syntax note:** The semicolon-delimited key=value format (`SelectPdfVersion=2;UseLosslessCompression=true;...`) works inside a single `--convert-to` argument. For the JSON object syntax (used in the "Lossless PDF Export from LibreOffice" section below), see `references/libreoffice-pdf-export.md`.

**Failing gracefully:** The try/catch block lets the script complete even if soffice isn't installed / fails — the docx is still produced. Only the PDF error is logged as a warning.

### Optional: Batch process screenshots

Use `scripts/crop-resize.py` to resize retina-resolution captures and crop unusably tall full-page captures before embedding:

```bash
# Resize all screenshots to 1600px wide (maintains aspect ratio)
python scripts/crop-resize.py ./screenshots/

# Crop a tall full-page screenshot to the top 2400px, then resize
python scripts/crop-resize.py tall.png --crop 0 2400

# Resize to a custom width
python scripts/crop-resize.py screenshot.png --width 1200
```

The script overwrites files in place. Run it before generating the docx so the embedded images are already at the right resolution.

### Phase 5: Verify report content matches live UI

**Use quantitative pixel analysis, not vision-model estimates.** When a screenshot looks wrong (stretched, oversized, too much empty space), do not ask the vision model to describe it — it gives vague percentage estimates. Instead, load the image with PIL and measure the content bounding box programmatically:

```python
from PIL import Image
img = Image.open('screenshot.png')
pixels = img.load()
# Sample background from bottom-right corner
bg = pixels[img.width-50, img.height-50]
# Scan every 4th pixel to find content bounds
left, right, top, bottom = img.width, 0, img.height, 0
for y in range(0, img.height, 4):
    for x in range(0, img.width, 4):
        p = pixels[x, y]
        if abs(p[0]-bg[0]) > 15 or abs(p[1]-bg[1]) > 15 or abs(p[2]-bg[2]) > 15:
            left = min(left, x); right = max(right, x)
            top = min(top, y); bottom = max(bottom, y)
fill_pct = (right-left)*(bottom-top) / (img.width*img.height) * 100
print(f'Content: {right-left}x{bottom-top}  Fill: {fill_pct:.0f}%')
```

If `fill_pct < 50%`, the screenshot has a viewport/layout-width problem (see Step 0: Check the viewport meta tag).

Before delivering, cross-check every factual claim in the report against the current live application:

- **Metrics:** Open the actual dashboard and verify every KPI value (alert count, event total, severity distribution). Do not copy stale numbers from an earlier session or reference file.
- **Column labels:** Check each table/column header name in the report matches what's rendered in the UI. Renamed columns are the most common drift.
- **Button labels:** Action button text (e.g., "🔍 Deep" vs "Analyze", "Acknowledge" vs "Ack") must match exactly. Search the report for old labels.
- **Terminology:** If the project renamed features (e.g., "LLM Analysis" → "Investigation Report", "Phase 2" removed), ensure the report uses the current names everywhere.
- **Screenshot completeness:** The report should include a screenshot of every distinct UI view — every tab, every modal section (top, middle, bottom), every expandable state. Missing views mean the report is incomplete.
- **Formatting consistency:** Check that lists with labels (Limitations, Future plans) use mixed-format bullets (bold label + regular description) rather than making every word bold. In the docx script, use `boldLabelBullet()` instead of `boldBullet()` for items that have a title and explanation — readers report all-bold text is hard to scan.
- **Figure captions:** Labels and counts in captions must match what's visually in the screenshot. If the user says "take all possible screenshots," treat it as a requirement for complete visual coverage — one shot per logical view section.
- **Screenshot pixel dimensions:** Check every embedded image — `browser_vision()` can capture at 4x retina DPI (5000+ px wide) or full scrollable page height (15,000+ px tall). Run `identify` or `sips -g pixelWidth -g pixelHeight` on each file. If any image exceeds ~2000 px on either axis, resize (for width) or crop (for height) before regenerating the docx — oversized images render as illegible compressed blobs and balloon file size.

```bash
# Quick sanity grep for stale terminology
grep -n -i 'phase 1\\|phase 2\\|llm analysis\\|analyze button\\|5 alerts\\|direction.*column' report-text.txt || echo "No stale terms found"
```

### Verify screenshots are unique (not duplicates)

The `docx` npm library **deduplicates images by content hash** — if two screenshots happen to be identical (e.g., `browser_vision` was called before the DOM state actually changed), only one copy is embedded. This causes "missing" figures in the report.

Check after generation that every source screenshot has a unique hash:

```bash
cd screenshots/
shasum screenshot_*.png | awk '{print $1}' | sort | uniq -d
```

If any duplicates appear, identify them:

```bash
shasum screenshot_*.png | sort | uniq -d -w 40 | while read h; do
  echo "Duplicate hash: $h"
  shasum screenshot_*.png | grep "$h"
done
```

Then re-capture the affected views — the DOM state didn't actually change between captures.

Also verify the docx has the expected number of embedded images:

```bash
python3 -c "
import zipfile
z = zipfile.ZipFile('Aegis_SOC_Project_Report.docx')
images = [f for f in z.namelist() if f.startswith('word/media/') and f != 'word/media/']
print(f'{len(images)} images embedded')
for img in images:
    print(f'  {img.split(\"/\")[-1][:16]}... {z.getinfo(img).file_size//1024}KB')
"
```

Compare the count against the number of `screenshotSection()` calls in the script.

### Verify PDF image quality

After converting to PDF, check that image streams are lossless (FlateDecode) and not JPEG-compressed (DCTDecode):

```bash
python3 -c "
with open('Aegis_SOC_Project_Report.pdf', 'rb') as f:
    c = f.read()
print('Images:', c.count(b'/Image'))
print('DCTDecode (JPEG):', c.count(b'/DCTDecode'))
print('FlateDecode (lossless):', c.count(b'/FlateDecode'))
"
```

Expect `DCTDecode=0` and `FlateDecode>images*2` (each image has at least a stream and a filter ref).

Also check image pixel dimensions match expectations:

```bash
python3 -c "
import re
with open('Aegis_SOC_Project_Report.pdf', 'rb') as f:
    content = f.read()
for m in re.finditer(b'/Subtype/Image.{0,200}', content):
    block = m.group().decode('latin-1')
    w = re.search(r'/Width (\d+)', block)
    h = re.search(r'/Height (\d+)', block)
    f_match = re.search(r'/Filter (\S+)', block)
    w_val = w.group(1).rjust(5) if w else '  ?  '
    h_val = h.group(1).rjust(5) if h else '  ?  '
    filt = f_match.group(1) if f_match else '?'
    print(f'{w_val}x{h_val} {filt}')
"
```

Images that are still ~6000px wide were not cropped before embedding. Images that are ~1600-3000px wide were properly processed. An image that should be a dashboard screenshot but is 6000px wide needs cropping before re-export.

## Example: Full implementation

See `references/example-report-script.md` for a complete working script that integrates all phases end-to-end.

## Reference: Modal screenshot technique

See `references/modal-screenshot-technique.md` for the JS scroll-and-overflow technique needed to capture fixed-position modal content that would otherwise appear as a solid black image.

## Font-Size Override for Readable Text

Full-page screenshots at letter/A4 size (~6.27" wide) have a fundamental readability limit: text at 14px CSS captured at native resolution renders at ~4pt in the PDF. Even with `font-size: 22px !important` overrides, the text-to-page-width ratio caps out at ~6.3pt.

The **only reliable way** to get 8pt+ readable text is a **close-up crop** of a specific section (e.g., a single KPI card, a 3-row slice of the alert table). Full-page screenshots with readable text are not achievable at letter size — inform the user and offer close-up alternatives.

### CSS font-size override (for marginal improvement)

Before capturing, inject a style element that overrides all font sizes. This increases text from ~4pt to ~6pt:

```js
var s = document.createElement('style');
s.id = 'big-fonts';
s.textContent = `
  body, button, td, th, input, select, textarea, .badge, .tab {
    font-size: 22px !important;
  }
  h1 { font-size: 32px !important; }
  h2 { font-size: 26px !important; }
  .kpi-card .value { font-size: 42px !important; }
  .kpi-card .label { font-size: 18px !important; }
`;
document.head.appendChild(s);
```

**Must also constrain modal width** — otherwise modals overflow and make the screenshot wider, negating the benefit:

```css
.modal-content { max-width: 800px !important; width: 90% !important; }
body > div { max-width: 800px !important; }
html, body { overflow-x: hidden !important; }
```

### Close-up crop approach (section-level)

```python
from PIL import Image
img = Image.open('screenshot.png')
# Crop to just the top portion (KPI cards + first 3 alert rows)
crop = img.crop((0, 0, img.width, 1200))  # height depends on content
crop.save('screenshot_cropped.png', optimize=True)
```

Then embed `screenshot_cropped.png` at the same docx width (600px) — the crop effectively magnifies the text 2-3x.

**Background sampling approach (preferred over hard-coded thresholds):**
Instead of guessing the background color, sample it from the bottom-right corner of the image (which is reliably background for any page, light or dark). Then compare every pixel against the sampled color with a delimited tolerance. This handles any theme without tuning:

```python
from PIL import Image

def auto_trim(path, pad=10, tolerance=15):
    img = Image.open(path)
    w, h = img.size
    pixels = img.load()
    
    # Sample background from bottom-right corner
    BG = pixels[w-50, h-50]
    
    def is_content(p):
        return (abs(p[0]-BG[0]) > tolerance or
                abs(p[1]-BG[1]) > tolerance or
                abs(p[2]-BG[2]) > tolerance)
    
    left, right, top, bottom = w, 0, h, 0
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            if is_content(pixels[x, y]):
                if x < left: left = x
                if x > right: right = x
                if y < top: top = y
                if y > bottom: bottom = y
    
    cropped = img.crop((
        max(0, left - pad),
        max(0, top - pad),
        min(w, right + pad),
        min(h, bottom + pad)
    ))
    cropped.save(path, optimize=True)
    old_area = w * h
    new_area = cropped.size[0] * cropped.size[1]
    print(f"saved {(1 - new_area/old_area)*100:.0f}% waste")
```

The hard-coded `is_bg` with per-theme thresholds (below this section) is a fallback for when the background-sampling approach fails (e.g., gradient backgrounds, full-white pages where the bottom-right is clipped).

```python
from PIL import Image

def is_bg(r, g, b, a=255):
    """Return True if pixel is dark background (customize threshold per theme)."""
    return r < 40 and g < 40 and b < 45

def auto_trim(path, pad=10):
    img = Image.open(path)
    w, h = img.size
    pixels = list(img.getdata())
    
    # Find leftmost content column
    left = w
    for x in range(w):
        for y in range(h):
            p = pixels[y * w + x]
            if not is_bg(p[0], p[1], p[2]):
                left = x; break
        if left < w: break
    
    # Find rightmost (skip scrollbar zone ~6% from right)
    right = 0
    scroll_zone = int(w * 0.06)
    for x in range(w - 1, -1, -1):
        for y in range(h):
            p = pixels[y * w + x]
            if x < w - scroll_zone and not is_bg(p[0], p[1], p[2]):
                right = x + 1; break
        if right > 0: break
    
    # Find topmost content row
    top = h
    for y in range(h):
        for x in range(w - scroll_zone):
            p = pixels[y * w + x]
            if not is_bg(p[0], p[1], p[2]):
                top = y; break
        if top < h: break
    
    # Find bottommost (skip scrollbar zone)
    bottom = 0
    for y in range(h - 1, -1, -1):
        for x in range(w - scroll_zone):
            p = pixels[y * w + x]
            if not is_bg(p[0], p[1], p[2]):
                bottom = y + 1; break
        if bottom > 0: break
    
    cropped = img.crop((
        max(0, left - pad),
        max(0, top - pad),
        min(w, right + pad),
        min(h, bottom + pad)
    ))
    cropped.save(path, optimize=True)
    old_area = w * h
    new_area = cropped.size[0] * cropped.size[1]
    print(f"{path}: {w}x{h} → {cropped.size[0]}x{cropped.size[1]} "
          f"(saved {(1 - new_area/old_area)*100:.0f}% waste)")
```

**Call this BEFORE the docx generation** so the embedded images are already tight. For the dark theme CSS used by Aegis SOC, a threshold of `rgb(40,40,45)` catches the background. Adjust thresholds for other color schemes.

See `references/screenshot-auto-trim.md` for edge cases (scrollbar strip, modal overlays, gradient backgrounds) and per-theme threshold tables.

If you prefer a CLI, use `scripts/crop-resize.py --auto-trim <file_or_dir>` (see the script's `--auto-trim` flag).

## Lossless PDF Export from LibreOffice

LibreOffice headless defaults to JPEG-compressed, downsampled images. To preserve full-resolution PNG streams in the output PDF, pass filter options as a JSON object in the `--convert-to` parameter:

```bash
rm -f /tmp/report.pdf
soffice --headless --convert-to \
  'pdf:writer_pdf_Export:{"SelectPdfVersion":{"type":"long","value":1},"UseLosslessCompression":{"type":"boolean","value":true},"MaxImageResolution":{"type":"long","value":600},"ExportImagesOriginalSize":{"type":"boolean","value":true}}' \
  --outdir /tmp report.docx
cp /tmp/report.pdf .
```

The filter object syntax is `"Key":{"type":"<type>","value":<value>}` where type is one of `long`, `boolean`, `string`, `double`. Key options:

| Key | Type | Description |
|-----|------|-------------|
| `SelectPdfVersion` | `long` | 0 = PDF/A-1a, 1 = PDF 1.6 (default) |
| `UseLosslessCompression` | `boolean` | `true` → FlateDecode instead of JPEG DCT |
| `MaxImageResolution` | `long` | Max DPI for image downsampling (default 300, pass 600) |
| `ExportImagesOriginalSize` | `boolean` | `true` → don't scale images down to page width |

Verify the result has FlateDecode streams and no DCTDecode:

```bash
python3 -c "
with open('report.pdf', 'rb') as f:
    c = f.read()
print('Images:', c.count(b'/Image'))
print('DCT (JPEG):', c.count(b'/DCTDecode'))
print('Flate (PNG):', c.count(b'/FlateDecode'))
"
```

Expect `DCT: 0, Flate: >0` if lossless export succeeded.

See `references/libreoffice-pdf-export.md` for the full filter-options reference, edge cases, and JSON syntax pitfalls.

## Verification: Check all screenshots made it into the docx

After generating the docx, verify the number of embedded images matches the number of unique screenshots. The `docx` npm library deduplicates by content hash — if two screenshots happen to be identical (e.g., `browser_vision` was called before the DOM state changed), only one copy is stored:

```bash
python3 -c "
import zipfile
z = zipfile.ZipFile('report.docx')
images = [f for f in z.namelist() if f.startswith('word/media/') and f != 'word/media/']
print(f'{len(images)} images:')
for img in images:
    info = z.getinfo(img)
    print(f'  {info.file_size//1024}KB  {img}')
"
```

Also compare shasums of source screenshots to ensure no two have the same hash:

```bash
shasum screenshots/screenshot_*.png | awk '{print $1}' | sort | uniq -d
```

If any duplicate hashes appear, re-capture the affected view (the DOM state didn't change between captures).

## Version History / Changelog Page

When a report documents a software project, include a **Version History** page between the cover and the table of contents showing what changed between releases. This is for executive audiences who need a high-level summary without reading the full document.

### Structure

```
[Cover page]
[Version History page]  ← NEW
[Executive Summary / main content]
```

### Content rules

- **Categories only** — group changes into 3–4 project-facing categories (e.g., "Agentic Investigation Pipeline", "Dashboard UI Overhaul", "Data Pipeline & Detection"). Do NOT include documentation/report changes as a category — the report documents the project, it is not the project.
- **Technical details** that don't affect the user experience (e.g., "Removed legacy Phase 1 / Phase 2 terminology") are noise for executives — omit them.
- **One body paragraph per change** — no bullet lists inside the changelog. Use `body()` for each change item with a bold category heading before each group.
- **Version label** in the changelog heading must match the versioned output filename.

### Versioned output filenames

Output to `<project>/docs/` with versioned names so the project root stays clean:

```js
const DOCS_DIR = path.resolve(__dirname, '..', 'docs');
fs.mkdirSync(DOCS_DIR, { recursive: true });
const BASE_NAME = 'Project_Report_v0.1.1';
const OUTPUT = path.resolve(DOCS_DIR, `${BASE_NAME}.docx`);
const PDF_OUTPUT = path.resolve(DOCS_DIR, `${BASE_NAME}.pdf`);
```

Keep `BASE_NAME` in sync with the version label on the cover page and in the Version History heading — they're manual, but must match.

### Reference

See `references/version-history-pattern.md` for a complete worked example with category hierarchy and output naming.

## Pitfalls

- **pypdf `extract_text()` wraps lines, so substring checks false-negative on wrapped content:** `PdfReader.extract_text()` inserts a newline at every PDF text-line wrap. A present-but-wrapped phrase (e.g. `not \nhardware-isolated`) fails a naive `in full` check, and you will wrongly conclude content is missing. **Fix: whitespace-normalize before asserting** — join all pages, `re.sub(r"\s+", " ", full)`, then run substring checks. This applies to any PDF verification with pypdf; rasterize with pdftoppm when available, but the normalized-text check is authoritative either way. See `references/text-report-pipeline.md`.
- **`sources.py render --replace-in` deletes any footer appended after the `## Sources` block:** the renderer rewrites from the Sources heading to EOF, so a trailing "no credentials" / author note line added with `cat >>` silently vanishes (and `sources.py verify` still passes — it only checks the citation block). Append footers BEFORE the Sources block or re-append after the final render, then `grep -c` to confirm. See `references/text-report-pipeline.md`.
- **Em-dash / forbidden-character audit must exclude the machine-rendered Sources block:** with the `grounded-citations` ledger, `—` separators inside `## Sources` are mechanically generated and exempt from a no-em-dash writing rule. Audit prose only: `awk 'BEGIN{s=1} /^## Sources/{s=0} s' report.md | grep -c "—"`. Same cut applies to any content that must not be counted (verbatim quotes stay, separators stay).
- **Screenshot file needs manual copy**: `browser_vision()` saves screenshots to `~/.hermes/cache/screenshots/`. You must `cp` them to your project's `screenshots/` dir — they are not automatically placed there.
- **`annotate=false` for clean captures**: The `annotate=true` mode overlays element labels on the screenshot. Pass `annotate=false` for report-quality captures.
- **Modal content shows as solid black / blank:** Modals often use `position: fixed` with `overflow: hidden` on `.modal-content`. The viewport-only screenshot captures nothing below the fold. Fix: set `overflowY: 'auto'`, `maxHeight: '80vh'` on `.modal-content`, then `scrollTop` to the desired depth via `browser_console`. Take separate screenshots for modal top, middle, and bottom sections.
- **Prefer viewport constraint over post-processing:** Rather than capturing a 15,000+ px tall full-page image and then cropping/resizing it, prevent the page from being tall in the first place. Override rendering functions to limit rows (e.g., `renderEvents(events.slice(0, 15))`), then constrain `document.documentElement` and `document.body` with `overflow: hidden` and `maxHeight: window.innerHeight + 'px'` before capturing. This gives you a viewport-sized image with no quality loss from resizing and no content decisions from cropping. Only fall back to Pillow resize/crop when you cannot control the page content.
- **Constrain BOTH html and body, not just body:** Setting `document.body.style.maxHeight` alone doesn't prevent `browser_vision` from capturing the full `document.documentElement` scroll height. Always constrain both elements:
  ```js
  document.documentElement.style.overflow = 'hidden';
  document.documentElement.style.maxHeight = window.innerHeight + 'px';
  document.body.style.overflow = 'hidden';
  document.body.style.maxHeight = window.innerHeight + 'px';
  ```
- **re-renderEvents keeps the original ref:** Patching an already-patched function creates closure chains where the second wrapper wraps the first wrapper. Instead of saving `origRE` and re-patching, navigate fresh and apply a single atomic override before triggering the data load. If you need a different row count, write a self-contained override function that doesn't rely on capturing a stale reference.
- **No `\\n` in docx-js**: Use separate `Paragraph` elements instead.
- **`\\u2705` and `\\u23F3` in JS template literals**: Use Unicode escapes for emoji inside backtick strings to avoid encoding issues.
- **Port conflicts**: Kill stale `lsof -ti:8080 | xargs kill -9` before restarting the server.
- **Reload browser tool after server restart**: After killing and restarting the server, call `browser_navigate(url)` again — the tool still shows the old page from the previous session.
- **Viewport meta `width=X` clips content to sub-fraction of capture:** If the page has `<meta name="viewport" content="width=800">`, the layout viewport is 800 CSS px wide regardless of the actual browser window (~1496px). `browser_vision()` captures the full browser viewport at 4x DPR, producing a ~5984px wide image where the dashboard (rendered at 800 CSS px = 3200 physical px) only fills the left 53%. The right 2800px is empty background. When scaled to 780px in the docx, the UI content stretches from 3200px → 780px while the empty area compresses — warping proportions and making text look oversized. **Fix:** Change server HTML to `width=device-width, initial-scale=1.0` and restart the server before capturing. Verify `window.innerWidth` is ~1496 (full browser width), not ~800.
- **Image width overflows docx printable area:** Default Letter/A4 page has 1-inch margins, giving a 6.5-inch printable width. At 96 DPI, a docx image transformation `{ width: 780 }` equals 8.125 inches — 1.625 inches wider than the printable area. LibreOffice clips the right edge, cutting off dashboard content in the PDF. **Fix:** All image widths must be ≤ 600px (= 6.25 inches at 96 DPI, leaving 0.25-inch clearance). Use `{ width: 600, height: proportional }` for every `ImageRun`. The proportional height is `600 * source_height / source_width`. For 3008px-wide cropped screenshots at ~16:9 ratio, use `height: 377`. For other aspect ratios, recalculate: `height = 600 * (h / w)`. **Verification:** After PDF export, run the pixel-dimension check and confirm the widest screenshot image is ≤ 1920px (at ~300 DPI rendering) — wider images indicate the 600px docx width constraint was not applied.

- **Figure numbering must be sequential in document order:** When you add new screenshots or reorder sections, renumber ALL figures to match their final display order. A Figure 6 that appears physically between Figures 2 and 3 (because it's in an earlier document section but was numbered after Figures 3–5) will be flagged as wrong. Number figures in the order they appear in the document, not in the order you captured them. Example: if Section 3.2 has two event-table screenshots (originally numbered 2 and 6), renumber 6→3 and bump 3→4, 4→5, 5→6 so every figure count is contiguous from 1 through N. After renumbering, regenerate the docx + PDF, commit, and run tests — this is purely a label change but verify the output renders correctly.

- **NEVER set `keepNext: true` on figure captions** — a caption's `keepNext` chains to the next figure's heading, creating an unbreakable sequence across multiple figures. If the chain exceeds one page, LibreOffice splits it unpredictably — the last figure's heading ends up on one page and its image on the next, even though the heading has `keepNext` pointing at the image. The fix: caption must have NO `keepNext`. Each figure (heading→image→caption) is self-contained via `keepNext` on heading (→ image) and image (→ caption), but the chain stops at the caption so consecutive figures can page-break independently. This applies even when a multi-figure group has an explicit `PageBreak` before the first one — the break ensures they start on a clean page, but `keepNext` on any caption inside the group still creates intra-group chains that break unpredictably.

- **Prefer body() over bullet hierarchies for documentation guide text:** When writing navigation instructions ("How to reach", "What to look for") or "How to interact" steps under figures, use `body()` flat paragraphs instead of `boldBullet()` / `subBullet()` nesting. Nested bullets are appropriate for technical specs (features, limitations, architecture items that need strict hierarchy) but not for guide text — readers find the indentation and markers distracting when the `boldBullet → subBullet` distinction isn't functional.

  ```js
  // ✅ For documentation guide text:
  body('How to reach: Click the "Events" tab in the tab bar (next to "Alerts").'),
  body('What to look for: Event table with columns: ID, SOURCE TYPE, EVENT TYPE...'),

  // ✅ For bulleted technical items (keep):
  boldLabelBullet('Storage: ', 'SQLite is adequate for prototypes...'),
  boldLabelBullet('Authentication: ', 'No user authentication...'),
  ```

  Use `boldLabelBullet()` (bold label + regular description) for items that have a title/explanation structure. Use `body()` for everything else in guide sections. Reserve `boldBullet()` + `subBullet()` hierarchy for genuine nested specifications where the level-1 heading and level-2 details serve distinct semantic roles.

  **Mixing bullet levels in the same section creates visual inconsistency.** `boldBullet()` uses `level: 1` (indented), while `boldLabelBullet()` uses `level: 0` (top-level). If you use both in the same list section — e.g., 4 items with `boldLabelBullet` and 1 stray `boldBullet` — that one item renders at a different indentation depth, which users flag as "not formatted right." Always use the same bullet-level helper throughout a section. When the section has a `boldLabelBullet` pattern everywhere, convert any lone `boldBullet` call to `boldLabelBullet` with the title as the bold label, not keep the `boldBullet` just because the title is short.

- **Orphaned headings and figure groups:** docx-js will place a heading at the bottom of one page and its body text at the top of the next unless you set `keepNext: true` on the heading paragraph. This applies to both section headings (`heading: HeadingLevel.HEADING_1/2`) and figure-group elements (figure heading, image paragraph, caption). Chain `keepNext: true` on every paragraph in the figure group (heading, image) so they stay together. **CRITICAL: Do NOT set `keepNext` on the caption** — that chains into whatever follows, creating an unbreakable sequence that LibreOffice splits unpredictably when consecutive figures exceed one page. Each figure group should be self-contained: heading→image→caption via heading+image `keepNext`, but the chain stops at the caption so the next figure can start on a fresh page if needed.

  ```js
  // Section heading — sticks to first body paragraph
  new Paragraph({
    children: [new TextRun({ text: title, bold: true, size: 28 })],
    heading: HeadingLevel.HEADING_1,
    keepNext: true,
  })

  // Figure group — heading stays with image, image stays with caption,
  // but the chain STOPS at the caption so LibreOffice can break between
  // consecutive figures independently.
  new Paragraph({ children: [new TextRun({ text: title, ... })], keepNext: true }),  // → chains to image
  new Paragraph({ children: [new ImageRun(...)], keepNext: true }),                   // → chains to caption
  new Paragraph({ children: [new TextRun({ text: caption, ... })] }),                 //  NO keepNext — don't chain to next figure
  ```

  The "How to interact" / "What you can do" heading after each figure group does NOT need `keepNext` — `keepNext` chains FORWARD to the next paragraph (the body text below), not backward to the caption. Since the caption has no `keepNext`, the figure group (heading→image→caption) is self-contained, and a page break between the caption and the heading is natural and correct. Users consistently report broken layouts when the chain accidentally spans multi-figure groups; independent figure blocks are the reliable fix.

- **Major sections on new pages:** Every top-level section (HEADING_1, e.g. "1. Executive Summary", "2. Architecture") should use `pageBreakBefore: true` so each section starts on a fresh page. Sub-sections (HEADING_2, e.g. "1.2", "2.1") should NOT have pageBreaks — they flow naturally under their parent. Apply this on the `section()` helper function, not `subSection()`:

  ```js
  function section(title) {
    return new Paragraph({
      children: [new TextRun({ text: title, bold: true, size: 28 })],
      heading: HeadingLevel.HEADING_1,
      pageBreakBefore: true,
      keepNext: true,
    });
  }
  ```

  When a sub-section contains 2+ back-to-back figures (e.g., 3 modal screenshots in a row), rely on self-contained `keepNext` chains (heading→image only, caption has NO `keepNext`) — this lets consecutive figures page-break independently. Do NOT insert an explicit `PageBreak` before the first figure — when preceding content already fills the page, the break creates a blank page. The `keepNext` approach is the reliable fix; explicit `PageBreak` is fragile.
