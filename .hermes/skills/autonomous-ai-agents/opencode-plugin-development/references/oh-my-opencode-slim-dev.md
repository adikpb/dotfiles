---
name: oh-my-opencode-slim-dev
description: Use when working in the oh-my-opencode-slim plugin repo.
---

# oh-my-opencode-slim plugin development

The user's own OpenCode plugin (fork `adikpb/oh-my-opencode-slim`, upstream `alvinunreal/oh-my-opencode-slim`, many merged PRs). Runs from a local dev path (`./plugins/oh-my-opencode-slim/src/index.ts`) in their opencode.json. Working repo lives at `~/dotfiles/.config/opencode/plugins/oh-my-opencode-slim/`.

## Config architecture (the important part)

- **Single read point**: `loadPluginConfig(directory)` in `src/config/loader.ts` reads the plugin config files once. The merged result lives ONLY in the closure variable `config` declared at `src/index.ts:144`, assigned at `src/index.ts:197`. Every subsystem (agents, hooks, tools, mcps, multiplexer, fallback manager) gets its values from this object at construction time.
- **IN-FLIGHT (Aug 2026): unified RuntimeConfig interface.** Branch `feat/runtime-config-interface` refactors the closure-only world: new `src/config/runtime.ts` (per-process singleton, `Map<directory>` registry, `init`/`get`/`reset`, typed getters wrapped around the merged plugin config, static `isCacheSafe` marker), host snapshot captured in the `config` hook **at entry, before any mutation**, runtime overrides via `setRuntimePreset`/`getRuntimePreset`. Consumers migrate from the closure `config` to runtime getters; `src/config/runtime-preset.ts` is deleted (its state folds into RuntimeConfig, incl. `getPreviousRuntimePreset` = dead code). TUI (`src/tui.ts`) and CLI (`src/cli/*`) keep using the loader directly (separate processes). Verify what has landed via `git log` on that branch before assuming the newer `runtime.ts` exists on master. Update this section after the PR merges.
- **File sources**: user config via `getConfigSearchDirs()` (`oh-my-opencode-slim.{jsonc,json}`, jsonc preferred) + project config `<dir>/.opencode/oh-my-opencode-slim.{jsonc,json}` (project deep-merges over user). JSONC comments stripped, `{env:VAR}` interpolated, preset merged into `agents`, `OH_MY_OPENCODE_SLIM_PRESET` env overrides `preset`, deprecation warnings for legacy `tmux`, `council.master`, `fallback.*`.
- **Runtime preset state**: `src/config/runtime-preset.ts` module-level singleton survives plugin re-init (Instance.dispose → factory rerun). `src/index.ts:203-214` re-merges the persisted runtime preset into `config.agents` and clears stale names.
- **Host `opencode.json` is NOT read by the server plugin**: the plugin's `config` hook (`src/index.ts:629`) receives the already-parsed object from OpenCode and mutates it in memory only.
- **TUI process is separate**: `src/tui.ts` (loaded via `tui.json`) reads its own config copy at startup via `readConfigState`, and re-validates only when the working directory changes. The 1s render timer re-reads the `.oh-my-opencode-slim/` snapshot file (job state), NOT config.

## Disk re-read audit (verified against current master)

Invariant that holds: config is read once at startup and served from memory. Known exceptions, in order of severity:

1. **FIXED (was the hot offender)**: smartfetch secondary-model resolution no longer touches disk per call. `resolveSecondaryModels(input)` in `src/tools/smartfetch/secondary-model.ts` is a pure in-memory builder; `small_model` is captured once from the host's merged `opencodeConfig` inside the plugin `config` hook and passed via `smallModelRef`; explorer/librarian model ids are resolved from in-memory `config.agents` at `createWebfetchTool` time (index.ts uses exported `pickAgentModelRef`). Enforced by `src/tools/smartfetch/config-read-guard.test.ts`, which source-scans `secondary-model.ts` + `tool.ts` and fails on any `node:fs` / `config/loader` / `cli/paths` import. Do not re-introduce disk reads there without updating the guard.
2. **User-action re-reads (justified, they rewrite the file)**: `src/tools/preset-switch.ts` (`/preset` + `writePreset`/`deletePreset`) and `src/tui-preset.ts` (preset manager picker, calls `loadPluginConfig` on open) — keep as-is.
3. **Gated startup re-read**: `src/hooks/auto-update-checker/` scans all `opencode.json` paths (`findPluginEntry`/`getLocalDevPath`) when a check runs. Gated by the in-memory flag `config.autoUpdate ?? true` (index.ts). User's config sets `"autoUpdate": false`, so no checks run.

Everything else (agents/, mcp/, multiplexer/, utils/, most hooks/) does NO config-file I/O after construction. `loadAgentPrompt` reads `.md` prompt files from `oh-my-opencode-slim/` dirs only at init.

## Re-audit recipe

```bash
rg -n "(readFileSync|parseConfig|parseConfigFile|getExistingConfigPath|loadPluginConfig|findPluginConfigPaths)" src --glob '!*.test.ts'
```
Classify each hit: CLI install-time (`src/cli/config-io.ts`, config-manager, cache warm), startup (index.ts:197, tui.ts:298), user-action (preset-switch, tui-preset), gated (auto-update-checker), or per-call (should be NONE now — smartfetch is guarded by `config-read-guard.test.ts`).

## Contribution workflow (user's established pattern)

- Work in the local repo at `~/dotfiles/.config/opencode/plugins/oh-my-opencode-slim/`; branch from master, never commit to master.
- Verify: `bun run check:ci` → `bun run typecheck` → `bun test` (full suite incl. cache-safety tripwire, snapshots) → `bun run build` (regenerates `oh-my-opencode-slim.schema.json`; expect no diff when the schema is unchanged).
- Open the PR against upstream from the fork:
  `gh pr create --repo alvinunreal/oh-my-opencode-slim --head adikpb:<branch> --base master --title "..." --body "..."`
- Docs live update requirement per AGENTS.md: when behavior changes, sync `docs/` (e.g. `docs/webfetch.md` for smartfetch model resolution) and note it in the PR.

## Build & verify

`bun run check:ci` (lint+format+imports), `bun run typecheck`, `bun test`, `bun run build`. Single test: `bun test -t "pattern"`. Per AGENTS.md read `codemap.md` first; cache-safety tests are sensitive to prompt-surface changes — never reorder/rewrite early messages; inject only through `src/hooks/cache-safe-injection.ts`.

## User environment shortcuts

- Live configs live in `~/dotfiles/.config/opencode/` (real files), symlinked into `~/.config/opencode/`. Edit the dotfiles paths; read through the symlinks.
- Their `oh-my-opencode-slim.json`: preset `"free"` (models deepseek-v4-flash-free / mimo-v2.5-free), `disabled_agents: ["designer","council"]`, `autoUpdate: false`, `disabled_mcps: ["websearch"]`, `multiplexer.type: "auto"`.
- `opencode.json` loads 5 plugins incl. the local dev path; disables build/explore/general/plan agents; permission allowlist for bash.

See `references/plugin-config-audit.md` for the file:line detail of the full config read map and the smartfetch resolution order.