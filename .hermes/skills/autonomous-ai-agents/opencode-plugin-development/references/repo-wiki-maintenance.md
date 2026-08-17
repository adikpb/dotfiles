# Editing the in-repo requirements wiki (hermes-opencode-plugin)

The design-spec wiki for this bridge lives INSIDE the repo at `<repo>/wiki/`
(gitignored, WIKI_PATH unset — never `~/wiki`). Orient with `SCHEMA.md` +
`index.md` + `log.md` before any edit. Every page needs `sources:` frontmatter
with per-claim refs (path:line) and a `confidence` field; the local SCHEMA
enforces the evidence rule (claim verified against the vendored clones in
`.slim/clonedeps/repos/` BEFORE it is written).

## Operational pitfalls (from 2026-08-09 editing sessions)

- **log.md appends via `patch` can merge lines.** When the file's last line
  lacks a trailing newline, the appended entry concatenates onto it (diff shows
  `old+new` on one line, and re-patching reports "already applied" while the
  file is still wrong). After every log append, `read_file` the tail; if
  merged, replace the merged line with the two separate lines in one patch.
- **Write pages in chunks.** Very large single `write_file` calls (several KB
  of content) can stall the tool stream mid-delivery. Write the page skeleton
  first, then append sections via `patch` mode replace. Keep each tool call
  under ~8K tokens.
- **Verify before writing.** This wiki's SCHEMA treats the vendored clones
  (`anomalyco__opencode` v1.18.13, `NousResearch__hermes-agent` v2026.8.3) as
  the ground truth: read the source first, then cite `path:line` in the page's
  `sources:` frontmatter. Never write claims from memory of the spec.
- **Prefer patches over rewrites.** Update existing pages ([[wikilink]]-level
  references) with targeted `patch` replaces per section; full-file rewrites
  risk the chunking problem above and clobber hand-edited prose. The one
  exception: new standalone pages get a full `write_file` (kept small).

## Lint before finishing

Run `scripts/wiki-lint.py` from the skill's scripts directory (or the inline
equivalent): it scans `wiki/{entities,concepts,comparisons,queries}` for
broken wikilinks (resolving links that only appear in index.md too), orphan
pages not listed in index.md, and index entries with no file on disk. The
verification in this session: 18 pages, 0 broken, 0 orphans after the run.

Key pages: `concepts/plugin-requirements.md` (the spec, R1-R6 + settled
decisions), `concepts/hermes-approval-route.md`, `concepts/opencode-permissions.md`,
`concepts/opencode-commands.md`, `concepts/opencode-question-api.md`,
`entities/opencode-http-api.md`.