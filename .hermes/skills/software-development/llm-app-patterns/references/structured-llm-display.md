---
name: structured-llm-display
description: Render structured LLM verdicts as formatted dashboard cards.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [ui, llm, dashboard, display]
---

# Structured LLM Display

## When to Use

A web dashboard integrates an LLM analysis endpoint and the raw JSON verdict needs to be presented as a readable structured card rather than a `<pre>` blob.

Applies to any SOC-like dashboard, alert triage UI, investigation panel, or report view where an LLM returns a structured verdict with fields like `verdict`, `severity_assessment`, `summary`, `evidence_cited`, `recommended_actions`, `confidence_score`, etc.

## Core Pattern

Replace a raw JSON `<pre>` block with an IIFE that parses the JSON and builds HTML sections. The pattern lives inside a template literal (JS-in-HTML-in-Python), which requires careful escaping.

### Structure

```
+------------------------------------------------------------------+
| Investigation Report                                              |
| [Malicious] [Critical] Confidence: 92%                          |
|                                                                  |
| Single inbound SMS containing malware detected. The message      |
| was sent from a disposable email account...                      |
|                                                                  |
| Evidence                                                         |
| • Malware signature detected...                                  |
| • Sender uses disposable email service...                        |
|                                                                  |
| Recommended Actions                                              |
| 1. Block sender address at gateway level                         |
| 2. Add domain to blocklist                                       |
|                                                                  |
| MITRE ATT&CK Techniques                                          |
| [T1596]  [T1597]  [T1563]                                       |
|                                                                  |
| ▼ Raw JSON                                                       |
+------------------------------------------------------------------+
```

## Section Pattern (building the HTML)

Each section follows a consistent pattern:

```javascript
// 1. Field presence check
if (analysis.evidence_cited && analysis.evidence_cited.length) {
  // 2. Section header
  html += '<div style="font-size:12px;font-weight:600;color:var(--text2);margin-bottom:4px">Evidence</div>';
  // 3. Open list
  html += '<ul style="margin:0 0 10px 0;padding-left:18px;font-size:12px;line-height:1.5">';
  // 4. Iterate items
  analysis.evidence_cited.forEach(function(e) {
    html += '<li>' + htmlEscape(e) + '</li>';
  });
  // 5. Close list
  html += '</ul>';
}
```

## Verdict Color Mapping

| Verdict value | Color |
|---|---|
| `malicious`, `tp`, `true_positive` | `#ef4444` (red) |
| `benign`, `fp`, `false_positive` | `#22c55e` (green) |
| `suspicious`, `needs_review`, others | `#f59e0b` (amber) |

```javascript
var vColor = (v+'').toLowerCase().includes('malicious')
  || (v+'').toLowerCase() === 'tp'
  || (v+'').toLowerCase() === 'true_positive'
  ? '#ef4444'
  : (v+'').toLowerCase().includes('benign')
    || (v+'').toLowerCase() === 'fp'
    || (v+'').toLowerCase() === 'false_positive'
    ? '#22c55e'
    : '#f59e0b';
```

## Severity Color Mapping

```javascript
var sevColor = sev.toLowerCase() === 'critical' ? '#ef4444'
  : sev.toLowerCase() === 'high' ? '#f97316'
  : sev.toLowerCase() === 'medium' ? '#f59e0b'
  : '#22c55e';
```

## Sections to Render

Render in this order, showing only sections that have data:

1. **Badge row** — verdict + severity + confidence (always if verdict exists)
2. **Summary** — narrative text (if `analysis.summary`)
3. **Evidence** — bullet list (if `analysis.evidence_cited?.length`)
4. **Correlated Findings** — bullet list (if `analysis.correlated_findings?.length`)
5. **Recommended Actions** — numbered list (if `analysis.recommended_actions?.length`)
6. **False Positive Indicators** — bullet list (if `analysis.false_positive_indicators?.length`)
7. **MITRE ATT&CK Techniques** — pill tags (if `analysis.mitre_attack_techniques?.length`)
8. **Raw JSON** — collapsible `<details>` at the bottom (always)

## Template Literal Escaping (Critical Pitfall)

When the card builder JavaScript lives inside a Python string that generates a web page, each layer of escaping must match exactly.

**Context:** Python string -> HTML -> JS `<script>` block -> JS template literal -> HTML concatenation in JS.

| Context | Escaping needed |
|---|---|
| Python string | `\"` for HTML attribute quotes, `\'` for JS single-quoted strings |
| JS template literal | Backticks — `"` inside does not need escaping |
| JS single-quoted string | `\'` embeds literal single quotes inside a `'...'` string |

**Best practice:** Use double quotes for the outermost Python string, backslash-escape only the `"` that appear as HTML attribute delimiters inside the JS.

```python
# The \" inside the Python string preserves " for HTML attributes
html += '<span class=\"badge\">' + text + '</span>'
```

## Complete IIFE Scaffold

