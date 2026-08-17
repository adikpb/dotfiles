---
name: colab-cli-advanced-workflows
description: Run headless Colab notebooks and purge runtime locks.
---

# Advanced Headless Colab CLI Workflows

Extends the official Colab CLI (`google-colab-cli`) with robust patterns for long-running notebook execution, dependency conflict resolution, and resource lock recovery.

## 1. Notebook Hardening for Headless Execution
Interactive Colab features (`getpass`, `files.download`, file pickers) will hang or fail when executed via `colab exec -f notebook.ipynb`.
- **Secrets**: Guard `getpass()` by checking `os.environ.get("HF_TOKEN")` first, with a fallback to unauthenticated downloads.
- **File Exports**: Replace `from google.colab import files; files.download(...)` with a print statement; pull artifacts asynchronously from the local terminal using `colab download -s NAME /content/path ~/Desktop/`.

## 2. Numeric Stack ABI Repair
Installing modern ML tooling (`heretic-llm`, transformers 5.x) via pip can corrupt Colab's pre-installed numeric bindings, raising `ImportError: cannot import name '_center' from 'numpy._core.umath'`. Always wrap imports with an automatic reinstall safeguard:
```python
try:
    import numpy, transformers, heretic
except Exception:
    !pip install -q -U --force-reinstall numpy bottleneck pandas
```

## 3. High-VRAM Accelerator Allocation & Fallbacks
- **T4 Limits**: Standard 16GB T4 GPUs lack sufficient VRAM (~14.5 GiB allocatable) for 27B+ parameter models in bitsandbytes NF4 quantization. 27B models require ~13.8–14.5 GiB at load, causing inevitable CPU fallback or OOM failures.
- **Quota-Aware Polling**: When requesting L4/A10G accelerators via Colab CLI or free tier automation, implement automated retry loops with backoff to catch off-peak allocation windows without manual intervention.
- **Alternative Runtimes**: For heavy workloads exceeding free-tier resource caps, offload execution to serverless providers (e.g., Modal) with configurable ephemeral storage (default 512 GiB) to prevent local-disk exhaustion during massive model weight downloads and abliteration passes.
When converting unpacked weights to quantized GGUF formats (e.g., Q1_0 via `oxibonsai`), ensure the repository and local output folder bundle both the GGUF text weights and the vision tower (`mmproj-*.gguf`) so the resulting model is immediately usable for both text and vision inputs in LM Studio or llama.cpp.

If the Colab backend retains an unmanaged browser session, `colab new` fails with `TooManyAssignmentsError`. Since local session tracking (`~/.config/colab-cli/sessions.json`) ignores unmanaged orphans, clear them via the raw backend API:
```python
import json, os, urllib.request

# 1. Load OAuth token from ~/.config/colab-cli/token.json
with open(os.path.expanduser("~/.config/colab-cli/token.json")) as f:
    token_data = json.load(f)
token = token_data.get("access_token")

# 2. Fetch active endpoints
req = urllib.request.Request(
    "https://colab.research.google.com/tun/m/assignments",
    headers={"Authorization": f"Bearer {token}"}
)
with urllib.request.urlopen(req) as resp:
    data = json.loads(resp.read().decode())
```
*Note*: Always append `?authuser=0` to unassign endpoints to avoid 400 Bad Request responses.
