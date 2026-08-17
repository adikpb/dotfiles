#!/usr/bin/env python3
"""
crop-resize.py — Batch-resize, crop, and auto-trim screenshots for docx embedding.

Usage:
    python crop-resize.py <file_or_dir> [--width 1600] [--crop TOP HEIGHT]
    python crop-resize.py <file_or_dir> --auto-trim [--width 1600]

Examples:
    # Resize all PNGs in screenshots/ to 1600px wide (maintains aspect ratio)
    python crop-resize.py ./screenshots/

    # Auto-trim empty borders, then resize to 1600px wide
    python crop-resize.py ./screenshots/ --auto-trim

    # Crop top 2400px then resize to 1600px wide
    python crop-resize.py tall_screenshot.png --crop 0 2400

    # Auto-trim only, no resize
    python crop-resize.py ./screenshots/ --auto-trim --width 99999

Notes:
    - Overwrites the source file in place.
    - --auto-trim runs before --crop (if both specified, though unusual).
    - --auto-trim detects content by finding non-background pixels.
      Background threshold: R < 40, G < 40, B < 45 (dark themes).
      Adjust by editing the is_bg() function below.
    - Default target width 1600 px gives ~2x oversampling at docx render width 780.
"""

import argparse, os, sys
from PIL import Image


def is_bg(r, g, b, a=255):
    """Return True if pixel is dark background / empty space.
    Customize thresholds for different color themes."""
    return r < 40 and g < 40 and b < 45


def auto_trim(img, pad=10):
    """Auto-detect content bounding box and crop to it.

    Scans for the first/last row and column with non-background
    pixels, skipping the scrollbar zone (~6% from right edge).

    Returns: cropped Image, or original if no content found.
    """
    w, h = img.size
    pixels = list(img.getdata())
    scroll_zone = int(w * 0.06)  # typical scrollbar width

    left = w
    for x in range(w):
        for y in range(h):
            p = pixels[y * w + x]
            if not is_bg(p[0], p[1], p[2]):
                left = x
                break
        if left < w:
            break

    right = 0
    for x in range(w - 1, -1, -1):
        for y in range(h):
            p = pixels[y * w + x]
            if x < w - scroll_zone and not is_bg(p[0], p[1], p[2]):
                right = x + 1
                break
        if right > 0:
            break

    top = h
    for y in range(h):
        for x in range(w - scroll_zone):
            p = pixels[y * w + x]
            if not is_bg(p[0], p[1], p[2]):
                top = y
                break
        if top < h:
            break

    bottom = 0
    for y in range(h - 1, -1, -1):
        for x in range(w - scroll_zone):
            p = pixels[y * w + x]
            if not is_bg(p[0], p[1], p[2]):
                bottom = y + 1
                break
        if bottom > 0:
            break

    if left >= right or top >= bottom:
        return img

    return img.crop((
        max(0, left - pad), max(0, top - pad),
        min(w, right + pad), min(h, bottom + pad),
    ))


def process(path, target_width, crop, auto_trim_flag):
    img = Image.open(path)
    w, h = img.size
    ops = []

    if auto_trim_flag:
        img = auto_trim(img)
        w2, h2 = img.size
        if (w2, h2) != (w, h):
            ops.append(f"auto-trim {w}x{h} -> {w2}x{h2}")
            w, h = w2, h2

    if crop:
        top, height = crop
        img = img.crop((0, top, min(top + height, h)))
        w, h = img.size
        ops.append(f"crop({top},{height})->{w}x{h}")

    if w > target_width:
        ratio = target_width / w
        img = img.resize((target_width, int(h * ratio)), Image.LANCZOS)
        ops.append(f"resize->{target_width}x{img.size[1]}")

    if ops:
        img.save(path, optimize=True)
        print(f"  + {path}: {' + '.join(ops)}")
    else:
        print(f"  - {path}: unchanged ({w}x{h})")


def main():
    parser = argparse.ArgumentParser(description="Resize and crop screenshots for docx")
    parser.add_argument("target", help="Image file or directory of PNGs")
    parser.add_argument("--width", type=int, default=1600, help="Target width in px")
    parser.add_argument("--crop", type=int, nargs=2, metavar=("TOP", "HEIGHT"),
                        help="Crop rectangle: (top_offset, height)")
    parser.add_argument("--auto-trim", action="store_true",
                        help="Auto-detect content bounding box and trim empty borders")
    args = parser.parse_args()

    target_path = os.path.abspath(args.target)
    files = []
    if os.path.isdir(target_path):
        files = sorted(
            os.path.join(target_path, f)
            for f in os.listdir(target_path)
            if f.lower().endswith(".png")
        )
        if not files:
            print(f"No PNG files found in {target_path}")
            sys.exit(1)
    elif os.path.isfile(target_path):
        files = [target_path]
    else:
        print(f"Path not found: {target_path}")
        sys.exit(1)

    for f in files:
        process(f, args.width, args.crop, args.auto_trim)

    print("Done.")


if __name__ == "__main__":
    main()
