# Rate-Limit Hang: Diagnosis + Resume (session-verified 2026-08-08)

Context: a long implementation run (`opencode run --auto`, free tier `deepseek-v4-flash-free`
via opencode provider) stalled mid-step-3 of a multi-commit refactor. Verified transcript
of what happened and what fixed it.

## Timeline
- 13:22 local — last file edit (`src/index.ts` mtime), agent mid-migration, no commit.
- 13:23 local — last log activity for the run:
  `level=ERROR run=<id> message="stream error" providerID=opencode modelID=deepseek-v4-flash-free ... error.error="AI_APICallError: Rate limit exceeded. Please try again later."`
- 13:33 — one `cleanup prune=7.days` INFO line (housekeeping, not progress).
- 14:25 — 1h+ later: no new log lines for `run=<id>`, no new commits, process alive.
- Root cause: headless `opencode run` does not retry/recover a failed stream turn. The
  orchestrator waits indefinitely for a response that never arrives. Free-tier rate limits
  are per-account and SHARED with the driving Hermes session (same model/provider), so a
  heavy implementation run on top of an active session is the classic trigger.

## Diagnosis commands that nailed it (run in this order)
```bash
date '+%H:%M:%S'
ps aux | grep -i opencode | grep -v grep | head -3        # proc alive? CPU%?
ls -lt ~/.local/share/opencode/log/ | head -3             # newest log file
tail -5 ~/.local/share/opencode/log/$(ls -t ~/.local/share/opencode/log/ | head -1)
  # last "stream error ... Rate limit exceeded" line is the smoking gun
git -C <repo> log --oneline -8                            # commits since stall?
stat -f '%Sm %N' -t '%H:%M' src/index.ts                  # last file touch (BSD mac) / -c '%y %n' (GNU)
```
Rule of thumb: last stream error + last commit/mtime all within a few minutes, then
>30 min of nothing => rate-limit hang, not a normal inter-step pause.

## Resume prompt that worked (structure, not verbatim)
1. `RESUME TASK: a previous implementation run stalled on provider rate limits after
   committing <list exact hashes>. Continue from its state, do not restart from scratch.`
2. HARD CONSTRAINT block (see SKILL.md §5) — sequential, no lanes, no wait_for_user.
3. Rate-limit resilience line: "the model provider is a free tier and WILL occasionally
   return 'Rate limit exceeded'. When that happens WAIT 60-120 seconds and retry the same
   call; up to 4 retries. Never end a turn merely because of a transient rate limit.
   Do not treat it as a task failure."
4. Exact state: committed hashes (don't redo), uncommitted in-flight file list copied
   verbatim from `git status --short` (finish, don't reset), "FIRST actions: git diff,
   then bun run typecheck, then complete the partial work."
5. The full original spec restated (fresh session knows nothing) + PR contract + report
   contract (commit list, verification outputs, PR URL, deviations).

## Lessons
- `process kill` on the hung run is safe: committed work survives; the in-flight dirty
  files are preserved for the resume run (do NOT clean them before relaunch).
- After resume dispatch, check at 5-10 min for either a new commit or a newer rate-limit
  log line. A second rate-limit row = window not open yet; wait longer or reschedule.
- If the resume prompt itself contains typos in repo/file identifiers, kill BEFORE it
  does anything and re-dispatch: proofread against `git remote -v` / `git status --short`.
