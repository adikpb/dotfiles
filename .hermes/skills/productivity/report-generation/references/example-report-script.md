# Example: Aegis SOC Dashboard Report

This reference documents the full report-generation workflow used for Aegis SOC v0.1.1 — a single-page SOC dashboard with alerts, events, and agentic investigation capabilities via a tool-calling LLM loop.

## Project Structure

```
agentic-soc/
├── screenshots/                      # Captured PNGs
│   ├── screenshot_01_alerts_dashboard.png    # Alerts main view (397 KB)
│   ├── screenshot_02_events_tab.png          # Events tab (1.6 MB)
│   ├── screenshot_03_alert_modal_top.png     # Modal top — Investigation Report card (434 KB)
│   ├── screenshot_04_investigation_source.png # Modal bottom — history + source events (455 KB)
│   ├── screenshot_05_investigation_expanded.png # Expanded run — tool call details (500 KB)
│   └── screenshot_06_events_detail.png       # Events tab with expanded row (1.7 MB)
├── scripts/
│   └── generate_report.js    # ~440-line docx generation script
├── src/
│   └── api.py                # FastAPI server (dashboard HTML+JS embedded)
├── Aegis_SOC_Project_Report.docx   # Output report (4.1 MB)
└── Aegis_SOC_Project_Report.pdf    # PDF export (14 pages, ~800 KB)
```

## View States Captured

| Screenshot | View | Captured via |
|---|---|---|
| `01_alerts_dashboard` | Default landing — KPI cards, filter bar, 7-alert table | `browser_navigate` + `browser_vision()` |
| `02_events_tab` | Events table with 100 normalized events | `browser_click` on Events tab + `browser_vision()` |
| `03_alert_modal_top` | Alert #1 detail — Investigation Report card (verdict, severity, evidence, MITRE tags) | `browser_click` on alert row + `browser_vision()` |
| `04_investigation_source` | Modal scrolled — Investigation History + Source Events | JS scroll on `.modal-content` + `browser_vision()` |
| `05_investigation_expanded` | Expanded run showing tool calls with parameters + durations | JS click on `<details>` summary + scroll + `browser_vision()` |
| `06_events_detail` | Events tab with fraud event row expanded | `browser_click` on event row + `browser_vision()` |

**No JS patches to the server needed.** All state changes are done via browser tool clicks and console JS — the running server is never restarted or modified.

## Screenshot Capture Workflow (via Hermes browser tools)

```bash
# 1. Navigate to dashboard
browser_navigate(url="http://127.0.0.1:8080/")

# 2. Take alert dashboard screenshot — browser_navigate already returns a snapshot
browser_vision(annotate=false)
# → copies screenshot_path to ./screenshots/screenshot_01_alerts_dashboard.png

# 3. Switch to events tab, capture events table
browser_click(ref="e7")   # Events tab element from snapshot
browser_vision(annotate=false)
# → screenshot_02_events_tab.png

# 4. Switch back to alerts, open modal, capture report card
browser_click(ref="e6")   # Alerts tab
browser_click(ref="e39")  # Alert #1 row
browser_vision(annotate=false)
# → screenshot_03_alert_modal_top.png

# 5. Make modal content scrollable, scroll to bottom, capture Investigation History
browser_console(expression="document.querySelector('.modal-content').style.overflowY='auto'; document.querySelector('.modal-content').style.maxHeight='80vh'; document.querySelector('.modal-content').scrollTop=1500")
browser_vision(annotate=false)
# → screenshot_04_investigation_source.png

# 6. Expand the details run entry, scroll further, capture tool call detail
browser_console(expression="document.querySelector('#inv-content-1 details summary').click()")
browser_console(expression="document.querySelector('.modal-content').scrollTop=5000")
browser_vision(annotate=false)
# → screenshot_05_investigation_expanded.png

# 7. Close modal, switch to events, click a fraud-row, capture expanded event detail
browser_console(expression="closeModal()")
browser_click(ref="e7")
browser_console(expression="document.querySelectorAll('#events-table tbody tr')[63].click()")
browser_vision(annotate=false)
# → screenshot_06_events_detail.png
```

## Docx Report Script

The `scripts/generate_report.js` is a ~440-line Node.js script that:
1. Defines helper functions: `body()`, `bullet()`, `boldBullet()`, `subBullet()`, and the mixed-format `boldLabelBullet()`
2. Embeds 6 screenshots via `ImageRun` at 780×490 px (users found 650×480 illegibly small)
3. Includes a data dictionary table with 13 field rows
4. Uses docx `numbering` config with 3 `LevelFormat.BULLET` levels
5. Builds a cover page with centered title/subtitle
6. Converts to PDF via LibreOffice headless

Key API calls:

```js
// Image at readable size — avoid 650×480
new ImageRun({
  data: `image/png;base64,${buf.toString('base64')}`,
  transformation: { width: 780, height: 490 },
  type: 'png',
})

// Mixed-format bullet — saves users from all-bold reading fatigue
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
```

## PDF Conversion (macOS)

```bash
# LibreOffice is not in PATH on macOS by default — use full path:
/Applications/LibreOffice.app/Contents/MacOS/soffice \
  --headless --convert-to pdf --outdir . Aegis_SOC_Project_Report.docx

# Or symlink it:
sudo ln -s /Applications/LibreOffice.app/Contents/MacOS/soffice /usr/local/bin/soffice
soffice --headless --convert-to pdf --outdir . report.docx

file Aegis_SOC_Project_Report.pdf   # → PDF document, version 1.7, 14 pages
ls -lh Aegis_SOC_Project_Report.pdf # ~800 KB with all 6 images
```

## Verification

```bash
# Check embedded images count and size
python3 -c "
import zipfile
with zipfile.ZipFile('Aegis_SOC_Project_Report.docx') as z:
    media = [n for n in z.namelist() if 'media' in n]
    print(f'Images: {len(media)}')
    for m in media: print(f'  {m}: {z.getinfo(m).file_size} bytes')
"

# Verify headings/sections
pandoc -t markdown Aegis_SOC_Project_Report.docx | grep '^#' | head -30

# Stale terminology check
pandoc -t plain Aegis_SOC_Project_Report.docx | \
  grep -n -i 'phase 1\|phase 2\|llm analysis\|analyze button\|5 alerts\|650' || \
  echo "No stale terms found"
```
