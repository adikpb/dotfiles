---
name: oss-contribution-prep
description: "Use before OSS PRs: read the governing md files first."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [GitHub, Open-Source, Contributing, PR, Documentation]
    related_skills: [github-pr-workflow, hermes-source-development]
---

# OSS Contribution Prep

What to read and verify BEFORE opening a PR against any open-source repo. The user expects this as a standing pre-contribution step: they explicitly quizzed on it ("what md files should you read before even thinking of contributing?") and then required re-reading the governing docs before the final PR check. Skipping these files is how PRs get closed for violating rules the maintainers wrote down.

## 1. Read the governing docs (before creating a branch)

1. **README.md** (or docs home) — what the project is, how to install/run.
2. **CONTRIBUTING.md** — dev setup, branch naming, commit conventions, PR process, test requirements. Fetch and read the FULL file (`curl -s https://raw.githubusercontent.com/<owner>/<repo>/main/CONTRIBUTING.md`), not just the top.
3. **CODE_OF_CONDUCT.md** — behavioral expectations.
4. **LICENSE** — what you're allowed to do with the code.
5. **SECURITY.md** — vulnerability reporting (never via public issues).
6. **`.github/` templates and config**: `PULL_REQUEST_TEMPLATE.md` (governs the body exactly: sections, order, checklist — write the body with its `##` sections verbatim, then enrich inside them; never omit or rename its sections), `ISSUE_TEMPLATE/`, `CODEOWNERS`.
7. **Agent/dev instruction files**: `AGENTS.md`, `CLAUDE.md`, `.cursorrules` — these override your defaults. Find them: `find . -name "AGENTS.md" -o -name "CLAUDE.md" -o -name ".cursorrules"`. Sub-project files (e.g. `apps/desktop/AGENTS.md`) scope OUT of your change, but check and say why.
8. **Docs that document the behavior you're changing** — before marking "N/A" on the template's documentation/config checklist boxes: `grep -rn "<changed-keyword>" website/docs/` and inspect `cli-config.yaml.example` (or equivalent) for the changed surface. N/A is only honest after checking, never by assumption.
9. **Search closed PRs and issues** for your topic — duplicates get closed fast, and close comments carry reusable evidence (bot verdict tags, policy rulings).

## 2. PR body: follow the repo's template

- Check `.github/PULL_REQUEST_TEMPLATE.md` in the target repo FIRST; the body must match its sections verbatim. It is fine to ADD content beyond the template (evidence tables, out-of-scope notes), never to omit or rename its sections.
- Checklist boxes must be filled honestly: unchecked + annotated beats checked + false. If a note pointer is needed, reference a heading that actually resolves (GitHub auto-anchors `## Headings` as `#headings`).
- "I've added tests" is REQUIRED for bug fixes — write a regression test and commit it separately (`test(scope): ...`).
- Delete template sections that don't apply (e.g. "For New Skills" on a non-skill PR).
- Write the body to a temp file and pass it: `gh pr edit <n> --repo <owner>/<repo> --body-file /tmp/pr-body.md` (avoids shell-escaping pain).

## 3. Final pre-submit verification pass (before declaring a PR done)

Re-read the governing md files (template, CONTRIBUTING, AGENTS.md), then verify the LIVE PR against them line by line — never trust the local draft:

1. Fetch the live body and grep for regressions: em dashes (0, if user forbids them), stale test counts, dangling comment references ("see the comment on this PR" breaks when comments get deleted — bodies must be self-contained), present `##` sections.
2. Type of Change: exactly ONE box checked when the template says "the one that applies".
3. Cross-check live PR metadata: `gh pr view <n> --json state,mergeable,baseRefOid,headRefOid,additions,deletions,changedFiles` — base equals current main, MERGEABLE, conventional commits, local HEAD == fork remote HEAD.
4. If the PR is a draft and everything is addressed, flip it: `gh pr ready <n>`.

## User writing preferences (binding for this user)

- **Never use em dashes (—)** in PR bodies, comments, commit messages, or chat. Use commas, colons, semicolons, or restructure. Verify after editing: `grep -c "—" <file>` must be 0.
- **No decorative/emoji headings** in comments (e.g. `## Addressed the follow-up ✓` was explicitly called out as bad).
- **State the plan before editing PR content** ("tell me what you are gonna do before doing it"): narrate the exact edits, then execute.
- **Don't duplicate body content as comments** — if a note is already in the PR body, comments shouldn't repeat it; prefer the body as the single home for scope notes.

## Notes

- For the Hermes Agent repo specifically (`NousResearch/hermes-agent`), see the `hermes-source-development` skill: sweeper-bot loop, `max-tokens-knob` policy, full-suite pre-existing-failure proof on clean-main worktrees, `gh api` comment editing with GraphQL databaseIds.
- Full PR lifecycle (branch, commit, CI, merge) is covered by the bundled `github-pr-workflow` skill.
