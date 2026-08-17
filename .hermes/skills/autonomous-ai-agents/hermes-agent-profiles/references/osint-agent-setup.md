# OSINT Agent — Full Setup Guide (Free-Only)

Create a dedicated Hermes agent for Open-Source Intelligence (OSINT)
investigations. All tools listed here are **100% free** — no API keys,
no pay-per-call backends, no commercial tiers required.

## Free-Only Tool Map

| Category | Tool | Cost | What it does |
|---|---|---|---|
| Username search (deep) | **maigret** 🥇 | 🆓 3000+ sites, no API key | Profile extraction, recursive search, AI summary |
| Username search (broad) | **sherlock** | 🆓 400+ sites, no API key | Cross-platform username discovery |
| Email recon | **holehe** | 🆓 120+ sites, no API key | Check email registration across platforms |
| Email/domain recon | **theHarvester** | 🆓 Free (source install) | Email harvesting, subdomain discovery, name scraping. See install method below — not available via `uv tool install`. |
| Phone number intel | **phoneinfoga** | 🆓 Free basic scan | Carrier, country, line type. Skip this unless you specifically need phone recon — free mode is limited. |
| Instagram content | **instaloader** | 🆓 Free (anonymous or free IG account) | Download posts, stories, highlights, comments |
| Public records | **osint-investigation** | 🆓 Python stdlib only | SEC, OFAC, ICIJ, courts, property, OpenCorporates, news |
| Domain recon | **domain-intel** | 🆓 Python stdlib, no API keys | WHOIS, DNS, SSL certs, subdomains via crt.sh |
| Stealth scraping | **scrapling** | 🆓 Free & open source | Cloudflare bypass, spider crawling, anti-fingerprinting |
| GitHub forensics | **oss-forensics** | 🆓 Free (GitHub API) | Deleted commit recovery, force-push detection, IOC extraction |
| Data broker exposure | **unbroker** | 🆓 Free | Find what data brokers expose about a person (545+ sites) |
| Meta-search | **searxng-search** | 🆓 Free, 70+ engines, no API key | Aggregated search across engines |

## Profile Creation

**Primary: Clone from your main profile** so OSINT inherits your model,
API keys, and existing skills. This is the recommended path:

```bash
# 1. Clone from default (inherits model, API keys, config)
hermes profile create osint --clone
hermes profile alias osint

# 2. Create work directory
mkdir -p ~/Desktop/hermes/osint

# 3. Lock agent to that directory & tune for OSINT
osint config set terminal.cwd ~/Desktop/hermes/osint
osint config set agent.max_turns 200
osint config set terminal.timeout 300

# 4. Install official OSINT skills (all free)
osint skills install official/research/osint-investigation
osint skills install official/security/sherlock
osint skills install official/research/domain-intel
osint skills install official/research/scrapling
osint skills install official/security/oss-forensics
osint skills install official/security/unbroker
osint skills install official/research/searxng-search
```

What cloning gives the OSINT agent:
- ✅ Model config (e.g., `deepseek-v4-flash-free`)
- ✅ API keys (OpenRouter, Anthropic, Exa, etc.)
- ✅ Context compression, display preferences
- ❌ NOT memory or session history — clean slate per profile

**Alternative: Blank profile** if you want a separate config:

```bash
hermes profile create osint
hermes profile alias osint
mkdir -p ~/Desktop/hermes/osint
osint config set terminal.cwd ~/Desktop/hermes/osint
```

Most tools install cleanly via `uv tool install`:
```bash
uv tool install maigret              # 3000+ site username profiling
uv tool install holehe               # email registration check (120+ sites)
uv tool install sherlock-project     # username search (400+ sites) — note: package is "sherlock-project", not "sherlock"
uv tool install instaloader          # Instagram content download
```

**theHarvester exception:** The `uv tool install theHarvester` command installs a
stub (v0.0.1 on PyPI), not the real tool. Install from source:
```bash
mkdir -p ~/Desktop/hermes/osint/tools
git clone https://github.com/laramies/theHarvester.git ~/Desktop/hermes/osint/tools/theHarvester
cd ~/Desktop/hermes/osint/tools/theHarvester && uv sync
# Wrapper script, so "theHarvester" works anywhere:
echo '#!/usr/bin/env bash
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/theHarvester" && uv run theHarvester.py "$@"' > ~/Desktop/hermes/osint/tools/theHarvester.sh
chmod +x ~/Desktop/hermes/osint/tools/theHarvester.sh
ln -sf ~/Desktop/hermes/osint/tools/theHarvester.sh ~/.local/bin/theHarvester
```

## SOUL.md

Save this to `~/.hermes/profiles/osint/SOUL.md`:

```markdown
# OSINT Specialist Agent

You are a professional Open-Source Intelligence (OSINT) specialist.
You operate only from public, legally accessible sources.

## Core Principles
- Every finding must trace back to a verifiable public source
- Distinguish "confirmed," "probable," and "unconfirmed" in all findings
- Never fabricate evidence
- Respect privacy — OSINT is public records, not harassment
- If unsure about legality, flag it

## Tools at your disposal
- **maigret** — username search across 3000+ sites, recursive, extracts profile info
- **sherlock** — social media presence across 400+ platforms
- **osint-investigation** — SEC, USAspending, OFAC sanctions, ICIJ offshore,
  OpenCorporates, CourtListener, ACRIS, Wayback Machine, Wikipedia, GDELT news
- **domain-intel** — WHOIS, DNS, SSL certs, subdomains via crt.sh
- **scrapling** — stealth scraping, Cloudflare bypass, spider crawling
- **holehe** — check email registration on 120+ sites
- **theHarvester** — email harvesting, subdomain discovery (source install)
- **instaloader** — download Instagram profiles, posts, stories
- **phoneinfoga** — phone number intelligence (free basic scan)
- **oss-forensics** — GitHub repo forensics
- **unbroker** — data broker exposure checks
- **web_search/web_extract** — general web recon
- **searxng-search** — meta-search across 70+ engines
```

