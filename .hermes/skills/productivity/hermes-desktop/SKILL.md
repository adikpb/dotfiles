---
name: hermes-desktop
description: "Theme Hermes and write desktop UI plugins."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [desktop, themes, plugins, ui, skins]
    related_skills: [hermes-agent]
---

# Hermes desktop customization

Author a Hermes **skin** (one YAML that themes CLI, TUI, and desktop) and write **desktop plugins** (plain-JS ESM that add panes, statusbar items, commands, keybinds, routes). No app rebuild. Skins live in `<hermes-home>/skins/`; plugins live in `<hermes-home>/desktop-plugins/`.

Absorbed from: `hermes-themes`, `hermes-desktop-plugins`.

## When to Use

- "Make me a synthwave theme", match brand colors, iterate a palette live
- Add a desktop pane, statusbar widget, command-palette command, or route without modifying the app

Don't use for: Hermes CLI/gateway Python plugins (load `hermes-source-development`); named agent profiles (`hermes-agent-profiles`).

## Prerequisites

- Write access to `$HERMES_HOME` (usually `~/.hermes`, or the active profile dir).
- Desktop plugins require the Hermes desktop app (CLI/gateway alone will not load `plugin.js`).
- Native tools: `write_file`, `read_file`, `search_files`, `terminal` (`hermes config set`).

## Skins (themes)

1. Pick a lowercase hyphenated `name` (e.g. `synthwave`).
2. Copy `templates/skin.yaml` and fill every key — missing keys inherit `default`.
3. `write_file` to `<hermes-home>/skins/<name>.yaml`.
4. Activate: `hermes config set skin <name>` (confirm with `hermes config get skin`).
5. Edit and save — every surface repaints. No reload step.

Theming is semantic hex (`#rrggbb`). Full key map and pitfalls: `references/hermes-themes.md`.

## Desktop plugins

1. Create `$HERMES_HOME/desktop-plugins/<id>/plugin.js` from `templates/plugin.js`. Keep directory name equal to plugin `id`.
2. The desktop app watches the directory: the file loads within a few seconds; later saves hot-reload. Fallback: ⌘K → **Reload desktop plugins**.
3. A plugin can talk to its own Python backend namespace (`ctx.rest` / `ctx.socket` → `/api/plugins/<id>`). The general Python plugin system (`~/.hermes/plugins/`) is separate — see `hermes-source-development`.

Full SDK orientation (exports, area payloads, security): `references/hermes-desktop-plugins.md`. Human reference in the Hermes repo: `website/docs/developer-guide/desktop-plugin-sdk.md`.

## Pitfalls

- Missing skin keys silently inherit `default` — copy the full template.
- Plugin directory name must match `id` or the app will not bind commands/routes.
- Desktop plugins are not Hermes Agent Python plugins. Do not drop `plugin.js` in `~/.hermes/plugins/`.
- Profile-scoped Hermes homes use `~/.hermes/profiles/<name>/` for skins and desktop-plugins.

## Verification

- Skin: `hermes config get skin` equals the file stem; CLI/TUI/desktop share the palette.
- Plugin: it appears in the command palette within a few seconds of the file landing; a save hot-reloads without a restart.
