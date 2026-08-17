# Thinking vs Non-thinking probe (local LM Studio models)

Model *name/size is not a reliable signal* for whether a model thinks. Verify
empirically by checking whether the chat-completions response carries a
non-empty `reasoning_content` field.

## Probe recipe (LM Studio on :1234)

```bash
curl -s -m 90 http://localhost:1234/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"<MODEL_ID>","messages":[{"role":"user","content":"Say the word HELLO and nothing else."}],"max_tokens":60}' \
  -o /tmp/probe.json
python3 - <<'PY'
import json
d = json.load(open("/tmp/probe.json"))
m = d["choices"][0]["message"]
rc = m.get("reasoning_content") or ""
print("thinking:", bool(rc.strip()))
print("content  :", repr(m.get("content","")))
print("finish   :", d["choices"][0].get("finish_reason"))
PY
```

Read:
- `reasoning_content` present + non-empty  -> **THINKING** (answer hidden in the trace; Hermes recovers it via `extract_content_or_reasoning`).
- `reasoning_content` empty, answer in `content`, `finish_reason: stop` -> **NON-THINKING**.

Note: a *thinking* model probed with a tiny `max_tokens` (e.g. 20-60) often
returns `content: ""` with `finish_reason: length` because it burns the budget
reasoning and never reaches the answer. That is NOT a failure — it still proves
the model thinks. Use `max_tokens: 60` and read `reasoning_content`, not `content`.

## Verified local-model thinking status (LM Studio, probed 2026-08)

| Model | Thinking? | Used for (this user's config) |
|-------|:---------:|----------|
| `qwen3.5-4b-mlx` | yes | web_extract, triage_specifier, kanban_decomposer |
| `lfm2.5-2.6b-mlx` | yes | approval (kept thinking on purpose) |
| `lfm2.5-vl-3b-mlx` | no  | vision, title_generation, profile_describer |

Implication for aux slots: `lfm2.5-vl-3b-mlx` is the only non-thinking local
model in this family. When the user wanted thinking OFF for title/profile but
ON for approval, the fix was to move title_generation + profile_describer onto
`lfm2.5-vl-3b-mlx` (a multimodal model that is fully text-capable) and leave
approval on the thinking `lfm2.5-2.6b-mlx` — NOT to toggle thinking per-slot
(see below; that is impossible).

## Per-request thinking toggles are SILENT NO-OPS (verified 2026-08)

You CANNOT disable thinking for a local Qwen3.5 / LFM2.5 model via `hermes config`
or the OpenAI-compatible API. All of the following were probed against a live
`localhost:1234` and STILL returned a full `reasoning_content` trace:

- `reasoning_effort: "none"` (top-level or inside `extra_body`)
- `extra_body: { "chat_template_kwargs": { "enable_thinking": false } }`
- `reasoning: { "enabled": false }`

LM Studio bug tracker issues #1559 and #1990 confirm the OpenAI-compatible REST
translation layer drops the toggle before it reaches the runtime / Jinja
template. So `hermes config set auxiliary.<slot>.reasoning_effort none` does
NOT turn thinking off for these models — never claim it does.

## How to actually get non-thinking output (model-level only)

Thinking is a property of the **model identity**, not the request. Two working paths:

1. **Non-thinking virtual model via `model.yaml`** (cleanest, scoped to a new ID).
   Create an empty model directory, drop a `model.yaml` that points `base` at the
   real weights and bakes the toggle into the Jinja template:

   ```yaml
   model: qwen/Qwen3.5-4B-MLX-nothink
   base:
     - key: <original-model-key>   # e.g. qwen3.5-4b-mlx as LM Studio knows it
   customFields:
     - key: enableThinking
       displayName: Enable Thinking
       type: boolean
       defaultValue: false
       effects:
         - type: setJinjaVariable
           variable: enable_thinking
   metadataOverrides:
     paramsStrings:
       - 4B
   ```

   Reload the model in LM Studio; it appears under the new name with thinking off.
   Then assign the aux slot to that virtual model ID. This keeps the thinking
   model available under its original ID for slots that want reasoning.

2. **Edit the Jinja template directly** — add `{%- set enable_thinking = false %}`
   at the top of the model's chat template in LM Studio and reload. Nuclear: kills
   thinking for EVERY use of that model, including any future thinking-on need.
   Avoid unless no other use of the model needs reasoning.

**Per-slot / per-model split rule:** if slots sharing one model need different
thinking states, you MUST split them across model identities (thinking model vs
non-thinking virtual model). A single `lfm2.5-2.6b-mlx` instance cannot serve
one slot thinking and another non-thinking.
