---
name: hermes-auxiliary-models
description: "Configure Hermes aux model slots with free-tier options."
version: 1.0.0
author: Hermes Agent
category: autonomous-ai-agents
platforms: [macos, linux, windows]
metadata:
  hermes:
    tags: [hermes, configuration, models, auxiliary, gemini, providers]
---

# Hermes Auxiliary Models

How to configure Hermes' auxiliary model slots for side-jobs (vision, compression, title gen, approval, etc.).

## The Slots

Hermes defines **18** configurable aux slots — the dashboard surfaces 11, the other 7 are feature-gated or inert (MoA, honcho memory, mail-monitor cron, TTS tags). ~10 need active attention (see table). Authoritative enumeration with per-slot `timeout`/`reasoning_effort`/dormancy from `config_defaults.py`: **`references/slot-reference.md`**.

| Slot | What it does | Override priority |
|------|-------------|:-----------------:|
| **vision** | Image analysis + browser screenshots | **High** — main model likely lacks vision |
| **title_generation** | Auto-generating session titles | **High** — docs say "almost always" override |
| **compression** | Context summarization | **High** — don't burn reasoning tokens |
| **approval** | Smart command approval scoring | **High** — docs recommend cheap model |
| **web_extract** | Web page summarization | **High** — summarization doesn't need reasoning |
| **curator** | Skill-usage review pass | **High** — runs for minutes, cheap model worthwhile |
| **triage_specifier** | Kanban: expand one-liner to spec | **Medium** — cheap capable model |
| **kanban_decomposer** | Kanban: task decomposition | **Medium** — cheap capable model |
| **profile_describer** | Auto-generate profile descriptions | **Medium** — short cheap call |
| **goal_judge** | `/goal` continuation verdict | **Medium** — ~200 tokens/turn, cheap model recommended |
| **skills_hub** | Skills search/install matching | **Low** — docs say "fine at auto" |
| **mcp** | MCP tool routing | **Low** — docs say "fine at auto" |
| **session_search** | Past-conversation recall | **Removed** — DB-backed FTS5, no aux LLM needed |
| `background_review` | Post-turn memory/skill self-improvement | **High** — runs after turns, saves main-model tokens |

### Key Trade-offs: Local vs Cloud for Aux Slots
- **Text Aux Slots (Compression, Title Gen, Approval, etc.)**: Cloud models (Gemini free tier) are vastly superior for long-context compression and reasoning-heavy auxiliary judgment. Local models (like LFM 2.6B) struggle with long-context compression fidelity and burn reasoning tokens inefficiently on small tasks. However, for strict security/privacy environments (e.g. cybersecurity contexts) where zero data retention, no training, and provable isolation are mandated, cloud free tiers that train on user prompts (like direct Gemini free) must be avoided in favor of **Trusted Execution Environment (TEE) confidential inference providers** (such as Chutes, Phala, or NEAR AI running DeepSeek V4 Flash TEE with hardware attestation) or local LM Studio models.
- **Vision Aux Slot**: An ideal candidate for hybrid local execution using current-gen MLX VLMs in LM Studio (such as `Qwen3.5-4B-MLX-4bit` at ~3.03GB or `Qwen3.5-2B-MLX-4bit` at ~1.72GB). Qwen3.5-4B is natively multimodal (early fusion), features 262K context, and leads general perception benchmarks (MMMU 77.6, RealWorldQA 79.5) over sub-4B models while cutting memory footprint by ~1.7GB compared to larger 27B+ models, making it ideal for privacy-sensitive local general scene and UI understanding. When configuring thinking models like Qwen3.5 for aux vision, note that reasoning tokens contribute to latency (~20s/call) but produce high accuracy; configure Hermes' `max_tokens: 2000` and use `extract_content_or_reasoning` for reliable content extraction.

### Free-tier options (in order of capability)

| Model | Provider | Free tier? | Vision? | Best for |
|-------|----------|:---------:|:-------:|----------|
| `gemini-3.6-flash` | Google Gemini API (gemini) | ✅ Free | ✅ | Vision, quality-sensitive text (replaces deprecated gemini-2.5-flash) |
| `gemini-3.5-flash` | Google Gemini API | ✅ Free | ✅ | General-purpose text (May 2026 release) |
| `gemini-3.5-flash-lite` | Google Gemini API | ✅ Free | ✅ | Classification, summarization |
| `gemini-3.1-flash-lite` | Google Gemini API | ✅ Free | ✅ | Tiny tasks (titles, descriptions) — shuts down May 7, 2027 |

