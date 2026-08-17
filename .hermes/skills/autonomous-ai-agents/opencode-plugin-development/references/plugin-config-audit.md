# Plugin config read map (audited 2026-08 against master @ f65eec5b; smartfetch section updated after fix e498054 / PR #981)

Goal of the audit: verify the invariant "config files are read once at startup,
then served from an in-memory map". Verdict: HOLDS now — the single hot-path
violation (smartfetch) was fixed by resolving secondary models purely from
in-memory values; a source-level guard test pins it.

## The config files (user's machine)

- `~/dotfiles/.config/opencode/opencode.json` (REAL file, symlinked to `~/.config/opencode/opencode.json`):
  - plugin: dcp, cc-safety-net, opencode-caffeinate, opencode-handoff, `./plugins/oh-my-opencode-slim/src/index.ts`
  - permission.bash allowlist (`git *`, `bun *`, `gh *`, `rg *`, `uv run pytest *`, ...), catch-all `*: ask`
  - agent: build/explore/general/plan disabled; lsp: pyright disabled, ty + ruff via `uvx ... server`
- `~/dotfiles/.config/opencode/oh-my-opencode-slim.json`: preset "free", disabled_agents [designer, council], autoUpdate false, disabled_mcps [websearch], multiplexer.type auto
- `tui.json`: theme tokyonight, plugins dcp + `./plugins/oh-my-opencode-slim/src/tui.ts`, attention enabled
- `dcp.jsonc`: compress maxContextLimit 50% / minContextLimit 20%

## Initial-load path (correct)

1. `src/index.ts:197` — `config = loadPluginConfig(ctx.directory)` inside the plugin factory.
2. `loadPluginConfig` (`src/config/loader.ts:403`):
   - `findPluginConfigPaths` → user config via `getConfigSearchDirs()` + project `<dir>/.opencode/oh-my-opencode-slim.{jsonc,json}`
   - `loadConfigFromPath` (`loader.ts:61`): readFileSync → `stripJsonComments` → `{env:VAR}` interpolation → JSON.parse → deprecated-key warnings (tmux, council.master, fallback.*) → `PluginConfigSchema.safeParse` → webfetch.enabled default stripping
   - merge user (base) + project (override); preset resolved and deep-merged into `config.agents`; `OH_MY_OPENCODE_SLIM_PRESET` env override; companion defaults; image_routing validation; disabled_* array normalization
3. The `config` closure var (declared `src/index.ts:144`) is the in-memory map. Subsystems receive slices at construction: `createAgents`, `getAgentConfigs`, `createBuiltinMcps(config.disabled_mcps)`, `createFilterAvailableSkillsHook(ctx, config)`, foreground-fallback (`config.fallback.*`), task-session-manager (`config.backgroundJobs.*`), `createWebfetchTool` (`options.webfetchModels` from `config.webfetch`, index.ts:268-270).
4. Runtime preset singleton `src/config/runtime-preset.ts` (module-level, survives re-init); `src/index.ts:203-214` re-merges it into config.agents; no disk read.
5. The plugin `config` hook (`src/index.ts:609-660`) receives OpenCode's already-parsed config object and mutates it in memory (default_agent forcing, per-agent shallow merge, model chain selection). NEVER reads `opencode.json` from disk.
6. `loadAgentPrompt` (`loader.ts:527`) reads `.md` prompt files from `oh-my-opencode-slim/` dirs — init-time only, not config.

## Re-read points found

