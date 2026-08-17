---
name: hermes-source-development
description: "Use when patching Hermes source (config-driven values, output-cap removal), running its test suite, contributing PRs to NousResearch/hermes-agent (template + sweeper), or building/diagnosing Hermes plugins (surface map, plugin.yaml + register(ctx) contract)."
version: 1.0.0
author: Hermes Agent
related_skills: [github-pr-workflow, hermes-auxiliary-models]
category: software-development
---

# Hermes Source Development

Guide for modifying the Hermes Agent source at `~/.hermes/hermes-agent/` — specifically the pattern of replacing hardcoded values with config-driven settings, running the test suite, and contributing the fix back.

## Diagnose missing or truncated tools

When a tool listed in `platform_toolsets` is missing from the session, or a tool's output is truncated/wrong, do not guess. Almost always: the **toolset filter** excluded it, the per-tool **check_fn** rejected it, or the **check_fn cache** served a stale `False` (30s TTL) that locked the tool out at session creation.

Triage: (1) TUI sessions resolve via `platform_toolsets.cli` — `platform_toolsets.tui` has no effect even when the prompt says `Platform: tui`. (2) Import `tools.registry` and check `registry._entries`. (3) Call the tool's `check_fn` in a fresh Python process. If it returns True now, the cache is the culprit.

Full procedure, truncation limits, and case studies (vision, terminal, TUI, dotenv override, execute_code workaround): `references/diagnose-hermes-tool-availability.md`, `references/vision-tool-truncation.md`, `references/terminal-tool-case-study.md`, `references/tui-full-investigation-case-study.md`, `references/dotenv-override-case-study.md`, `references/execute-code-workaround.md`.

## Plugin architecture (writing or debugging plugins, mapping the surface)

When the task is *building a Hermes plugin*, *explaining the plugin system*, or *diagnosing why a plugin doesn't load*, use `references/hermes-plugin-surface.md` — a verified map of the plugin surface at tag v2026.8.3: the 4 discovery sources (bundled `plugins/`, `~/.hermes/plugins/`, project `./.hermes/plugins/` via `HERMES_ENABLE_PROJECT_PLUGINS`, pip entry-point group `hermes_agent.plugins`), the directory contract (`plugin.yaml` + `__init__.py` with `register(ctx)`), the 5 `kind`s (standalone/backend/exclusive/platform/model-provider) and their loading policy (bundled backends+platforms auto-load, everything else opt-in via `plugins.enabled`), the full `PluginContext` registration surface (tools, slash/CLI commands, 27 `VALID_HOOKS`, 4 middleware kinds, category providers, platforms), and the config keys (`plugins.enabled`/`disabled`/`entries.<id>.allow_tool_override`).

Quick orientation: the engine is `hermes_cli/plugins.py` (~2485 lines) — `PluginManager.discover_and_load()` (:1298) scans the 4 sources, `PluginContext` (:339) is the `register(ctx)` facade, `VALID_HOOKS` at :135, `ENTRY_POINTS_GROUP = "hermes_agent.plugins"` at :217. Install/enable tooling lives in `hermes_cli/plugins_cmd.py` (`.git clone into ~/.hermes/plugins`, writes `plugins.enabled`), argparse table in `hermes_cli/subcommands/plugins.py`. Plugins are **opt-in by default** since config migration v20→21 (`hermes_cli/config_migrations.py:_migrate_to_21`), so a freshly-cloned user plugin must be `hermes plugins enable`d. Two pitfalls from recon: `plugins/kanban/` is NOT a plugin (dashboard/systemd assets, no manifest), and the memory category (`plugins/memory/`) uses its own loader with a fake `ctx` (`register_memory_provider` is not on `PluginContext`). Installer gate: `hermes plugins install` only accepts `manifest_version: 1` (`plugins_cmd.py:_SUPPORTED_MANIFEST_VERSION = 1`) — a plugin declaring a higher manifest version is refused with a "run hermes update" hint. Surface re-verified identical at tag v2026.8.3 across independent recon passes.

**Before trusting that a plugin actually LOADS in the runtime, read `references/hermes-plugin-load-path.md`.** The directory loader imports the plugin as the synthetic `hermes_plugins.<slug>` package and NEVER puts the plugin dir on `sys.path` — a plugin whose root `__init__.py` or internals use top-level absolute self-imports fails SILENTLY (loader records `loaded.error`; `hermes plugins list` still shows it enabled; tools never register; tests and E2E smokes mask it because cwd/repo root sits on `sys.path`). That file has the relative-import fix pattern, the loader-replication verification recipe, the symlink dev-loop (replace the installed clone with a symlink to the dev repo — the loader reads the dev tree live, performs no git ops), and the TUI agent+gateway double-load topology that double-spawns auto-served servers (EADDRINUSE; probe-first attach fixes it).

