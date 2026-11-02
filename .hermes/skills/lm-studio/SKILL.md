---
name: lm-studio
version: 1.0.0
description: Use when running local models via LM Studio.
category: software-development
---

# LM Studio Local Models

Run models under ~/.lmstudio/models/<publisher>/<repo>/ and verify behavior against the live server, never from docs alone.

## Procedure

1. Inspect the template first: tail chat_template.jinja and confirm the enable_thinking block exists before claiming a toggle.
2. Test live via OpenAI-compat API: POST /v1/chat/completions and read completion_tokens_details.reasoning_tokens. 0 means NoThink, nonzero means Think.
3. Try flags in order: chat_template_kwargs.enable_thinking false, then reasoning_effort none. Treat both as untrusted until reasoning_tokens proves them.
4. Use assistant prefill with an empty think block as the API fallback when flags are ignored.
5. For GUI use build a NoThink variant: new folder with symlinked weights plus one rewritten chat_template.jinja, then rescan with lms ls.
6. Route auxiliaries by need: fast literal slots to NoThink, planning slots to Think, vision stays on a VL model.

## Pitfalls

- Verify reasoning off via reasoning_tokens count, never via empty content alone, because Think responses can put the full trace in reasoning_content with empty content.
- Exclude dotfiles when symlinking a variant folder: link only model, tokenizer, config, and README files, because .cache and .gitattributes symlinks hide the variant from lms ls.
- Expect LM Studio to silently ignore thinking flags on some MLX builds, because the server layer does not always propagate them to the MLX runtime; a live 58-vs-0 token test settles it.
- Keep GUI and API paths separate: GUI chat cannot append an assistant prefill turn, so variants are the only GUI off switch while prefill suffices for HTTP.
- Never unload the user active model for a test: probe the target model id directly via /v1/chat/completions, which serves without changing lms ps state.