## Investigation Flow

1. **Username search** — `maigret <username> -a` (3000+ sites, recursive)
2. **Cross-check** — `sherlock --print-found --no-color <username>` (400+ sites)
3. **Instagram content** — `instaloader profile <username>` (posts, bio, stories)
4. **Public records** — osint-investigation scripts (corps, courts, property, sanctions)
5. **Domain recon** — domain-intel if a domain is found
6. **Email recon** — `holehe <email>` if email is discovered (120+ sites)
7. **Stealth scrape** — scrapling for Cloudflare-protected pages
8. **Evidence chain** — entity resolution between sources with confidence levels

## Alternative: One-Liner Setup (Clone + Source-of-Truth)

For setup scripts or a single copy-paste command. Uses `hermes -p` for
PATH-safe script execution and `--clone` to inherit from default profile:

```bash
P="osint"; D="$HOME/Desktop/hermes/$P"; mkdir -p "$D"; \
hermes profile delete "$P" --yes 2>/dev/null; \
hermes profile create "$P" --clone; \
hermes profile alias "$P"; \
hermes -p "$P" config set terminal.cwd "$D"; \
hermes -p "$P" config set agent.max_turns 200; \
hermes -p "$P" config set terminal.timeout 300; \
for s in official/research/osint-investigation official/security/sherlock official/research/domain-intel official/research/scrapling official/security/oss-forensics official/security/unbroker official/research/searxng-search; do hermes -p "$P" skills install "$s" 2>/dev/null; done; \
uv tool install maigret 2>/dev/null; \
uv tool install holehe 2>/dev/null; \
uv tool install sherlock-project 2>/dev/null; \
uv tool install instaloader 2>/dev/null; \
# Symlink .env for source-of-truth
ln -sf ~/.hermes/.env ~/.hermes/profiles/$P/.env; \
echo "✅ Done — type: $P"
```

Key differences from the interactive approach:
- `--clone` inherits model, API keys, config from default profile
- `hermes -p "$P"` works in non-interactive scripts where `~/.local/bin/` may not be on PATH
- Delete + recreate is idempotent — safe to re-run
- `.env` is symlinked to main so API keys stay in sync

## Config Inheritance / Source-of-Truth

When you have multiple specialized profiles, keep the default profile as the
**source of truth** for shared settings (model, API keys, timeouts) while
each child keeps its own CWD, skills, and SOUL.md.

### Symlink .env (API keys)

Make OSINT's `.env` point to the main profile's `.env` so API keys stay
in sync automatically:

```bash
ln -sf ~/.hermes/.env ~/.hermes/profiles/osint/.env
```

**Path note:** There is no `profiles/default/` directory — the main agent's
secrets live at `~/.hermes/.env` (not `config.yaml.env`).

### Install hermes-sync (config propagation)

The `hermes-sync` command pushes the default profile's `config.yaml` to all
children while preserving each child's **full terminal block** (backend, cwd, timeout, docker image):

```bash
cat > ~/.local/bin/hermes-sync << 'SYNC'
#!/usr/bin/env bash
set -euo pipefail
MAIN="$HOME/.hermes/config.yaml"
[ -f "$MAIN" ] || { echo "❌ Main config not found at $MAIN"; exit 1; }
echo "🔄 Syncing main profile config to all children..."
for p in "$HOME/.hermes/profiles/"*/; do
  NAME="$(basename "$p")"
  [ "$NAME" = "default" ] && continue
  CHILD="$p/config.yaml"
  [ -f "$CHILD" ] || continue
  # Save child's full terminal: block before overwriting (macOS-compatible)
  TERMINAL_BLOCK=$(awk '/^terminal:/{flag=1; next} /^[a-z]/{flag=0} flag' "$CHILD" || echo "")
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
  CHILD_ENV="$p/.env"
  if [ ! -L "$CHILD_ENV" ] && [ -f "$CHILD_ENV" ]; then
    mv "$CHILD_ENV" "$CHILD_ENV.bak" 2>/dev/null || true
    ln -sf "$HOME/.hermes/.env" "$CHILD_ENV" 2>/dev/null || true
  fi
done
echo "✅ All profiles synced"
SYNC
chmod +x ~/.local/bin/hermes-sync
```

### Workflow

```bash
# 1. Change something in default profile
hermes config set terminal.timeout 300

# 2. Push to all children
hermes-sync

# 3. Each child keeps its own terminal settings (backend, CWD, timeout, docker image)
```

## Verification

```bash
# Check the profile
hermes profile list
osint doctor
osint skills list

# Check source-of-truth
readlink ~/.hermes/profiles/osint/.env        # should point to ~/.hermes/.env
hermes-sync                                    # push latest config from main

# Test tools
maigret --version
sherlock --version
holehe --help

# Start the agent
osint
```
