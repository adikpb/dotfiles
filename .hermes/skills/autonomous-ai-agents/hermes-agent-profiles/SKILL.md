---
name: hermes-agent-profiles
description: "Create and manage specialized Hermes agent profiles — directory locking, skills, SOUL.md, and CLI tool setup. uv-only for Python tools."
version: 1.3.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [hermes, profiles, multi-agent, setup, configuration, osint]
    related_skills: [hermes-agent]
---

# Hermes Agent Profiles — Specialized Agents

Create multiple independent Hermes agents on the same machine, each locked
to a specific directory with its own skills, personality, and tools.

**Core principle:** The default profile is your main "generalist" agent.
Named profiles are specialists — focused, directory-scoped, and purpose-built.

## When to Use

Use this skill when the user asks to:

- Create a specialized Hermes agent for a specific task (OSINT, coding, research, etc.)
- Lock an agent to a specific project directory
- Set up multiple agents with different skills, personalities, or tools
- Configure an agent that auto-starts in a specific working directory
- Install CLI tools for an agent (via `uv tool install`, never pipx)

## Creating a Specialized Agent Profile

### Quick-start: `create-agent` script

The fastest way to create a new agent:

```bash
bash ~/.hermes/skills/autonomous-ai-agents/hermes-agent-profiles/scripts/create-agent coder "Web Developer Agent"
```

It clones from your main profile, creates `~/Desktop/hermes/<name>/`, locks CWD,
symlinks `.env`, and prompts for a SOUL.md. See `scripts/create-agent` for details.

### Manual creation step-by-step

### 1. Create the profile

**Preferred: Clone from the default/main profile** so the child inherits your
model config, API keys, personality, and existing skills:

```bash
hermes profile create <name> --clone
```

This copies everything from your default profile (config, secrets, skills, SOUL.md)
but NOT memory or session history — each child starts with a clean investigation log.

Then create the shell wrapper so you can type `<name>` instead of `hermes -p <name>`:

```bash
hermes profile alias <name>
```

What you get:
- `~/.hermes/profiles/<name>/` — fully isolated config, memory, sessions
- `~/.local/bin/<name>` — standalone command wrapping `hermes -p <name>`
- Inherited model, API keys, and skills from your main profile

**Alternative: Create blank.** If you want a clean slate with no inherited config:

```bash
hermes profile create <name>   # blank profile
hermes profile alias <name>    # creates ~/.local/bin/<name>
```

**Name it after the role** (e.g., `osint`, `backend`, `research`, `writer`).
Avoid session-specific names like `project-x-analysis`.

**Script-safe creation (for setup scripts):** When writing a setup script,
the bare profile alias command (`"$PROFILE"`) may not be on PATH because
`~/.local/bin/` is often loaded by an interactive shell's rc file, not by
a non-interactive script shell. Use `hermes -p` explicitly instead:

```bash
hermes profile create "$NAME" --clone
hermes profile alias "$NAME"                  # creates ~/.local/bin/<name>
hermes -p "$NAME" config set terminal.cwd "$WORKDIR"   # always works in scripts
```

The alias still gets created for interactive use — but all scripted operations
use the robust `hermes -p` form so they never depend on `~/.local/bin/` being
in the script's PATH.

### 2. Lock it to a directory

```bash
<profile> config set terminal.cwd /absolute/path/to/workdir
```

For example:
```bash
osint config set terminal.cwd /home/you/osint-work
```

Every terminal command in that agent will start from that directory.
The agent's project context files (`.hermes.md`, `AGENTS.md`, etc.) are
resolved relative to this path.

To create the work directory if it doesn't exist:
```bash
mkdir -p /home/you/osint-work
```

### 3. Install skills

Install official skills from the Hermes hub directly into the profile:

```bash
<profile> skills install official/<category>/<skill>
```

Example:
```bash
osint skills install official/research/osint-investigation
osint skills install official/security/sherlock
```

Skills are per-profile — each agent has its own `~/.hermes/profiles/<name>/skills/`.