### 1. FIXED — smartfetch secondary-model resolution (was the hot-path violation)
- **Before**: `readSecondaryModelFromConfig` ran at the top of every webfetch execute (`tool.ts:103`) and re-read BOTH config surfaces per call: `readEffectiveOpenCodeConfig` (existsSync + readFile of `opencode.jsonc`/`opencode.json` in project `.opencode/` + user dirs, for `small_model`) and a full `loadPluginConfig(directory)` parse (for `agents.explorer.model` / `agents.librarian.model`).
- **After (PR #981)**: resolution is in-memory only.
  - `src/tools/smartfetch/secondary-model.ts`: pure `resolveSecondaryModels(input)` — inputs are `webfetchModels` (from options), `smallModel`, `explorerModel`, `librarianModel`. `pickAgentModelRef` is exported. No fs/config-loader imports remain.
  - `src/index.ts`: `small_model` captured from the host's merged `opencodeConfig` inside the `config` hook (host already parsed the files) via `smallModelRef: () => hostSmallModel`; explorer/librarian ids resolved from in-memory `config.agents` at construction (`createWebfetchTool(ctx, { webfetchModels, smallModelRef, explorerModel, librarianModel })`).
  - `src/tools/smartfetch/types.ts`: `SmartfetchOptions` extended with `smallModelRef?`, `explorerModel?`, `librarianModel?`.
  - Guard: `src/tools/smartfetch/config-read-guard.test.ts` source-scans `secondary-model.ts` + `tool.ts` and fails on `node:fs`, `node:fs/promises`, `config/loader`, `cli/config-io`, `cli/paths`, `loadPluginConfig`, `getExistingConfigPath`.
  - Behavior parity: resolution order (webfetchModels → small_model → explorer → librarian) and variant-scoped dedupe keys unchanged; dedicated-model `variant` distinguishes dedupe keys (a variant-tagged entry and the plain ref both listed).
- Secondary-model execution itself (unchanged): creates a temp session via `getClient(input)`, disables all tools, prompts with only fetched content, deletes session with 3 retries (500ms apart, 30s timeout).

### 2. User-action — preset management (justified; they rewrite the file)
- `src/tools/preset-switch.ts:168` (`persistPresetName`) and `:189` (`readUserConfig`): read the user plugin config file to persist `preset` / edit `presets` (used by `/preset`, `writePreset`, `deletePreset`). Writes back as plain JSON (JSONC comments lost — documented behavior).
- `src/tui-preset.ts:75,169,235,276`: TUI preset manager calls `loadPluginConfig(state.directory, { silent: true })` whenever the picker opens or edits — needs fresh disk state after edits. User-initiated only.
- NOTE: server-side runtime preset switching does NOT re-read; `setActiveRuntimePreset` has no runtime callers currently (only index.ts:213 clearing stale state).

### 3. Gated — auto-update checker
- `src/hooks/auto-update-checker/checker.ts`: `findPluginEntry` (434-472) + `getLocalDevPath` (345-367) scan all opencode.json paths (user json/jsonc + project `.opencode/`) for the plugin entry/pin, plus package.json walks (`findPackageJsonUp`, `getCachedVersion` with memoization).
- Gated by in-memory `config.autoUpdate ?? true` passed at `src/index.ts:343-344`; hook body checks `if (!autoUpdate)` (`index.ts` of the hook, line 207). Runs once per session start, not per message.
- User's config sets `"autoUpdate": false` → no checks run.

### 4. TUI process (separate process, cannot share server memory)
- `src/tui.ts:298` `readConfigState` → `loadPluginConfig(directory, { silent: true })`: once at TUI startup, re-run only when the working directory changes (`tui.ts:365-368`).
- The 1s `renderTimer` re-reads `readTuiSnapshotAsync` (job-board snapshot under `.oh-my-opencode-slim/` state dir) — runtime state, NOT config.

### 5. CLI-only (install-time, not the running plugin)
- `src/cli/config-io.ts` (`parseConfig`/`parseConfigFile`, addPluginToOpenCodeConfig, getConfiguredExactVersion), `src/cli/config-manager.ts`, cache warm (`warmOpenCodePluginCache`). Only invoked by `opencode oh ...` commands.

## Clean areas (verified no config I/O after construction)

agents/, mcp/, multiplexer/, utils/ (logger reads its own log files), hooks other than auto-update-checker (image-hook existsSync is for image files/save dirs), foreground-fallback, task-session-manager.

## Re-audit one-liner

```bash
rg -n "(readFileSync|parseConfig|parseConfigFile|getExistingConfigPath|loadPluginConfig|findPluginConfigPaths)" src --glob '!*.test.ts'
```
Classify hits as: cli-time / startup / user-action / gated / per-call. Only per-call is a violation.
