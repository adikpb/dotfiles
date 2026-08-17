---
name: opencode-team
description: Use when using OpenCode.
version: 0.3.2
author: Hermes
license: MIT
platforms: [macos]
metadata:
  hermes:
    tags: [OpenCode, oh-my-opencode-slim, Agents]
    related_skills: [opencode]
---

# OpenCode Team (oh-my-opencode-slim)

## Overview

This skill documents how OpenCode is configured on this machine and how to use
it effectively. OpenCode runs the oh-my-opencode-slim plugin: an Orchestrator
plans work, dispatches specialists (Explorer, Librarian, Oracle, Fixer) as
background tasks, reconciles results, and verifies output. It does NOT cover
generic OpenCode CLI mechanics (flags, sessions, `opencode run`); load the
`opencode` skill for those.

All config lives in dotfiles, symlinked into `~/.config/opencode/`.

## When to Use

- Use for coding tasks routed to the opencode agent team
- Don't use for: generic opencode CLI mechanics (that's the `opencode` skill)

## Prerequisites

- OpenCode installed; config symlinked from dotfiles into `~/.config/opencode/`
  (oh-my-opencode-slim registered in `opencode.json` as
  `./plugins/oh-my-opencode-slim/src/index.ts`)
- Auth: `opencode auth login` (opencode-zen free models need an API key, no balance)

## How to Run

Start the TUI through the `terminal` tool (pty required), then submit prompts:

```
terminal(command="opencode", workdir="<project>", background=true, pty=true)
process(action="submit", session_id="<id>", data="<prompt or @agent task>")
process(action="poll"|"log", session_id="<id>")
```

## Current Setup

`opencode.json` registers oh-my-opencode-slim plus background-only plugins
(opencode-dcp, cc-safety-net, caffeinate, handoff); built-in `explore` and
`general` agents are disabled, and bash runs on an allowlist (git, grep/rg/awk,
ls/head/tail/wc, stat/date, python3/.venv/bin/python, pytest, ruff; everything
else asks). `oh-my-opencode-slim.json` runs `preset: "free"` (all agents on
free opencode-zen models), with `disabled_agents: ["designer", "council"]` and
`disabled_mcps: ["websearch"]` (the built-in websearch tool covers that).
Layering: user config is the base, project-local
`.opencode/oh-my-opencode-slim.json` overrides it; runtime `/model` changes
only the orchestrator (the foreground session), specialists keep their preset
models.

## Quick Reference

| Command | Effect |
|---------|--------|
| `run codemap` | Build/refresh hierarchical `codemap.md` maps |
| `/deepwork <task>` | Structured multi-phase workflow with Oracle review gates |
| `work in a worktree` | Isolated `.slim/worktrees/<slug>/` coding lane |
| `@oracle <task>` | Architecture review, hard debugging, code review, simplification |
| `@fixer <task>` | Bounded implementation with clear scope, no research |
| `@explorer <task>` | Read-only codebase recon (grep/glob/AST), compressed map back |
| `@librarian <task>` | External docs / library research (context7 + gh_grep MCPs) |
| `@observer <task>` | Read-only visual analysis of images, screenshots, PDFs, diagrams |
| `clone dependencies` | Mirror deps into `.slim/clonedeps/repos/` |
| `/reflect` | Suggest reusable skills/config from repeated friction |
| `/reflect --sessions [--last N]` | Cross-session archaeology over past OpenCode sessions (default 50) |
| `verification-planning` | Automatic pre-work plan before non-trivial tasks |
| `tune my setup` | oh-my-opencode-slim skill; adjust plugin behavior |
| `ask oracle to simplify` | simplify skill; Oracle cleans up recent changes |

## Procedure

1. Start OpenCode in the project dir (`terminal` with `background=true, pty=true`).
2. Give the Orchestrator a high-level goal; it plans, dispatches background
   specialists, and reconciles. Do not over-specify and do NOT route manually:
   the orchestrator owns the work graph and assigns specialists itself.
   `@agent <task>` manual routing is optional, for when you want to force a
   specific specialist.
3. For heavy work, invoke `/deepwork <task>` (phased plan with declared Oracle
   review gates) or ask for a worktree lane for risky/parallel changes.
4. For unfamiliar codebases, ask the orchestrator to `run codemap` first.
5. Track progress with `process(action="poll"|"log")`.
6. Exit the TUI with Ctrl+C (`process(action="write", data="\x03")`), never `/exit`.

## Pitfalls

- `designer` and `council` are disabled here; `@council` / `@designer` fail or
  are missing. Route design review and multi-perspective questions to
  `@oracle` instead.
- Thinking control: `/thinking` only toggles the VISIBILITY of thinking blocks,
  not thinking itself. Disable via agent `options`: `reasoningEffort: "none"`
  (openai-compatible) or `thinking: { type: "disabled" }` (anthropic-style).
- `websearch` MCP is disabled; the built-in `websearch` tool (Exa-backed, no
  API key on the OpenCode provider) covers it.
- Config edits (presets, disabled agents, MCPs, skills) require an OpenCode restart.

## Verification

To diagnose agent issues, run `ping all agents` inside a session; every
configured agent (orchestrator, oracle, librarian, explorer, fixer, observer)
should respond. For config sanity: `ls -la ~/.config/opencode/` should show
the dotfiles symlinks.
