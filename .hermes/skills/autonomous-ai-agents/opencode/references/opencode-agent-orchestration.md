---
name: opencode-agent-orchestration
description: Use when recovering crashed OpenCode multi-agent sessions.
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos, linux]
metadata:
  hermes:
    tags: [OpenCode, Orchestration, Subagents]
    related_skills: [opencode, opencode-team]
---

# OpenCode Agent Orchestration & Recovery

## When to Use
- Running multi-agent coding workflows with OpenCode and background sub-sessions (`@fixer`, `@explorer`, etc.).
- Handling session crashes, abandoned background subagents, or resuming long-running PR/cleanup campaigns.

## Core Workflows

### 1. Resuming Interrupted Multi-Agent Sessions
When an orchestrator session dies while background fixer subagents are active, the background workers become orphaned and the TUI resume can wedge waiting on dead process locks.
- **Do not** blindly resume the interactive TUI if background tasks were active.
- **Clean up** stale worktree states and dead background worker processes (`pkill -f opencode`).
- **Use persistent serve + attach with auto-approve** to drive runs non-interactively without stalling on permission prompts:
  ```bash
  opencode serve --port 4199 &
  opencode run -s <session_id> --attach http://localhost:4199 --auto "<prompt>"
  ```

### 2. Preventing Permission Stalls in Autonomous Runs
- Non-interactive `opencode run` aborts or stalls on permission dialogs (e.g. executing git or build tools not explicitly in the allowlist).
- **Pitfall:** `--auto` does **not** auto-approve `external_directory` access attempts (e.g. running scratch checks or tools referencing paths outside the repo root like `/tmp/*`). Always keep worktrees strictly self-contained or perform gates manually.
- Always pre-configure allowed bash commands in `opencode.json`.

### 3. Preserving Prompts and State
- For multi-step campaigns (e.g. 4 distinct cleanup PRs), save detailed prompts and recovery plans in a durable markdown file (e.g. `~/oh-my-opencode-pr-prompts.md`) before executing, so interruptions never lose task state.

### 4. Run Exiting Before Background Subagents Finish
- `opencode run` exits when its parent turn completes — a dispatcher/todo prompt that says "dispatch lanes, reconcile later" ends the run with EXIT 0 while background subagent lanes are still working. Their final reports NEVER reach the run output or the parent session.
- **Pitfall:** a clean exit code is not evidence the audit/report completed. If the last transcript lines show lanes still running, the deliverable is missing.
- **Recover lane evidence from the SQLite store** (`~/.local/share/opencode/opencode.db`, tables `session` (id, title, time_created), `message` (id, session_id, role, time_created, data JSON), `part` (message_id, data JSON — `type: 'text'` carries text, tool outputs are separate part types)):
  ```sql
  SELECT id, title FROM session WHERE time_created >= 1786... ORDER BY time_created; -- find subagent lanes
  SELECT id, data FROM message WHERE session_id='ses_...' ORDER BY time_created;   -- lane turns
  SELECT data FROM part WHERE message_id IN (SELECT id FROM message WHERE session_id='ses_...');
  ```
  Lane sessions are titled with the subagent name (search `title LIKE '%subagent%'` or filter by creation window). Their gathered evidence (read_file/tool outputs) survives in `part` rows even when no final summary was ever written.
- **Prefer single-turn self-contained prompts**: when you need a verified report back from `opencode run`, phrase the goal so the agent must complete and answer in ONE turn (no task-list/dispatch pattern). Or inspect the DB, never trust the run's word alone.

### 5. Prevention That Works (validated recipe)
The strongest lever is a hard constraint block at the very top of the prompt — explicitly overriding the orchestrator's default dispatch-reflex (it defaults to planner+spawn-lanes, and without the block the run exits at a lane-wait). Both runs that carried this block completed; both identical tasks without it died at a lane-wait. Verbatim block:

```
HARD CONSTRAINT: Do NOT spawn background subagents or explorer lanes. Do NOT
parallelize. Do NOT block on wait_for_user or any out-of-band input. Work
directly and sequentially in this single session from start to finish. The
previous run died because it spawned lanes and then waited for them; that is
forbidden here.
```

- **wait_for_user stall signature:** the orchestrator may end its turn with a `wait_for_user {"reason":"Waiting for ... background lanes ..."}` tool call while lanes are still out — the parent process then exits (code 0) immediately, leaving NO final report. Grep the run log for `wait_for_user` before believing the output; it is the same abandonment as section 4, one stall variant earlier.
- **File-deliverable pattern:** for any recon/plan/audit task, require the agent to write its deliverable to ONE fixed file path (e.g. `/Users/<user>/.hermes/plans/<name>.md`), explicitly: "write the file with a single write; that is the only file you create." The artifact survives the process exit, so a truncated run still leaves its work on disk for you.
- **Parallel lanes still valuable for interactive TUI sessions** (`process submit` on the pty) — the abandonment failure is specific to non-interactive `opencode run`. Use lanes there, forbid them in one-shot runs.
- **Cheat sheet:** prompt blocks that prevent the failure mode, its symptom signatures, and the lane-evidence SQLite script live in `references/opencode-run-abandonment.md`.

