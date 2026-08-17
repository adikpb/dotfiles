#!/usr/bin/env python3
"""Extract per-cell text from a grid PDF using char positions + line clustering.

Works where naive pdfplumber text extraction fails: CID/subset fonts,
overlapping text copies, and per-glyph positioning offsets scramble naive
concatenation. Cells are defined by (1) column centers (typically the x
positions of column-header numbers) and (2) row bands (top-origin y ranges).

Usage:
  uv run --with pdfplumber python3 extract_pdf_grid_cells.py report.pdf \
      --centers "1=125,2=146,3=167,4=194,...,31=1063" \
      --bands "checkin=164.4:199.6,attended=284.7:308.3,status=321.4:334.6" \
      [--left 116.6] [--right 1105.1]

Column boundaries default to midpoints between adjacent centers; pass --left
and --right for the true outer edges. Each cell prints as lines joined by '|'
(segment order top-to-bottom), columns separated by two spaces.
"""
import argparse
import pdfplumber


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pdf')
    ap.add_argument('--centers', required=True, help='day=centerX,...')
    ap.add_argument('--bands', required=True, help='name=top:bottom,...')
    ap.add_argument('--left', type=float, default=None)
    ap.add_argument('--right', type=float, default=None)
    a = ap.parse_args()

    centers = {int(k): float(v) for k, v in (p.split('=') for p in a.centers.split(','))}
    bands = [(n, float(t), float(b)) for n, t, b in (p.split('=') for p in a.bands.split(','))]
    ids = sorted(centers)
    xs = [a.left if a.left is not None
          else centers[ids[0]] - (centers[ids[1]] - centers[ids[0]]) / 2]
    xs += [(centers[ids[i]] + centers[ids[i + 1]]) / 2 for i in range(len(ids) - 1)]
    xs.append(a.right if a.right is not None
              else centers[ids[-1]] + (centers[ids[-1]] - centers[ids[-2]]) / 2)

    with pdfplumber.open(a.pdf) as pdf:
        for page in pdf.pages:
            chars = page.chars
            print(f'== page {page.page_number} ==')
            for name, lo, hi in bands:
                row = []
                for i, d in enumerate(ids):
                    cs = [c for c in chars if xs[i] <= c['x0'] < xs[i + 1] and lo <= c['top'] < hi]
                    lines = []
                    for c in sorted(cs, key=lambda c: c['top']):
                        for ln in lines:
                            if abs(ln['y'] - c['top']) <= 3.0:
                                ln['cs'].append(c)
                                break
                        else:
                            lines.append({'y': c['top'], 'cs': [c]})
                    lines.sort(key=lambda l: l['y'])
                    txt = '|'.join(''.join(
                        cc['text'] for cc in sorted(l['cs'], key=lambda cc: cc['x0'])
                    ) for l in lines)
                    row.append(txt)
                print(f'{name:10s} ' + '  '.join(row))


if __name__ == '__main__':
    main()