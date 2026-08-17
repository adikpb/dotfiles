# Modal / Overlay Screenshot Technique

When `browser_vision()` returns a solid black image, the target content is likely inside a fixed-position modal with `overflow: hidden` on its container. The viewport-only capture has nothing to snap below the fold.

## Root Cause

CSS `overflow: hidden` on `.modal-content` (or `position: fixed` on `.modal-overlay`) prevents the browser rendering surface from including content outside its visible box. `browser_vision()` screenshots the viewport — if the modal overflows the viewport, the overflow area captures as black.

## Fix

Use `browser_console` to force the modal container to be scrollable with a fixed height, then programmatically scroll it.

```js
// Step 1: Make modal content scrollable
document.querySelector('.modal-content').style.overflowY = 'auto';
document.querySelector('.modal-content').style.maxHeight = '80vh';

// Step 2: Scroll to the desired section
document.querySelector('.modal-content').scrollTop = 1500;  // middle section
// Or: .scrollTop = 3000 for bottom section
// Or: .scrollTop = 0 for top section (default view)

// Step 3: Take screenshot
```

Then call `browser_vision()` as normal.

## Capture Strategy for Multi-Section Modals

Don't try to capture the entire modal in one screenshot — the image will be too small to read. Instead, plan one screenshot per logical section:

| ScrollTop | Section | What it shows |
|-----------|---------|---------------|
| `0` | Modal top | Header, metadata, report card header + narrative |
| `1500` | Modal middle | Investigation History, expandable run entries |
| `3000` | Modal bottom (expanded) | Tool call details, durations, LLM artifacts, source events table |

Each section becomes its own figure in the report with its own caption.

## Expanding Disclosure Triangles (`<details>` / `<summary>`)

Some modal content uses HTML `<details><summary>` elements for expandable sections (investigation runs, tool call histories, raw JSON). These often **do not appear as clickable `@ref` elements** in the browser snapshot because the accessibility tree collapses them as generic groups — `browser_click` cannot target them.

**Fix:** Toggle them via `browser_console` using JavaScript:

```js
// Step 1: Find all <details> elements in the modal
var mc = document.querySelector('.modal-content');
var allDetails = mc.querySelectorAll('details');

// Step 2: Close others, open the target (by index)
allDetails[0].open = false;  // e.g., Close "Raw JSON"
allDetails[1].open = true;   // e.g., Open "Run: abc123..."

// Step 3: Scroll the expanded content into view
allDetails[1].scrollIntoView({block: 'start'});
```

**Sanity check — list all details elements:**
```js
var mc = document.querySelector('.modal-content');
var allDetails = mc.querySelectorAll('details');
var result = [];
for (var d of allDetails) {
  var summary = d.querySelector('summary');
  result.push(summary ? summary.textContent.trim() : '(no summary)');
}
result;  // e.g., ["Raw JSON", "Run: abc123..."]
```

**Why this works:** Setting `.open = true` on a `<details>` element is equivalent to clicking its `<summary>` — the element expands to show its child content. The `.open = false` collapses it. This bypasses the need for a clickable `@ref` in the accessibility snapshot.

**Modal content with many `<details>`:** In dashboards that nest investigation runs (each with its own tool calls), you may need to toggle specific indices. Always list them first with the sanity-check code to find the right index.

## Event Row Detail Panels (data-table click-to-expand)

Some dashboards render event tables where clicking a row shows a detail panel below it. Two common issues:

**Issue A — onclick uses HTML-escaped JSON that fails to parse:**

```html
<!-- The escaped &quot; breaks eval -->
<tr onclick="showEventDetail({&quot;id&quot;:2627,...})">
```

**Fix:** Extract data from DOM `<td>` cells and pass it to the function directly:

```js
var rows = document.querySelectorAll('.event-row');
var r = rows[0];
var cells = r.querySelectorAll('td');
var eventData = {
  id: parseInt(cells[0].textContent.replace('#','')),
  source_type: cells[1].textContent.trim(),
  event_type: cells[2].textContent.trim(),
  sender: cells[3].textContent.trim(),
  recipient: cells[4].textContent.trim(),
  count: parseInt(cells[6].textContent.trim()),
  timestamp: cells[7].textContent.trim()
};
// Call the page's existing show function with clean data
showEventDetail(eventData);
```

**Issue B — rows are aggregate summaries with no detail to show:** If all rows show `-` for sender/recipient/subject, they may be aggregation rows (e.g., `total`/`clean` counts per domain). The detail panel exists but has no useful data. In that case, construct sample data with meaningful values to demonstrate the panel's appearance — the function will render it regardless of whether the real data is populated.

## Complete Workflow

```
1. Open modal (browser_click on alert row)
2. browser_vision(annotate=false)         → screenshot_03_modal_top.png
3. browser_console → set scroll, overflow  → scroll to 1500
4. browser_vision(annotate=false)         → screenshot_04_modal_middle.png
5. browser_console → expand a <details> element via JS (.open = true)
6. browser_console → scroll to 3000       → show expanded tool calls
7. browser_vision(annotate=false)         → screenshot_05_modal_expanded.png
8. Copy each to screenshots/ dir
```
