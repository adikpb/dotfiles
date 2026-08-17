# Auxiliary Model Slots — Authoritative Reference

Verified against live source `hermes_cli/config_defaults.py` (`auxiliary:` block) and
`agent/auxiliary_client.py` on repo `main` (NousResearch/hermes-agent), 2026-08.
This corrects the older "~20 slots" prose in SKILL.md — the real count is **18**.

## Slot-count reconciliation
- The dashboard / docs surface **11** task slots ("Show auxiliary").
- `config_defaults.py` actually defines **18** configurable slots.
- The extra 7 are feature-gated or largely inert (MoA, honcho memory, mail-monitor cron, TTS tags).
- `session_search` was **removed** (PR #27590): now DB-backed FTS5, no aux LLM. Leftover
  `auxiliary.session_search.*` in `config.yaml` is harmless and ignored.

## The 18 slots (line numbers are in `config_defaults.py`)

| Slot | Purpose | timeout (s) | reasoning_effort | Status / override guidance |
|------|---------|-------------|------------------|----------------------------|
| vision (929) | Image + browser screenshot analysis | 120 | yes | Override if main model lacks vision; needs multimodal model + `download_timeout` |
| web_extract (939) | Web page summarization | 360 | yes | High priority; raise timeout for local models |
| compression (948) | Context summarization | 120 | yes | Enforces `MINIMUM_CONTEXT_LENGTH`; needs long context, no reasoning tokens |
| skills_hub (961) | `hermes skills search` matching | 30 | yes | Fine at `auto` (Low priority) |
| approval (970) | Smart command-approval scoring | 30 | yes | Cheap/fast model (haiku/flash/gpt-5-mini) |
| mcp (979) | MCP tool routing | 30 | yes | Inert — MCP calls hit servers, not the model |
| title_generation (988) | Session title gen | 30 | yes | `prefer_fast_model` opt-in; High priority; tiny fast model ideal |
| memory_query_rewrite (1000) | Rewrite query for honcho backend | 8 | no | Dormant unless `memory.provider` set to external honcho |
| tts_audio_tags (1008) | TTS audio tags | 30 | yes | Inert in current code |
| triage_specifier (1022) | Kanban: one-liner → spec | 120 | yes | Cheap capable model (gemini-flash) |
| kanban_decomposer (1036) | Kanban: task-graph decomposition | 180 | yes | More tokens than specifier; allow headroom |
| profile_describer (1049) | Auto profile descriptions | 60 | yes | Short cheap call |
| goal_judge (1061) | `/goal` continuation verdict | 60 | yes | ~200-tok structured JSON; cheap model fine |
| curator (1075) | Skill-usage review pass | 600 | yes | Can run minutes on reasoning models; cheaper aux worthwhile |
| monitor (1090) | Mail-monitor urgency classifier | 60 | yes | Cron-only (`cron/scripts/classify_items.py`); cheap model fine |
| background_review (1110) | Post-turn memory/skill fork | 120 | yes | `auto`=main model (warm cache, full replay); different model=digest replay |
| moa_reference (1119) | MoA reference advisor | 900 | no (preset-driven) | Dormant unless MoA preset `enabled:true` |
| moa_aggregator (1131) | MoA aggregator | 900 | no (preset-driven) | Dormant unless MoA enabled; config-only even then |

## Notes
- `flush_memories` is a real aux *consumer* (compression/flush/MoA in `auxiliary_client.py`)
  but has **no dedicated config slot** — it routes via the main model. Do not configure it.
- Every slot: `provider: auto` / `model: ""` = use main model, then task `fallback_chain` →
  main `fallback_providers`/`fallback_model` → built-in discovery (main → OpenRouter → Nous
  Portal → custom endpoint → native Anthropic → direct API-key providers).
- `compression` enforces a minimum context length (resolver ~`auxiliary_client.py:5390`) — pick a
  long-context model; small local models mangle heavy summaries.
- Source of truth: `https://raw.githubusercontent.com/NousResearch/hermes-agent/main/hermes_cli/config_defaults.py`
  (search for `"auxiliary":`). Routing/fallback logic: `agent/auxiliary_client.py`.
