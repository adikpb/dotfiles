# PR merge-pattern analysis (predicting whether a PR will merge)

Technique for estimating merge likelihood of an open PR (especially a first-time
contributor's) by studying the repo's ACTUAL merge behavior. Built and verified
against `NousResearch/hermes-agent` on 2026-07-31.

## Verified findings (hermes-agent, 2026-07-31)

1. **First-time contributors DO get merged, at scale.** 1,492 of 2,369 distinct
   authors on `main` (63%) have exactly ONE commit ever on the branch: their PR
   was squash-merged and they never returned. Weekly first-timer merges were
   30-120/week sustained (W15-W30), 30 in W31 alone. First-timer status is NOT a
   blocker in this repo.

2. **`keep_open` verdicts die only by author action.** Sampled ~600 recent PRs
   by sweeper verdict vs final state:
   - 300 most recent MERGED: 6 carried `keep_open` (2%); the rest had no sweeper
     comment (maintainer PRs mostly don't get swept).
   - 300 most recent CLOSED-not-merged: 25 carried `keep_open`, 275 none.
   - Every `keep_open` PR that closed was closed BY ITS OWN AUTHOR: #75190
     "opened in error", #69967 "Closing in favour of #75262" (superseded), the
     rest abandoned. The bot and maintainers never close a `keep_open` PR.
   - Implication: `keep_open` + author still engaged + mergeable + up to date =
     strong merge signal. The only failure modes are author abandonment and
     supersession by a newer PR on the same area.

3. **Precedent matching works.** #74581 (mollusk, near-first-timer): created
   07-30T04:10, sweeper review 07-30T18:07 (`keep_open salvageability=high`),
   merged 07-30T19:08, one hour after review, same day. The other five
   `keep_open` merges (#64623, #64686, #63164, #65254, #62718, all AtakanGs)
   merged in a 20-minute batch on 07-28: maintainers sweep `keep_open` PRs in
   batches, so a clean `keep_open` PR is a wait-for-the-next-batch situation,
   not a rejection risk.

## Techniques

### 0. Determine whether a bot re-reviews (one-pass vs push-triggered)

Verified for the hermes-agent sweeper on 2026-07-31: it is **one-pass — each
PR gets exactly ONE review, ever, and no action triggers another one.** Method
that established it (reuse when the question is "did the bot re-review yet"):

```bash
# 1. Count sweeper review comments per PR across a sample (GraphQL batch):
#    len([c for c in comments if "hermes-sweeper:review" in c.body]) > 1 => re-review
#    Zero found in 200 PRs sampled (first:20 comments each).
# 2. Check whether review comments are EDITED in place:
gh pr view <n> --repo NousResearch/hermes-agent --json comments \
  --jq '.comments[] | select(.body | contains("hermes-sweeper:review")) | {created: .createdAt, updated: .updatedAt}'
#    updated == None (field absent) => never edited; verdicts are never revised.
# 3. Prove batch-cron, not push webhook: histogram review-post times by UTC hour
#    (clusters/bursts of 5-6 at once, e.g. 04:00Z/07:00Z/09:00Z on 07-30), and
#    find a PR reviewed hours after creation with no commits between (e.g. #74581
#    created 04:10, reviewed 18:07, single commit at 04:09).
# 4. Prove ready-for-review is not a trigger: the sweeper reviewed our DRAFT PR
#    21 min after creation (drafts get swept too).
# 5. Prove no manual trigger exists: scan PR comments for re-review requests
#    ("re-?review|/sweep|please.*review.*again|sweeper", non-maintainer authors);
#    none ever produced a second sweeper comment.
```

Consequences for workflow: post an "Addressed the sweeper review" comment with a
coverage table as the protocol, but understand it is read by the HUMAN
maintainer, not the bot. `keep_open` is a permanent state (never revoked, never
author-auto-closed by the bot); merge does not require a re-review. A
"latest review" phrasing in a contributor comment (#68206) refers to a fresh
sweeper comment on a NEWER PR or a human review, not a re-review of the same PR.

### 1. Identify first-time contributors from LOCAL git (zero API cost)
An author with exactly 1 commit on `origin/main` = one squash-merged PR = a
first-time contributor whose PR got merged.

```bash
git log origin/main --pretty=%H|%an|%ad|%s --date=short
# In Python: count per author; len(commits)==1 (non-bot) => first-timer.
# Weekly histogram via datetime.date.isocalendar()[1] shows the merge cadence.
```

### 2. Sampling bias: never measure merge rates from an UPDATED_AT-ordered sample
`orderBy: {field: UPDATED_AT, direction: DESC}` under-samples merged PRs: they
stop being updated after merge and sink below open/stale ones. A "recent 400"
sample showed ZERO merged `keep_open` PRs even though #74581 was merged, a pure
artifact. Sample by STATE: separate GraphQL sweeps for `states: [MERGED]` and
`states: [CLOSED]`, plus an open sweep for the denominator.

### 3. Use GraphQL for batch PR+comment fetch (REST search rate-limits fast)
The REST `search/issues` API rate-limits quickly, and a per-author filter inside
a paginate-until-empty loop short-circuits (page 1 has <100 filtered rows, so
the loop exits after one page). GraphQL has a separate pool and fetches 100
PRs + their comments in one call:

```bash
gh api graphql -f query='query { repository(owner:"NousResearch", name:"hermes-agent") {
  pullRequests(first:100, states:[MERGED], orderBy:{field:UPDATED_AT,direction:DESC}) {
    pageInfo { hasNextPage endCursor }
    nodes { number state mergedAt author { login }
            comments(first:8) { nodes { body } } } } } }'
```

Then parse `review-verdict=(\S+)` and `salvageability=(\S+)` out of
`hermes-sweeper` comment bodies. Follow `endCursor` for more pages.

### 4. Determine WHO closed a PR (author-close vs merge): timeline API
```bash
gh api repos/NousResearch/hermes-agent/issues/<n>/timeline?per_page=100 \
  --jq '[.[] | select(.event == "closed") | {actor: .actor.login, commit_id}]'
```
- actor = author, no `commit_id` => author-closed (abandoned/superseded), NOT merged.
- actor = merger + `commit_id` => squash-merged.
- Also useful: `gh pr view <n> --json stateReason,closedBy`, and the last
  non-sweeper comment for "Closing in favour of #X" / "opened in error" text.
- `gh pr view --json state` distinguishes MERGED from CLOSED (GraphQL `state`
  field does too).

### 5. Assemble the prediction for a specific PR
Gather, in order:
1. Sweeper verdict + salvageability (`gh pr view --json comments`).
2. Whether the author addressed the cited tests: compare sweeper comment
   timestamp vs the PR's commit timestamps. The tests must land AFTER the
   review (this session: review 06:12, test commits 06:15 + 06:23, complaint
   closed 11 minutes after filing, on the exact cited files).
3. Draft state + mergeable + base/head OIDs vs `origin/main`
   (`gh pr view --json isDraft,mergeable,baseRefOid,headRefOid`).
4. Whether a newer PR supersedes it on the same code area (search open PRs for
   the same file/keyword).
5. Closest precedent: same verdict class (e.g. `keep_open` + `salvageability=high`)
   and same PR shape (small `fix(...)` + regression tests), then its
   review-to-merge delta.

## Output shape that worked
A verdict table (sweeper verdict -> final state counts), the first-timer merge
weekly histogram, the direct precedent's timeline, and a bullet list of the
specific PR's evidence chain. The user's question ("will our PR get merged")
was answered with: high confidence, wait-for-next-batch risk profile, and the
specific caveat (sweeper had not re-reviewed after the test commits).
