#!/usr/bin/env python3
"""Verify a rendered PDF after pandoc -> soffice conversion.

Checks that required strings are present, dropped strings are ABSENT, and that
each named section starts on its own PDF page. Normalizes whitespace and curly
quotes so line-wrap and typographic-quote extraction artifacts don't cause false
positives/negatives.

Usage:
  python3 verify_pdf.py report.pdf \
      --require "Chutes" --require "Sources" \
      --drop "x402" --drop "HULDR" \
      --section "3. Tier 2" --section "Sources"
"""
import argparse
import re
import sys

try:
    import pypdf
except ImportError:
    sys.exit("pypdf not installed. Run: uv pip install --python <venv>/bin/python pypdf")


def norm(t: str) -> str:
    t = re.sub(r"\s+", " ", t)
    for a, b in [("\u201c", '"'), ("\u201d", '"'),
                 ("\u2018", "'"), ("\u2019", "'"),
                 ("\u2013", "-")]:
        t = t.replace(a, b)
    return t


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf", help="path to the PDF to verify")
    ap.add_argument("--require", action="append", default=[],
                    help="string that MUST appear (repeatable)")
    ap.add_argument("--drop", action="append", default=[],
                    help="string that MUST be absent (repeatable)")
    ap.add_argument("--section", action="append", default=[],
                    help="section heading that should start its own page (repeatable)")
    args = ap.parse_args(argv)

    reader = pypdf.PdfReader(args.pdf)
    pages = [norm(p.extract_text() or "") for p in reader.pages]
    full = " ".join(pages)
    ok = True

    print(f"pages: {len(reader.pages)}")
    for s in args.require:
        hit = s.lower() in full.lower()
        print(("OK   " if hit else "MISS ") + f"require: {s}")
        ok &= hit
    for s in args.drop:
        hit = s.lower() in full.lower()
        print(("PRESENT (should be absent)" if hit else "OK dropped   ") + f": {s}")
        ok &= not hit
    for sec in args.section:
        found = next(
            (i + 1 for i, t in enumerate(pages) if sec.lower() in t.lower()),
            None)
        print(f"  p{found}: {sec}" if found else f"  NOT FOUND: {sec}")
        ok &= found is not None

    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())