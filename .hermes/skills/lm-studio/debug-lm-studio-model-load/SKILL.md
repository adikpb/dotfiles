---
name: debug-lm-studio-model-load
description: "Use when LM Studio model JIT load hangs. Diagnose and fix."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos]
---

# Debugging LM Studio Model Load Failures

When LM Studio's model listing API responds but chat completions time out, the model JIT loading is likely stuck. Here's how to diagnose and fix.

## Symptoms

- `curl -s http://127.0.0.1:1234/v1/models` returns fast (model list)
- `curl -s http://127.0.0.1:1234/v1/chat/completions` times out (even for 2-token "ping" prompts)
- LM Studio worker process shows sustained 40-50% CPU for minutes

## Diagnosis

### 1. Check LM Studio worker process

```bash
ps aux | grep -i lmstudio | grep llmworker
```

Key signals:
- **Healthy**: CPU < 10% when idle, spikes to 30-60% only during inference
- **Stuck**: 40-50% CPU sustained for 5+ minutes with no API response

### 2. Check system memory pressure

```bash
top -l 1 -n 0 | grep PhysMem
```

- If free memory < 2GB with a 9B model, the model may be swapping
- macOS memory pressure > 50% (red zone) means the kernel is paging heavily

### 3. Verify inference server health

```bash
# Models endpoint (fast — doesn't load the model)
curl -s http://127.0.0.1:1234/v1/models

# Inference endpoint (triggers JIT load if not yet loaded)
curl -s --max-time 60 http://127.0.0.1:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.5-9b-abliterated-mlx","messages":[{"role":"user","content":"ok"}],"max_tokens":2}'
```

If models responds but inference times out → stuck JIT load.

## Resolution

1. **Quit LM Studio fully** (Cmd+Q) — do not just kill the process
2. **Reopen LM Studio**
3. **Load only the model you need** — unload any others
4. **Wait** for the model tab to show "Ready" before making inference calls
5. Test with a minimal query (< 5 tokens)

If the problem recurs:
- Reduce context length (e.g., from 32768 to 8192)
- Check if other GPU-intensive apps are running (browser tabs, Figma, video editing)
- Try a smaller model (e.g., 7B instead of 9B, or a 3B model)
- Check LM Studio's console logs: View → Toggle Developer Tools → Console

---

## Distinguishing "Busy Processing" from "Stuck JIT Load"

The same symptoms (models list responds, completions timeout) can mean TWO different things. Distinguish before acting.

| Symptom | Stuck JIT Load | Busy Processing |
|---------|---------------|-----------------|
| Models endpoint | Fast (< 1s) | Fast (< 1s) |
| Completions endpoint | Times out (any request) | Times out or slow |
| Worker CPU | Sustained 40-50% for 5+ min | Variable: spikes > 60% during inference |
| Worker CPU pattern | Flat line at ~45% | Pulsing: 70% → 30% → 70% |
| Multiple models in /v1/models | Yes (registry) | Only the loaded one responds |
| User report | "I just started LM Studio" | "It's working on something" |

### What to do when it's Busy Processing

**Do NOT make additional requests.** The model is working through a queue. Each new request adds to the backlog.

1. **Check once, then wait:** Query `/v1/models` once to confirm the server is alive. Then stop — don't keep polling.
2. **Check the worker process:** `ps aux | grep lmstudio | grep llmworker` — if CPU is moderate (30-70%) with variation, it's working.
3. **Send ONE request at a time** with a generous timeout (120-600s). Do not send a second request until the first completes.
4. **Use background mode** (`terminal(background=true, notify_on_complete=true)`) so you can continue working while waiting.
5. **Inspect state between requests:** Check the application's DB or API for results rather than making redundant LLM calls to probe.

### Inspection commands (safe — no side effects)

```bash
# Check if server is alive (fast, doesn't load model)
curl -s --max-time 3 http://127.0.0.1:1234/v1/models

# Check worker process health
ps aux | grep lmstudio | grep llmworker

# Check system memory
top -l 1 -n 0 | grep PhysMem
```

### Inspect application state instead of re-pinging LM Studio

When the LLM is processing a queue of requests, making additional curl calls to LM Studio just adds to the backlog. Instead, inspect the **application's own state** to determine progress:

```bash
# Check for queued/pending investigation runs in the application DB
sqlite3 app.db "SELECT id, status, started_at FROM investigation_runs ORDER BY started_at DESC LIMIT 10;"

# Check if new results appeared since your last request
sqlite3 app.db "SELECT id, status, completed_at FROM investigation_runs WHERE status = 'completed' ORDER BY completed_at DESC LIMIT 5;"

# Check if the analysis was saved to the alert record
sqlite3 app.db "SELECT id, agent_analysis IS NOT NULL as has_analysis FROM alerts WHERE id = <alert_id>;"

# Or use the application's own API endpoint
curl -s http://localhost:8080/api/alerts/<id>/investigations
```

These queries produce ZERO load on LM Studio and give you a direct answer about whether work completed. If the number of pending/incomplete runs is > 0, the system is still working — do not send a new LLM request.

## Pitfall: Qwen3.5 (and other thinking) models return empty `content` at low `max_tokens`

Qwen3.5 MLX builds (`qwen3.5-9b-abliterated-mlx`, `qwen3.5-4b-mlx`, etc.) run in persistent thinking mode. They emit their answer in `reasoning_content` and `choices[0].message.content` arrives EMPTY — unless given a realistic token budget. Verified across all three models:

- `max_tokens: 10 / 50 / 150` → empty `content`, answer sits in `reasoning_content` (or cut mid-thought)
- `max_tokens: 4096` (Hermes default) → real `content` returned normally

**Diagnosis:** don't conclude the model is broken from one low-`max_tokens` probe. Re-test with `max_tokens: 512+` before assuming a loader/runtime fault.
**Integration:** Hermes' aux path handles this via `extract_content_or_reasoning` in `agent/auxiliary_client.py` (~line 9341) which falls back to `reasoning_content` when `content` is empty. The 2.6B `lfm2.5-2.6b-mlx` is non-thinking and returns `content` even at low budgets.

## Pitfall: `Failed to load model` for OptiQ / mixed-precision MLX builds

`mlx-community/Qwen3.5-4B-OptiQ-4bit` (and any `optiq_mixed_precision` build) FAILS to load in LM Studio with `Failed to load model`. Root cause: LM Studio's MLX loader only handles uniform affine quant (e.g. plain 4-bit). OptiQ uses a **per-layer 8/4-bit bit map** (in `config.json` `quantization`) plus bundled `mtp.safetensors` (speculative head) and `optiq_vision.safetensors` extra tensors. LM Studio lists the model in `/v1/models` but its loader rejects the per-layer map.

**Verdict:** OptiQ/optiq-mixed-precision builds are NOT usable through LM Studio's server. They need the separate `mlx-optiq` runtime (`optiq serve --mtp`) on a side port, wired as a custom provider with its own `base_url`.

## Pitfalls

- `/v1/models` responding does NOT mean the model is loaded — LM Studio registers all available models at startup from its model registry
- Multiple models listed in `/v1/models` doesn't mean they're loaded simultaneously; JIT loading only loads on first inference call
- LM Studio on macOS with Metal can silently hang JIT loading if GPU memory is exhausted by other processes
- The inference worker process at 40-50% CPU is the LLM runtime stuck in a Metal kernel wait — it won't timeout on its own; only a full process restart helps
