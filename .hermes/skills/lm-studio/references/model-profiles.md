# Verified model profiles (measured on a 16 GB Apple Silicon Mac)

## Bonsai-27B Q1_0 (1-bit, prism-ml), LM Studio, verified 2026-08-03

Hardware: 16 GB unified-memory Apple Silicon Mac.

Model files (in `~/.lmstudio/models/lmstudio-community/Bonsai-27B-GGUF/`):
- `Bonsai-27B-Q1_0.gguf` (3.5 GB, binary {−1,+1} weights, ~1.125 bpw, Q1_0_g128)
- `mmproj-Bonsai-27B-BF16.gguf` (888 MB vision tower, lazy-loaded only on image input)

Key facts:
- Hybrid SSM+attention arch (from GGUF meta via `uvx --from gguf gguf-dump`):
  64 layers, `full_attention_interval = 4` -> only 16 layers carry KV caches,
  48 are SSM layers (state ~0.4 MB total, context-independent). KV heads 4,
  head_dim 256 -> KV = 2*16*4*256 = 32,768 elems/token -> 18 KiB/token at q4_0.
  Max context 262144. `rope.dimension_sections = [11,11,10,0]`.
- Q1_0 is fully merged in mainline llama.cpp, so LM Studio's bundled runtime runs it
  natively (tested on bundled llama.cpp 2.27.1). Do NOT use the ternary Q2_0 group-128
  GGUFs or MLX 1-bit pack with stock runtimes: both need the PrismML fork
  (mlx#3161 pending). GGUF is also smaller than MLX (3.53 vs 3.92 GiB).
- Memory (measured): 4.96 GB RSS @ 8K, 5.95 GB @ 64K, 7.08 GB @ 128K (KV 2.25 GiB;
  +1.13 GiB per 64K step, matches the 18 KiB/token math), parallel 1, q4_0 KV,
  full Metal offload. README table: 4.8 GiB @ 4K, 5.2 @ 10K, 10.8 @ 100K
  (FP16 KV 64 KiB/token).
- Default LM Studio load uses `--parallel 4`: each slot reserves its own full KV
  cache, so set numParallelSessions 1 (verified drop 5.20 -> 4.96 GB RSS).
- KV cache quant defaults to q4_0 for this model ("near-lossless" per model card).

Verified load command:
```bash
lms load prism-ml/bonsai-27b --gpu max --context-length 131072 --parallel 1 --identifier bonsai-27b -y
```

Persistent per-model settings file (survives restarts, applies to GUI loads):
`~/.lmstudio/.internal/user-concrete-model-default-config/prism-ml/bonsai-27b.json`
Fields used: `llm.load.contextLength` (131072), `llm.load.numParallelSessions` (1),
`llm.load.llama.kCacheQuantizationType` / `vCacheQuantizationType` (q4_0),
`llm.load.llama.acceleration.offloadRatio` ("max").
The app only rewrites this file when settings change in the GUI, so direct edits
are safe; verify with a bare `lms load` + `lms ps` (shows CONTEXT/PARALLEL).
`schema` keys discovered: contextLength, numParallelSessions, seed,
llama.kCacheQuantizationType, llama.vCacheQuantizationType, mlx.kvCacheQuantization,
llama.acceleration.offloadRatio.
GPU offload gotcha (verified): the GUI labels the setting "GPU Offload"
(locale key `llm.load.llama.gpuOffload`) but the STORAGE key is
`llm.load.llama.acceleration.offloadRatio`, value = "max" | "off" | number 0..1
(-ngl = round(ratio x n_layers); verified 0.5 -> --n-gpu-layers 33 on 64 layers).
Default when unset is "auto" -> app computes a ratio per load (showed 43% for
Bonsai at 128K on this 16 GB Mac, which would leave ~21 layers on CPU). Pin
"max" in the config so GUI and CLI both use full offload (--n-gpu-layers 999999).
KV quant + parallel cannot both be set via CLI/REST (known LM Studio bug) — GUI/SDK
or direct config-file edit instead.
Guardrail note: loading Bonsai while the 9B is resident is BLOCKED (estimate 5.26 GB
@ 64K + 9B + macOS > 16 GB); unload the other model first (lms unload) or the load
fails even with guardrails on "low".

Inference gotchas:
- It is a heavy thinker: ~190-200 reasoning tokens even for trivial prompts at
  default effort. With max_tokens < ~250 you get an EMPTY reply (budget eaten by
  thinking). Via API use `"reasoning_effort": "none"|"low"|"medium"|"high"` (tested:
  "none" -> instant reply, 0 reasoning tokens; works on /v1/chat/completions).
- Thinking is capped by LM Studio per-model default only if you set it in GUI
  (Inference > Reasoning > budget); API reasoning_effort overrides per request.

Quality note: Q1_0 is the footprint variant. Ternary-Bonsai-27B Q2_0 (~6.7 GB,
~7.8 GiB peak) is the quality variant and fits this 16 GB Mac, but needs the
Bonsai-demo fork binaries, not LM Studio.

## qwen3.5-9b-abliterated-mlx (9B, MLX 4-bit, lukey03), verified 2026-08-03

Installed: `~/.lmstudio/models/lukey03/Qwen3.5-9B-abliterated-MLX-4bit` (4.7 GB on disk).
Same Mac (M4, 16 GB). Arch from config.json: 32 layers, 4 KV heads, head_dim 256,
hidden 4096, max_position_embeddings 262144, all 32 layers full attention ->
65,536 KV elems/token -> 128 KiB/token bf16, ~34 KiB/token 4-bit group 128.

- Also a heavy thinker (~199 reasoning tokens on trivial prompts at default effort);
  API `reasoning_effort: "none"` gives instant replies (tested).
- Memory (measured): 8K ctx ~4.7 GiB (system ~11 GB used); 64K ctx (current)
  ~7.1 GiB model, system ~15 GB used, 569 MB free, no swap, heavy compression.
  lms SIZE label stays 5.06 GB (disk), CONTEXT column is the real signal.
- Guardrails BLOCK bare cross-loads: any model load is estimated while the other is
  resident and fails ("insufficient system resources"). Run one big model at a time;
  unload first (lms unload), or rely on the app's auto-unload of the previous JIT
  model only when a load would fit the budget.
- MLX has no GPU-offload/flash-attention knobs; KV quant is `mlx.kvCacheQuantization`
  {bits 4, groupSize 128, quantizedStart 0} (final, applied 2026-08-03).
  quantizedStart 0 = quantized from the first token: leanest possible (KV max
  ~306 MB at 8K with group 128, no full-precision phase, no transition cliff).
  It matches the model's original behavior (was group 32, start 0); group 32
  costs +54 MB at 8K (verified formula: bytes/elem = bits/8 + 4/group_size,
  bf16 scales+bias per group per mlx.core.quantize docs; group 64 = ~324 MB).
  Full precision is ~144 KiB/token.
  CORRECT quantizedStart semantics (verified in mlx-lm source, generate.py/cache.py):
  "start quantizing the KV cache from this step onwards". Cache is full precision
  until offset reaches the start, then to_quantized() converts the ENTIRE cache
  (early tokens included). It does NOT keep recent context full precision.
  Memory math (9B, ~144 KiB/token FP16, ~34 KiB/token 4-bit group 128,
  ~40 KiB/token 4-bit group 32): at 8K group 128 = 306 MB KV vs group 32 = 360 MB;
  at 64K group 128 = 2.13 GiB KV (KV dominates at 64K: 4.5 GiB weights + 2.13 KV).
  mlx-lm's own server defaults quantizedStart to 5000 (their quality choice).
- max_tokens trap confirmed on this model too: empty content at max_tokens 100-200
  even with reasoning_effort "none" (still burns ~130 reasoning tokens); needs 250+.

Persistent config: `~/.lmstudio/.internal/user-concrete-model-default-config/lukey03/Qwen3.5-9B-abliterated-MLX-4bit.json`
(contextLength 65536, numParallelSessions 1, mlx.kvCacheQuantization 4-bit group 128
start 0). Verified via bare `lms load qwen3.5-9b-abliterated-mlx -y` -> CONTEXT 65536,
PARALLEL 1.
Also on disk but NOT installed: huihui-ai/Huihui-Qwen3.5-9B-abliterated-mlx-4bit
config; do not confuse the two.

Model max contexts: BOTH models support 262144 (256K). Feasibility on 16 GB:
Bonsai 64K = 5.95 GB RSS (comfortable), 128K = 7.08 GB RSS (current, works,
system ~15/16 GB, no swap), 256K ~9.3 GB (no; guardrail blocks at ~17 GB demand).
9B 64K = ~7.1 GiB (tight, ~15 GB system), 128K ~9.7 GiB (no), 256K ~13.5 GiB (no).
The MLX/llama.cpp estimator does NOT scale with --context-length (flat output);
trust the per-token math instead.

See debug-lm-studio-model-load skill for the JIT-hang trap.
