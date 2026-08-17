# PR / Issue Comment-Graph Triage (gh CLI)

Use when the user asks to trace PR comment trails, e.g. "check all comments of the PRs I tagged, get the PRs mentioned in them, then their comments" (DFS to a given depth).

## Core commands

```bash
# PR metadata (status + title)
gh pr view <n> --repo <owner>/<repo> --json number,title,state,mergedAt,body \
  --jq '"#\(.number) [\(.state)] merged=\(.mergedAt != null)\n\(.title)\n---\n\(.body)"'

# Issue comments on a PR live under issues/<n>/comments (NOT pulls/<n>/comments)
gh api repos/<owner>/<repo>/issues/<n>/comments --jq '.[] | "--- @\(.user.login):\n\(.body)\n"'

# Inline review comments (line-level) and review summaries:
gh api repos/<owner>/<repo>/pulls/<n>/comments --jq '.[] | "--- @\(.user.login):\n\(.body)\n"'
gh api repos/<owner>/<repo>/pulls/<n>/reviews --jq '.[] | "--- @\(.user.login) \(.state):\n\(.body)\n"'

# An issue, when the number isn't a PR:
gh issue view <n> --repo <owner>/<repo> --json number,title,state,body
```

## DFS traversal algorithm

1. **Depth 0** — the tagged/root PRs. Fetch metadata + issue comments + inline comments for each.
2. **Extract references** — regex `#\d+` from comment bodies AND PR bodies. Bodies matter: a PR's "Closes #N" or "Related: #N" is an edge.
3. **Depth 1..N** — recurse into referenced numbers. For each: try `gh pr view` first; if GraphQL says "Could not resolve to a PullRequest", it's an issue → `gh issue view`.
4. **Build the tree** — depth-indented structure: `depth 0 → depth 1 (in comments) → depth 2 (in those PRs' comments)`.
5. **Table output** — columns: depth, PR, what it does, status, reason for status. The "reason" almost always comes from a bot comment (see sweeper verdicts below) or a human maintainer comment (e.g. "cherry-picked onto main via PR #X").

## hermes-sweeper bot verdicts (NousResearch/hermes-agent)

Machine-readable tags in close comments:

| Verdict tag | Meaning | Re-scope strategy |
|---|---|---|
| `reason=not_planned` | Design-direction rejection (e.g. `max-tokens-knob` policy) | Align with the policy the close cites; the close comment usually states the accepted alternative explicitly |
| `reason=implemented_on_main` | A broader fix already covers this path | Don't re-litigate; find the merged fix and align (often: delete your narrow branch, the broad fix supersedes it) |
| `reason=cannot_reproduce` / `incoherent` | Premise doesn't hold | Verify the premise against actual code before retrying |

## Pitfalls

- **A number that fails `gh pr view` is often an issue, not a typo** — e.g. #13901 in this session. Always fall back to `gh issue view`.
- **PR issue comments are NOT under `pulls/<n>/comments`** — that endpoint only returns inline review comments. The main comment thread (including bot verdicts) is `issues/<n>/comments`.
- **Sweeper verdicts are the reason for status in most cases** — quote them verbatim in the "reason" column rather than paraphrasing policy.
- **Depth is user-specified** — a "depth 2 (dfs)" request means roots → referenced PRs → referenced-by-those. Stop there; note deeper nodes as one-line extras ("depth 3, outside requested depth").
