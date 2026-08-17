# Avoiding ghost blank pages in pandoc → docx → PDF reports

## Symptom
A multi-section report (one major section per page) comes out with invisible
empty pages after some sections. pypdf text extraction reports those pages as
0 chars; vision on the raster shows a blank or near-blank page. The page count
talks (e.g. "16 pages") but pages 9 and 11 are ghost pages.

## Root cause
The common recipe is to insert a raw OpenXML page-break block before each
`## ` heading:

```````{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```````

This usually works. But when a section's content (typically a wide table) fills
its page exactly, the `---` horizontal-rule separator + the break paragraph land
alone at the top of a fresh page, and the following heading pushes again. The
result is a mostly-empty page (the rule is a graphic, so text extraction sees
0 chars). Same effect if a previous section ends right at a page boundary.

## Robust fix: switch page breaks to the Heading style
Stop using manual break paragraphs entirely. Set `pageBreakBefore` on the
Heading 2 (or Heading 1) style in a pandoc reference doc:

```bash
# 1. Generate the default reference doc once
pandoc --print-default-data-file reference.docx > ~/.pandoc/ref.docx

# 2. Add <w:pageBreakBefore/> to the Heading2 <w:style> block's <w:pPr>
#    (unzip, edit word/styles.xml, rezip into ~/.pandoc/ref.docx) -- do this ONCE,
#    it persists across renders.

# 3. Render with the reference doc on EVERY call
pandoc --reference-doc="$HOME/.pandoc/ref.docx" report.md -o report.docx
soffice --headless --convert-to pdf --outdir . report.docx
```

Every `## ` section now starts on a fresh page with NO manual break paragraph in
the body, so no empty page can form. Remove the redundant standalone `---`
separator lines that previously preceded each heading (keep the title-page one).

## Verification
- `unzip -p out.docx word/styles.xml | grep -A1 'styleId="Heading2"'` shows
  `<w:pageBreakBefore/>`.
- pypdf per-page check: no page has 0 extracted chars; each major section's
  title appears at the top of its own page.
- Note: pass the reference doc as `$HOME/.pandoc/ref.docx`, not `~/.pandoc/...` —
  pandoc does not expand a literal `~`.

## Also check: a `---` glued to a bullet
When parts are concatenated, a horizontal-rule separator can be glued to the end
of a line: `...TrustedGenAi)---`. It renders as a literal trailing dash. Split
it onto its own line (`sed`) so it becomes a true horizontal rule, then re-render.