### 4. Set the agent's personality (SOUL.md)

```bash
cat > ~/.hermes/profiles/<name>/SOUL.md << 'EOF'
# <Role> Agent

You are a [description of role]. [Specific instructions about behavior, style, constraints].

## Key tools
- [Tool 1] — [what it does]
- [Tool 2] — [what it does]

## Rules
- [Rule 1]
- [Rule 2]
EOF
```

`SOUL.md` is loaded every session and sets the agent's identity and constraints.
Keep it focused on behavioral rules — put procedural steps in skills.

### Tool Cost Principles

When recommending tools for a profile (especially OSINT), follow these rules:

1. **Free only.** Recommend only tools that work with zero API keys, no pay-per-call backends, and no commercial tiers. Tools with optional free tiers (rate-limited) are acceptable if the core functionality works without payment.
2. **Name the cost.** In any tool recommendation, note whether it requires API keys or payment. If a tool requires a paid tier, exclude it and find a free alternative.
3. **Prefer Python stdlib tools.** Skills like `osint-investigation` and `domain-intel` use Python stdlib only — zero dependencies, zero API keys, works everywhere.

Tools that are NOT acceptable for OSINT recommendations (require paid API):
- `insto` / HikerAPI — pay-per-call
- Shodan — paid API key for most features
- PhoneInfoga advanced scanners — paid
- Amass — paid API rate limits
- osint-mcp MCP server — bundles tools needing paid keys

## 5. Install CLI tools (uv only, NEVER pipx)

All Python CLI tools must be installed via `uv tool install`:

```bash
uv tool install <package-name>
```

**Never use `pipx`.** The user's standard is `uv` for all Python tool installations.
This applies to: `uv tool install` (isolated CLI tools) and `uv pip install`
(library deps in an active virtualenv).

Examples:
```bash
uv tool install sherlock-project       # OSINT username search (400+ sites)
uv tool install maigret                # Deep username profiling (3000+ sites, free, no API key)
uv tool install holehe                 # Email registration check (120+ sites, free)
uv tool install instaloader            # Instagram content download (free, anonymous or free account)
```

**⚠️ theHarvester exception:** `uv tool install theHarvester` does NOT work — the PyPI package (v0.0.1) is a stub, not the real tool. Install from source:
```bash
git clone https://github.com/laramies/theHarvester.git ~/tools/theHarvester
cd ~/tools/theHarvester && uv sync
# Create a wrapper so "theHarvester" works anywhere:
echo '#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/theHarvester" && uv run theHarvester.py "$@"' > ~/tools/theHarvester.sh
chmod +x ~/tools/theHarvester.sh
ln -sf ~/tools/theHarvester.sh ~/.local/bin/theHarvester
```

### 6. Verify the agent works

```bash
<profile> doctor           # Check config, dependencies, tools
<profile> skills list      # Confirm skills are installed
<profile>                  # Start the agent
```

## Managing Profiles

```bash
hermes profile list              # Show all profiles
hermes profile use <name>        # Set as sticky default
hermes profile rename <old> <new> # Rename (updates alias + service)
hermes profile alias <name>      # Regenerate the shell wrapper
hermes profile alias <name> --name <custom>  # Custom alias name
hermes profile alias <name> --remove         # Remove the wrapper
hermes profile delete <name>     # Delete profile + alias + service
```

## Running Agents Simultaneously

Open separate terminals:

```bash
# Terminal 1 — main agent
hermes

# Terminal 2 — specialized agent in its own directory
osint

# Terminal 3 — another specialist
research
```

For git repos where agents might edit the same files, use `--worktree` (`-w`):

```bash
osint -w   # Isolated git worktree, no branch conflicts
```

## Gateways Per Profile

Each profile runs its own gateway with its own bot token:

```bash
<profile> gateway start              # Start that profile's gateway
<profile> gateway install            # Create systemd/launchd service
```

Configure different bot tokens in each profile's `.env`:
```bash
nano ~/.hermes/profiles/<name>/.env
```

