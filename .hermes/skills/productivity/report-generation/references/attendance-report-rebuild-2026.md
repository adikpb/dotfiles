# Worked example: June -> July attendance report rebuild

Source: a typical exported Attendance Monthly Report PDF (letterhead
image + yellow header row + day columns). Fictional employee and
employer. Task: July version, same working days/times for 1-24, days
25-31 marked A (absent, including 31), attended minutes correct,
summary recomputed.

## Source geometry (all points, top-left origin)
- Page: 1190.98 x 841.97 (A3 landscape). Fonts: ArialMT 9.9 (body),
  Arial-BoldMT 12 (title) / 9.9 (From-To) / 8.1 (header), Helvetica 9.9 (times/values).
- Letterhead = ONE background image Im5 (1661x2463 portrait source displayed
  squished to x 45.7..1107.5, y ~16..842). ~99% off-white pixels; content mostly
  in the top band. Extract via pypdf: `page.images['/Im5'].image.save(...)`.
- Gridlines: vlines x = [70.1, 116.6, 139.1, 157.9, 181.1, 212.6, 244.1, 275.6,
  307.1, 338.6, 370.1, 401.6, 433.1, 464.6, 496.1, 527.6, 559.1, 590.6, 622.1,
  653.6, 685.1, 716.6, 748.1, 779.6, 811.1, 842.6, 874.1, 905.6, 937.1, 968.6,
  1000.1, 1031.6, 1105.1]; hlines at top = [13.1, 111.1, 126.8, 140.1, 151.2,
  164.4, 199.6, 234.8, 247.9, 261.1, 284.7, 308.3, 321.4, 334.6, 347.8, 388.2];
  stroke width 0.22677. Header row cells filled yellow (1,1,0); body cells white.
- Rows: header 140-151, Date 151-164, Check-in1 164.4-199.6, Check-out1
  199.6-234.8, OT 234.8-247.9, Late 247.9-261.1, Early Leave 261.1-284.7,
  Attended 284.7-308.3, Break 308.3-321.4, Status 321.4-334.6, Summary
  334.6-347.8, Notes 347.8-388.2.
- Column centers (x of day numbers): 1:125, 2:146, 3:167, 4:194, 5:226, 6:257,
  7:289, 8:320, 9:352, 10:381, ..., step ~31.5, 24:822, 25:853, 26:885, 27:916,
  28:948, 29:979, 30:1011, 31:1063 (last column wider: 1031.6-1105.1).
- Time cells render the full timestamp as THREE stacked segments HH: / MM: / SS
  (offsets +5.2 / +16.6 / +28.0 pt from row top) because the exporter wraps
  narrow cells. Value = segments concatenated top-to-bottom.

## Sample month data (day: checkin / checkout / attended-min)

Synthetic times for the rebuild recipe. Weekends 7/14/21 are off (`-/- 0`).

1 09:00:00/18:00:00 540; 2 09:00:00/18:00:00 540; 3 09:00:00/18:00:00 540;
4 09:00:00/18:00:00 540; 5 09:00:00/18:00:00 540; 6 09:00:00/18:00:00 540;
7 -/- 0; 8 09:00:00/18:00:00 540; 9 09:00:00/18:00:00 540; 10 09:00:00/18:00:00 540;
11 09:00:00/18:00:00 540; 12 09:00:00/18:00:00 540; 13 09:00:00/18:00:00 540;
14 -/- 0; 15 09:00:00/18:00:00 540; 16 09:00:00/18:00:00 540; 17 09:00:00/18:00:00 540;
18 09:00:00/18:00:00 540; 19 09:00:00/18:00:00 540; 20 09:00:00/18:00:00 540;
21 -/- 0; 22 09:00:00/18:00:00 540; 23 09:00:00/18:00:00 540; 24 09:00:00/18:00:00 540;
25-30 A(absent), attended 0; 31 (nonexistent day) -/-/0.

## Reading gotchas in the source
- CID/subset fonts: extract_words() scrambles strings. Use char positions,
  cluster into lines by top (tol ~3 pt), join by x0.
- Day 1 can hold TWO overlapping time strings (stale copy). Prefer the pair
  whose checkout-minus-checkin matches the attended-minutes cell.
- Two summary rows can exist as overlapping text. OCR the visible one.
- Status "#" may print on days that are not weekends while the summary
  still says Weekend:N. Treat the summary as authoritative.

## Decisions for the rebuilt month
- Days 1-24 copied from the source month unchanged; 25-31 status A (time
  cells AND status row), attended 0, check-in/out "A".
- Weekend "#" kept ONLY on true no-work days (7, 14, 21 here); stray "#"
  on midweek days cleaned to "-" so the day counts sum.
- Recompute the summary line from those counts (normal / weekend / absence
  / attended duration).
- Footer Date/Time can stay at the original export stamp if the layout
  requires it; do not invent a new clock unless the user asks.
- In headers "Check-out1" must be drawn wrapped ("Check-" + "out1") or its
  tail glyph lands inside the day-1 cell.
- Reportlab baseline: y = 841.97 - (top + 0.72*size).
