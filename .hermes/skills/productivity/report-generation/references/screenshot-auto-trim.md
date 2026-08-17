# Screenshot Auto-Trim: Edge Cases & Per-Theme Thresholds

## Why auto-trim is needed

Browser-captured screenshots typically contain 50-80% empty space:
- **Centered layout**: Content constrained to `max-width: 800px` in a 1500px viewport leaves ~350px of dark background on each side.
- **Full-page capture**: `browser_vision()` captures the entire scroll height — a 7-row table in a dashboard produces a 7000+ px tall image where only the top 1500px is content.
- **Scrollbar strip**: Full-page captures always include the native scrollbar as a persistent ~80px strip on the right.

Auto-trim removes all this waste before embedding in a docx.

## Background threshold adjustments

The `is_bg()` function uses a threshold of `R < 40, G < 40, B < 45` which works for the Aegis SOC dark theme (`background: #1a1d27`). For other themes:

| Theme | Background color | Threshold R/G/B | Notes |
|-------|-----------------|-----------------|-------|
| Aegis SOC dark | `#1a1d27` | `(40, 40, 45)` | Default |
| GitHub dark | `#0d1117` | `(20, 20, 30)` | Very dark |
| VS Code dark | `#1e1e1e` | `(35, 35, 35)` | Uniform |
| Tailwind gray-900 | `#111827` | `(25, 30, 45)` | Blue-tinted |
| Light theme | `#ffffff` | `(245, 245, 245)` | Near-white |

For light themes, invert the logic: `is_bg` returns True when all channels are > 245.

## Edge cases

### Scrollbar strip detection

The scrollbar sits on the rightmost ~6% of the image. The auto-trim algorithm excludes the rightmost 6% from content detection. If the scrollbar is on the left (RTL layout), adjust `scroll_zone` to skip the left edge instead.

If no scrollbar is visible (e.g., headless browser with no scrollbar), set `scroll_zone = 0`.

### Gradient or textured backgrounds

If the background isn't a solid color, the pixel-level `is_bg()` scan will see noise everywhere. Solutions:
1. Convert to grayscale first, then check luminance vs a threshold.
2. Sample the four corners to determine background color, then check `abs(r - bg_r) < tolerance`.
3. Apply a median filter before scanning to smooth noise.

```python
def is_bg_from_corners(img, tolerance=20):
    """Sample corners to determine background color adaptively."""
    w, h = img.size
    corners = [
        img.getpixel((0, 0)),
        img.getpixel((w-1, 0)),
        img.getpixel((0, h-1)),
        img.getpixel((w-1, h-1)),
    ]
    bg_r = sum(c[0] for c in corners) // 4
    bg_g = sum(c[1] for c in corners) // 4
    bg_b = sum(c[2] for c in corners) // 4
    
    def check(r, g, b, a=255):
        return abs(r - bg_r) < tolerance and \
               abs(g - bg_g) < tolerance and \
               abs(b - bg_b) < tolerance
    return check
```

### Modal overlays with semi-transparent background

Modal overlays use `position: fixed; background: rgba(0,0,0,0.7)`. This is darker than the page background but not fully black. The default threshold `(40, 40, 45)` typically catches this since `rgba(0,0,0,0.7)` produces RGB values around `(18, 18, 18)` when composited against a `#1a1d27` background.

If the overlay background isn't caught, lower the threshold or use a multi-pass approach: first detect the modal overlay's bounding box (it's typically much darker than the page background), then crop to the modal content within it.

### Images with content touching the edges

If the web page has a header bar or border that goes edge-to-edge, the left/right scan will find content at column 0, and no horizontal trimming occurs. This is correct behavior — there's nothing to trim.

### No content detected fallacy

If the image is entirely background (e.g., blank page, loading state), `auto_trim` returns the image unchanged. The caller should handle this gracefully rather than producing a zero-size crop.

## Verification after trimming

```bash
# Check all screenshots are < 4000px on both axes after processing
sips -g pixelWidth -g pixelHeight screenshots/*.png | grep pixel

# Check no image has a scrollbar-width leftover strip
python3 -c "
from PIL import Image
import os
for f in sorted(os.listdir('screenshots/')):
    if not f.endswith('.png'): continue
    img = Image.open(os.path.join('screenshots/', f))
    w, h = img.size
    right_col = [img.getpixel((w-1, y)) for y in range(min(10, h))]
    left_col  = [img.getpixel((0, y)) for y in range(min(10, h))]
    avg_r = sum(p[0] for p in right_col) / len(right_col)
    avg_l = sum(p[0] for p in left_col) / len(left_col)
    flags = []
    if avg_r < 40: flags.append('scrollbar strip right')
    if avg_l < 40: flags.append('scrollbar strip left')
    flag_str = ' (' + ', '.join(flags) + ')' if flags else ''
    print(f'{f}: {w}x{h}{flag_str}')
"
```