### 6. Delegation Style (maintainer preference — upstream in `opencode-team`)
- When delegating to opencode, **rephrase what the user asked, add recon** — do not hand over a detailed technical spec. The agent does its own recon and design; the maintainer prefers phrasing to be a close rephrasing of the user's intent plus a recon directive.
- Large workstream FLOW: (1) run recon (self + opencode agents in parallel, using the sequential constraint above if `opencode run` is non-interactive) → (2) present findings, review and get the plan explicitly approved → (3) only then dispatch implementation.
- Deliverables that outlive the run: files (see §5), and separately confirm the agent's claims (PR URL exists, tests really pass, commit list matches) — never trust a subagent's self-report alone.
- Home: the `opencode-team` skill (`~/.hermes/skills/autonomous-ai-agents/opencode-team`) is authoritative for this machine's opencode layout; if it needs edits, run `hermes curator adopt opencode-team` to opt it into curation.

### 7. Implementation Dispatch (post-approval) and Mid-Run Evidence
- Once the plan is approved, dispatch ONE implementation run whose prompt is: HARD CONSTRAINT block (§5) + SPEC pointer to the approved plan file (cite the exact sections approved) + explicit guardrails (dormant features stay dormant, separate-process subsystems keep their own loader, write paths untouched, **user-facing docs untouched**) + numbered work plan committing after each step with the repo's checks green at each commit + final verification step + PR contract (fork head, base, title/body) + final-report contract (commit list, verification outputs, PR URL, deviations).
- **User-facing docs policy (maintainer preference, enforced twice):** internal refactor/architecture details (new interfaces, module layouts, "runtime config" sections) do NOT belong in user-facing docs (`docs/*.md`, README). They go in the repo's internal codemaps only (`codemap.md`, per-directory `codemap.md`). If an approved plan contains a step that writes such a section into user-facing docs, drop that part during dispatch — or the maintainer walks the PR back ("docs are user exposed, we don't need the internals there"). Codemap stale-reference fixes (e.g. after deleting a module) are fine and expected.
- Never let the run guess about a fix that exists on another branch: tell it which files are in what state (e.g. "branch is master WITHOUT PR #981: old disk reads still present; remove them and go straight to the interface getters").
- Full working template and the prompt skeleton in `references/implementation-dispatch-template.md`.
- **Mid-run evidence discipline (user expectation):** `background=true` + `notify_on_complete=true` yields exactly ONE event, at exit. Mid-run, ground truth is the repo: `git log --oneline -8` (commits landed), `git show --stat` (deltas real), and the run log tail (current step). When the user asks "is anything happening?", answer with commit hashes and the current step, not "it's running". A run can legitimately sit silent for many minutes between tool calls; silence is not a stall. A frozen log tail with no commit on a quick step is. Verify the run's claims yourself (commits, gates, `gh pr view/checks`) before reporting done.
- **Proofread delegation prompts before dispatch:** the prompt is the only contract the agent sees; a single mangled token derails the run. Before launching, verify against ground truth, never memory: repo owner/name from `git remote -v`, in-flight file paths from `git status --short` (copy them verbatim), branch name from `git branch --show-current`. A typo in the upstream repo (e.g. `algoinunreal` vs `alvinunreal`) or a mangled file name in a resume prompt sends the agent to the wrong place; catch it before dispatch, it costs 30 seconds. Also proofread the plan-file section anchors you cite.

### 8. Free-Tier Rate-Limit Hang (silent, hours-long) and Resume
- **Signature:** the run's last log line is a stream error `AI_APICallError: Rate limit exceeded. Please try again later.` (free-tier provider, e.g. deepseek-v4-flash-free via opencode) and then NOTHING for a long time: process alive (`ps` shows the opencode process, low CPU), no new commit, no new log line. Headless mode never recovers from a failed stream: it waits forever for a response that will never arrive. Silence here is NOT the normal inter-step pause — it is death.
- **Why it hits:** free-tier models have aggressive per-account rate limits, and the driving Hermes session usually runs the SAME model/provider (shared bucket). A long implementation run on top of an active Hermes session is the classic trigger. Expect it on free tier; the remedy is below, not astonishment.
- **Diagnosis (30 seconds):**
  ```bash
  date '+%H:%M:%S'; ps aux | grep -i opencode | grep -v grep | head -3   # last stream entry
  ls -lt ~/.local/share/opencode/log/ | head -3                          # latest log file
  tail -5 ~/.local/share/opencode/log/$(ls -t ~/.local/share/opencode/log/ | head -1)  # last "stream error" line beats everything
  git -C <repo> log --oneline -8                                       # commits since the presumed stall
  stat -c '%y %n' src/index.ts 2>/dev/null || stat -f '%Sm %N' -t '%H:%M' <file>  # last file touch
  ```
  If the last commit/file-mtime is minutes before the last log stream error and nothing advanced for >30 min → rate-limit hang, kill and resume.
- **Resume pattern (validated):** kill the process (`process kill`), then relaunch a RESUME prompt that:
  1. States "previous run was killed after hitting provider rate limits; continue, do not restart from scratch" at the top.
  2. Lists the exact committed hashes already done (from `git log`) so it never redoes steps, plus the EXACT uncommitted in-flight files (from `git status --short`), with "do NOT reset or discard these; first actions: git diff, then typecheck, then finish the partial work".
  3. Adds a rate-limit resilience line: "If a model call returns rate limit exceeded, WAIT 60-120 seconds and retry the same call up to 4 times; never end a turn merely because of a transient rate limit."
  4. Keeps the HARD CONSTRAINT block (§5) and the rest of the spec — a fresh session knows nothing, the full contract must be re-stated.
- Punctuated logging of the resume run: after 5-10 min check for either (a) a new commit or (b) a newer rate-limit line; a second rate-limit row means the window hasn't opened — wait longer or run during off-peak hours.
- Full transcript of the diagnosis + the resume prompt that worked lives in `references/rate-limit-recovery.md`.
