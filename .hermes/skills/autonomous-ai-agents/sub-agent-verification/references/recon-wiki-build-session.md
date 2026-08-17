# Recon-Based Wiki Build: Batch Delegation Session Case

Session 2026-08-09: user asked to build a gitignored LLM wiki covering
Hermes + OpenCode plugin surfaces, grounded in cloned source repos.
Workflow: 3 parallel recon subagents → disk-recovered reports → wiki pages.

## What worked

1. **Dispatch 3 parallel recon agents** (`delegate_task` batch, one goal per
   surface): (a) Hermes plugin surface, (b) Hermes agent internals,
   (c) OpenCode plugin API + SDK. Each got exact repo paths, explicit
   deliverable (structured markdown report with "Key files" table), and
   instructions to quote small verbatim snippets with line refs.
2. **Ask each agent to say exactly what it verified** (file + line refs,
   `git describe --tags` output). Subagent 3 ended its report with a
   full list of files read and "No fabricated symbols" — that explicit
   provenance claim makes the report usable as fact.
3. **Batched handing**: even so, the consolidated batch message truncated
   every report (head+tail only). Full recovery worked via
   `~/.hermes/cache/delegation/subagent-summary-<n>-<ts>.txt` (+
   extraction of the JSON-escaped `"report"` key) and via report files
   agents had written to `/private/tmp/*.md`.
4. Representative real path:
   `~/.hermes/cache/delegation/subagent-summary-1-20260809_074032_596069.txt`
   → JSON block → `report` key → 16 KB markdown, saved back to `/private/tmp/recon_task1.md` for `read_file`.

## The wiki-side pattern (project-local variant)

- `git init` the project first, then `wiki/` in `.gitignore` with a
  `# BEGIN <scope> wiki` block, and `!wiki/` + `!wiki/**` in `.ignore`
  (opencode allowlist) so git ignores it but the coding agent reads it.
- Pages: `frontmatter` (type entity/concept/comparison), wikilinks
  `[[page-name]]`, `sources:` pointing at the clone path, plus
  `runtime: hermes|opencode` + `confidence:` for this two-runtime domain.
- Cross-verify: link-check script (every `[[target]]` resolves to an
  existing page), em-dash sweep after writes (user forbids `—`).
- Author pages from the recon, then spot-check the top claims against
  the clone yourself (e.g. verify hooks catalog entries against the
  source line refs the subagent cited).

## Pitfalls seen

- The whitespace/truncation in the batch message: never author pages
  from the collapsed snippet; always read the on-disk summary file.
- `find /private/tmp -name "*report*"` catches agent-written report
  files; don't re-run the whole recon to recover a report.