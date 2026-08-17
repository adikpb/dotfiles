---
name: modal-gpu-jobs
description: Run GPU jobs on Modal free tier when Colab T4 is too small.
---

# Modal GPU jobs (free tier)

Modal free Starter plan: $30/month compute credits, no subscription floor, no card required to start. L4 ~$0.80/hr, A100-40GB ~$2.10/hr. Containers get 512 GiB ephemeral disk by default (`ephemeral_disk` param up to 3 TiB). Billing is per-second, scale-to-zero.

## Install + auth (uv only, never pipx)

```bash
uv tool install modal
modal token new        # browser OAuth; token cached in ~/.modal.toml
modal profile current  # verify
```

## Verified image recipe for transformers/Heretic/bnb stacks (L4, 2026-08)

```python
image = (modal.Image.debian_slim(python_version="3.12")
    .apt_install("rustc", "cargo", "git", "curl")
    .pip_install("numpy==2.2.6")                     # pin FIRST (base numpy can be broken hybrid)
    .pip_install("heretic-llm==1.4.0", "huggingface_hub")
    .pip_install("torchvision", "pillow"))           # multimodal archs (Qwen2VL) need these
```

Result: numpy 2.2.6, transformers 5.14.1, torch 2.13.0+cu130, bitsandbytes 0.50.0, heretic CLI works. Build takes ~97s (+~2 min with torchvision). The transformers[kernels] extra resolves WITHOUT flash-attn (falls back to torch path, same as Colab).

PITFALL (cost a failed run): multimodal architectures (e.g. Qwen3_5ForConditionalGeneration, Qwen2VL-style) instantiate an image processor that hard-requires torchvision + pillow; without them Heretic dies with an opaque ImportError from transformers' requires_backends. Colab ships these preinstalled, Modal does NOT.

## Function skeleton

```python
@app.function(image=image, gpu="L4", memory=49152, timeout=60*60*8, retries=0,
              volumes={"/mnt/out": out_vol})
def run_pipeline():
    print(f"MILESTONE start", flush=True)   # tag lines for log-based watchers
```

- `memory` is in MiB. 48 GiB = 49152. 27B in bnb NF4 needs ~14.5 GiB GPU (fits L4 24GB, NOT Colab T4 14.56 GiB) + ~10-16 GiB CPU RAM for shard staging.
- Add a keepalive thread (`print ALIVE every 10 min`) because Heretic/convert phases are silent for hours; log-monitors false-alarm "stalled" otherwise.
- Long silent subprocesses: `Popen(["heretic", path], cwd=WORK, stdin=PIPE, stdout=logfile)`, write stdin answers up front (feeder pattern), poll + tail.
- `modal run app.py` streams function prints; wrap with `| tee log` in background.

## Gotchas

- `modal.Secret.from_name("x")` is LAZY: a missing secret raises `NotFoundError` at app-sync time, NOT at the call, so a module-level try/except does NOT catch it. Either create the secret (`modal secret create name KEY=val`) or don't reference it. Optional HF upload: check `os.environ.get("HF_TOKEN")` inside the function instead.
- Volume delivery: `modal.Volume.from_name("out", create_if_missing=True)`, mount at /mnt/out, `shutil.copy2` artifacts, `vol.commit()`; pull locally with `modal volume get out <file> <dest>`.
- Validate the image with a tiny import-check app (same image, `modal run`, ~2-3 min) BEFORE the expensive run; catches pip/build failures cheaply.
- Downloads from HF are fast unauthenticated (~550 MB/s on Modal CDN); a 54.7 GB snapshot took 99s.
- HF token on this Mac is dead (401); recreate at huggingface.co/settings/tokens (write scope) before relying on repo uploads.
