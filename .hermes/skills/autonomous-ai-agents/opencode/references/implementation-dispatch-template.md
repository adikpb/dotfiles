# Implementation Dispatch (approved plan → opencode run)

Use after a recon/plan has been written to a file (SKILL.md §5 file-deliverable
pattern) and explicitly approved by the user. This template was validated
end-to-end: a 6-step refactor running as one background `opencode run` that
committed per step, passed all gates, and produced a PR (and survived a
rate-limit stall mid-run via the §8 resume pattern).

```bash
opencode run --auto '<PROMPT>'   # background=true, notify_on_complete=true
```

## Prompt skeleton (keep this order)

1. **Mission line**: "IMPLEMENTATION TASK - the approved plan must be carried
   out fully. You are already on the correct branch (<branch>, based on
   <base>, clean). Current directory IS the repo root."
2. **HARD CONSTRAINT block** - verbatim from SKILL.md §5 (no lanes, no
   parallelize, no wait_for_user, work sequentially; a previous run died
   spawning lanes and waiting).
3. **SPEC pointer**: "read the approved design first: <abs path>; sections
   §3/§4 are the approved scope." Name the decisions the approval pinned
   (e.g. "as scoped: steps 1-6").
4. **Guardrails (what NOT to do)** - the approval's exclusions, spelled out:
   "Do NOT activate the dormant X feature (stays dormant; relocating state
   only). Do NOT change user-visible behavior. Do NOT touch <subsystems
   that keep their own loader> (separate processes). Keep <write path> as
   is. **User-facing docs untouched** (docs/*.md must not carry internal
   architecture detail; codemap maintenance is the allowed docs work)."
   Scope creep creeps in here; name it. User-facing-docs exclusion also
   applies to the plan itself: if a plan step says "write docs/configuration.md
   section about the new interface", rewrite that step to say codemaps only.
5. **Work plan**: numbered steps in the plan's order, each ending in a
   commit with a conventional message. Explicitly gate each step:
   "keep check:ci + typecheck + tests green at each commit." Name the
   check command of THIS repo.
6. **Smart-merge expectations**: if the branch lacks a fix that exists on
   another branch/PR, say what state files are in (e.g. "branch is based on
   master WITHOUT #981: file still contains the old disk reads; remove them
   and go straight to the interface getters"). Deciding this halts runs.
7. **Final verification step**: full local gate (lint, typecheck, build,
   full test suite 0 fail). If snapshot tests fail on a change that touched
   no prompt surfaces, investigate, do NOT blindly --update-snapshots; if it
   is formatting-only, update and note in the commit.
8. **PR contract**: push to origin (the fork), then `gh pr create` with
   exact head (<fork>:<branch>), base, title, body contents (what was
   unified, boundary notes, verification commands + pass counts, file list).
9. **Final report contract**: "(a) commit list, (b) verification outputs
   (commands + pass counts), (c) PR URL, (d) deviations and why. Never
   claim success without running the verification commands - report actual
   outputs."
10. **Rate-limit resilience line** (free-tier providers; see SKILL.md §8):
   "The model provider is a free tier and WILL occasionally return 'Rate
   limit exceeded'. When that happens WAIT 60-120 seconds and retry the
   same call; up to 4 retries. Never end a turn merely because of a
   transient rate limit."

## Mid-run status protocol (while the process is silent)

- One event arrives at exit (notify_on_complete). Between events there is
  NO update; polling is the only mid-run insight.
- Healthy long run: commits landing in `git log --oneline -8`; the current
  step visible in `process log` tail (tool reads, greps, a context-
  compression marker `⚙ compress`). Commits are the strongest liveness
  signal.
- Stall red flags: log tail frozen for many minutes with NO tool calls AND
  no commit while on a step that should be quick, a `wait_for_user` line
  before exit (§5 signature), or a trailing stream error with no follow-up
  (§8 rate-limit hang).
- NEVER tell the user "it's running" as the whole answer when they asked
  for proof: report `git log` heads + what step the log tail shows, or the
  absence of commits honestly.

## Post-run verification (never trust the self-report)

1. `git log --oneline -N` - commits exist, order matches the claim.
2. `git show --stat HEAD` - the deltas are real (files, line counts).
3. Re-run the cheapest gates yourself: check:ci, typecheck, targeted tests.
4. `gh pr view <n>` / `gh pr checks <n>` - PR exists, head/base correct,
   CI started.
5. If the maintainer later asks to drop a docs section ("docs are user
   exposed"), revert the user-facing file to base and re-check the PR:
   `git diff <base>...HEAD -- docs/<file> | wc -l` should be 0; the push to
   PR supersedes it.