# .env File Override Case Study — TERMINAL_ENV in TUI Sessions

## Symptom

In a Hermes TUI session (`display.interface: tui`), the tools `terminal`,
`read_file`, `write_file`, `patch`, and `search_files` were absent.
The `process` tool (same `terminal` toolset, no `check_fn`) was available.
The `execute_code` tool was also available.

## Config State (apparently correct)

```yaml
# ~/.hermes/config.yaml
terminal:
  backend: local          # ← config says local

platform_toolsets:
  cli: [... terminal, file, ...]   # ← both toolsets enabled
```

No `disabled_toolsets`. No `HERMES_TUI_TOOLSETS` env var. The config
bridge set `TERMINAL_ENV=local` at gateway startup (confirmed via
`ps eww -p $(pgrep -f tui_gateway.entry)` which showed
`TERMINAL_ENV=local`).

## The Red Herring: Config Bridge Looks Fine

The `ps` command showed `TERMINAL_ENV=local` in the gateway process's
environment. `check_terminal_requirements()` was tested in a sandbox
(`execute_code`) and returned `True` for local backend. All signs
pointed to a stale check_fn cache or a coding_selection() collapse.

## The Smoking Gun: agent.log

The agent log at `~/.hermes/logs/agent.log` revealed the clue:

```
2026-07-28 14:06:14,133 INFO run_agent: Loaded environment variables from
  ~/.hermes/.env
```

This `.env` file was loaded **after** the config bridge ran. It contained:

```
TERMINAL_ENV=docker
```

This overrode the config bridge's `TERMINAL_ENV=local` inside the Python
process's `os.environ`, but `ps` still showed the *spawn-time* value
(`local`) — creating the illusion that config was correct.

## The Failure Chain

```
Gateway spawn (14:06:13)     →  TERMINAL_ENV=local (from config bridge)
.env loaded (14:06:14.133)   →  TERMINAL_ENV=docker (override)
check_fn call (14:06:18.701) →  env_type="docker"
                              →  find_docker() returns /usr/local/bin/docker
                              →  "docker version" returns exit code 1
                                 (Docker daemon not running on macOS)
                              →  check_terminal_requirements() = False
                              →  cached for 30s → tools locked out
```

All this happened **4 seconds before the first tool definition resolution**.

## Key Diagnostic Steps

1. **Search `agent.log` for `Loaded environment variables`** — this line
   appears at every session startup and names the `.env` file used.

2. **Read `~/.hermes/.env`** — check for `TERMINAL_ENV`, `HERMES_TUI_TOOLSETS`,
   or any env var that could affect tool loading.

3. **Cross-reference timestamps** — the `.env` load always happens before
   the first `check_fn` call. If `.env` overrides a config setting, the
   override is active when checks run.

4. **Do NOT trust `ps` for runtime env** — `ps eww -p PID` shows the
   process's spawn-time environment (the `envp` kernel struct). Python
   `os.environ[key] = value` mutations (from `.env` loading or config
   bridging) are NOT reflected in `ps` output. The agent log is the
   authoritative record of runtime state.

## Root Cause

A `TERMINAL_ENV=docker` line in `~/.hermes/.env` persisted from a prior
session where the user was evaluating Docker backend. It was left behind
and silently overrode the `terminal.backend: local` config on every
subsequent startup.

## Fix

Remove or correct the relevant line in `~/.hermes/.env`:

```bash
sed -i '' '/^TERMINAL_ENV=/d' ~/.hermes/.env        # remove
# or
sed -i '' 's/^TERMINAL_ENV=.*/TERMINAL_ENV=local/' ~/.hermes/.env
```

Fix takes effect on next TUI session startup.
