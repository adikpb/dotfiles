# Workaround: Using execute_code When Tools Are Unavailable

When `terminal`, `read_file`, `write_file`, or `patch` are absent from the
tool list, the agent can still perform file I/O and shell commands using
`execute_code` with Python stdlib.

## File Operations

```python
# Write a file
content = '''def hello():
    print("hello world")
'''
with open("/path/to/target.py", "w") as f:
    f.write(content.lstrip())

# Read a file
with open("/path/to/target.py") as f:
    print(f.read())

# List directory
import os
for f in sorted(os.listdir(".")):
    print(f, os.path.getsize(f))
```

Works for any number of files — one `execute_code` call can write many.

## Shell Commands

```python
import subprocess
import os

# Check a binary exists
r = subprocess.run(["which", "opencode"], capture_output=True, text=True)
print(f"Found: {r.stdout.strip() or 'NOT FOUND'}")

# Run a command
r = subprocess.run(["opencode", "--version"], capture_output=True, text=True, timeout=30)
print(r.stdout)

# Run in a specific directory
r = subprocess.run(
    ["ls", "-la"],
    capture_output=True, text=True,
    cwd=os.path.expanduser("~/src/project")
)
print(r.stdout)
```

## Invoking CLI Tools (e.g. OpenCode)

```python
import subprocess, os

os.chdir("/path/to/project")

result = subprocess.run(
    ["opencode", "run", "Implement CSV parser in src/parser.py"],
    capture_output=True, text=True, timeout=300
)
print(result.stdout[-2000:])  # tail
if result.returncode != 0:
    print("STDERR:", result.stderr)
```

## Limits

| Constraint | Value |
|------------|-------|
| Timeout | 5 minutes |
| Stdout cap | 50 KB |
| Tool calls per script | 50 |
| Background/pty | Not supported — foreground only |
| `subprocess.Popen` | Works for background but output not tracked by `process` tool |

For large builds or long-running work, prefer `delegate_task` (subagents
have `terminal` and `read_file`/`write_file` available).