```javascript
${a.agent_analysis ? (() => {
  try {
    var analysis = JSON.parse(a.agent_analysis);
    var v = analysis.verdict || 'needs_review';
    var sev = analysis.severity_assessment || '';
    var conf = analysis.confidence_score;

    var vColor = /* verdict color mapping */;
    var sevColor = /* severity color mapping */;

    var html = '<div class=\"kpi-card\"><div class=\"label\">Investigation Report</div>';

    // Badge row
    html += '<div style=\"display:flex;gap:8px;margin-bottom:10px;flex-wrap:wrap;align-items:center\">';
    html += '<span style=\"padding:3px 10px;border-radius:4px;font-weight:700;font-size:13px;background:' + vColor + '22;color:' + vColor + '\">' + htmlEscape(v) + '</span>';
    html += sev ? '<span style=\"padding:3px 8px;border-radius:4px;font-size:11px;background:' + sevColor + '22;color:' + sevColor + '\">' + htmlEscape(sev) + '</span>' : '';
    html += conf !== undefined && conf !== null ? '<span style=\"font-size:11px;color:var(--text2)\">Confidence: ' + conf + '%</span>' : '';
    html += '</div>';

    // Summary
    if (analysis.summary) {
      html += '<div style=\"font-size:13px;margin-bottom:12px;line-height:1.6;color:var(--text1)\">' + htmlEscape(analysis.summary) + '</div>';
    }

    // Evidence / Correlated Findings / False Positive Indicators
    // Use same pattern: header + <ul> + forEach + </ul>

    // Recommended Actions (numbered list)
    if (analysis.recommended_actions && analysis.recommended_actions.length) {
      html += '<div style=\"font-size:12px;font-weight:600;color:var(--text2);margin-bottom:4px\">Recommended Actions</div><ol style=\"margin:0 0 10px 0;padding-left:18px;font-size:12px;line-height:1.5\">';
      analysis.recommended_actions.forEach(function(a) { html += '<li>' + htmlEscape(a) + '</li>'; });
      html += '</ol>';
    }

    // MITRE ATT&CK Techniques (pill tags)
    if (analysis.mitre_attack_techniques && analysis.mitre_attack_techniques.length) {
      html += '<div style=\"font-size:12px;font-weight:600;color:var(--text2);margin-bottom:4px\">MITRE ATT&amp;CK Techniques</div><div style=\"display:flex;gap:4px;flex-wrap:wrap;margin-bottom:10px\">';
      analysis.mitre_attack_techniques.forEach(function(t) {
        html += '<span style=\"padding:2px 8px;border-radius:3px;font-size:11px;background:rgba(139,92,246,0.15);color:#a78bfa;font-family:monospace\">' + htmlEscape(t) + '</span>';
      });
      html += '</div>';
    }

    // Collapsible Raw JSON
    html += '<details style=\"margin-top:8px\"><summary style=\"cursor:pointer;font-size:11px;color:var(--text2)\">Raw JSON</summary><pre style=\"font-size:11px;margin-top:4px;white-space:pre-wrap;background:var(--bg2);padding:8px;border-radius:4px\">' + htmlEscape(JSON.stringify(analysis, null, 2)) + '</pre></details>';
    html += '</div>';
    return html;

  } catch(e) {
    // Fallback for malformed JSON
    return '<div class=\"kpi-card\"><div class=\"label\">Investigation Report</div><pre style=\"font-size:12px;margin-top:4px;white-space:pre-wrap\">' + htmlEscape(a.agent_analysis) + '</pre></div>';
  }
})() : ''}
```

## Error Handling

The `catch` block must fall back gracefully — if JSON is malformed or missing expected fields, show raw content in a `<pre>`. Never let a parsing error crash the whole modal.

## Field Naming Convention

| Field | Type | Display |
|---|---|---|
| `verdict` | string | Colored badge |
| `severity_assessment` | string | Colored badge |
| `confidence_score` | number | "Confidence: N%" |
| `summary` | string | Narrative paragraph |
| `evidence_cited` | string[] | Bullet list |
| `correlated_findings` | string[] | Bullet list |
| `recommended_actions` | string[] | Numbered list |
| `false_positive_indicators` | string[] | Bullet list |
| `mitre_attack_techniques` | string[] | Pill tags |
| Others | any | Inside collapsible Raw JSON |

## Pitfalls

- **Do NOT embed htmlEscape inside the JSON.stringify** — apply htmlEscape to the *result* of stringify, not inside it
- **forEach inside template literal**: `this` is the global object, but since we use `function(e)` referencing only local `var html`, it's safe
- **Parameter name collision**: Avoid `function(a)` in forEach — `a` shadows outer alert-loop variable. Use `function(e)` or `function(f)`
- **Missing fields crash**: Always check `&& field.length` before iterating. An undefined `.length` throws
- **Escaping order**: JSON.stringify is NOT HTML-safe. Always wrap with htmlEscape()
- **Confidence score type**: Can be `null`, `undefined`, or `0` — test with `!== undefined && !== null` since `0` is falsy but valid
