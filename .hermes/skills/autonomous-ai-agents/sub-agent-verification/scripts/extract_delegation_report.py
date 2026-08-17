#!/usr/bin/env python3
"""Recover full subagent reports from delegation cache files.

Batch delegate_task consolidated messages truncate per-task reports;
the full text is on disk. This script extracts it.

Usage:
    python3 extract_delegation_report.py <summary-file> [<output.md>]

Works on either:
  * ~/.hermes/cache/delegation/subagent-summary-<n>-<ts>.txt
    (JSON object with a "report" key, optionally wrapped in ```json fences)
  * Any file containing a ```json {...} ``` block with a "report" key

Prints the report to stdout (or writes it to <output.md> and prints the
path). Exit 0 on success, 1 if no report found.
"""
import json
import re
import sys


def extract(raw: str) -> str | None:
    # Try fenced JSON first, then bare {...}, then whole file as JSON.
    candidates = []
    m = re.search(r"```json\s*(\{.*?\})\s*```", raw, re.S)
    if m:
        candidates.append(m.group(1))
    m = re.search(r"(\{.*\})", raw, re.S)
    if m:
        candidates.append(m.group(1))
    candidates.append(raw)
    for c in candidates:
        try:
            data = json.loads(c)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict) and isinstance(data.get("report"), str):
            return data["report"]
    # Some summaries wrap the report directly (no JSON): return as-is if
    # it looks like markdown.
    if raw.strip().startswith("# "):
        return raw
    return None


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else None
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    report = extract(raw)
    if not report:
        print(f"no report found in {path}", file=sys.stderr)
        return 1
    if out:
        with open(out, "w", encoding="utf-8") as f:
            f.write(report)
        print(out)
    else:
        sys.stdout.write(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())