For the **runtime engine** a bridge must reach — the agent loop and where messages may enter a session, the tool registry (not the plugin loader), the SessionDB schema, skills/cron/gateway internals — see `references/hermes-agent-internals-map.md` (verified at the same v2026.8.3 tag). Highlights: `PluginContext.inject_message` is **CLI-only** (returns False in gateway mode); `send_message` is **NOT an agent-callable tool** in this tag (send-only, used by cron/`hermes send`/MCP); there is **no OpenCode tool** in the core — `opencode`/`codex` tokens are port citations/category names, not the only external-agent mechanism is `delegate_task` subagents.

For the **human-approval gate** any plugin bridges into (`request_tool_approval`, pre_tool_call `approve` escalation, gateway notify, allowlist persistence) see `references/hermes-approval-gate-internals.md` (verified at v2026.8.3 while auditing a hermes-opencode bridge wiki against the source). The four facts that routinely break designs: (1) **no smart/aux-LLM approval on the plugin path** — `_smart_approve` is invoked only from the terminal-command and execute_code guards, even though the default `approvals.mode` is `smart`; (2) **every approved outcome returns the identical `{"approved": True, "message": None}` dict** — once/session/always/yolo/cache-hit are indistinguishable, and `display_target` is hardcoded head for `request_tool_approval`, so the bridge's only controllable surface is the `reason` string; (3) `[s]ession` approvals are **in-memory only**, only `[a]lways` persists — to the top-level `command_allowlist` key, not `plugins.entries.*`; (4) a plugin thread must bind `set_current_session_key` + `set_current_observability_context` + **`set_hermes_interactive_context(True)`** per thread or it fails closed with `fail_closed_when_no_human` in every non-gateway context.

