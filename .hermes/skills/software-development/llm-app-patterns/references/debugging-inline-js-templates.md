# Reproduction Recipe: Silent JS Failure in Aegis SOC Dashboard

## Symptom

Clicking an alert row in the dashboard table — no modal overlay appeared.
No error shown on the page itself.

## Detection Trace

1. `browser_console(clear=false)` showed 3 JS exceptions with empty messages.
2. `typeof openAlertModal` returned `undefined`.
3. `document.querySelectorAll('script').length` returned 2.
4. `new Function(scripts[1].textContent)` threw "missing ) after argument list".
5. Binary search isolated the error: `${a.id}` on the `setTimeout` call line.

## Root Cause

The second `<script>` block had this code:

```js
setTimeout(function() { loadInvestigations(${a.id}); }, 0);
```

The `${a.id}` is outside any JavaScript backtick string (it's in raw JS code).
`${...}` is only valid inside JavaScript template literals. The browser's JS
parser errors on this, and the entire second script block is discarded — all
functions defined in it (openAlertModal, closeModal, loadInvestigations, etc.)
are never registered.

## Why It Happened

The code lives in a Python `"""..."""` string (DASHBOARD_HTML in src/api.py).
When opencode or a human writes backtick-delimited template interpolation
inside the Python string, it's easy to mistake the scope boundary: which parts
are inside the JavaScript backtick (where `${}` is valid) vs outside (where it's
syntax).

## Fix

Changed `${a.id}` to `a.id`:

```js
setTimeout(function() { loadInvestigations(a.id); }, 0);
```

## Lesson

Any `${...}` in a `<script>` block that is NOT inside a JavaScript backtick
string is a syntax error. Look for:

1. Lines that are after the closing `\`;` of the backtick template but still
   contain `${...}` — these are always wrong.
2. Event handler attributes (`onclick="${...}"`) in HTML that was supposed to
   be plain JS, not a template literal.

## Verification

After fix:
- `typeof openAlertModal` returned `function`.
- Clicking a row opened the modal.
- `new Function(scripts[1].textContent)` succeeded.
- 14/14 tests passed.
