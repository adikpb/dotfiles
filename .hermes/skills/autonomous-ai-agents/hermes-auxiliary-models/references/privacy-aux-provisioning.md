# Privacy / Confidential Aux Provisioning

How to satisfy "utmost privacy — no training, no data retention" for Hermes aux slots
in a security-conscious environment (e.g. a cybersecurity company).

## The privacy ladder (what "max privacy" actually means)

| Tier | Providers | Who can read your data | Verifiable? |
|------|-----------|------------------------|-------------|
| 1. Local | LM Studio | No one, nothing leaves the machine | Inherent |
| 2. TEE / confidential compute | Chutes, Phala, NEAR AI, Venice (TEE) | No one: even the operator can't read prompts in memory (Intel TDX + NVIDIA confidential GPU) | Hardware attestation per request |
| 3. Zero-retention policy | DeepInfra, Fireworks, Novita, Together | Operator *could*, contractually doesn't | Trust-based |
| 4. Free tier that trains | Google AI Studio, OpenCode Zen free | Provider does read/train inputs | No |

Rule: for strict privacy, NEVER use tier-4 for slots that see raw session/conversation data
(compression, curator, background_review all see your real content). "Free tier trains on
your data" is the disqualifier regardless of model quality.

## TEE providers hosting DeepSeek V4 Flash (verified, 2026-08)

| Provider | Model | In/out per 1M | Notes |
|----------|-------|---------------|-------|
| Chutes | `deepseek-ai/DeepSeek-V4-Flash-0731-TEE` | $0.14 / $0.28 | Cheapest verified TEE; optional E2EE; OpenAI-compatible base_url `https://llm.chutes.ai/v1`; `confidential_compute=true`; no rate-limit ceilings; no subscription |
| Phala | `deepseek/deepseek-v4-flash` | $0.20 / $0.40 | GPU TEE, no-log by construction, signed ACI `x-receipt-id` per response, `zdr=true` filter, base_url `https://inference.phala.com/v1` |
| NEAR AI Cloud | `DeepSeek-V4-Flash` | $0.17 / $0.35 | Intel TDX + H200, on-chain attestation, E2EE option, OpenAI-compatible |
| NanoGPT | deepseek v4-flash | $0.20 / $0.40 | TEE, auto-routing only |
| Confidential.ai | DeepSeek V4-Flash | $0.20 / $0.40 | TEE-backed inference |
| OODA AI | 150+ LLMs | varies | NASDAQ, TDX+H100/H200 GPU TEE, ACI receipt, OpenAI-compatible |

**Venice: DISCONFIG for tier-2 despite its marketing (verified 2026-08 from Venice's own docs).** Two conflicting pages:
- `/docs > pricing` table lists `deepseek-v4-flash-0731` at **$0.17 / $0.35**, tier **Private**.
- Its model page's Limitations says verbatim: *"Does not run inside a TEE or with end-to-end encryption on Venice (private zero-retention tier, but not hardware-isolated)."* — yet the same page advertises "$0.07 / $0.14" and shows TEE/E2EE badges.
Trust the pricing-docs + limitation text: Venice is tier-3 trust-based (zero-retention policy, NO hardware isolation), not tier-2 TEE. General rule: before classifying a privacy provider, cross-check its docs pricing page against its marketing page; a TEE claim that contradicts the provider's own limitation text is not TEE.

Config note: NONE of Chutes/Phala/NEAR/Venice ship a built-in Hermes provider plugin, so they
wire through the `custom` provider (base_url + api_key + model), with the raw key in
`~/.hermes/.env`. Example:

```bash
export CHUTES_API_KEY="cpk_..."   # in ~/.hermes/.env
hermes config set auxiliary.compression.provider custom
hermes config set auxiliary.compression.base_url "https://llm.chutes.ai/v1"
hermes config set auxiliary.compression.api_key "$CHUTES_API_KEY"
hermes config set auxiliary.compression.model "deepseek-ai/DeepSeek-V4-Flash-0731-TEE"
```

Groq and Cloudflare Workers AI also lack built-in plugins, and both have free-tier RATE ceilings
(Groq ~8K TPM/200K TPD on gpt-oss-120b; Cloudflare ~10K neurons/day) that make them unusable
for long-context compression/curator — free tiers gate on rate, and heavy slots blow through
them immediately. Preferred split: paid / TEE for long-context heavy slots (pennies per call,
no rate ceiling); free or local for tiny high-frequency slots.

## Tiering a fully-local or hybrid aux stack (16GB Apple Silicon)

Versioned practical mapping that worked for this user (16GB Mac, LM Studio as `lmstudio`
provider, port 1234). "Heavy" = compression, curator, background_review; "Mid" =
vision, web_extract, triage_specifier, kanban_decomposer; "Tiny" = title, approval,
goal_judge, profile_describer, skills_hub.

Hybrid (heavy on cloud/main, mid+tiny local):
- heavy -> auto (main) OR a TEE custom provider (see above)
- mid (vision/web_extract/triage/kanban) -> `qwen3.5-4b-mlx` (262K ctx, natively multimodal)
- tiny -> `lfm2.5-2.6b-mlx` (leads instruction-following/tool-use benchmarks among small options)

Key praises from the local-model research:
- `lfm2.5-2.6b-mlx` is a KEEP for tiny slots: it beats Gemma 4 E2B/E4B and both Qwen3.5 4B/9B
  on most instruction-following and tool-use benchmarks despite being the smallest/fastest.
- `qwen3.5-9b` (or a TEE frontier model) belongs on HEAVY compression/curator. Independent
  on-device benches show 4B ≈ 9B on general reasoning, BUT a production transcript
  benchmark showed Qwen3.5-4B repetition loops + garbling on 15K-token inputs, and Liquid's
  Antidoom work documents a ~22.9% doom-loop rate under greedy sampling. 9B's wider margin
  matters on long-context. Do not put a 4B on compression.
- If heavy must run locally on the same 16GB Mac as mid+tiny, dropping to 2.6B+4B only (no 9B)
  keeps it light; otherwise the 9B churn competes with everything.

## Local multi-model setup requirements (LM Studio)

- `modelLoadingGuardrails.mode` MUST be `off` in `~/.lmstudio/settings.json` for the
  multi-model JIT swap on a low-RAM Mac. `mode: high` + `alwaysAllowLoadAnyway: true` is
  ignored by the API and blocks swaps (macOS reads ~3GB hw.physmem). Back up settings.json
  before editing.
- Starting LM Studio API server: `lms server start` brings up port 1234. If a fresh model
  download doesn't appear in `/v1/models`, the in-app server may have stopped; restart it.
- Get models via `lms get <FULL huggingface.co/org/repo URL>` — bare names fail
  (lowercased + hub-resolved). Models land under `~/.lmstudio/models/`.
- Verify a model actually LOADS in LM Studio before wiring slots to it (see OptiQ pitfall in
  SKILL.md). The `custom`/LM Studio provider can only serve models the running server lists
  in `/v1/models` — cross-check the exact servable id (often a short slug, e.g. `qwen3.5-4b-optiq`).