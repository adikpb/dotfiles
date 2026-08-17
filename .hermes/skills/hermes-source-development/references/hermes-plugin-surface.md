# Hermes Plugin Surface (verified against tag v2026.8.3 / pyproject 0.20.0)

Source recon done 2026-08-09 on a clone of `NousResearch__hermes-agent` at tag
`v2026.8.3` (commit `3c27eb62`, git line "chore: release v0.20.0 (2026.8.3)"). All
paths below are relative to the repo root; line numbers are for that tag and
shift between releases — re-grep, don't trust them blindly.

The plugin engine lives in ONE file: `hermes_cli/plugins.py` (2485 lines).

## 1. Discovery — four sources, later overrides earlier on key collision

Module docstring (`hermes_cli/plugins.py:1-32`) is the contract:

1. **Bundled** `<repo>/plugins/<name>/` — `get_bundled_plugins_dir()` (:55,
   honors `HERMES_BUNDLED_PLUGINS` env override). Top-level skip list
   `{"memory", "context_engine", "platforms", "model-providers"}`; `platforms/`
   is scanned one level deeper (:1355-1366).
2. **User**: `~/.hermes/plugins/<name>/` = `get_hermes_home() / "plugins"`
   (`hermes_constants.py:114`).
3. **Project**: `./.hermes/plugins/` — ONLY with env `HERMES_ENABLE_PROJECT_PLUGINS=1`.
4. **Pip entry points**: group `hermes_agent.plugins` (`ENTRY_POINTS_GROUP`,
   `plugins.py:217`), enumerated via `importlib.metadata`; entry-point plugin
   module must still expose `register(ctx)`; no plugin.yaml required.

`PluginManager.discover_and_load()` (:1298) → `_discover_and_load_inner()`
(:1336). Registry key = `name` (flat, e.g. `disk-cleanup`) or
`<category>/<name>` (nested, e.g. `image_gen/openai`, `web/firecrawl`); depth
capped at 2 (`_scan_directory` :1501).

Loading (`_load_plugin` :1767): import the plugin dir's `__init__.py` as a
synthetic namespace package `hermes_plugins.<slug>` (slug = key with `/`→`__`,
`-`→`_`; `_NS_PARENT = "hermes_plugins"` :219), then call `register(ctx)` with a
`PluginContext` (:339). Missing `register` ⇒ `loaded.error = "no register() function"`.
`HERMES_SAFE_MODE=1` skips discovery entirely (:1357); `HERMES_PLUGINS_DEBUG=1`
tees verbose discovery logs to stderr (:96-129).