**The live bridge instance is `hermes-opencode`** (repo `~/src/hermes-opencode-plugin`, installed as a symlink under `~/.hermes/plugins/`, own wiki at `<repo>/wiki/`). When diagnosing bridge failures against the headless opencode server, read `references/hermes-opencode-bridge.md` FIRST — it carries the verified 2026-08-11 lockout chain: the v1/v2 agent-registry split (runtime-injected plugin agents never reach the fork's v2 `AgentV2` map → `info: undefined` → `missingAgentPermissions` deny-all on EVERY tool, with no ask ever born), the deny signature (`role:"tool"` rows with `error: ...Unable to execute...`), the plugin-side fix (explicit `agent`/`model` on v2 session create + v1 API fallback with the same agent+directory, outcome flagged `fallback: "v1"`), the API body shapes, and the plugin wiki conventions (SCHEMA frontmatter, provenance refs, log/index updates).

## Credential Pool Model-Scoped Exhaustion (429 Rate Limits)

When implementing or fixing credential pool rate-limit handling (429s):

1. **Model-scoped exhaustion**: A 429 on one model (e.g. Gemini per-model RPM/RPD caps) must bench only the `(key, model)` pair via `model_exhaustions` dictionary, rather than marking the key globally exhausted (`last_status = "exhausted"`). Global exhaustion kills the key for all models for up to 24 hours.
2. **Primary-agent recovery forwarding**: `recover_with_credential_pool` in `agent/agent_runtime_helpers.py` must forward `agent.model` into `mark_exhausted_and_rotate` when `rotate_status == 429`. Calls without a known model should omit the kwarg to preserve legacy key-level behavior.
3. **Sibling propagation**: `mark_exhausted_and_rotate` must propagate per-model benches to every pool entry sharing the same runtime key (`runtime_api_key`), mirroring the key-level sibling invariant. This prevents duplicate entries (e.g. explicit pool entry + a `model_config` auto-seeded entry) from reselecting the depleted key.
4. **Model-agnostic selectors**: `peek()` and `has_available()` must ignore per-model benches so model-agnostic callers still see the key as usable.
5. **Testing**: Add real-pool recovery tests (`TestFailureAttribution` in `test_credential_pool_routing.py`) and per-model rotation/duplicate-key sibling tests (`test_credential_pool_model_exhaustion.py`).

> **⚠ Output caps (`max_tokens`) are NOT config-driven — they get OMITTED.** Hermes policy (`max-tokens-knob`, enforced by the `hermes-sweeper` bot) prohibits user-facing `max_tokens` configuration surfaces, even per-task (`auxiliary.vision.max_tokens`). PRs adding such a knob are closed as `not_planned` (verified: #15430, #74945). The sanctioned fix for a hardcoded output cap is to REMOVE it and let the aux client omit the field — providers then use the model's max output. See "Output Cap Removal Pattern" below. The config-driven pattern applies ONLY to non-cap settings like `timeout`/`temperature`.

## Output Cap Removal Pattern (max_tokens — the sanctioned approach)

When a vision/aux call site hardcodes `"max_tokens": N`:

1. Delete the `"max_tokens": N,` line from `call_kwargs` entirely — do NOT replace it with a config read.
2. The centralized aux client (`agent/auxiliary_client.py` `_build_call_kwargs`, fixed in #34845) already omits `max_tokens` on all OpenAI-compatible paths → provider model max output.
3. Other wires are safe upstream: Anthropic Messages (mandatory field) falls back to the model output ceiling via `_resolve_anthropic_messages_max_tokens`; Gemini native omits `maxOutputTokens` → 65K ceiling.
4. If more output is genuinely needed, that's a provider/model selection question (`auxiliary.<task>.model`), not a per-call knob.

Known hardcoded caps on current main:

| File | Line | Cap | Task | Verdict |
|---|---|---|---|---|
| `tools/vision_tools.py` | ~1270 | `"max_tokens": 2000` | image analysis | REMOVE — description is the deliverable |
| `tools/vision_tools.py` | ~1777 | `"max_tokens": 4000` | video analysis | REMOVE |
| `tools/browser_tool.py` | ~4360 | `"max_tokens": 2000` | browser screenshot | REMOVE |
| `tools/browser_tool.py` | ~2799 | `"max_tokens": 4000` | `web_extract` snapshot summarization | **LEAVE (flag to user)** — deliberately lossy: full snapshot is stored to cache and a pointer note is returned, so truncation is by design, unlike vision where the description IS the deliverable |

The 4th site is easy to miss: a `"task": "vision"`-only search doesn't find it (`task: "web_extract"`). Grep for `max_tokens` across ALL `call_kwargs` dicts in the file to enumerate the whole bug class, then apply judgment per task — not every cap is a bug. When the user's PR is vision-scoped, surface the sibling site as a decision point rather than silently widening the PR.

## Config Validation and TUI Warning Separation

When modifying config loaders (`src/config/loader.ts`) to emit warnings for deprecated or migrated keys, ensure the warning kind distinguishes **benign deprecation notices** (`deprecated-key`, `missing-preset`) from **genuine configuration rejections** (`invalid-json`, `invalid-schema`, `read-error`). If the TUI consumes `onWarning` to set `configInvalid = true` (which lights up a persistent red "Config invalid" badge in the sidebar), benign deprecation notices must NOT trip the flag, otherwise a config that strips deprecated keys and loads successfully will still be incorrectly flagged as invalid.

## Config-Driven Patching Pattern (temperature/timeout only)

Many Hermes tools build their own `call_kwargs` dicts that hardcode sampling values like `temperature` or `timeout`. The pattern to make them config-driven:

### 1. Find the existing config-reading block

Look for the `try/except` block that reads `_vision_cfg.get("timeout")` and `_vision_cfg.get("temperature")`. This block loads from `auxiliary.vision` in config.yaml. Known locations:

| File | Config block | `call_kwargs` |
|---|---|---|
| `tools/vision_tools.py` | ~L1234-1244 | ~L1250-1256 |
| `tools/browser_tool.py` | ~L4306-4314 | ~L4322-4331 |

### 2. Add your key in the same pattern

Insert after the `temperature` block:

```python
_vtmp = _vision_cfg.get("top_p")   # example: a NON-cap setting
if _vtmp is not None:
    vision_top_p = float(_vtmp)
else:
    vision_top_p = 1.0  # preserve original hardcoded default
```

In the `except` fallback, also set the fallback:

```python
except Exception:
    vision_top_p = 1.0  # same default on config read failure
```

Do NOT do this for `max_tokens` — see the Output Cap Removal Pattern instead.

### 3. Replace in `call_kwargs`

Change the hardcoded value → `"top_p": vision_top_p`.

### 4. Add config entry

```bash
hermes config set auxiliary.vision.top_p 0.9
```

The "not a recognized config key" warning is harmless — new keys are saved anyway.

### Why this pattern is required

- Both files build their kwargs dicts **manually** (not through `agent/auxiliary_client.py` which was fixed in PR #34845)
- The existing `try/except` already handles optional config gracefully; piggyback on it
- Falls back to the original hardcoded value if config is absent, so existing users see zero behavior change
- **Scope: sampling params only** — `temperature`/`timeout` are legitimately config-driven in these files. `max_tokens` is the one key the project deliberately refuses to expose; remove it instead (see the warning at the top).

## Running the Vision Test Suite

**ALWAYS use `scripts/run_tests.sh`, never in-process `uv run python -m pytest` across multiple files.** The runner spawns each test file in a fresh subprocess (per-file isolation, CI parity). Running several files in ONE pytest process leaks state between files: this session, `test_vision_tools.py` + `test_auxiliary_client.py` in one process gave **11 false failures** (`TestCustomEndpointApiKeyInheritance`), while `scripts/run_tests.sh` passed **224/224**. This matches the AGENTS.md warning — direct pytest on a dev machine diverges from CI.

```bash
cd ~/.hermes/hermes-agent
scripts/run_tests.sh \
  tests/tools/test_vision_tools.py \
  tests/tools/test_vision_native_fast_path.py \
  tests/run_agent/test_vision_aware_preprocessing.py \
  tests/agent/test_vision_routing_31179.py \
  tests/agent/test_vision_resolved_args.py \
  tests/agent/test_auxiliary_client.py \
  tests/tools/test_browser_console.py \
  tests/tools/test_video_analyze.py
```

The last two files were added when the sweeper required no-cap assertions in the browser-screenshot (`test_browser_vision_uses_configured_temperature_and_timeout`) and video (`test_api_message_format`) kwargs captures. The canonical no-cap regression set is these 8 files / **261 tests**.

If `pytest` is not installed, add it:

```bash
uv pip install pytest pytest-asyncio
```

## Submitting a PR

Forking and PR creation are covered by the [github-pr-workflow](https://hermes-agent.nousresearch.com/skills/github/github-pr-workflow) skill. Hermes-specific notes:

### SSH timeout on push

If `git push` via SSH hangs (common on macOS with long-lived SSH agent), switch to HTTPS:

```bash
git remote set-url fork https://github.com/<your-username>/hermes-agent.git
# gh auth handles credentials automatically
git push --set-upstream fork fix/your-branch
```

### PR description template — follow the REPO's template, don't invent sections

**Always check the target repo for a PR template first**: `read_file .github/PULL_REQUEST_TEMPLATE.md` in the checkout. `NousResearch/hermes-agent` has one, and it governs the body exactly — sections, order, and the checklist. The user explicitly corrected this ("always follow the pr template if the repo has one, its okay to add things to the pr body"): write the body with the template's `##` sections verbatim, then enrich inside them. It is fine to ADD content/sections beyond the template (wire-safety tables, out-of-scope notes, test evidence), never to omit or rename its sections.

The hermes-agent template's checklist is load-bearing — fill it HONESTLY:
- Check boxes only when true. If the full suite isn't green, leave `I've run pytest tests/ -q and all tests pass` UNCHECKED and annotate with a pointer that ACTUALLY RESOLVES. **The user caught a dangling reference**: the annotation "see note below" pointed nowhere because the full-suite note lives in the "How to Test" section, which renders ABOVE the checklist. Use `see the full-suite note in [How to Test, step 4](#how-to-test)` — GitHub auto-generates the anchor from the `## How to Test` heading (lowercase, spaces→hyphens, punctuation stripped). Before finalizing, verify every in-body pointer resolves: `gh pr view <n> --repo ... --json body --jq '.body'` and grep for the referenced heading.
- "I've added tests" is REQUIRED for bug fixes — add a regression test (extend the sibling config test that asserts the other kwargs, e.g. assert `"max_tokens" not in kwargs`), commit it separately (`test(vision): ...`).
- "I've read the Contributing Guide" — actually fetch and read it (`curl -s https://raw.githubusercontent.com/NousResearch/hermes-agent/main/CONTRIBUTING.md`), including the PR process + cross-platform sections.
- Delete the "For New Skills" section for non-skill PRs.

Write the body to a temp file and pass it (avoids shell-escaping pain with backticks/code blocks):
```bash
gh pr edit <n> --repo NousResearch/hermes-agent --body-file /tmp/pr-body.md
```

### PR comments: editing, style, and the user's writing preferences

Editing an existing PR comment (removing a heading, rewording) uses the REST PATCH endpoint with the comment's NUMERIC databaseId. `gh pr view --json comments` returns new-style IDs (`IC_...`) that REST PATCH 404s on; fetch the numeric id via GraphQL:

```bash
gh api graphql -f query='query { repository(owner:"NousResearch", name:"hermes-agent") { pullRequest(number:<n>) { comments(first:10) { nodes { databaseId, body } } } } }' --jq '.data.repository.pullRequest.comments.nodes[] | select(.body | contains("<unique fragment>")) | .databaseId'
gh api -X PATCH repos/NousResearch/hermes-agent/issues/comments/<databaseId> -f body='<new body>'
```

User writing preferences for PR bodies and comments (stated corrections; treat as binding for this user):
- **Never use em dashes (—).** Use commas, colons, semicolons, or restructure the sentence. Applies to PR bodies, comments, commit messages, and chat replies. After editing, verify zero remain: `grep -c "—" <body-file>`.
- **User-facing docs: affirmative framing, no negative ontologies.** When rewriting READMEs or plugin descriptions for this user, do not define things by what they lack: ban "TUI only", "refused", "never", "fail closed", "nothing appears", "stays pending", standalone "only". Say what each mode DOES ("In TUI sessions completion notices and questions land in the conversation; gateway and desktop sessions keep the full tool surface with reads and replies on demand"). Target power users: quick-start walkthrough first, config/tools reference after. After rewriting, verify: `grep -c '—'` = 0 and `grep -cE 'never|refused|fail clos|TUI only'` = 0. **Keep machine-readable description surfaces in sync**: when the README changes framing, also update `plugin.yaml` `description:` and `pyproject.toml` `description` (both show in `hermes plugins list` / packaging metadata) — they stale independently.
- **No decorative/emoji headings in comments** (e.g. a `## Addressed the sweeper follow-up ✓` heading was explicitly called out as bad). Keep headings plain text; if the comment reports on body changes, say so in a plain lead line.
- **State the plan before editing PR content.** The user asked "tell me what you are gonna do before doing it": narrate the exact edits (which comment, what changes, what stays), then execute in the same turn.
- **When a note is already in the PR body, don't duplicate it as a comment.** The user deleted the web_extract-note comment because the PR body's "Deliberately out of scope" section already covered it. Prefer the body as the single home for scope notes; use comments only for conversation (sweeper replies, review responses).

### Full-suite runs: prove pre-existing failures on clean main

The template's "all tests pass" box needs a real full run (`scripts/run_tests.sh tests/ -q`, background it — ~20k tests). Dev machines fail environment-bound suites (port binding, remote sandboxes like daytona, external messaging services, video-gen APIs). When the suite shows failures:

1. Check none of them touch your changed files: `grep FAILED /tmp/full-suite.log | grep -iE "your_file|your_other_file"` (empty = clean).
2. **Prove they're pre-existing** by running the same failing files on a pristine `origin/main` worktree — identical failures there mean they're not yours:
```bash
git worktree add /tmp/main-worktree origin/main
cd /tmp/main-worktree
uv run --with pytest python -m pytest <failing_files> -q --tb=no   # worktree has no venv; --with pytest pulls it
cd ~/.hermes/hermes-agent && git worktree remove /tmp/main-worktree --force
```
3. Document the proof in the PR body (count, domains, the clean-main reproduction, "zero in files touched by this PR").
4. Run the Windows footgun check CI runs on every PR. **Use a SINGLE ref, not a triple-dot range**: `uv run python scripts/check-windows-footguns.py --diff origin/main` (or pass explicit file paths). The triple-dot form `--diff origin/main...HEAD` silently scans 0 files and prints a misleading "✓ No Windows footguns found (0 file(s) scanned)" — a false pass. Verify the scan actually covered your files by checking the "(N file(s) scanned)" count.

### When a PR gets closed by the sweeper

Don't just open a replacement silently. After re-scoping per the close comment's guidance (see Pitfalls), comment on the CLOSED PR with a pointer to the new one — the maintainers keep the close thread as the decision record, and the cross-link makes the re-scope visible:

```bash
gh pr comment <closed-n> --repo NousResearch/hermes-agent --body "Re-scoped per the ... policy guidance — no knob. New PR: #<new-n>"
```

**Before re-scoping, understand the policy.** Named sweeper policies (like `max-tokens-knob`) are NOT defined in the repo — trace them to their canonical origin issue to learn the actual design rationale and the sanctioned alternatives (web-search the policy name verbatim, find the "canonical issue", read its maintainer close comment). See `references/sweeper-policy-origins.md` for the technique and the full `max-tokens-knob` origin chain (issue #4404, primary-source table, enforcement history).

### When the sweeper says `keep_open`: the follow-up loop

A `hermes-sweeper:review-verdict=keep_open` comment is NOT a rejection — it's a precise to-do list. It cites the EXACT existing tests to extend (file:line, e.g. `tests/tools/test_vision_tools.py:246`, `tests/tools/test_browser_console.py:254`, `tests/tools/test_video_analyze.py:181`) and names the assertion it wants ("assert the captured kwargs omit `max_tokens`"). Close the loop:

1. Implement its suggestions VERBATIM, extending the cited tests rather than writing new test files — a future refactor restoring the caps is exactly what these protect.
2. Run the suite (`scripts/run_tests.sh`), commit the test changes separately (`test(vision): ...`), push.
3. Reply on the PR with a coverage table mapping each suggested item → test → verification result ("261 passed, 0 failed, no flaky retries") + branch head OID.
4. Re-verify the PR BODY afterwards: counts drift when you add tests (a body written at "224 passed" is stale at 261). Grep the body for stale numbers before re-reading.
5. When all suggestions are addressed and verified, mark the PR ready for review if it's still a draft: `gh pr ready <n> --repo NousResearch/hermes-agent`. Check `gh pr view <n> --json isDraft` first — a PR opened with `--draft` stays a draft until flipped; reviewers (and the sweeper) may not act on a draft. Then confirm `{"isDraft": false, "mergeable": "MERGEABLE"}`.
6. **Do NOT wait for or try to force a re-review — the sweeper is one-pass.** Verified 2026-07-31: every PR gets exactly ONE `hermes-sweeper:review` comment, ever. Review comments are never edited (`updatedAt` absent), it runs as a batch cron sweeping *unreviewed* PRs (review times cluster in bursts, e.g. 6 at 04:00Z + 6 at 07:00Z on 07-30; #74581 was reviewed 14h after creation with zero intervening commits), and it even reviews drafts (our draft PR was reviewed 21 min after creation). Pushing commits or marking ready-for-review does NOT queue a new review — the scheduled batches pass it over. There is NO trigger (searched 200 PRs for re-review requests; none produced a second comment). The community protocol is to post an "Addressed the sweeper review" comment (with a coverage table, see step 3) — that is for the HUMAN maintainer, not the bot. Merge happens when a maintainer picks the PR up and does NOT require a re-review (#74581 merged 1h after its single review). Full evidence in `references/pr-merge-pattern-analysis.md` §0 (re-review detection).

### Predicting whether a PR will merge (merge-pattern analysis)

When asked "will this PR get merged" / "do first-time contributors get merged here", do NOT speculate from vibes — measure the repo's actual merge behavior. See `references/pr-merge-pattern-analysis.md` for the full technique. Key facts verified on hermes-agent (2026-07-31):

- **First-timers merge at scale**: 63% of all distinct authors on `main` (1,492/2,369) have exactly ONE commit = one squash-merged PR, never returned. Detect them from LOCAL git (`git log origin/main --pretty=%H|%an|%ad|%s`), zero API cost, no rate limits.
- **`keep_open` PRs die only by author action**: sampled ~600 recent PRs, every closed `keep_open` PR was closed by its own author (superseded, "opened in error", abandoned). The bot/maintainers never close a `keep_open` PR. So `keep_open` + author engaged + mergeable + up to date = strong merge signal; the risks are author abandonment and supersession.
- **Direct precedent**: #74581 (mollusk, `keep_open salvageability=high`) reviewed 18:07, merged 19:08 same day; a 5-PR `keep_open` batch merged in 20 min on 07-28. Maintainers sweep `keep_open` PRs in batches, so a clean one is a wait-for-the-next-batch situation, not a rejection.
- **Pitfall — never measure merge rates from an UPDATED_AT-ordered sample**: merged PRs stop being updated after merge and sink below open ones; a "recent 400" sample showed ZERO merged `keep_open` PRs even though #74581 was merged (pure artifact). Sample by STATE: separate GraphQL sweeps for `states:[MERGED]` and `states:[CLOSED]`.
- **GraphQL over REST search**: search/issues rate-limits fast and per-author filters inside pagination loops short-circuit after page 1. Batch PR+comments via `gh api graphql`; parse `review-verdict=(\S+)` / `salvageability=(\S+)` from sweeper comments.
- **Who closed it?** `gh api repos/NousResearch/hermes-agent/issues/<n>/timeline` — `event=="closed"` with actor=author and no commit_id = author-closed (NOT merged); actor + commit_id = squash-merged.

### Final pre-submit verification pass (do this BEFORE declaring a PR done)

The user's standing expectation: before checking a PR, re-read the governing md files (`.github/PULL_REQUEST_TEMPLATE.md`, `CONTRIBUTING.md`, `AGENTS.md`), then verify the live PR against them line by line. Run this checklist after any body/comment/test edit:

1. **Fetch the live body and grep for regressions** — never trust the local draft:
```bash
BODY=$(gh pr view <n> --repo NousResearch/hermes-agent --json body --jq '.body')
echo "em dashes: $(echo "$BODY" | grep -c '—')"          # must be 0 (user rule)
echo "stale-count refs: $(echo "$BODY" | grep -c '224 passed')"  # 0 once tests grew to 261
echo "dangling comment refs: $(echo "$BODY" | grep -c 'comment on this PR')"  # 0 — body must be self-contained
echo "sections:"; echo "$BODY" | grep -E '^## '
```
2. **Type of Change: exactly ONE box checked.** The template says "Check the one that applies" — a bug fix with test additions checks only `🐛 Bug fix`; the `✅ Tests` box is for test-only PRs. Verify with `sed -n '/## Type of Change/,/## Changes Made/p'`.
3. **Body must be self-contained — never reference a comment from the body.** Comments can be deleted (the user deleted the web_extract note after it was folded into the body's "Deliberately out of scope" section); any "See the comment on this PR" pointer then dangles. Scope notes live in the body, period.
4. **Every in-body pointer must resolve** — especially the "see note in How to Test step N" pattern in the checklist: confirm the heading exists (`grep -c '^## How to Test'`).
5. **Screenshots/Logs section must match the current run** — it goes stale when the test set grows (224→261), and a mismatched log undercuts the whole body.
6. **Cross-check the live PR metadata**: `gh pr view <n> --json state,mergeable,baseRefOid,headRefOid,additions,deletions,changedFiles,commits` — base must equal current `origin/main`, mergeable MERGEABLE, commits conventional (`git log origin/main..HEAD --format='%s'`), local HEAD == fork remote HEAD (`git ls-remote fork <branch>`).
7. **Proof of pre-existing failures stays in the body** with the clean-main worktree reproduction (see "Full-suite runs" above) — don't delete it to make the body prettier; it's what justifies the unchecked "all tests pass" box.
8. **Verify the docs N/A boxes against the actual docs, never by assumption.** Before marking "updated relevant documentation" / "cli-config.yaml.example" as N/A, confirm no doc documents the behavior you changed: `grep -rn "<changed-keyword>" website/docs/` and check `cli-config.yaml.example` for the changed surface. This session: `website/docs/user-guide/features/vision.md` and `configuring-models.md` mention no caps, and the example's auxiliary block has no `max_tokens` key, so N/A was honest — but only after checking. Also inventory the OTHER governing docs that may apply: `find . -name "AGENTS.md" -o -name "CLAUDE.md" -o -name ".cursorrules"` (sub-project files like `apps/desktop/AGENTS.md` scope OUT — say why), `.github/` contents beyond the PR template (workflows only, no CODEOWNERS/issue templates → nothing else to read), `SECURITY.md`/`LICENSE` (only for security/legal-sensitive PRs).

### Target branch

`NousResearch/hermes-agent:main` — always.

### Re-basing an open PR after `hermes update`

When the user reports "the branch wasn't updated" (main advanced while the PR sat open), the procedure is:

```bash
cd ~/.hermes/hermes-agent
git checkout main
hermes update                 # pulls new commits; resets working tree to main
git checkout fix/your-branch
git rebase origin/main        # replay your commit(s) on the new main
# CRITICAL: re-enumerate the bug class AFTER the rebase — upstream may have added
# new sibling call sites or line-shifted the known ones.
git diff --stat origin/main..HEAD
git push --force-with-lease fork fix/your-branch   # --force-with-lease, never bare --force
gh pr view <n> --repo NousResearch/hermes-agent --json state,headRefOid,baseRefOid,mergeable
```

- `--force-with-lease` refuses to clobber remote commits you haven't seen (a bare `git push --force` on a fork can silently overwrite a maintainer's push).
- Verify `mergeable` = MERGEABLE and head/base OIDs after pushing; re-run the test suite on the rebased branch (new main commits can regress adjacent behavior).
- Re-check line numbers in the cap table above after a rebase — they shift.

### Tracing PR comment trails (depth-N DFS)

When asked to analyze PR comments and the PRs referenced within them (e.g. "depth 2"), see `references/pr-comment-graph-triage.md` — gh commands, the DFS algorithm, and the hermes-sweeper verdict taxonomy (`not_planned` vs `implemented_on_main`).

## Pitfalls

- **`max-tokens-knob` policy — never add a `max_tokens` config surface.** The `hermes-sweeper` bot closes any PR exposing `max_tokens` via config (even per-task `auxiliary.vision.max_tokens`) as `not_planned`. Verified closes: #15430 and #74945 (same commit pattern). A re-scope that merely *removes* the hardcoded caps is accepted — that's the PR #75253 pattern. Don't re-attempt the knob.
- **Handoffs under-report call sites — search for the whole bug class.** A handoff may say "two files"; the vision bug class has THREE hardcoded caps (image 2000, video 4000, browser 2000). Search `"task": "vision"` across `tools/` before editing, and grep the file for every `max_tokens` in a `call_kwargs` dict.
- **`hermes update` resets the working tree — verify git state before patching.** This session: `hermes update` switched the repo back to `main` mid-work, so a `patch` fuzzy-matched against a different region than intended and deleted config lines it shouldn't have (the browser_tool.py timeout block). Before patching Hermes source: `git status` + `git branch` first. If a patch's diff removed MORE than your old_string, restore with `git checkout -- <file>` and re-read before retrying — don't pile more fuzzy patches on a mangled file.
- **`except` fallback must set your variable too** — if you only set your config variable in the `try` block, an exception leaves it undefined and causes a `NameError` at the `call_kwargs` dict.
- **Config validator warnings are harmless** — `hermes config set` may flag new keys as unrecognized. The value is stored correctly.
- **Always check sibling files** — if a pattern exists in multiple files (like `vision_tools.py` and `browser_tool.py`), fix all of them. Partial fixes leave the bug half-open.
- **Re-read target after paginated read** — if you use `read_file` with offset/limit, the patch tool warns about stale view. Re-read the relevant lines after patching to confirm.
- **Credential pool exhaustion is per-key, not per-(key, model).** A 429 on one model (Gemini's per-model RPM/RPD limits) poisons the whole key for ALL models until `reset_at` (up to 24h for daily caps). Gap analysis, model-scoped fix design, related PRs, and the pool test-file list: `references/credential-pool-exhaustion.md`.
- **Sweeper verdicts are reusable evidence.** Closed PRs carry `hermes-sweeper` comments with machine-readable verdict tags (`reason=not_planned`, `reason=implemented_on_main`). When triaging why a PR was closed, read those tags — `implemented_on_main` means a broader fix already covers the path, so a re-scope should align with that fix's approach rather than re-litigate it.
- **`PluginContext.inject_message` only targets sessions with a live CLI ref** — it returns `False` in gateway mode ("not available in gateway mode"). A bridge that must push messages into gateway sessions needs a routing surface instead (gateway platform adapter / `pre_gateway_dispatch` hook / `hermes send` transport), not `inject_message`.
- **Plugin-tool approvals never hit smart mode.** `request_tool_approval` (approval.py:3299) has no aux-LLM branch — `_smart_approve` runs only in the terminal/execute_code guards (approval.py:3749, :4117), even though the default `approvals.mode` is `smart`. Also `display_target` is hardcoded to `"<tool> (plugin approval rule)"` and the approved-path return dict can't distinguish once/session/always/yolo. Anything relying on those distinctions is unbuildable as designed.
- **`[s]ession` approvals die with the process; only `[a]lways` persists** — into the top-level `command_allowlist` config key (approval.py:2386-2390, :2546-2554). "No reprompt" claims are only valid within one process lifetime.
- **Approval-binding checklist on bridge threads**: `set_current_session_key` + `set_current_observability_context` + `set_hermes_interactive_context(True)` (approval.py:69-200), and pass `approval_callback=` explicitly. Missing the interactive flag ⇒ `fail_closed_when_no_human` ⇒ every ask BLOCKED in non-gateway processes.
- **`delegation.subagent_auto_approve` silently kills approvals in subagents.** Subagent threads always get a non-interactive callback: default auto-DENY (config_defaults.py:1718-1726, delegate_tool.py:70-93). A plugin asking for approval inside a `delegate_task` run is denied with zero prompt unless `delegation.subagent_auto_approve: true`.
- **Pip entry-point plugins bypass the tool-override gate.** The durable override policy keys on `hermes_plugins.<slug>` (plugins.py:1776-1781) but `_plugin_owner_of` only recognizes that namespace (registry.py:481-503) — an `ep.load()`-ed module's real name misses it, so `override=True` passes ungated. Directory plugins are gated correctly; archive this asymmetry when designing trust boundaries.
- **Directory plugins must import relative-first — absolute self-imports fail SILENTLY in the runtime.** The loader imports the plugin as `hermes_plugins.<slug>` with `submodule_search_locations=[plugin_dir]` and never adds the dir to `sys.path`; `from hermes_opencode import ...` (top-level) inside the root `__init__.py` or package modules raises ModuleNotFoundError, the loader catches it into `loaded.error`, and the plugin looks enabled while NO tools register. Tests/E2E smokes mask it (repo root on sys.path via cwd). Fix: root shim does relative-first with absolute fallback inside `register()` (pytest imports the root as a bare top-level module where relative raises ImportError — hence try/except, not a plain relative import), package internals use relative imports. `hermes plugins list` does NOT prove register() ran — verify with the loader-replication subprocess (scrubbed sys.path). Full recipe: `references/hermes-plugin-load-path.md`.
- **Core messaging gates: no agent-callable `send_message` tool, no mid-loop synthetic user messages.** The `send_message` engine is transport-only (cron/`hermes send`/MCP/gateway); and AGENTS.md forbids injecting synthetic user role messages mid-loop — the only sanctioned in-context mutation is context compression. Design bridge/skill flows around turns, not live-transcript edits.
- **Grep "cookbook vs capability" when mapping Hermes tools:** `opencode`/`codex`/`claude` tokens in `tools/*.py` are usually port citations (e.g. "Ported from anomalyco/opencode#…") or provider names (`"openai-codex"` Responses API), NOT tool capabilities. Verify whether a name is a registered tool by looking for `registry.register(name=…)` in the file before claiming it callable.
