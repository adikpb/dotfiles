#!/usr/bin/env python3
"""Idempotent docx/PDF markdown processors for the text-report pipeline.

Run from the report directory with the report markdown as argv[1]; each mode
edits the file in place. All are idempotent (safe to re-run).

Modes:
  pagebreaks   Insert a raw-OpenXML page break before every "## " heading so
               each major section starts on a new page in the docx AND the
               PDF (LibreOffice honors it). Deletes any existing page-break
               blocks first, so repeated runs never double-insert.
  normalize    Ensure a blank line precedes every # / ## / ### heading.
               Fixes headings glued to the previous line when a markdown file
               was built by concatenating part files with `cat`
               (a glued heading renders as literal text in the PDF).
  hypercite    Revert footnote-marker citations `[^n]` back to inline clickable
               hyperlinks `[[n]](url)`, taking each source URL from the file's
               own `[n]: URL — title` definition lines or a passed ledger URL.
               Deletes the footnote-definition lines. NOTE: delete the
               definition block BEFORE replacing refs, or the ref regex
               rewrites definitions too and the block-deletion filter misses.
None of these are for the caller to hand-edit around; run and then re-render.
"""

import re
import sys

PAGEBREAK = (
    "```{=openxml}\n"
    "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>\n"
    "```"
)
# a page-break block of 3 lines (fence, w:p line, fence)
PB_RE = re.compile(
    r"```\{=openxml\}\n<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>\n```\n"
)


def pagebreaks(path: str) -> None:
    s = open(path).read()
    s = PB_RE.sub("", s)  # strip all existing blocks first -> idempotent
    lines = s.split("\n")
    out, i = [], 0
    while i < len(lines):
        if lines[i].startswith("## "):
            # page break block goes BEFORE the heading
            out.extend(["", PAGEBREAK, ""])
        out.append(lines[i])
        i += 1
    open(path, "w").write("\n".join(out))


def normalize(path: str) -> None:
    s = open(path).read()
    # blank line + heading
    s = re.sub(r"(?m)^(\n*)(#{1,6} )", r"\n\1\2", s).lstrip("\n")
    # collapse 3+ blank lines
    s = re.sub(r"\n{4,}", "\n\n\n", s)
    open(path, "w").write(s)


def hypercite(path: str) -> None:
    s = open(path).read()
    # URLs come from the footnote definition lines: "[^n]: URL — title"
    src = dict(re.findall(r"^\[\^(\d+)\]: (\S+) — .+$", s, re.M))
    if not src:
        print(f"hypercite: no [^n]: URL — title definitions found in {path}")
        return
    # 1) DELETE the definition block FIRST — if refs are rewritten first,
    #    definitions become [[n]](url): url — title and no longer match
    #    ^\[\^(\d+)\]:, so they survive and corrupt the Sources region.
    s = re.sub(r"^\[\^(\d+)\]: (\S+) — [^\n]*\n(\n)?", "", s, flags=re.M)
    # 2) rewrite inline [^n] -> [[n]](url)
    def repl(m):
        n = m.group(1)
        if n in src:
            return f"[[{n}]]({src[n]})"
        return m.group(0)
    s = re.sub(r"\[\^(\d+)\]", repl, s)
    s = re.sub(r"\n{4,}", "\n\n\n", s)
    open(path, "w").write(s)
    print(f"hypercited {path} from {len(src)} sources")


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    mode, path = sys.argv[1], sys.argv[2]
    {"pagebreaks": pagebreaks, "normalize": normalize, "hypercite": hypercite}[mode](path)


if __name__ == "__main__":
    main()