> **Load-path reality check**: this loader NEVER adds the plugin dir to
> `sys.path` (the dir is only the package's `submodule_search_locations`).
> Top-level absolute self-imports in the plugin root or internals therefore
> fail silently at runtime while tests pass. Import rules, the loader-
> replication verification recipe, the symlink dev-loop, and the agent+gateway
> double-load topology live in `hermes-plugin-load-path.md`.

## 2. Plugin format (the contract)

A directory plugin MUST contain:
- `plugin.yaml` (or legacy `plugin.yml`) — manifest; and
- `__init__.py` exporting `def register(ctx) -> None`.

Manifest fields parsed into `PluginManifest` (:280): `name`, `version`,
`description`, `author`, `kind`, `requires_env`, `provides_tools`,
`provides_hooks`, `source`, `path`, `key`. `_VALID_PLUGIN_KINDS` (:277):
`{"standalone", "backend", "exclusive", "platform", "model-provider"}`.

- `standalone` (default): own hooks/tools; **opt-in** via config `plugins.enabled`.
- `backend`: pluggable backend for a core tool; bundled backends AUTO-load,
  user-installed gated by `plugins.enabled`.
- `exclusive`: one active provider (memory); selected via `<category>.provider`
  config; own discovery in `plugins/memory/__init__.py`.
- `platform`: gateway messaging adapter; bundled auto-load as *deferred*
  loaders (`_register_deferred_platform`, :1730-1765 — imports heavy SDKs only
  on first use).
- `model-provider`: routed to `providers/__init__.py` discovery, not the
  general loader.

Auto-coercion for `kind` (only when `kind` absent, `_parse_manifest` :1619-1648):
`__init__.py` text mentioning `register_memory_provider`/`MemoryProvider` ⇒
`exclusive`; `register_provider`+`ProviderProfile` ⇒ `model-provider`.

Extra manifest keys consumed by tooling: `pip_dependencies` (dashboard/memory
setup, `hermes_cli/web_server.py:5237`), `optional_env` + dict-form
`requires_env` entries (`name`, `description`, `prompt`, `password`, `url`)
surfaced by `hermes config` (config.py `_inject_platform_plugin_env_vars`,
:5341) and by the installer for prompting; free-form keys like
`provides_web_providers` (`plugins/web/firecrawl/plugin.yaml`) or `label` /
`hooks` are descriptive metadata — **execution is driven by `register(ctx)` calls, not
the YAML**.

## 3. register(ctx) capabilities — `PluginContext` (`hermes_cli/plugins.py:339-1261`)

| Capability | Method (:line) | Notes |
|---|---|---|
| Tool | `register_tool(name, toolset, schema, handler, check_fn=..., is_async, description, emoji, override=False)` (:410) | delegates to `tools.registry.registry.register()` (`tools/registry.py:521`, singleton :911); `override=True` on a built-in requires `plugins.entries.<id>.allow_tool_override: true` unless bundled (:469-491, `PluginToolOverrideError`) |
| Slash command | `register_command(name, handler, description, args_hint)` (:539) | handler `fn(raw_args)->str` or async; conflicts with built-ins rejected; resolve via `get_plugin_command_handler` (:2364) |
| CLI subcommand | `register_cli_command(name, help, setup_fn, handler_fn)` (:523) | argparse subparser; attached to `hermes <name>` in `hermes_cli/main.py:11630` |
| Hook | `register_hook(hook_name, callback)` (:1177) | unknown names warned but stored (forward-compat) |
| Middleware | `register_middleware(kind, callback)` (:1196) | kinds from `VALID_MIDDLEWARE` (`hermes_cli/middleware.py:29`) |
| Context engine | `register_context_engine(engine)` (:635) | only ONE allowed; must subclass `agent.context_engine.ContextEngine` |
| Category providers | `register_image_gen_provider` (:667), `register_video_gen_provider` (:734), `register_web_search_provider` (:761), `register_browser_provider` (:789), `register_dashboard_auth_provider` (:694), `register_secret_source` (:821), `register_tts_provider` (:868), `register_transcription_provider` (:906) | instance-checked against the category ABC; selection via config `<category>.provider` by `provider.name`; bad plugins warn, never crash |
| Gateway platform | `register_platform(name, label, adapter_factory, check_fn, validate_config, ...)` (:950) | `gateway.platform_registry`, `PlatformEntry` |
| Slack actions | `register_slack_action_handler(action_id, callback)` (:1006) | wired into slack_bolt AsyncApp at connect |
| Auxiliary LLM task | `register_auxiliary_task(key, *, display_name, description, defaults)` (:1066) | own `auxiliary.<key>` config block + `AUXILIARY_<KEY>_*` env bridge; must not shadow built-in task keys |
| Host LLM | `ctx.llm` property (:352) | `agent.plugin_llm.PluginLlm`, fail-closed, gated by `plugins.entries.<id>.llm.*` |
| Skill (read-only) | `register_skill(name, path, description)` (:1217) | resolvable as `<plugin>:<name>`; NOT in `<available_skills>` index |
| Message injection | `inject_message(content, role="user")` (:495) | CLI-only; interrupts or queues input |
| Tool dispatch | `dispatch_tool(name, args)` (:604) | registry dispatch w/ parent-agent context |

### VALID_HOOKS (`hermes_cli/plugins.py:135-215`)
`pre_tool_call`, `post_tool_call`, `transform_terminal_output`,
`transform_tool_result`, `transform_llm_output`, `pre_llm_call`,
`post_llm_call`, `pre_verify`, `pre_api_request`, `post_api_request`,
`api_request_error`, `on_session_start`, `on_session_end`,
`on_session_finalize`, `on_session_reset`, `subagent_start`, `subagent_stop`,
`pre_gateway_dispatch`, `pre_approval_request`, `post_approval_response`,
`kanban_task_claimed`, `kanban_task_completed`, `kanban_task_blocked`.

`pre_tool_call` is the POLICY hook: return `{"action": "block", "message": ...}`
to veto, or `{"action": "approve", "message": ..., "rule_key": ...}` to escalate
to the human approval gate (`resolve_pre_tool_block` :2247). `pre_verify` can
keep the turn going with `{"action": "continue", "message"}` (:2298).

### Middleware kinds (`hermes_cli/middleware.py:1-34`)
`tool_request`, `tool_execution`, `llm_request`, `llm_execution`;
`OBSERVER_SCHEMA_VERSION = "hermes.observer.v1"`, `MIDDLEWARE_SCHEMA_VERSION =
"hermes.middleware.v1"`. Consumer call sites: `agent/conversation_loop.py:2229`
(llm_request), `agent/tool_executor.py:485` (tool_request),
`agent/agent_runtime_helpers.py:2812`. Semantics: observers report; middleware
rewrites the request or wraps execution.

## 4. Install / enable CLI — `hermes plugins ...`

- Parser: `hermes_cli/subcommands/plugins.py:build_plugins_parser()` — subcommands
  `install` (`--force/-f`, `--enable`, `--no-enable`), `update <name>`,
  `remove|rm|uninstall <name>`, `list`/`ls` (`--enabled --user --no-bundled --plain --json`),
  `enable <name>` (`--allow-tool-override`, `--no-allow-tool-override`), `disable <name>`.
- Dispatch: `hermes_cli/plugins_cmd.py` `plugins_command()` (:2047), wired via
  the `cmd_plugins` handler in `hermes_cli/main.py` (def :11133; parser built by
  `build_plugins_parser` at :11595).
- Install clones git into `~/.hermes/plugins/<name>` (`_plugins_dir :76`,
  `_install_plugin_core :450`); accepts full git URL, `owner/repo` shorthand,
  `owner/repo/path/to/plugin` subdir, and `<url>#subdir`; warns on `http://` :
  `file://`; prompts for missing `requires_env`, then "Enable now?".
- Enable writes `plugins.enabled` via `_save_enabled_set` (:771);
  `--allow-tool-override` writes `plugins.entries.<id>.allow_tool_override`
  (`_set_plugin_entry_flag` :829). Default: plugins are **opt-in** — not enabled
  ⇒ `LoadedPlugin.enabled=False`, loader records error "not enabled in config".
- Bundled `backend` and `platform` kinds auto-load WITHOUT being in
  `plugins.enabled`; bundled platforms load lazily.

## 5. config.yaml interaction

- `plugins.enabled` — allow-list (None/missing = "nothing enabled yet").
- `plugins.disabled` — deny-list, wins over enabled.
- `plugins.entries.<id>.allow_tool_override` — trust gate for replacing built-ins.
- `plugins.entries.<id>.llm.*` — gates `ctx.llm` overrides.
- Category selection keys: `image_gen.provider`, `video_gen.provider`,
  `web.search_backend`/`web.extract_backend`/`web.backend`, `browser.cloud_provider`,
  `tts.provider`, `stt.provider`, `memory.provider`.
- All reads via `hermes_cli.config.load_config()` + `cfg_get` (plugins.py:227-270).
- `hermes config` auto-surfaces platform-plugin `requires_env`/`optional_env`
  entries; `OPTIONAL_ENV_VARS` gets them from bundled
  `plugins/platforms/*/plugin.yaml` (added at import of `hermes_cli/config.py`).

## 6. Real example plugins (read these before writing your own)

- Flat standalone + hooks + slash command: `plugins/disk-cleanup/` (`plugin.yaml`
  + `__init__.py` whose `register(ctx)` calls `ctx.register_hook` ×2 and
  `ctx.register_command`).
- Backend: `plugins/image_gen/openai/` (`kind: backend`, `requires_env:
  [OPENAI_API_KEY]`; `register(ctx) → ctx.register_image_gen_provider(...)`).
- Web provider: `plugins/web/firecrawl/` (`kind: backend`,
  `provides_web_providers`; `register(ctx) → ctx.register_web_search_provider(...)`).
- Platform: `plugins/platforms/slack/` (`kind: platform`, `name: slack-platform`;
  `adapter.py:9052` `register(ctx) → ctx.register_platform(name="slack", label=...,
  adapter_factory=..., check_fn=..., required_env=[...], setup_fn=...)`).
- Memory provider: `plugins/memory/hindsight/` (kind auto-coerced to
  `exclusive`; `register(ctx) → ctx.register_memory_provider(HindsightMemoryProvider())`;
  loaded by `plugins/memory/__init__.py` which passes a fake collector context,
  `_ProviderCollector` :331).
- **NOT plugins**: `plugins/kanban/` (dashboard assets + systemd units, no
  manifest); `plugins/memory/` itself and `plugins/context_engine/` are
  category roots with their own discovery.

## 7. v2026.8.3-specific facts

- New opt-in model: config migration 20→21 (`hermes_cli/config_migrations.py:_migrate_to_21`,
  :312) grandfathers installed user plugins into `plugins.enabled`; bundled
  plugins NOT grandfathered.
- Entry-point group name: `hermes_agent.plugins`.
- Both `plugin.yaml` and `plugin.yml` accepted.
- `allow_tool_override` trust gate, deferred platform loading, and the
  memory/model-provider kind auto-coercion heuristics are current behavior.
- AGENTS.md philosophy: "The core is a narrow waist; capability lives at the
  edges" — new capability should arrive as CLI command + skill, service-gated
  tool, plugin, or MCP server, in that order; plugins must live in their own
  directory and use the ABCs/hooks; third-party SaaS integrations ship as
  STANDALONE plugin repos installed into `~/.hermes/plugins/` (or pip entry
  point), not under `plugins/` in the core repo.