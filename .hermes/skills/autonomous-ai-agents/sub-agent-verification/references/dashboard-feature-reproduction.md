# Reproduction: Dashboard Features via opencode

## What happened

Delegated three dashboard improvements (filter bar, LLM badge, event browser tab) to `opencode run` with a markdown spec. OpenCode produced diffs and reported success.

## What verification found

### 1. Syntax check passed
```
uv run python -c "import ast; ast.parse(open('src/api.py').read()); print('Syntax OK')"
→ Syntax OK
```

### 2. Module import passed
```
cd /project && timeout 10 uv run python -c "import sys; sys.path.insert(0,'.'); from src.api import app; print('FastAPI app loaded OK')"
→ FastAPI app loaded OK
```

### 3. Content verification revealed the issue
OpenCode used JS template literals (`${var}`) inside Python triple-quoted strings (the DASHBOARD_HTML variable in api.py). The backslash escaping was broken — OpenCode's first pass produced `\`` instead of just `` ` ``, and a second pass switched to string concatenation to avoid the conflict.

The auto-fix pattern: OpenCode itself detected the escaping issue and patched it in a follow-up edit, switching `showEventDetail` from template literals to `var` + string concatenation.

### 4. Smoke test passed
Started uvicorn, curled the dashboard, confirmed all expected HTML markers appeared:
```
filter-bar, tabs, switchTab, badge-llm, renderEvents, events-view, alerts-view
```

## Key takeaway

OpenCode's diff output looked correct but the actual file had broken template literal escaping. Only independent content verification (grep for expected DOM markers on the live page) caught the escaping mismatch. Syntax and import checks alone were insufficient.
