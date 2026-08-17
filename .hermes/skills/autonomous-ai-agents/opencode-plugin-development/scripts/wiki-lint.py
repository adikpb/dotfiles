#!/usr/bin/env python3
"""Wiki lint: broken wikilinks, orphans, index completeness.

Usage:
    python3 wiki-lint.py [WIKI_DIR]        # default: ./wiki

Checks every page under {wiki}/{entities,concepts,comparisons,queries}:
  - broken [[wikilinks]] (targets that resolve to neither a page nor an
    index.md entry)
  - orphan pages (on disk, missing from index.md)
  - index entries with no matching page
Exit code 0 = clean, 1 = issues found. Prints a per-section report.
"""
import os
import re
import sys

def main() -> int:
    wiki = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.getcwd(), "wiki")
    dirs = ["entities", "concepts", "comparisons", "queries"]

    pages: dict[str, tuple[str, set[str]]] = {}
    for d in dirs:
        base = os.path.join(wiki, d)
        for f in sorted(os.listdir(base)) if os.path.isdir(base) else []:
            if not f.endswith(".md"):
                continue
            name = os.path.splitext(f)[0]
            txt = open(os.path.join(base, f), encoding="utf-8").read()
            pages[name] = (os.path.join(d, f), set(re.findall(r"\[\[([^\]]+)\]\]", txt)))

    index_path = os.path.join(wiki, "index.md")
    index_txt = open(index_path, encoding="utf-8").read()
    indexed = set(re.findall(r"\[\[([^\]]+)\]\]", index_txt))
    known = set(pages)

    broken = sorted(
        f"{name} -> [[{link}]]"
        for name, (_, links) in pages.items()
        for link in links if link not in known and link not in indexed
    )
    orphans = sorted(n for n in pages if n not in indexed)
    dangling = sorted(indexed - known)

    print(f"pages on disk: {len(pages)}")
    print(f"index entries: {len(indexed)}")
    print("broken links:", broken if broken else "NONE")
    print("orphans (on disk, not indexed):", orphans if orphans else "NONE")
    print("index entries without page:", dangling if dangling else "NONE")
    return 1 if (broken or orphans or dangling) else 0


if __name__ == "__main__":
    sys.exit(main())