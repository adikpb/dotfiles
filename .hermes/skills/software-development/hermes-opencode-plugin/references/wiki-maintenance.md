# Maintaining the hermes-opencode LLM wiki against pinned clones

The `wiki/` KB documents the surfaces this plugin consumes. It is sourced from
two release-tag-pinned clones under `.slim/clonedeps/repos/`:
- `NousResearch__hermes-agent` (Hermes plugin/approval contract) — default branch `main`, tags `v2026.8.x`
- `anomalyco__opencode` (opencode v1 HTTP/SSE API) — default branch `dev`, tags `v1.18.x`

The `clonedeps.json` records the pinned `ref` per dependency.

## Updating both clones to latest

Clones are shallow/tag checkouts; the remote default branch may not be a local
ref after a plain `git fetch`. Fetch the specific branch or tag explicitly:

```bash
cd .slim/clonedeps/repos/NousResearch__hermes-agent
git fetch origin 'refs/tags/v2026.8.13:refs/tags/v2026.8.13'   # or 'refs/heads/main:refs/remotes/origin/main'
git checkout v2026.8.13
git describe --tags          # confirm

cd .slim/clonedeps/repos/anomalyco__opencode
git fetch origin 'refs/tags/v1.18.18:refs/tags/v1.18.18'
git checkout v1.18.18
```

- **Hermes**: `git tag --sort=-creatordate | head` shows the newest release tag
  (e.g. `v2026.8.13`). The clone ships at an older tag; bump to the newest.
- **OpenCode**: `git tag --sort=-creatordate | head` newest; `dev` is 19+ commits
  ahead of the newest tag but **tags are the pinned surface** — update to the
  newest tag, not `dev`. Verify the newest tag with `git describe --tags` at HEAD.
- After bumping, update `clonedeps.json` `resolvedVersion` + `ref` for both.

## Diffing what changed (targeted, not the whole 22k-commit bump)

A huge commit count (Hermes 22.9k) almost never means the consumed surface
changed. Find the real surface drift:

```bash
# which source files the plugin cites, and what changed between tags
git log --oneline v2026.8.3..v2026.8.13 -- hermes_cli/plugins.py hermes_cli/config.py tools/approval.py
# confirm the exact symbols the plugin depends on STILL EXIST at the new tag
grep -nE "def register_hook|def request_tool_approval|display_target = f\"<\{tool_name\}> \(plugin approval rule\)\"" hermes_cli/plugins.py tools/approval.py
```

For opencode, the v1 instance endpoints the bridge calls:
```bash
git log --oneline v1.18.13..v1.18.18 -- \
  packages/opencode/src/server/routes/instance/httpapi/handlers/{session,permission,question}.ts \
  packages/schema/src/event-manifest.ts
# confirm v1 event names + endpoints still exist
grep -nE "permission.asked|question.asked|session.status" packages/schema/src/v1/*.ts packages/schema/src/session-status-event.ts
```

Refresh ONLY the wiki pages whose cited facts shifted. Behavioral-contract facts
that are unchanged should be marked "re-verified vX.Y.Z, unchanged" rather than
re-anchoring every `file.py:NNNN` line number (line numbers shift every release;
**symbol names** in citations survive).

## Citation style that survives version drift

- BAD (brittle):  `register_tool(...) — line 410`
- GOOD (stable):  `register_tool(...) — hermes_cli/plugins.py` + symbol name
- When you MUST cite a line, re-anchor it against the new tag and note the
  version: `plugins.py:1602 (v2026.8.13)`.

## Verify before declaring done

- Link-integrity scan: build the set of page basenames; assert every
  `[[target]]` resolves to a real file. (Literal `[[page-name]]` / `[[wikilinks]]`
  in SCHEMA.md/log.md are doc examples, not links — ignore those.)
- Source-truth check: the wiki's behavioral claims (e.g. "display_target is
  hardcoded", "rule_key mandatory on pre_tool_call", "smart_approve terminal-only")
  must be re-confirmed against the new tag with `grep`, not assumed stable.

## The wiki is gitignored — edits are on-disk only

`wiki/` is excluded by a `.gitignore` block (`# BEGIN hermes-opencode-plugin
wiki`). `git status` stays clean after wiki edits; `git check-ignore wiki`
confirms. The only tracked clone-bump artifact is `.slim/clonedeps.json`. Report
the wiki as "updated on disk (local KB, gitignored)" — never "committed the
wiki". Offer to un-ignore + commit if the user wants it tracked.
