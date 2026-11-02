# Kanban Toolset Gating — Why `hermes tools enable kanban` Fails

Verified: Hermes v0.21.0 (2026.8.31), 2026-09-01.

## Symptom

```
$ hermes tools list          # kanban not listed
$ hermes tools enable kanban
✗ Unknown toolset 'kanban'
```

Docs and `toolsets.py:TOOLSETS["kanban"]` suggest it should work. It intentionally does not.

## Root cause: three gating layers, only one is `hermes tools`

Kanban has a three-layer enable model. `hermes tools` controls only the *configurable* subset.

| Layer | Where | Default | How to enable | How to disable |
|-------|-------|---------|---------------|----------------|
| **1. Board** | `~/.hermes/kanban.db` (+ `~/.hermes/kanban/boards/<slug>/kanban.db` for multi-board) | absent | `hermes kanban init` (idempotent) | `hermes kanban boards rm <slug> --delete` or `hermes kanban gc` |
| **2. Dispatcher** | `kanban.dispatch_in_gateway` in `config.yaml` | `true` | `hermes config set kanban.dispatch_in_gateway true` + `hermes gateway restart` | `hermes config set kanban.dispatch_in_gateway false` |
| **3. Toolset** | `toolsets.py:_HERMES_CORE_TOOLS` + `tools/kanban_tools.py:check_fn` | gated off | see below | automatic |

## Why layer 3 is not in `hermes tools`

* `toolsets.py:31` — 14 tools (`kanban_show`, `kanban_list`, `kanban_complete`, `kanban_block`, `kanban_request_review`, `kanban_request_changes`, `kanban_heartbeat`, `kanban_comment`, `kanban_create`, `kanban_link`, `kanban_unblock`, `kanban_attach`, `kanban_attach_url`, `kanban_attachments`) are in `_HERMES_CORE_TOOLS`.
* `toolsets.py:297` — `TOOLSETS["kanban"]` exists with those 14 tools, gated via `check_fn` in `tools/kanban_tools.py:52` (`_check_kanban_mode` / `_check_kanban_orchestrator_mode`).
* `hermes_cli/tools_config.py:CONFIGURABLE_TOOLSETS` — the checklist that `hermes tools` renders — deliberately omits `"kanban"`. Only toolsets in that list appear in `hermes tools list` and accept `enable/disable`. Kanban plus other `check_fn`-gated toolsets (e.g. `computer_use`) are excluded by design.
* `hermes_cli/tools_config.py:_checklist_toolset_keys()` confirms: it filters `CONFIGURABLE_TOOLSETS` by platform; non-configurable toolsets are never offered.

Result: `kanban` is a real toolset in the code but an *unknown* toolset to the configurator — expected behavior, not a bug.

## How `check_fn` gates it (`tools/kanban_tools.py:103`)

```python
def _check_kanban_mode() -> bool:
    # True only if:
    # 1. HERMES_KANBAN_TASK env is set (dispatcher-spawned worker), OR
    # 2. profile's platform_toolsets contains "kanban"
```

* **Worker**: dispatcher (`kanban.dispatch_in_gateway: true`, sweeps every `kanban.dispatch_interval_seconds: 60`) spawns each worker with `HERMES_KANBAN_TASK=<id>` + `HERMES_KANBAN_BOARD=<slug>`. Worker gets `kanban_show/complete/block/heartbeat/comment/create/link/attach*` automatically — no config needed. `kanban_list` and `kanban_unblock` require orchestrator mode.
* **Orchestrator**: a normal profile that needs `kanban_list`/`kanban_unblock` (board routing) must explicitly opt in via `platform_toolsets` (see workaround).
* **Normal session**: `check_fn` returns False → zero kanban tools in schema, even though they are in `_HERMES_CORE_TOOLS`. This keeps the schema clean; `delegate_task` docs call this the "narrow waist".

Additional block: `tools/delegate_tool.py:1380` adds `kanban` to `blocked_toolset_names` for leaf `delegate_task` subagents — a delegated child cannot mutate kanban even if parent had it.

## Workaround for orchestrator profiles

`hermes tools` cannot add it — edit `config.yaml` directly:

```bash
hermes config get platform_toolsets   # inspect current
# Add "kanban" to the desired platform's array, preserve existing entries:
hermes config set platform_toolsets.cli '["web","terminal","file","todo","memory","kanban"]'
# Verify:
hermes config get platform_toolsets.cli
# Effects apply on next session only (/reset or new hermes chat):
hermes config check
```

Gate still applies: `kanban_list`/`kanban_unblock` are further gated by `_check_kanban_orchestrator_mode` — only profiles with `kanban` in toolsets get them.

## Debugging checklist

1. `hermes kanban --help` — board exists? `hermes kanban list` should not error.
2. `hermes config get kanban` — check `dispatch_in_gateway`, `dispatch_interval_seconds`, `failure_limit`.
3. `grep -n kanban ~/.hermes/config.yaml` — is `"kanban"` in any `platform_toolsets.<platform>`?
4. `HERMES_KANBAN_TASK=1 hermes --help` vs plain `hermes --help` — compare tool count to confirm `check_fn` behavior.
5. `python3 -c "from tools.kanban_tools import _check_kanban_mode; print(_check_kanban_mode())"` in a fresh process (bypass 30s `check_fn` cache).

## When to document vs fix

Do not add `kanban` to `CONFIGURABLE_TOOLSETS` — exclusion is intentional to prevent users toggling a dispatcher-coupled toolset out of context. If the UX needs changing, propose it in `docs/hermes-kanban-v1-spec.pdf` discussion, not a direct `tools_config.py` edit.
