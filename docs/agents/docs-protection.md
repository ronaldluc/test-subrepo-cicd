# Docs protection — two-layer design

## Why

`docs/` is not a throwaway directory. Architecture docs, runbooks, and routing maps directly inform agent context (Layer 6 of the validation plan). The two real failure modes:

1. **Accidental destruction** — someone (human or agent) deletes a docs subtree by mistake or merges a PR that does. Without a check, this lands silently.
2. **Drift** — code changes, the corresponding docs don't. Agents load stale context; suggestions become subtly wrong.

A purely-human review gate is unreliable: reviewers skim docs diffs and miss subtle drift. The mitigation has two layers, both running as workflows on every PR.

## Layer 1 — `docs-sanity.yml`

Cheap, fast, advisory-then-required.

**Trigger:** `pull_request` events touching `docs/**`.

**Implementation:**
- Workflow checks out the PR.
- Computes the diff: `git diff --name-status origin/main...HEAD -- docs/`.
- If lines-deleted &ge; some threshold (start with 200) OR files-removed &ge; some threshold (start with 5), it fans out to a single Claude call: *"Here is the diff. Is this deletion deliberate (refactor / file move) or accidental? Answer YES/NO with one-sentence reason."*
- On `NO`, the workflow fails with the agent's reason in the annotation.

**Required-check name:** `docs-sanity`.

**Why a model and not a static threshold:** the same 500-line deletion can be a legitimate restructure or a catastrophic mistake. The model reads the commit message + diff structure and tells them apart 99% of the time.

**Cost ceiling:** one Sonnet call (~3k tokens in, ~50 out) per qualifying PR. Order of cents per PR.

## Layer 2 — `docs-drift.yml`

Deeper, more expensive, advisory.

**Trigger:** `pull_request` events touching `prod/**` or `ops/**` (not docs-only changes — those don't introduce drift).

**Implementation:**
1. **Dispatcher step:** invokes Claude Code headless with a prompt that has access to (a) the changed-paths list and (b) the `docs/` tree contents. It returns a JSON list `{ "doc_path": "docs/architecture/frontend.md", "reason": "this PR touched prod/conjure_tech/frontend/", "subagent_prompt": "..." }`.
2. **Fan-out step:** for each entry, spawn a parallel job that runs Claude Code with:
   - `docs/<entry>` as required reading
   - The PR diff as required reading
   - Prompt: "Does the doc still accurately describe the code after this change? List concrete drift points or output `IN-SYNC`."
3. **Aggregator step:** collect outputs; post a single PR comment with the drift findings, grouped by doc file. Comment is updated in place on each push (`actions/github-script` upsert pattern).

**Required-check name:** none initially. Goal: ship as advisory, observe accuracy for 2–4 weeks, then promote to required once false-positive rate is acceptable.

**Cost ceiling:** depends on diff size. Worst case for a 1k-line prod PR with 5 plausibly-affected doc files: ~$0.10–$0.30. Set a per-PR budget in the workflow.

**Trust model:** the workflow uses a bot account's GitHub token (separate from `@github-actions[bot]`) for posting comments. That bot is *not* in any CODEOWNERS list, so its comments cannot satisfy review requirements — they're feedback, not approval. The existing `ai-cannot-approve.yml` ensures this even if someone configures it wrong.

## Wiring into the ruleset

```diff
 required_status_checks:
   - ci-gate
   - ops-gate
   - pass
+  - docs-sanity        # once stable
```

Drift gets added later, only after we've seen its false-positive rate.

## Why not put both in one workflow

Layer 1 has a hard time budget (~30s) so it can block fast PRs. Layer 2 can take minutes. Keeping them separate means Layer 1 alone gates merge once required; Layer 2's noise stays in advisory comments until trusted.

## CLAUDE.md update at the docs root

Add a short `docs/CLAUDE.md`:

```
# docs scope.
@./company/principles.md
This tree is load-bearing context for agents. Treat deletions as load-bearing too — every removal needs an explicit "why" in the commit message.
```

## Open questions

- Threshold tuning for Layer 1: 200 lines / 5 files is a guess. Tune after first 30 PRs.
- Which model: Haiku for Layer 1 (cheap, fast), Sonnet for Layer 2 (better reasoning). Revisit after a month.
- Caching: feed the docs tree into a prompt cache so the per-PR cost is the diff only, not the whole tree.
