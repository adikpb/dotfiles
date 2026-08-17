---
name: colab-cli-connect
description: Drive Google Colab VMs from terminal via official colab CLI.
---

# Google Colab CLI (official) operation

Google's official `google-colab-cli` lets agents drive Colab VMs from the terminal: allocate T4/L4/A100, run .py/.ipynb remotely, stream logs, download files. Bundled agent skill: `colab skill` (also `colab readme`).

## Install (uv only, never pipx)

```bash
uv tool install google-colab-cli --with "jupyter-kernel-client==0.9.0"
```

CRITICAL: jupyter-kernel-client 1.0.0 broke the API (removed top-level `KernelClient`); the CLI 0.6.0 crashes with `AttributeError: module 'jupyter_kernel_client' has no attribute 'KernelClient'` unless pinned to 0.9.0. After reinstalling, verify: `grep -rl "class KernelClient" $(uv tool dir)/google-colab-cli/lib/python3.13/site-packages/jupyter_kernel_client/`.

## Auth (one-time per machine)

`colab new` prints a Google OAuth URL (gcloud-style remote-code flow). Human must open it, approve, and paste the code back into the waiting process. Token cached at `~/.config/colab-cli/token.json` (has refresh_token). To open the browser from terminal: `open '<URL>'`. The waiting process needs a PTY or piped stdin to receive the code; a plain background pipe aborts with EOF.

## Core workflow

```bash
colab new -s NAME --gpu T4        # allocate (T4/L4/G4/H100/A100); CPU if omitted
colab status -s NAME              # hardware + IDLE/BUSY
colab exec -s NAME -f nb.ipynb    # run notebook remotely; outputs written to <base>_output.ipynb
colab exec -s NAME -f script.py   # or a python script (read locally, transmitted)
echo 'print(1)' | colab exec -s NAME   # or piped code
colab log -s NAME -n 20           # structured event log
colab download -s NAME /content/x.gguf ~/Desktop/  # pull artifacts
colab stop -s NAME                # ALWAYS stop when done; idle VMs burn quota (24h keep-alive cap)
```

Facts from the bundled skill:
- Kernel state PERSISTS across exec calls in the same session (imports/vars survive); default cwd is /content. restart-kernel/stop resets it.
- `colab exec` streams stdout/stderr live. `colab run SCRIPT` = new+exec+stop one-shot (exit codes propagate; script stdout on stdout, [colab] chatter on stderr).
- Never run repl/console/auth/drivemount interactively from an agent (hang risk); repl/console accept piped stdin.
- Unknown --gpu value silently falls back to A100 (then usually 400s); 400 on new = no quota/entitlement → use T4 or CPU.
- Notebook cells using getpass/files.upload (Colab UI-only) hang or fail under exec: guard with `os.environ.get("HF_TOKEN")` check + try/except around getpass, and replace files.download with a print (pull via colab download).
- "Session not found"/404 on exec = backend pruned VM; re-create with colab new.

## Unassigning orphan sessions (browser sessions the CLI can't stop)

`colab stop -s NAME` only works for CLI-tracked sessions (local state in ~/.config/colab-cli/sessions.json). An orphan (shown as `[?]` in `colab sessions`) has no local record → "Session not found". Free tier allows only ONE concurrent VM, so a leftover browser session blocks `colab new` with `TooManyAssignmentsError`. Kill it via the raw API (authuser=0 param is REQUIRED, else 400):

```python
# token from ~/.config/colab-cli/token.json (refresh if expired via refresh_token)
url = f"https://colab.sandbox.google.com/tun/m/unassign/{endpoint}?authuser=0"
# GET with Bearer -> body starts with ")]}'" (XSSI prefix, strip it) -> {"token": xsrf}
# POST same URL with headers Bearer + X-Goog-Colab-Token: xsrf -> 200
```

Endpoint names come from `GET https://colab.research.google.com/tun/m/assignments` (Bearer). The POST returns 200 even if the browser tab's keep-alive renews it; if the tab stays open, ask the user to close/disconnect it in the web UI.

## Pitfalls
- `colab exec` has `--timeout <seconds>` (default 30.0). A cell that runs longer than the client's reply wait (big downloads, model runs) kills the client with `TimeoutError: Timeout waiting for reply` — but the KERNEL keeps executing. Pass `--timeout 14400` for notebook runs with multi-hour cells. `colab restart-kernel -s NAME` reboots the kernel (safe when idle).
- Pip surgery on a live kernel does NOT take effect: modules stay cached in memory. After `pip uninstall/install` of anything imported, `colab restart-kernel -s NAME` before re-testing.
- Colab's base numpy (2.0.2) is a broken hybrid install: `ImportError: cannot import name '_center' from 'numpy._core.umath'` when transformers imports `numpy._core.strings`. Fix: `pip uninstall -y numpy && pip install --no-cache-dir numpy==2.2.6`, then restart kernel. Pin `numpy==2.2.6` FIRST in any notebook before installing transformers-family packages.
- transformers 5.x `max_memory` requires INTEGER device keys: `{0: "14GB", "cpu": "8GB"}`, not `{"0": ...}` (string keys → `Device 0 is not recognized`).
- transformers 5.x + bnb 4-bit: `device_map="auto"` (with or without max_memory) raises "Some modules are dispatched on the CPU or the disk" whenever the mapper (which overestimates quantized size) places any module off-GPU; 4-bit CPU dispatch is refused. To get the TRUE fit verdict, probe with `device_map={"": 0}` — it bypasses the mapper; a `CUDA out of memory` then means the model genuinely doesn't fit.
- T4 (14.56 GiB) CANNOT hold 27B params in bnb NF4: ~14.5 GiB needed at load (13.68 weights + ~0.6 quant state) with zero headroom for activations. 24B-class models need L4/A10 (24 GB). Free quota rejects `--gpu L4/A10/H100` ("Backend rejected accelerator"); T4-only. Retry loop pattern: every 10 min `colab new -s NAME --gpu L4`, on success exec the notebook with `--timeout 14400` (see /tmp/l4_retry.sh pattern; stop any existing session first — 1-VM limit).
- HF_TOKEN secret vault: on CLI VMs, `huggingface_hub` warns "Requesting secret HF_TOKEN timed out... Secrets can only be fetched from the Colab UI" — harmless; unauthenticated HF downloads just run at lower rate limits.
- macOS/BSD grep: use grep -E, not -P.
