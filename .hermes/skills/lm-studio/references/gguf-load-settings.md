# GGUF (llama.cpp) load settings reference, with MLX applicability

Source: LM Studio SDK schema (LLMLoadModelConfig, lmstudio-js), REST load docs,
and per-model config files observed on this machine
(`~/.lmstudio/.internal/user-concrete-model-default-config/*/`).

Engine selection: LM Studio picks the engine per model format (.gguf -> llama.cpp,
MLX safetensors -> MLX). Per-model config files store engine-specific keys; the
app only writes the keys valid for that model's engine.

Legend: llama.cpp = GGUF only, BOTH = both engines, MLX = MLX only.

## Load settings

| Setting | Config key (llm.load.*) | Engine | Memory impact |
|---|---|---|---|
| Context Length | contextLength | BOTH | Huge. KV grows ~linearly with window. llama.cpp q4_0 KV ~18 KiB/token, FP16 64 KiB/token; MLX KV scales with bits/groupSize |
| K Cache Quantization | llama.kCacheQuantizationType (f32/f16/q8_0/q4_0/q4_1/iq4_nl/q5_0/q5_1) | llama.cpp | Huge. q8_0 halves FP16, q4_0 quarters. V-quant requires Flash Attention |
| V Cache Quantization | llama.vCacheQuantizationType (same options) | llama.cpp | Huge (same as K). Requires Flash Attention |
| KV Cache Quantization | mlx.kvCacheQuantization {enabled, bits 2-8, groupSize 32/64/128, quantizedStart} | MLX | Huge. bits=8 ~half of bf16, bits=4 ~quarter. MLX defaults to bf16 cache |
| useFp16ForKVCache (legacy toggle) | useFp16ForKVCache | llama.cpp | Medium. Superseded by the quant types above |
| Max Concurrent Predictions | numParallelSessions / maxParallelPredictions | BOTH | Medium. Each concurrent slot gets KV space; llama.cpp reserves per slot (unified cache shares), MLX continuous batching (text-only, since 0.4.2). Default 4 in LM Studio; set 1 to minimize |
| Unified KV Cache | useUnifiedKvCache | llama.cpp | Medium. Slots share one KV pool (flag --kv-unified); on by default |
| Flash Attention | flashAttention | llama.cpp | Medium. ~20-30% less attention memory, faster; required for V-cache quant. MLX uses its own SDPA kernels, no toggle |
| GPU Offload | gpu.ratio (off/max/0-1) | llama.cpp (MLX auto-manages unified memory, no layer offload knob) | Low on Mac unified memory (weights in same 16 GB pool either way; speed only). Big on discrete GPUs: VRAM vs RAM split |
| Offload KV Cache to GPU | offloadKVCacheToGpu | llama.cpp | Low on Mac (same pool). Matters on discrete GPUs |
| Keep Model in Memory | keepModelInMemory (--mlock) | llama.cpp (evidenced); concept applies to MLX too | Low-Medium. Locks weights in RAM, prevents swap-out; commits weights-size RAM |
| Memory Mapping | tryMmap | llama.cpp (GGUF mmap; MLX loads safetensors its own way) | Low. Lazy page-in, OS can evict, lower baseline RSS |
| Direct I/O | tryDirectIO (O_DIRECT) | llama.cpp | Negligible. Bypasses page cache; usually slower loads |
| Eval Batch Size | evalBatchSize | llama.cpp (REST docs: llama.cpp engine only) | Low. Compute buffer; bigger = faster prefill, more RAM |
| Context Checkpoints | contextCheckpoints (--ctx-checkpoints) | llama.cpp | Low. Extra KV checkpoints for fast context shift; off by default |
| Speculative Decoding | speculativeDraftMtp / speculativeDraftSimple + speculativeDraftModel | llama.cpp | Medium-High. Loads a whole draft model (weights + KV); keep off for memory |
| numExperts (MoE) | numExperts | llama.cpp | Only for MoE models (Bonsai is dense, N/A) |
| RoPE base/scale | ropeFrequencyBase / ropeFrequencyScale | llama.cpp (MLX reads rope_theta from model config) | None |
| Seed | seed | BOTH | None |
| GPU Strict VRAM Cap | gpuStrictVramCap | llama.cpp guardrail | None (changes offload behavior only) |

## Inference (operation) settings

| Setting | Config key (llm.prediction.*) | Engine | Memory impact |
|---|---|---|---|
| Reasoning budget / effort | reasoning.budgetTokens {checked, value} | BOTH | Indirect. Thinking tokens grow the sequence -> KV grows during long chains. Bonsai-27B burns ~190-200 reasoning tokens on trivial prompts at default effort; API reasoning_effort "none"/"low" bypasses |
| Max tokens (per reply) | maxTokens | BOTH | Indirect. Caps KV growth per reply. Bonsai-27B returns EMPTY below ~250 max_tokens (budget eaten by thinking) |
| Temperature, top-p, top-k, min-p, penalties | temperature, topPSampling, topKSampling, ... | BOTH | None |

## Official docs (verified 2026-08-03)

- Per-model defaults (the mechanism behind the config files): https://lmstudio.ai/docs/app/advanced/per-model
  "When the model is loaded anywhere in the app (including through lms load) these
  settings will be used." Supported GUI flow: My Models tab -> gear icon -> set
  default parameters; you can also save current load settings as the model default.
  Parallel Requests (continuous batching) is listed as a per-model default.
  The internal JSON paths are NOT documented; the gear dialog is the supported way.
  Direct edits work (verified via bare lms load) but could be affected by app
  version changes; prefer the GUI for durable changes.
- lms load flags: https://lmstudio.ai/docs/cli/local-models/load
  Documented: --context-length, --gpu (0-1/off/max), --ttl, --identifier,
  --estimate-only. NOTE: --parallel is NOT documented (works in practice).
- Server settings (JIT, auto-unload, keep-last): https://lmstudio.ai/docs/developer/core/server/settings
  Maps to settings.json switches jitEnabled, jitAutoUnload, unloadPreviousJITModelOnLoad.
- REST load API: https://lmstudio.ai/docs/developer/rest/load
  Only context_length, eval_batch_size, flash_attention, num_experts,
  offload_kv_cache_to_gpu. KV quant types and parallel are NOT in REST
  (GUI/SDK/config-file only). echo_load_config=true returns the applied config.

## Where settings live

Per-model: `~/.lmstudio/.internal/user-concrete-model-default-config/<org>/<model>.json`
(verified keys on this machine: GGUF models use contextLength, numParallelSessions,
llama.k/vCacheQuantizationType; MLX models use contextLength, numParallelSessions,
seed, mlx.kvCacheQuantization). The app rewrites the file only when settings change
in the GUI, so direct edits are safe; verify with bare `lms load` + `lms ps`.
KV quant + parallel cannot both be set via CLI/REST (known LM Studio bug):
GUI/SDK or direct config-file edit instead.

Server-level (memory lifecycle, not per-model): JIT TTL (auto-unload after idle),
unload previous model on load, Model Loading Guardrails (blocks loads, no memory
change). App globals in ~/.lmstudio/settings.json (defaultContextLength etc.).
