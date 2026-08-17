# LibreOffice PDF Export Filter Options

## Reference: Filter JSON syntax

LibreOffice headless accepts filter options as a JSON object appended to the `--convert-to` filter name with a colon delimiter:

```
--convert-to 'pdf:writer_pdf_Export:{"Key":{"type":"<type>","value":<value>}}'
```

The types are: `long` (integer), `boolean` (true/false), `string`, `double`.

## Known working combination (lossless, high-res)

```bash
soffice --headless --convert-to \
  'pdf:writer_pdf_Export:{"SelectPdfVersion":{"type":"long","value":1},"UseLosslessCompression":{"type":"boolean","value":true},"MaxImageResolution":{"type":"long","value":600},"ExportImagesOriginalSize":{"type":"boolean","value":true}}' \
  --outdir /tmp report.docx
```

This produces a PDF where all images use FlateDecode (zlib/PNG) instead of DCTDecode (JPEG). Image dimensions stay close to original (LibreOffice still downscales proportionally to fit the page layout, but without JPEG artifacts).

## Verification

```bash
python3 -c "
with open('report.pdf', 'rb') as f:
    c = f.read()
print('Image references:', c.count(b'/Image'))
print('JPEG streams:', c.count(b'/DCTDecode'))
print('PNG/zip streams:', c.count(b'/FlateDecode'))
print('Total size:', len(c)//1024, 'KB')
"
```

Expected: `JPEG: 0`, `PNG/zip: > number_of_images`.

## Pitfalls

- The JSON syntax is sensitive — no extra spaces inside the outer JSON object
- The `--convert-to` value must be single-quoted on macOS (double quotes inside single quotes)
- LibreOffice still downscales images to fit the page layout even with `ExportImagesOriginalSize=true`; the setting prevents additional downscaling beyond layout fit
- The `MaxImageResolution` value (600) caps DPI but does not upscale; images under 600 DPI are left at original resolution
