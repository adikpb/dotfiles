# Tracing hermes-sweeper policy origins (e.g. `max-tokens-knob`)

When a PR is closed under a *named* sweeper policy and you need to know what the policy actually is, why it exists, and what re-scopes are accepted — trace it to its canonical origin. The policy name is NOT in the repo; it is internal to the sweeper bot's definitions, so the origin lives in GitHub issues/comments.

## General technique (works for any named policy)

1. **Web-search the policy name verbatim** with `site:github.com <owner>/<repo>` (e.g. `"max-tokens-knob" site:github.com NousResearch hermes-agent`). The sweeper repeats the same policy name across many closes — you get the enforcement history in one query.
2. **Find the canonical issue.** Close comments on later items often cite it explicitly (e.g. "Full reasoning (with primary-source citations) on the canonical issue: …/issues/4404"). The canonical issue is the one whose maintainer close comment explains the *design rationale*, not just the rejection.
3. **Read the canonical issue's close comment** — that's the actual policy text. It states what the design intends, why the knob is refused, and — critically — the sanctioned alternative.
4. **Cross-check the sweeper's per-PR close comments** for the consistent alternative phrasing. The sweeper's suggested re-scope is the path that survives review.

## `max-tokens-knob` — the specific origin chain

- **Canonical source: issue #4404** (2026-04-01, "[Bug]: model.max_tokens in config.yaml has no effect"). Maintainer **Teknium** (posts as `teknium1`; also the sweeper account) closed it 2026-04-17 as **"working as intended"** — not a bug.
- **The ruling:** "We intentionally don't send `max_tokens` by default. The design is: let the inference server use its full output budget unless Hermes has a specific per-provider reason to cap it."
- **Primary-source table from the close comment** (what backends do when `max_tokens` is omitted):

  | Backend | Behavior when omitted |
  |---|---|
  | llama.cpp / llama-server | `n_predict = -1` = infinity (until EOS/stop/context exhaustion) |
  | vLLM | `max_model_len − prompt_len` (remaining context) |
  | OpenAI API | dynamic default = remaining context |
  | OpenRouter | model's documented max output (pre-auth quirk handled surgically per-provider) |
  | Qwen Portal | low default → already overridden to 65536 internally |

- **Why a knob is refused:** wiring `model.max_tokens` through every path would cap llama.cpp users (currently unlimited) and truncate reasoning models' thinking blocks. Per-provider quirks are fixed surgically in `run_agent.py:_build_api_kwargs`, never via user config.
- **Sanctioned alternatives** (stated in close comments): fix the concrete truncation behavior without a knob — e.g. remove hardcoded caps entirely (merged #34845 pattern; PR #75253), fix a server/transport default, or change the aux model/provider selection. "Leave response-length selection to the configured auxiliary model/provider rather than adding a per-task max_tokens setting."
- **Enforcement history** (all `reason=not_planned`, all the same policy): #15037 (per-model `custom_providers.max_tokens`), #28782 (per-provider override), #35578 (`max_tokens_per_turn` RFC), #29259 (`ask_advisor` tool config), #5175 (skill `--max-tokens` tiers), #10924 (PR wiring `model.max_tokens` through CLI/gateway), #15430 and #74945 (our `auxiliary.vision.max_tokens` knob attempts).
- **What survived:** #13902 was cherry-picked onto main via #43336 *before* the policy direction fully landed; #34845 merged because it *omits* the cap rather than exposing it; #75253 merged the removal-of-hardcoded-caps re-scope.

## Re-scope checklist when hit by this policy

1. Delete the knob surface entirely (config read, `hermes config set` entry, `_vmt`-style blocks).
2. Prefer the merged-main pattern over your original idea (for output caps: omit the field; the aux client handles Anthropic mandatory field and Gemini native ceiling).
3. Enumerate the whole bug class across sibling call sites and per-task files — a handoff will under-report.
4. If a sibling site is intentionally lossy (e.g. `web_extract` snapshot summarization stores the full snapshot and returns a pointer), leave it and **flag it as a PR comment** rather than silently widening scope.
5. Comment on the closed PR pointing at the re-scoped one (the close thread is the decision record).