## Example: OSINT Agent Setup

See `references/osint-agent-setup.md` for the full OSINT agent configuration,
including which skills and tools to install and a ready-made `SOUL.md`.

## Config Inheritance / Source-of-Truth

When you have multiple specialized profiles, you want the **default profile**
to be the source of truth for shared settings (model, API keys, timeouts)
while each child keeps its own working directory, skills, and personality.

### Step 1: Symlink the .env (API keys)

Replace each child's `.env` with a symlink to the main profile's `.env`.
Now API keys are always identical across all profiles:

```bash
ln -sf ~/.hermes/.env ~/.hermes/profiles/<child>/.env
```

**Path note:** There is no `profiles/default/` directory — the main agent's
config lives at the top level (`~/.hermes/config.yaml`) and its secrets
live at `~/.hermes/.env` (not `config.yaml.env`).

### Step 2: Install `hermes-sync` (config propagation)

The `hermes-sync` command pushes the default profile's `config.yaml` to all
children while preserving each child's **full terminal block** (backend, cwd, timeout, docker image):

```bash
cat > ~/.local/bin/hermes-sync << 'SYNC'
#!/usr/bin/env bash
# hermes-sync — push main profile config to all child profiles
# Preserves terminal.cwd and .env symlink per child
set -euo pipefail

MAIN="$HOME/.hermes/config.yaml"
[ -f "$MAIN" ] || { echo "❌ Main config not found at $MAIN"; exit 1; }

echo "🔄 Syncing main profile config to all children..."
for p in "$HOME/.hermes/profiles/"*/; do
  NAME="$(basename "$p")"
  [ "$NAME" = "default" ] && continue
  # Note: there is no profiles/default/ — main config lives at ~/.hermes/config.yaml
  CHILD="$p/config.yaml"
  [ -f "$CHILD" ] || continue

  # Save child-only settings before overwriting
  TERMINAL_BLOCK=$(awk '/^terminal:/{flag=1; next} /^[a-z]/{flag=0} flag' "$CHILD" || echo "")

  # Copy main config
  cp "$MAIN" "$CHILD"
  echo "   ✓ $NAME"

  # Restore child's full terminal block (backend, cwd, timeout, docker image)
  if [ -n "$TERMINAL_BLOCK" ]; then
    LINE=$(grep -n '^terminal:' "$CHILD" | head -1 | cut -d: -f1)
    if [ -n "$LINE" ]; then
      END=$(tail -n +$((LINE+1)) "$CHILD" | grep -n '^[a-z]' | head -1 | cut -d: -f1)
      [ -z "$END" ] && END=$(wc -l < "$CHILD")
      END=$((LINE + END - 1))
      (head -n $((LINE-1)) "$CHILD"; echo "terminal:"; echo "$TERMINAL_BLOCK"; tail -n +$((END+1)) "$CHILD") > "$CHILD.tmp"
      mv "$CHILD.tmp" "$CHILD"
    fi
  fi

  # Ensure .env symlink still points to main
  CHILD_ENV="$p/.env"
  if [ -L "$CHILD_ENV" ]; then
    :
  elif [ -f "$CHILD_ENV" ]; then
    mv "$CHILD_ENV" "$CHILD_ENV.bak" 2>/dev/null || true
    ln -sf "$HOME/.hermes/.env" "$CHILD_ENV" 2>/dev/null || true
  fi
done
echo "✅ All profiles synced"
SYNC
chmod +x ~/.local/bin/hermes-sync
```

### Workflow

1. Make a change in your default profile (e.g., switch model, update timeout)
2. Run `hermes-sync` — all children get the change
3. Each child keeps its own terminal settings (backend, CWD, timeout, docker image)
4. Each child's `.env` still symlinks to default

### When to use

- After changing model/provider in default config
- After updating terminal timeout or max turns
- After changing context compression settings
- NOT needed for child-specific changes (skills, SOUL.md, CLI tools)

### Alternative: Full symlink (one-time, automatic)

If all profiles can share the same `terminal.cwd`:

```bash
ln -sf ~/.hermes/config.yaml ~/.hermes/profiles/<child>/config.yaml
ln -sf ~/.hermes/config.yaml.env ~/.hermes/profiles/<child>/.env
```

Change the main file, children see it instantly. But `terminal.cwd` will be
identical across all profiles — no per-child work directories.

1. **Using pipx instead of uv.** The user standard is `uv tool install` for all Python CLI tools. Never suggest pipx.

2. **Forgetting to lock the directory.** A profile without `terminal.cwd` starts in whatever directory Hermes was launched from, not the intended project directory. Always set `terminal.cwd` explicitly.

3. **Installing skills in the wrong profile.** `hermes skills install` installs into the active/default profile. Use `<profile> skills install` to target a specific profile.

4. **Confusing profiles with sandboxes.** Profiles isolate Hermes state (config, sessions, memory, skills) but do NOT sandbox filesystem access. The agent can still read/write anywhere. Directory locking only sets the starting working directory.

5. **Not setting SOUL.md for full contextual guidance.** Without a SOUL.md, the profile inherits the default personality. For a specialist agent, always provide a SOUL.md that defines its role, constraints, and key tools.

6. **Using bare profile alias in setup scripts.** In a script (non-interactive shell), `~/.local/bin/` may not be on PATH, so `"$PROFILE"` would fail. Always use `hermes -p "$PROFILE"` in scripts. See "Script-safe creation" above.

7. **Assuming `~/.local/bin/` is on PATH in scripts.** Non-interactive shells (scripts) often don't source shell rc files, so `~/.local/bin/` may not be on PATH. Use `hermes -p "$NAME"` in scripts, not `"$NAME"`.

8. **Creating blank profiles from scratch.** Without `--clone`, a new profile has no API keys, no model config, no skills. Always prefer `hermes profile create <name> --clone` unless you specifically want a clean slate.

9. **Not symlinking .env for child profiles.** Each profile has its own `.env`. If you set API keys only in the default profile, child profiles won't have them unless you either clone on creation or symlink the `.env` file. The `hermes-sync` command automatically re-checks this.

10. **Installing theHarvester via `uv tool install`.** The PyPI package `theHarvester` (v0.0.1) is a stub, not the real tool. Must clone from GitHub + `uv sync`. See the OSINT reference for exact steps.

11. **Using GNU-only grep flags in setup scripts.** `grep -oP` (GNU grep) breaks on macOS's BSD grep. Use `grep -E` with portable patterns instead, or `awk` for block extraction as shown in `hermes-sync`.

12. **Only preserving `terminal.cwd` in hermes-sync.** Child profiles may have different `terminal.backend` (local vs docker), different `terminal.timeout`, or different `terminal.docker_image`. Sync must preserve the **entire terminal block**, not just CWD. The `hermes-sync` code above does this via awk block extraction.

13. **hermes-sync reverting `terminal.backend`.** After setting `osint config set terminal.backend local`, running the old `hermes-sync` would clobber it back to docker. Always preserve the full terminal block — the fixed `hermes-sync` handles this.

14. **`terminal.backend` matters per profile.** When cloning the main profile, the child inherits the main's `terminal.backend`. If the main uses `docker` backend but the child's CLI tools are installed on your host (e.g., OSINT tools like maigret/sherlock), the child needs `terminal.backend: local` to access them. Set after creation:

    ```bash
    <profile> config set terminal.backend local
    ```

    The `hermes-sync` script preserves each child's terminal block so this setting survives config syncs.

## Verification Checklist

- [ ] `hermes profile list` shows the new profile
- [ ] `<profile>` command resolves and launches the agent
- [ ] `<profile> config get terminal.cwd` returns the expected absolute path
- [ ] `<profile> skills list` shows the installed skills
- [ ] `~/.hermes/profiles/<name>/SOUL.md` exists with role definition
- [ ] CLI tools installed via `uv tool install` (not pipx)
- [ ] Profile has a descriptive name matching its role (not session-specific)