**Important:** `gemini-2.5-flash` is **deprecated** (shutdown Oct 16, 2026). Replace with `gemini-3.6-flash`. Always check [Google's deprecations page](https://ai.google.dev/gemini-api/docs/deprecations) before recommending.

### Tiered assignment pattern (cost-quality balance)

```
Tier 1 (gemini-3.6-flash)    → vision          # best multimodal understanding
Tier 2 (gemini-3.5-flash-lite) → approval, web_extract, compression, 
                                  curator, triage_specifier, 
                                  kanban_decomposer, goal_judge,
                                  background_review, skills_hub,
                                  title_generation, profile_describer
auto (main model)             → mcp, memory_query_rewrite,
                                flush_memories, tts_audio_tags, 
                                monitor,
                                moa_reference, moa_aggregator
removed                       → session_search
```

### Which "auto" slots actually reach the main model (verified by source trace, 2026-08)

`provider: auto` genuinely resolves to the main model (auxiliary_client `_resolve_auto`), so ANY auto slot that fires sends data to main. But NOT every auto slot fires:

| Slot | Reads main model? | Condition |
|------|------------------|-----------|
| compression | ✅ ACTIVE | context hits `threshold` (default 0.5) |
| background_review | ✅ ACTIVE | every ~10 tool-iterations (`skill_nudge_interval:10`) |
| curator | ✅ ACTIVE (weekly) | `curator.enabled:true`, `interval_hours:168` |
| memory_query_rewrite | ⚠️ DORMANT | only if an external honcho memory backend is active (`memory.provider` != '') |
| moa_reference / moa_aggregator | ⚠️ DORMANT | only if the MoA preset `enabled:true` (default `false`); aggregator is config-only even then |
| mcp | ⚠️ INERT | read only in `config_defaults.py`; MCP calls go to servers, not the model |
| tts_audio_tags | ⚠️ INERT | nothing in the agent reads it |
| monitor | ⚠️ CRON-ONLY | consumed by `cron/scripts/classify_items.py`, not the live agent |

To reduce main-model aux spend / data exposure, the real levers are **compression**, **background_review**, and **curator** — the rest are dormant or inert and touching them changes nothing. Dormant slots become live only if you enable the feature (MoA, honcho, a monitor cron).

### Pitfalls

- **Do not blanket-set all slots to the same model** — it's overkill for tiny tasks (titles, approvals). Use tiered assignment.
- **Verify the slot list against live source, not the dashboard.** The dashboard shows 11 slots but `config_defaults.py` defines 18 (the rest are MoA / honcho / monitor-cron / TTS-tag slots). Full authoritative enumeration with config defaults and `reasoning_effort` support: `references/slot-reference.md`. Always load the `hermes-agent` skill first, then confirm slot facts against `hermes_cli/config_defaults.py` on repo `main` — skill prose can lag the source (this skill's earlier "~20 slots" count was one such lag).
- **Do not recommend `gemini-2.5-flash`** — shutting down October 16, 2026. Use `gemini-3.6-flash` instead.
- **`gemini-3.1-flash-lite`** has a shutdown date of **May 7, 2027**; plan migration to `gemini-3.5-flash-lite`.
- **`gemini-2.5-flash-lite`** also shuts down October 16, 2026 — replace with `gemini-3.5-flash-lite`.
- **`gemini-2.0-flash`** already shut down June 1, 2026.
- **session_search no longer uses an aux LLM** — PR #27590 made it DB-backed (FTS5). Don't configure it.
- **Thinking/Reasoning aux models (Qwen3.5, DeepSeek, LFM2.5) return the answer in `reasoning_content` and leave `content` empty.** Hermes aux slots feed responses through `extract_content_or_reasoning` (agent/auxiliary_client.py), which falls back to `reasoning`/`reasoning_content`/`reasoning_details`, so content is recovered automatically in real calls. BUT a smoke-test with a low `max_tokens` (e.g. 50-150) will look like "empty content / broke" because the model burns the whole budget reasoning and never reaches the answer. Always smoke-test thinking models with `max_tokens` >= the slot default (4096) and read `reasoning_len` + `finish_reason` too.
- **Do NOT assume a small LFM/Qwen model is non-thinking — verify empirically.** Model *name/size is not a reliable signal.* Counter-example: `lfm2.5-2.6b-mlx` (only 2.6B) IS a thinking model (emits `reasoning_content`); among the local LFM2.5 builds only `lfm2.5-vl-3b-mlx` is non-thinking. A thinking model on `approval` adds a reasoning pass to *every* terminal command — wrong pick for per-command scoring if you want zero overhead (use the non-thinking `lfm2.5-vl-3b-mlx` there). Probe any candidate with `references/thinking-model-probe.md` (curl LM Studio `/v1/chat/completions`, check whether `reasoning_content` is present + non-empty) BEFORE assigning it to a latency-sensitive slot. Verified local-model thinking table is in that reference.
- **Per-request thinking toggles are SILENT NO-OPS on LM Studio's REST layer (verified 2026-08).** You CANNOT turn thinking off for a local Qwen3.5/LFM2.5 model via `hermes config` or the API. All of these were probed against a live `localhost:1234` and STILL returned a full `reasoning_content` trace: `reasoning_effort: "none"` (top-level or in `extra_body`), `extra_body: { "chat_template_kwargs": { "enable_thinking": false } }`, and `reasoning: { "enabled": false }`. LM Studio bug tracker #1559 / #1990 confirm the OpenAI-compatible REST translation drops the toggle before it reaches the runtime. So `hermes config set auxiliary.<slot>.reasoning_effort none` does NOT disable thinking for these models — never claim it does. To actually get non-thinking output you must change it at the **model level** in LM Studio (global to that model identity): create a non-thinking *virtual model* via `model.yaml` (`customFields`/`metadataOverrides` baking `enable_thinking = false` into the Jinja template) and point the slot at that virtual model's ID, or edit the model's Jinja template directly (`{%- set enable_thinking = false %}`) and reload. Full recipe + the shared-model caveat in `references/thinking-model-probe.md`.
- **Thinking can only be toggled per MODEL, not per SLOT.** If slots sharing one model need different thinking states (e.g. `approval` wants thinking; `title_generation`/`profile_describer` want it off), split them across model identities: put thinking-wanted slots on the thinking model and thinking-unwanted slots on a non-thinking model (the local non-thinking option is `lfm2.5-vl-3b-mlx`). You cannot set one slot thinking and another non-thinking on the same `lfm2.5-2.6b-mlx`.
- **Qwen3.5-4B (and other small thinking models) have a documented doom-loop / repetition risk on long-context inputs.** Liquid AI's Antidoom work reports ~22.9% doom-loop rate under greedy sampling for Qwen3.5-4B. For long-context compression/curator, prefer a bigger local model or a cloud/TEE frontier model; don't drop a 4B onto compression just because it's smaller/faster.
- **`background_review` context is BOUNDED when routed to a different model than main**: `_digest_history` (agent/background_review.py) keeps the recent ~24 messages verbatim and collapses older turns into one digest. Only same-model-as-main replays the FULL conversation. So a local heavy model on background_review is chosen for judgment quality, not context length.
- **mlx-optiq / OptiQ mixed-precision MLX builds (e.g. `mlx-community/Qwen3.5-4B-OptiQ-4bit`) do NOT load in LM Studio.** LM Studio's MLX loader accepts uniform 4-bit affine; per-layer 8/4-bit bitmaps + `mtp.safetensors`/`optiq_vision.safetensors` extra tensors return "Failed to load model". They need the separate `mlx-optiq` runtime (`optiq serve --mtp`) on a side port, then a `custom`-provider base_url pointing elsewhere. For aux parity, stock 4B ≈ 4B-OptiQ on quality anyway; verify a model actually loads in LM Studio before configuring slots to it.
- **Privacy/confidential aux provisioning (TEE providers, local-model tiering, free-tier training traps)** → see `references/privacy-aux-provisioning.md`.
- **Fallback chains are safe on Gemini free tier** — per-task `fallback_chain` entries work, including same-provider entries with a different model: for model-specific failures (timeout, connection, rate limit) only the exact failed (provider, model) pair is skipped, siblings still run.

## Setup Commands

```bash
# Per-slot override:
hermes config set auxiliary.<slot>.provider gemini
hermes config set auxiliary.<slot>.model <model-name>

# Vision needs longer timeouts:
hermes config set auxiliary.vision.timeout 120
hermes config set auxiliary.vision.download_timeout 30
```

## Provider swaps & slot pruning

### Swap a hand-rolled `custom`/custom-provider for the first-class `lmstudio` provider
LM Studio is **first-class** (`provider: lmstudio`) — do NOT use `custom` + `base_url` for it.
`lmstudio` defaults to `http://127.0.0.1:1234/v1` with no auth (set `LM_API_KEY` only if LM
Studio server auth is on). To move every non-auto slot off a local custom provider, rewrite just
the `provider` field; keep `model:`/`base_url:` as-is (empty `base_url` = provider default):

```bash
for slot in vision web_extract approval title_generation triage_specifier kanban_decomposer profile_describer; do
  hermes config set auxiliary.$slot.provider lmstudio
done
```

Before swapping, confirm the model IDs you keep match what LM Studio actually serves
(`curl -s http://localhost:1234/v1/models`). Prove routing with a live probe and keep
`max_tokens` high (see thinking-model note in Pitfalls): the answer lands in `reasoning_content`
with `content` empty + `finish_reason: length` at low `max_tokens` — that is expected for
Qwen3.5 / LFM2.5, NOT a broken route.

### Remove a slot entirely (revert to built-in default)
`hermes config unset auxiliary.<slot>` deletes the slot block; it then falls back to the
built-in `auto` default. Use this to prune slots the user doesn't want configured (e.g. when
they say "keep only the slots in the docs" and you want to drop `goal_judge`/`background_review`
back to `auto`). **Gotcha:** `hermes config get auxiliary` STILL *prints* pruned slots because it
merges built-in defaults into the output — verify by reading the real `~/.hermes/config.yaml`
(`hermes config path`) to confirm the block is actually gone.

## Per-task fallback chain

Any aux slot can declare a `fallback_chain` (list of provider/model entries) tried on rate-limit / connectivity / payment failure. Same-provider entries with a different model DO work — for model-specific failures (timeout, connection, rate limit) only the exact failed model is skipped, so `gemini-3.6-flash` as fallback for a `gemini-3.5-flash` primary is valid:

```yaml
auxiliary:
  vision:
    provider: gemini
    model: gemini-3.5-flash
    fallback_chain:
      - provider: gemini
        model: gemini-3.6-flash
```

Pitfall: `hermes config set auxiliary.vision.fallback_chain.0.model X` does NOT create a list — it writes a dict `{'0': {...}}` (the CLI navigates existing lists only, never grows them), and the chain parser ignores non-list values. To create the chain, write the YAML list directly (or via a small script using `atomic_yaml_write`), then verify with `hermes config get auxiliary.vision`.

## Rotation strategies for multi-key pools (Gemini free tier)

When the provider pool holds several keys (e.g. two Gemini API keys), pick the `credential_pool_strategies.<provider>` value for free-tier quota behavior:

- `fill_first` (default) is the WORST fit for free tier: it piles traffic on key #1 until it 429s, causing constant rate-limit churn, and never exploits the doubled quota.
- `round_robin` is fine when keys are symmetric and always healthy; it alternates blindly regardless of health history.
- `least_used` is best for free-tier keys with per-day caps: a key's request counter freezes during its cooldown, so when it recovers it has the lower count and automatically carries more load until counts even out (fresh-quota prioritization).

Set with: `hermes config set credential_pool_strategies.gemini least_used`.

Caveat: pool exhaustion is tracked PER KEY, not per (key, model) — and Gemini rate limits are per-model (RPM, per-day RPD caps). A 429 on one model (e.g. gemini-3.5-flash-lite from compression) takes the whole key out of rotation for ALL models until `reset_at` (up to 24h for daily caps). Gap analysis + model-scoped fix design: `hermes-source-development` skill, `references/credential-pool-exhaustion.md`.

## Verification

```bash
hermes config get auxiliary | grep -E 'provider:|model:'
```
