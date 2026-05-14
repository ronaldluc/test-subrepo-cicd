# Validation progress log

Final state after three passes (initial scaffold + first PAT, full-scope PAT pass, codeowner-isolation experiment).

## Environment

- Repo: github.com/ronaldluc/test-subrepo-cicd
- Tools: git-lfs 3.0.2, pre-commit 4.6.0, node, ruff, gh, fine-grained PAT with Administration/Pull-Requests/Actions write.

## Layer build status

| Layer | What | Status |
|---|---|---|
| 0 | Scaffold | ✅ done |
| 1 | Branch ruleset | ✅ applied (`main-protection`; JSON snapshot at `docs/agents/branch-protection.json`) |
| 2 | Path-scoped CI + gate | ✅ inner `dorny/paths-filter`; required checks always report |
| 3 | CODEOWNERS | ✅ enforced under `count=0 + codeowner=true` |
| 4 | Pre-commit fast/heavy | ✅ tested locally |
| 5 | LFS | ✅ clip.mp4 round-tripped |
| 6 | Nested CLAUDE.md | ✅ `@-include` chain in place; sentinel-loading needs an interactive claude session to confirm |
| 7 | AGENTS.md symlinks | ✅ symlinks at every level + local hook |
| 8 | Mixed PR | ✅ PR #4 (`test/mixed`) behaved per CODEOWNER rules |
| 9 | Dependabot | ✅ PR #1 within minutes |
| 10 | ai-cannot-approve | ✅ workflow logic complete; live bot test deferred |

## User-story verdicts

| US | Verdict | Evidence |
|---|---|---|
| US-1 force-push rejected | ✅ pass | Remote: *"Cannot force-push to this branch"* |
| US-2 linear history / PR-required | ✅ pass | Same push: *"Changes must be made through a pull request"* |
| US-3 direct push to main for spikes | ⛔ dropped | Rulesets aren't path-scoped. Cost of "all paths go through PRs" is ~30s per spike change. |
| US-4 prod PR requires CODEOWNER review | ✅ pass | PR #6 (codeowner=@octocat ≠ author, touched `.github/CODEOWNERS`) blocked on merge. |
| US-5 spike-only PR doesn't need review | ✅ pass | PR #7 (spike-only diff) merged with zero reviews under `count=0 + codeowner=true`. |
| US-6 mixed PR governed by prod rules | ✅ pass | Same mechanism as US-4. |
| US-7 ci-gate green when no prod changes | ✅ pass | PR #7: `prod-ci / lint=SKIPPED`, `prod-ci / ci-gate=SUCCESS`. |
| US-8 author merges own prod PR | ✅ pass | PR #9: author=sole CODEOWNER of touched paths → `gh pr merge` succeeded, no flags. **Note:** literal self-approval blocked by GitHub API; the merge works because the rule silently no-ops. |
| US-9 pre-commit fast on every tier | ✅ pass | trailing-whitespace caught a `spikes/` file. |
| US-10 heavy stage scoped to prod | ✅ pass | ruff: no files on ops, 3 errors on the same file under prod. |
| US-11 large non-LFS file rejected | ✅ pass | `check-added-large-files`: 2048 KB exceeds 1000 KB. |
| US-12 mp4 → LFS | ✅ pass | `git lfs ls-files` lists OID; `git show HEAD:…` returns pointer. |
| US-13 fresh clone fetches blob | ✅ pass | `/tmp/cicd-fresh/…/clip.mp4` = 5,242,880 B binary. |
| US-14 CI lfs:true vs absent | ✅ pass | 5,242,880 B vs 132 B pointer. |
| US-15 frontend scope loads frontend sentinel | ⚪ needs claude session | Can't spawn `claude` in subdirectory from this session. |
| US-16 ops scope loads neither | ⚪ needs claude session | Same. |
| US-17 AGENTS.md symlink resolves | ✅ pass | Git mode 120000; diff empty. |
| US-18 hook fails on missing symlink | ✅ pass | Exit 1 with symlink removed, 0 after restore. |
| US-19 Dependabot for prod, not spikes | ✅ pass | PR #1 within minutes; spikes intentionally absent from config. |
| US-20 bot review fails ai-cannot-approve | 🟢 logic verified | Workflow YAML correct; live bot identity needed for end-to-end. |

**Final count:** 15 pass, 1 dropped, 2 needs-claude-session, 1 logic-only.

## Lessons fed back to migration plan

1. **US-3 dropped.** GitHub rulesets are per-branch, not per-path. The "direct push to main for spikes" path isn't worth a workflow gate. All paths go through PRs.
2. **US-8 mechanism**: the author can merge their own PR through normal channels when they're the sole CODEOWNER of touched paths; GitHub silently no-ops the codeowner rule. NOT literal self-approval — the GraphQL API blocks `addPullRequestReview` with `Review — Can not approve your own pull request`. With a multi-codeowner setup (the conjure case once teammates are added), peers approve.
3. **US-5 works natively** with `count=0 + codeowner=true`. No "trick", no path-filtered required-check hack — the codeowner rule just has nothing to fire on for spike-only PRs.
4. **Path-scoped required checks**: use inner `dorny/paths-filter`, never top-level `paths:` on the workflow trigger. Otherwise the required check shows *"expected / missing"* and PRs stick.
5. **UI-only enforcement is not possible.** GitHub's web UI and `gh` CLI hit the same merge endpoint. If "no CLI merge" matters, that's a policy/cultural choice, not a config.
6. **Dependabot SLA is minutes**, not the 24h budget in the original plan.

## Companion files

- `results.html` — per-US verdicts + evidence
- `executive-summary.html` — LFS-vs-R2 economics + CI runner alternatives (Blacksmith et al)
- `docs/agents/branch-protection.md` + `branch-protection.json` — live ruleset
- `_research/blacksmith-runners.md` — raw runner research
