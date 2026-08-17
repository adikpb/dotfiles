#!/usr/bin/env python3
"""Lint a Karpathy-style wiki (build/query/health-check).

Usage:
    python wiki-lint.py [wiki_dir] [--require-key sources] [--require-key confidence] [--check REGEX ...]

Path resolution: CLI arg > $WIKI_PATH > <cwd>/wiki (if it exists) > ~/wiki.

Checks:
  1. index.md "Total pages: N" vs actual content-page count
  2. index section links ([[slug]]) resolve to pages
  3. every [[wikilink]] in pages and index resolves
  4. orphan pages (content page not linked from index)
  5. frontmatter present on every content page; extra required keys via --require-key
  6. log.md: trailing newline + no glued lines (content immediately before "## [")
  7. --check REGEX: forbidden patterns scanned on all content pages (e.g.
     plural route names that were corrected: --check '/api/session/[^\s`|]*events')

Exit 0 = clean, 1 = problems found. Prints findings grouped by check.
Verified against the hermes-opencode-plugin wiki (2026-08-09, round-2 lint).
"""
import argparse
import os
import re
import sys


def content_pages(wiki):
    pages = {}
    for root, dirs, files in os.walk(wiki):
        dirs[:] = [d for d in dirs if d != "_archive"]
        for f in sorted(files):
            if not f.endswith(".md"):
                continue
            rel = os.path.relpath(os.path.join(root, f), wiki)
            if rel in ("index.md", "log.md", "SCHEMA.md", "README.md"):
                continue
            pages[os.path.splitext(f)[0]] = (rel, open(os.path.join(root, f), encoding="utf-8").read())
    return pages


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("wiki", nargs="?", default=None)
    ap.add_argument("--require-key", action="append", default=[], metavar="KEY",
                    help="frontmatter key that must be present on content pages (repeatable)")
    ap.add_argument("--check", action="append", default=[], metavar="REGEX",
                    help="forbidden regex scanned on all content pages (repeatable)")
    args = ap.parse_args()

    wiki = args.wiki
    if wiki is None:
        wiki = os.environ.get("WIKI_PATH")
    if wiki is None:
        cwd_wiki = os.path.join(os.getcwd(), "wiki")
        wiki = cwd_wiki if os.path.isdir(cwd_wiki) else os.path.expanduser("~/wiki")

    problems = []
    pages = content_pages(wiki)

    # 5. frontmatter
    for slug, (rel, text) in pages.items():
        if not re.match(r"^---\n", text):
            problems.append(f"{rel}: missing frontmatter")
            continue
        fm = text.split("---", 2)[1]
        for key in ["title"] + args.require_key:
            if f"{key}:" not in fm:
                problems.append(f"{rel}: missing frontmatter key '{key}'")

    # 1. index count + 2/4. index links + orphans
    idx_path = os.path.join(wiki, "index.md")
    idx = open(idx_path, encoding="utf-8").read() if os.path.exists(idx_path) else ""
    m = re.search(r"Total pages:\s*(\d+)", idx)
    declared = int(m.group(1)) if m else None
    actual = len(pages)
    if declared is not None and declared != actual:
        problems.append(f"index.md declares {declared} pages, actual {actual}")
    idx_links = set(re.findall(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]", idx))
    for link in idx_links:
        base = link.split("#")[0].strip()
        if base and base not in pages:
            problems.append(f"index.md: link [[{base}]] -> no page")

    # 3. wikilinks in pages
    for slug, (rel, text) in pages.items():
        for link in re.findall(r"\[\[([^\]|]+)(?:\|[^\]]+)?\]\]", text):
            base = link.split("#")[0].strip()
            if base and base not in pages and base != "index":
                problems.append(f"{rel}: broken link [[{base}]]")

    # 4. orphans
    for slug in pages:
        if slug not in idx:
            problems.append(f"orphan page: {slug}")

    # 6. log integrity
    log_path = os.path.join(wiki, "log.md")
    if os.path.exists(log_path):
        log = open(log_path, encoding="utf-8").read()
        if not log.endswith("\n"):
            problems.append("log.md: missing trailing newline")
        for lineno, line in enumerate(log.splitlines(), 1):
            if re.search(r"\S## \[", line) and not line.lstrip().startswith(">"):
                problems.append(f"log.md:{lineno}: glued/merged log entry (non-space char before '## [')")

    # 7. extra forbidden patterns
    for regex in args.check:
        try:
            rx = re.compile(regex)
        except re.error as e:
            problems.append(f"--check {regex!r}: invalid regex ({e})")
            continue
        for slug, (rel, text) in pages.items():
            for match in rx.findall(text):
                problems.append(f"{rel}: forbidden pattern {regex!r} -> {match!r}")

    print(f"pages={actual} declared={declared if declared is not None else 'n/a'}")
    print(f"PROBLEMS: {len(problems)}")
    for p in problems:
        print(" -", p)
    sys.exit(0 if not problems else 1)


if __name__ == "__main__":
    main()