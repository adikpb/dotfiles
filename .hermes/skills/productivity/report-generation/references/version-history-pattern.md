# Version History / Changelog Page — Worked Example

## Structure

```
[Cover page — Aegis SOC v0.1.1]
[Version History — one page, between cover and content]
[Executive Summary / main content]
```

## Output path

```
project/
  docs/
    Aegis_SOC_Project_Report_v0.1.1.docx
    Aegis_SOC_Project_Report_v0.1.1.pdf
  scripts/
    generate_report.js
```

## Script code

Inserted between the cover section and the Executive Summary section in `sections[]`:

```js
// ── VERSION HISTORY ────────────────────────────────────
{
  properties: {
    page: {
      margin: { top: convertInchesToTwip(1), bottom: convertInchesToTwip(1), left: convertInchesToTwip(1), right: convertInchesToTwip(1) },
    },
  },
  children: [
    new Paragraph({
      children: [new TextRun({ text: 'Version History', bold: true, size: 28, color: '1a1d27' })],
      heading: HeadingLevel.HEADING_1,
      pageBreakBefore: true,
      keepNext: true,
      spacing: { before: 400, after: 200 },
      thematicBreak: true,
    }),

    new Paragraph({ children: [new TextRun({ text: 'v0.1.1 — Agentic SOC', bold: true, size: 26, color: '3b82f6' })], keepNext: true, spacing: { before: 200, after: 40 } }),
    new Paragraph({ children: [new TextRun({ text: 'Changes from the initial prototype build to the current release:', italics: true, size: 20, color: '666666' })], spacing: { after: 100 } }),

    // ── Category 1 ──────────────────────────────────
    new Paragraph({
      children: [new TextRun({ text: 'Agentic Investigation Pipeline', bold: true, size: 22, color: '2c3e50' })],
      keepNext: true,
      spacing: { before: 240, after: 80 },
    }),
    body('Replaced static LLM prompt with a tool-augmented, OpenAI-compatible function-calling loop. The LLM now autonomously decides which database tools to call during investigation.'),
    body('6 SQL query tools implemented: sender lookup, domain lookup, recipient lookup, historical comparison, event window analysis, and MITRE ATT&CK classification.'),
    body('Investigation Ledger created — a persistent audit trail across 3 tables (investigation_runs, investigation_events, investigation_artifacts) recording every tool call, LLM response, and execution duration.'),

    // ── Category 2 ───────────────────────────────────
    new Paragraph({
      children: [new TextRun({ text: 'Dashboard UI Overhaul', bold: true, size: 22, color: '2c3e50' })],
      keepNext: true,
      spacing: { before: 240, after: 80 },
    }),
    body('Replaced raw JSON investigation output with structured Investigation Report cards: color-coded verdict badges (Safe / Suspicious / Malicious), confidence scoring (0–100%), narrative summary, numbered evidence items, correlated patterns, recommended actions, and MITRE ATT&CK tags.'),
    body('Added expandable Investigation History in the alert detail modal, showing each run\'s tool calls with parameters, execution duration (ms), and artifact links.'),
    body('Added event detail panel in the Events tab — click any row to expand metadata fields.'),

    // ── Category 3 ───────────────────────────────────
    new Paragraph({
      children: [new TextRun({ text: 'Data Pipeline & Detection', bold: true, size: 22, color: '2c3e50' })],
      keepNext: true,
      spacing: { before: 240, after: 80 },
    }),
    body('Ingested 3,652 events from production mail-log data across 7 auto-detected CSV types.'),
    body('10 YAML detection rules (M001–M010) covering threshold, presence, and pattern-based detection.'),
    body('Idempotent CSV ingestion with file fingerprinting to prevent double-insertion.'),
  ],
},

// ── 1. EXECUTIVE SUMMARY ────────────────────────────────
{
  properties: { ... },
  children: [
    section('1. Executive Summary'),
    ...
  ],
},
```

## Output filename config

At the bottom of the script, before `Packer.toBuffer`:

```js
const DOCS_DIR = path.resolve(__dirname, '..', 'docs');
fs.mkdirSync(DOCS_DIR, { recursive: true });
const BASE_NAME = 'Aegis_SOC_Project_Report_v0.1.1';
const OUTPUT = path.resolve(DOCS_DIR, `${BASE_NAME}.docx`);
const PDF_OUTPUT = path.resolve(DOCS_DIR, `${BASE_NAME}.pdf`);
```

The `BASE_NAME` must match:
- The subtitle on the cover page (`'Project Report — v0.1.1 Agentic SOC'`)
- The version heading in the Version History section (`'v0.1.1 — Agentic SOC'`)

Keep all three in sync manually.
