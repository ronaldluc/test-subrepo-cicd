# AI review pipeline — replacing `claude-ai-review`

## The problem we're solving

The hosted `claude-ai-review` GitHub App reviews are useful when they run, but the App auto-disables itself periodically — rate limits, billing thresholds, or transient GitHub App health issues. We don't see when or why; reviews just stop. For a tier that's meant to be a CODEOWNER-equivalent gate, intermittent availability is unacceptable.

The fix is to break the single hosted reviewer into three controlled pieces, each addressing a different review need.

## Layer A — CodeRabbit (style + CLAUDE.md compliance)

**Role:** the broad, fast, always-on front-line. Catches style violations, missed checklist items, obvious bugs, broken markdown, CLAUDE.md-rule infractions.

**Install:** CodeRabbit GitHub App on the repo (settings page). Auth is the App's own — nothing we maintain.

**Configuration:** a `.coderabbit.yaml` at the repo root with:
- File-pattern includes / excludes (skip `_research/`, generated files, etc.)
- Rules list that mirrors `CLAUDE.md` universal rules
- "Reviewer profile": tight on prod, lenient on spikes (CodeRabbit supports per-path tone).

**Cost:** flat monthly per repo / per dev. Lower than the deep-review tier and predictable.

**Trust:** CodeRabbit comments are advisory. They don't approve PRs. Required-check from CodeRabbit is the build pass/fail signal it emits (`coderabbit / review` or similar).

**Limit:** doesn't reason about cross-file architecture, doesn't understand the `@-include` chain in nested CLAUDE.md, doesn't go deep on logic. That's the next layer.

## Layer B — Claude Code via a bot account (deep review)

**Role:** the architecture-aware reviewer. Reads the diff, the CLAUDE.md chain for every touched file, the linked architecture docs, and writes a senior-engineer style review.

**Why a bot account, not a user PAT:** GitHub treats `users/<login>.type == "User"` and `type == "Bot"` differently. Our `ai-cannot-approve.yml` workflow already rejects Bot-type approvals. The bot reviewer must be of type `User` (a dedicated human-style GitHub account, e.g. `@conjure-reviewer`) so it can leave reviews that don't trip that guard — *but* it must never be added to CODEOWNERS (so its approval doesn't satisfy required-review).

**Implementation sketch (`.github/workflows/claude-deep-review.yml`):**

```yaml
name: claude-deep-review
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
permissions:
  pull-requests: write
  contents: read
jobs:
  review:
    if: '! github.event.pull_request.draft'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - name: Run Claude Code headless review
        env:
          ANTHROPIC_API_KEY: ${{ secrets.CLAUDE_REVIEWER_KEY }}
          GH_TOKEN: ${{ secrets.CLAUDE_REVIEWER_PAT }}   # bot account PAT
        run: |
          npx -y @anthropic-ai/claude-code \
            --headless \
            --prompt-file .github/prompts/deep-review.md \
            --max-cost-usd 1.50 \
            --pr ${{ github.event.pull_request.number }}
```

**Prompt** lives at `.github/prompts/deep-review.md`. It instructs Claude Code to:
1. Read the diff via `gh pr diff`.
2. Walk the nested CLAUDE.md chain for every touched directory (`@-includes` resolve recursively).
3. Read every architecture doc referenced.
4. Produce a single PR review comment with: critical issues, suggestions, and "questions for the author". Never approve, never request changes — comments only.

**Cost:** capped per PR with `--max-cost-usd`. Typical PR: $0.20–$1.00.

**Trust:** the bot's comments are advisory. The bot is not in CODEOWNERS, so it can't gate merge. `ai-cannot-approve.yml` continues to fail any APPROVED review of `type=Bot`, which the bot account isn't, so legitimate review-comments pass through.

**Open question:** whether to also have this bot post a summarised PR description / TL;DR. Useful for big diffs, but feels like CodeRabbit territory.

## Layer C — Chrome MCP journey tests (end-to-end on previews)

**Role:** the journey-tester. For UI-touching PRs, drive the deployed preview through critical user flows and report concrete failures (broken redirects, missing elements, console errors).

**Setup:**
- Each PR gets a Netlify preview deploy of the affected frontend (already exists).
- A workflow waits for the preview URL, then invokes Claude Code with the Chrome MCP server attached.
- Prompt: "Open ${{ PREVIEW_URL }}. Run journeys A, B, C from `e2e/journeys.md`. For each: succeed-or-fail, with screenshots."

**Why this is now realistic:** today's experiment showed Claude Code + Chrome MCP doing a full journey end-to-end with zero scaffolding — it explored the UI, found the issues, reported them. The bottleneck used to be Selenium-style brittleness; LLM-driven exploration sidesteps it.

**Implementation note:** Chrome MCP runs against a Playwright/headless Chrome instance the workflow boots. Anthropic's official MCP catalog has the `chrome` server. We don't need to maintain it.

**Cost:** higher per-PR than the other two ($1–$3 for a thorough journey set). Run only on PRs labelled `e2e` or that touch `prod/<product>/frontend/`.

**Trust:** comments only. Same rules as Layer B.

## Wiring all three into the PR experience

| Layer | Triggers on | Posts | Required check? |
|---|---|---|---|
| A — CodeRabbit | every PR | inline + summary | yes (its built-in `coderabbit / review`) |
| B — Claude deep review | every non-draft PR | one summary comment | no (advisory) |
| C — Chrome MCP journey | PRs touching `prod/**/frontend/` or labelled `e2e` | comment with findings + screenshots | no initially |

Once we've seen 2–4 weeks of signal, promote B (and possibly C) to required checks.

## Failure modes to design against

1. **Bot account compromise.** The Claude-reviewer PAT has `Pull requests: write` and `Contents: read`. If leaked, an attacker can post fake reviews / read source. Mitigate with: short-lived PATs rotated quarterly; secrets restricted to the deep-review workflow's env; audit logs reviewed monthly.
2. **Cost runaway.** Set `--max-cost-usd` in workflow per call, plus an Anthropic-side spending cap. CodeRabbit is flat; only B and C have per-PR variability.
3. **Reviewer noise.** Three reviewers on one PR can be annoying. Mitigations: CodeRabbit posts inline only; Claude-deep posts one summary; Chrome MCP posts only on label or path match. Tune over time.
4. **The `ai-cannot-approve` guard tripping on a legitimate bot comment.** The guard only fails on `state == APPROVED`. Comments and CHANGES_REQUESTED are fine. Verify in the workflow that the bot only ever does `COMMENT`.

## What we explicitly drop

- The hosted `claude-ai-review` GitHub App. Uninstall after Layer B is live for two weeks.
- Any plan to use `github-actions[bot]` as a reviewer. The `ai-cannot-approve.yml` guard rejects it on purpose; we don't want to weaken that guard.
