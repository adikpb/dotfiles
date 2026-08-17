# `opencode run` abandonment: prompt block, symptom, recovery

Validated on this machine (oh-my-opencode-slim plugin, orchestrator + free
opencode-zen models). Two identical-ish `opencode run --auto` tasks: the two
with the hard-constraint block completed; the two without died at a
lane-wait (one exit-code-0 mid-audit, one `wait_for_user` stall with a
missing deliverable file).

## 1. The prompt block that prevents abandonment (verbatim)

```
HARD CONSTRAINT: Do NOT spawn background subagents or explorer lanes. Do NOT
parallelize. Do NOT block on wait_for_user or any out-of-band input. Work
directly and sequentially in this single session from start to finish. The
previous run died because it spawned lanes and then waited for them; that is
forbidden here.
```

Place at the top of the prompt, right after the goal statement. Keep the
rest of the prompt a rephrase of the user's intent + recon guidance; do NOT
feel the need to over-specify — the agent recon-gathers on its own.

## 2. File-deliverable clause (add to any recon/plan/audit task)

```
DELIVERABLE: write ONLY one file: /Users/<you>/.hermes/plans/<name>.md
(create the directory if needed) containing: <A/B/C section list>. Write the
file with a single write; that is the only file you create.
```

Then print a short summary (`15-line summary`) — the summary is nice-to-have
but the file is the durable evidence. Verify the file exists on disk
afterward; the run may exit cleanly before its last words reach you.

## 3. Symptom signatures that the run abandoned work

- Log tail shows `✱ Glob ...` then "lanes are running in the background" and
  the process exits shortly after (exit 0) with no final report.
- `wait_for_user {"reason":"Waiting for background lanes..."}` appears, then
  exit — orchestrator ended its turn while lanes still worked.
- `notify_on_complete` fires with exit_code 0 but the announced deliverable
  file was never created.

## 4. Recovering lane evidence from the SQLite store

Store: `~/.local/share/opencode/opencode.db` (SQLite).
Core tables: `session(id, title, time_created)`, `message(id, session_id,
role, time_created, data JSON, summary_file)`, `part(message_id, data JSON —
`type:'text'` rows carry chat text; tool outputs are separate part types).

```python
import sqlite3, json
db = sqlite3.connect('<home>/.local/share/opencode/opencode.db')
db.row_factory = sqlite3.Row
rows = db.execute("SELECT id, title FROM session WHERE time_created >= ? ORDER BY time_created", (start_ms,)).fetchall()
# parent id = the session you launched; lanes = sessions with subagent-ish titles
for sid in [r['id'] for r in rows]:
    msgs = db.execute("SELECT id, data FROM message WHERE session_id=? ORDER BY time_created", (sid,)).fetchall()
    for m in msgs:
        for p in db.execute("SELECT data FROM part WHERE message_id=?", (m['id'],)):
            d = json.loads(p['data'])
            if d.get('type') == 'text' and d.get('text'):  # grep for keywords
                pass
```

Lane `part` rows retain the read_file/tool outputs each lane gathered, so a
lane that never wrote a final summary still leaves usable evidence
(confirmed by keyword-grep extraction).

## 5. Generalization

The mechanism is generic: any non-interactive runner that spawns background
sub-sessions and exits when the foreground turn ends will orphan them. Apply
the same constraint block, file-deliverable clause, and DB extraction to
other agent CLIs with background subtask support.