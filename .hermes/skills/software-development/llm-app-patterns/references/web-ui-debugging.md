---
name: web-ui-debugging
description: "Use Hermes browser tools to debug JS in rendered dashboards."
version: 1.0.0
author: Hermes Agent (from session experience)
metadata:
  hermes:
    tags: [debugging, browser, javascript, ui, dashboard, fastapi, html-templates]
---

# Web UI Debugging

## When to Use

Use this skill when a web dashboard/UI is not rendering or behaving as expected,
especially when the HTML/JS is served as inline template strings from a Python
server (FastAPI, Flask). This covers:

- Mouse clicks don't trigger expected UI changes (modals, menus, toasts)
- JavaScript functions are "not defined" despite being in the source
- UI elements are missing or look wrong
- Modal overlays don't appear

## Debugging Pipeline

### Phase 1: Check for JS Errors

Start here — silent JS errors are the #1 cause of "nothing happened" bugs.

```js
// Check how many <script> blocks exist
document.querySelectorAll('script').length

// Read the content of the second script block
document.querySelectorAll('script')[1].textContent.slice(0, 200)

// Compile-check for syntax errors
try { new Function(document.querySelectorAll('script')[1].textContent) }
catch(e) { 'Syntax error: ' + e.message }

// Binary-search the error line
const text = document.querySelectorAll('script')[1].textContent;
const lines = text.split('\n');
for(let i = 0; i < lines.length; i++) {
  try { new Function(lines.slice(0, i + 1).join('\n')); }
  catch(e) { return 'Error at line ' + i + ': ' + lines[i]; }
}
```

### Phase 2: Check Console for Runtime Errors

Use `browser_console(clear=false)` to read JS errors after interacting with
the page. Errors with empty messages are often parse errors in a prior script
block that prevented later code from running.

### Phase 3: Visually Inspect

Use `browser_vision(question=...)` to see what's actually on screen.
Compare what the accessibility tree says vs what the visual shows.

### Phase 4: Validate Function Definitions

```js
// Check that expected functions are defined
typeof openAlertModal
typeof loadInvestigations
```

## Common Server-Rendered JS Pitfalls

### `${...}` Outside Template Literal

**Problem:** A `${a.id}` expression ends up in raw JavaScript code outside any
backtick string. This is a syntax error — `${...}` is only valid inside JS
template literals.

**Detection:** `new Function()` fails with "missing ) after argument list" or
"illegal return statement".

**Fix:** Replace `${a.id}` with `a.id` (direct variable reference) or use string
concatenation when not inside a backtick scope.

### HTML Entities in `<script>` Tags

**Problem:** `&amp;` inside a `<script>` tag is NOT parsed as `&` by the browser
— `<script>` is a raw text element. The literal text `&amp;` breaks JS parsing.

**Fix:** Use raw Unicode or `String.fromCharCode(38)` in JavaScript code inside
script blocks.

### Inline IIFE in Template Interpolation

**Problem:** An immediately-invoked function expression like
`${a.analysis ? (() => { ... })() : ''}` inside a JavaScript template literal
can fail if braces inside string literals confuse the parser.

**Fix:** Keep the IIFE short. Test it in the browser console first. Extract
complex logic to a named helper function.

## Workflow: Edit → Verify Loop

1. Edit server source (e.g. `src/api.py`).
2. Restart the web server.
3. Navigate to the page with `browser_navigate`.
4. Check console for JS errors.
5. Visually confirm with `browser_vision`.
6. Run backend tests to confirm no regression.
