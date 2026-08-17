# Local LLM Queue Discipline for Agentic Loop Testing

## The Problem

When testing an agentic SOC loop against a local LLM (LM Studio, Ollama, etc.), every `investigate_alert_agentic()` call makes one or more `POST /v1/chat/completions` requests to the LLM server. Local LLMs serve requests **sequentially** — they have a single internal queue. If you fire multiple deep-analysis requests concurrently (e.g., via multiple tabs, auto-analyze at startup, repeated browser clicks, and terminal curls), they all pile up in the LLM's queue. Each waits for all previous requests to finish.

Result: the first request completes in ~2 minutes, the second in ~4, the Nth in ~2N minutes. Everything looks stuck. The investigation runs show tool calls completing instantly but the LLM reasoning step never finishes because the LLM is serving the queue.

## The Rule

**One deep analysis at a time.** Never start a second analysis until the first one's response has been received.

## Detection: Is the LLM Busy?

Before sending a new deep-analysis request, check whether the LLM is already processing work:

```bash
# Quick probe — if this takes >5s, the LLM is saturated
curl -s --max-time 5 http://localhost:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-9b-abliterated-mlx","messages":[{"role":"user","content":"ok"}],"max_tokens":2}'
```

- **Exit 0 with content** → LLM is free. Safe to send analysis.
- **Exit 124 (timeout)** → LLM is busy. Wait and retry.
- **Exit 28 (connection refused)** → LLM server is down.

The `/v1/models` endpoint always responds quickly even when the LLM is saturated — it reads the registry, not the model state. **Do not use `/v1/models` as a readiness check.**

## Workflow

### Single analysis (recommended for testing)

```bash
# Start one analysis in background, wait for it
curl -s --max-time 600 -X POST http://localhost:8080/api/alerts/1/analyze-agentic
```

Use `background=True` + `notify_on_complete=True` in a terminal call, or just a foreground curl with `--max-time 600`. Never fire a second curl until the first completes.

### Queue inspection

If analysis runs have been created previously and you're not sure if they completed:

```bash
# Check the latest investigation run
curl -s http://localhost:8080/api/alerts/<id>/investigations | python3 -c "
import json, sys
runs = json.load(sys.stdin)
latest = sorted(runs, key=lambda r: r['started_at'], reverse=True)[0]
print(f'Run: {latest[\"id\"][:8]}... status: {latest[\"status\"]} events: {len(latest.get(\"events\",[]))} completed: {latest.get(\"completed_at\",\"-\")}')
"
```

A run with `status: "running"` and `completed_at: null` is still queued or in progress. A run with `completed_at` set and events populated is done.

## Avoiding the Pile-Up

| Scenario | Correct Approach |
|---|---|
| **Auto-analyze on startup** | Set `auto_analyze_alerts: false` in config.yaml. Manually trigger each alert one at a time. |
| **Browser testing** | Click "🔍 Deep" on one alert, wait for the verdict to appear, THEN click the next. The dashboard auto-refreshes — watch for the LLM column to change from ⏳ to ✅. |
| **Terminal / curl testing** | Fire one curl, wait for the response, then fire the next. Do not use a loop or batch. |
| **Multiple alerts need analysis** | Analyze alert #1 → wait for completion → analyze alert #2 → wait → etc. Each takes 1-5 minutes depending on LLM speed and iteration count. |
| **Browser console API calls** | Do not use `browser_console` to call `deepAnalyzeAlert(id)` — the console has a 30s timeout that kills the async fetch before the LLM responds. Use terminal curl instead. |

## Why Local LLMs Are Sequential

Local LLM inference servers (LM Studio, Ollama, llama.cpp) typically run a single model instance on a single GPU or CPU. Each request holds the full context in memory. Running two requests concurrently would:
1. Double memory pressure
2. Cause context thrashing
3. Slow both requests to a crawl

This is not a bug — it's expected behavior for local inference.

## Relevant Config

```yaml
# config.yaml
llm:
  timeout: 120.0       # Per-LLM-call timeout (reasoning models need 120s+)
  max_tokens: 4096
  temperature: 0.1

agentic:
  max_iterations: 8    # Max tool-calling iterations per analysis
```
