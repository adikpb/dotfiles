# Credential Pool: per-key vs per-model exhaustion

Context: user runs Gemini free-tier aux with 2 keys in the credential pool
(`GOOGLE_API_KEY` + a manual key), `credential_pool_strategies.gemini: least_used`.
Investigated 2026-07-31 on branch `feat/credential-pool-model-scoped-exhaustion`,
base commit `98105f31f`. Implementation was handed to opencode with spec
`/tmp/spec-credential-pool-model-scoped-exhaustion.md`.

## The gap (verified in source)

- `PooledCredential` (`agent/credential_pool.py`) tracks exhaustion PER KEY only:
  `last_status`, `last_status_at`, `last_error_code/reason/message`,
  `last_error_reset_at` (lines ~166-182). No model dimension.
- `CredentialPool.select()` (line ~1593) and `mark_exhausted_and_rotate()`
  (line ~1796) take NO model parameter. `_available_entries()` (line ~1603)
  filters purely on key-level cooldown (`_exhausted_until`, line ~376).
- Gemini free-tier rate limits are PER MODEL (RPM and per-day RPD caps). A 429
  for model X (e.g. gemini-3.5-flash-lite from a compression call) marks the
  WHOLE key exhausted until `reset_at` (up to 24h for daily caps), removing it
  from rotation for every other model, even ones with full quota on that key.
  With 2 keys, one model's daily cap can disable the pool for all models for
  the day.
- Gemini's 429 `reset_at` IS parsed (`_normalize_error_context`, line ~358,
  falls back to `_extract_retry_delay_seconds(message)`) but lands on the key,
  not the (key, model) pair.
- Accidental mitigation: when `pool.select()` returns None (all keys in
  cooldown), provider resolution falls through to the raw env key
  (`GOOGLE_API_KEY`), so aux fallback-chain entries still run on it. Not
  deliberate, not reliable.

## Related prior art (no duplicates found)

- #73380 `feat(fallback): persist per-model rate-limit cooldowns` — OPEN;
  per-entry `cooldown_seconds` in the FALLBACK layer. Complementary, different
  subsystem (fallback chain vs credential pool). Cite in any PR body.
- #50960 `fix(auxiliary): rotate credential pool on connection errors` — OPEN.
- #38804 [Bug] Temporary Gemini rate limits surfaced as "quota exhausted" —
  CLOSED; error-classification only.

## Fix design (model-scoped exhaustion)

1. Add `model_exhaustions: Dict[str, Dict]` to `PooledCredential` (model →
   `{"until": float, "status_code": int, "reason": str, "reset_at": float}`).
   Serialize in auth.json: `to_dict` + `_ALWAYS_EMIT` (line ~222) and the
   from-dict loader. Missing field = `{}`, old auth.json files load fine.
2. `select(model=None)`, `_available_entries(..., model=None)`,
   `_exhausted_until(entry, model=None)`: when model given, also skip keys
   whose per-model exhaustion for that model is active; model=None behaves
   byte-for-byte like today.
3. `mark_exhausted_and_rotate(..., model=None)`: only for 429 + known model
   record the per-model entry WITHOUT flipping key-level `last_status`, then
   rotate for that model. 401 (auth) and 402 (billing) stay key-level: they
   are account-level for most providers. Keep the change conservative.
4. Callers that know the model and should pass it: `agent/auxiliary_client.py`
   `_recover_provider_pool()` (line ~3865) and `_select_pool_entry()` (line
   ~859), model available at the aux call site (~line 8390);
   `hermes_cli/runtime_provider.py` main path `pool.select()` (line ~1833) has
   `target_model`; `run_agent.py` / `agent/chat_completion_helpers.py` mark
   sites where model is in scope. `hermes_cli/proxy/adapters/xai.py`,
   `hermes_cli/auth.py`, `hermes_cli/nous_auth_keepalive.py`,
   `agent/account_usage.py` stay model-less.
5. `hermes auth reset <provider>` must clear `model_exhaustions`;
   `hermes auth list` should surface active per-model limits.
6. Docs: `website/docs/user-guide/features/credential-pools.md` Error Recovery
   table (429 row) gets one sentence about per-(key, model) tracking when the
   model is known.

No new config keys, no new env vars, no new deps. Backward compatible by
construction (model=None everywhere it isn't passed).

## Test files for this subsystem

`scripts/run_tests.sh` (never bare pytest), pool family:
`tests/agent/test_credential_pool.py`, `test_credential_pool_routing.py`,
`test_credential_pool_provider_boundary.py`,
`test_credential_pool_unmatched_rotation_bound.py`,
`test_credential_pool_oauth_writethrough.py`,
`test_credential_pool_oat_authtype.py`,
`test_credential_pool_env_fallback.py` (tests/tools/),
`test_credential_pool_no_entries_log_throttle.py`,
`tests/run_agent/test_credential_pool_interrupt.py`, plus
`tests/agent/test_auxiliary_client.py`. E2E persistence tests need a temp
`HERMES_HOME` (the `_isolate_hermes_home` autouse fixture), not mocks.

## User's contribution workflow (stated 2026-07-31)

1. Search GitHub for similar issues/PRs first: `gh search issues/prs --repo
   NousResearch/hermes-agent "<terms>"` — read close comments, they carry
   reusable evidence.
2. Pull all commits from main, then create the branch (`feat/...`).
3. Read ALL governing docs before branching: `AGENTS.md` (full),
   `CONTRIBUTING.md` (full), `.github/PULL_REQUEST_TEMPLATE.md`.
4. Hand implementation to opencode with a written spec attached (`-f`) and
   explicit no-push / no-PR instructions; background with
   notify_on_complete=true.
5. Verify opencode output yourself: tests via `scripts/run_tests.sh`,
   `scripts/check-windows-footguns.py --diff origin/main` (single ref),
   em-dash check on commits/docs, `git diff --stat` scope check.
