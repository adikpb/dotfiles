---
name: colab-cli
description: "Run Colab and Modal GPU jobs from the terminal."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [colab, modal, gpu, remote-compute, notebooks]
    related_skills: []
---

# Remote GPU jobs (Colab CLI + Modal)

Drive Google Colab VMs and Modal functions from the terminal. Use Colab first (official `google-colab-cli`). Escalate to Modal when a Colab T4 (~14.5 GiB allocatable) is too small — typically 27B+ in bitsandbytes NF4.

Absorbed from: `colab-cli-connect`, `colab-cli-advanced-workflows`, `modal-gpu-jobs`.

## When to Use

- Allocate a Colab GPU/CPU VM, exec a `.py`/`.ipynb`, stream logs, pull artifacts
- Headless notebook hangs, runtime locks, numeric-stack ABI breakage
- Colab T4 OOM / CPU-fallback → Modal L4/A100 free-tier job

Don't use for: interactive Colab in the browser; local-only training.

## Prerequisites

Install with **uv only, never pipx**:

```
terminal(command="uv tool install google-colab-cli --with \"jupyter-kernel-client==0.9.0\"")
terminal(command="uv tool install modal")
```

CRITICAL: jupyter-kernel-client 1.0.0 removed top-level `KernelClient`; CLI 0.6.0 crashes unless pinned to 0.9.0. After install, verify `class KernelClient` exists under `$(uv tool dir)/google-colab-cli/lib/.../jupyter_kernel_client/`.

Auth (human-in-the-loop, once per machine):

- Colab: `colab new` prints a Google OAuth URL. Open it, paste the code into the waiting PTY. Token: `~/.config/colab-cli/token.json`.
- Modal: `modal token new` → `~/.modal.toml`. Verify with `modal profile current`.

## Colab — core workflow

```
colab new -s NAME --gpu T4        # T4/L4/G4/H100/A100; omit --gpu for CPU
colab status -s NAME
colab exec -s NAME -f nb.ipynb    # writes <base>_output.ipynb
colab exec -s NAME -f script.py
echo 'print(1)' | colab exec -s NAME
colab log -s NAME -n 20
colab download -s NAME /content/x.gguf ~/Desktop/
colab stop -s NAME                # ALWAYS stop; idle VMs burn quota
```

Kernel state persists across `exec` in the same session. Default cwd is `/content`. Unknown `--gpu` silently falls back to A100 (then usually 400s). 400 on `new` = no quota → use T4 or CPU.

Never run `repl`/`console`/`auth`/`drivemount` interactively from an agent (hang risk).

Full connect notes: `references/colab-cli-connect.md`.

## Colab — headless hardening

Interactive Colab features hang under `colab exec -f notebook.ipynb`:

- Secrets: prefer `os.environ.get("HF_TOKEN")`; do not call `getpass()`.
- Exports: never `files.download(...)`. Print the path; pull with `colab download`.
- Numeric ABI: `pip install` of modern ML stacks can raise `ImportError: cannot import name '_center' from 'numpy._core.umath'`. Guard imports and force-reinstall `numpy bottleneck pandas` on failure.
- T4 cannot hold 27B NF4 (~13.8–14.5 GiB). Escalate to L4/A100 or Modal.
- `TooManyAssignmentsError` on `colab new` → unmanaged browser session still holds the runtime. Purge it (see `references/colab-cli-advanced-workflows.md`).

When converting to GGUF, bundle the vision tower (`mmproj-*.gguf`) with the text weights.

## Modal — when Colab T4 is too small

Free Starter: $30/month credits, no card required. L4 ~$0.80/hr, A100-40GB ~$2.10/hr. Default ephemeral disk 512 GiB.

Verified image (transformers / Heretic / bnb, L4, 2026-08):

```python
image = (modal.Image.debian_slim(python_version="3.12")
    .apt_install("rustc", "cargo", "git", "curl")
    .pip_install("numpy==2.2.6")
    .pip_install("heretic-llm==1.4.0", "huggingface_hub")
    .pip_install("torchvision", "pillow"))
```

Pin numpy FIRST. Multimodal arches (Qwen2VL) hard-require torchvision + pillow — Colab ships them, Modal does not.

```python
@app.function(image=image, gpu="L4", memory=49152, timeout=60*60*8, retries=0,
              volumes={"/mnt/out": out_vol})
def run_pipeline():
    print("MILESTONE start", flush=True)
```

Add a keepalive print every 10 min — Heretic/convert phases are silent for hours. `modal.Secret.from_name("x")` is lazy: missing secret raises at app-sync, not import.

Full recipe + gotchas: `references/modal-gpu-jobs.md`.

## Pitfalls

- Forgetting `colab stop` burns the 24h keep-alive quota.
- Auth needs a PTY or piped stdin; a plain background pipe EOFs.
- Modal secrets fail late. Probe them before the long job.
- Do not claim a 27B NF4 fit on Colab T4.

## Verification

- Colab: `colab status -s NAME` shows hardware + IDLE/BUSY; `exec` streams output; `stop` leaves no assignment.
- Modal: `modal run app.py` prints MILESTONE lines; GPU type matches the decorator; artifacts land on the volume.
