# Validation progress log

Live log of layer build + user-story testing.

## Environment

- Date: 2026-05-13
- Operator: ronaldluc (gh authenticated via fine-grained PAT)
- Repo: github.com/ronaldluc/test-subrepo-cicd
- Tools: git-lfs 3.0.2, pre-commit 4.6.0, node, ruff, gh

## Layer build status

| Layer | What | Status | Notes |
|---|---|---|---|
| 0 | Scaffold | ✅ done | full tree, sentinels embedded |
| 1 | Branch ruleset | ❌ blocked | PAT lacks `Administration: write` |
| 2 | Path-scoped CI + gate | ✅ done | refactored to internal `dorny/paths-filter` so required checks always report |
| 3 | CODEOWNERS | ✅ done | enforcement blocked on Layer 1 |
| 4 | Pre-commit fast/heavy | ✅ done | tested locally |
| 5 | LFS | ✅ done | clip.mp4 round-tripped |
| 6 | Nested CLAUDE.md | ✅ done | @-include chain validated by inspection |
| 7 | AGENTS.md symlinks | ✅ done | symlinks + local hook both work |
| 8 | Mixed PR | ⏭ skipped | PR creation also blocked by PAT scope |
| 9 | Dependabot | ✅ done | PR #1 opened automatically within minutes |
| 10 | ai-cannot-approve | ✅ done (logic only) | workflow live-fires from PR review events |

## User-story verdicts

| US | Verdict | Evidence |
|---|---|---|
| US-1 force-push rejected on main | 🟡 blocked | needs ruleset (PAT can't create) |
| US-2 merge commits rejected | 🟡 blocked | needs ruleset |
| US-3 direct push to main with spike-only | ✅ mechanical pass | commit `79d434f` pushed; full *enforcement* claim needs ruleset |
| US-4 prod PR requires CODEOWNER review | 🟡 blocked | needs ruleset; workflow trigger confirmed via Dependabot PR #1 |
| US-5 spike-only PR doesn't need review | 🟡 blocked (PR API) | required-check skip-as-success confirmed on main push |
| US-6 mixed PR governed by prod rules | 🟡 blocked (PR API) | — |
| US-7 `prod-ci / ci-gate` = success when no prod changes | ✅ PASS | run 25812457218 on spike push: lint=`skipped`, ci-gate=`success` |
| US-8 author self-approves own prod PR | 🟡 blocked | needs ruleset |
| US-9 pre-commit fast on every tier | ✅ PASS | trailing-whitespace fired & fixed file in spikes/ |
| US-10 heavy stage scoped to prod | ✅ PASS | ruff skipped on `ops/_us10.py`; ran and failed on `prod/_us10.py` |
| US-11 large non-LFS file rejected | ✅ PASS | "2048 KB exceeds 1000 KB" from `check-added-large-files` |
| US-12 `.mp4` auto-routed to LFS | ✅ PASS | `git lfs ls-files` shows entry; `git show HEAD:…` returns pointer |
| US-13 fresh clone fetches LFS blob | ✅ PASS | `/tmp/cicd-fresh/prod/mock-app/clip.mp4` = 5 242 880 B binary |
| US-14 CI `lfs:true` vs absent | ✅ PASS | with-lfs: 5 242 880 B binary; without: 132 B pointer text |
| US-15 frontend scope loads only frontend sentinel | ⚪ unverifiable from this session | @-include chain inspected and resolves correctly |
| US-16 ops scope loads neither sentinel | ⚪ unverifiable from this session | same |
| US-17 AGENTS.md symlink resolves | ✅ PASS | symlinks stored as git mode 120000; `diff cat AGENTS.md cat CLAUDE.md` empty |
| US-18 hook fails on missing symlink | ✅ PASS | `scripts/check-agents-symlinks.sh` exit 1 with rm, exit 0 after restore |
| US-19 Dependabot PR for prod, none for spikes | ✅ PASS | PR #1 (lodash 4.17.0 → 4.18.1) for `/prod/mock-app`; spikes/ absent from `dependabot.yml` ⇒ none |
| US-20 bot review fails ai-cannot-approve | 🟢 logic verified | workflow correct; live test needs a bot identity and a triggered review event |

## Blockers found

1. **PAT scope** — current token can `repo:contents:write` only. Cannot create rulesets/branch-protection, cannot create PRs, cannot `workflow_dispatch`. Either regenerate with `Administration: write` + `Pull requests: write` + `Actions: write`, or do those steps manually.
2. **Required-status-check + `paths:` filter** — naive `on: push: paths:` on the workflow level means the required check never reports → PR blocked. Fixed by moving the path filter into an inner `dorny/paths-filter` job so the workflow always runs and the `ci-gate` job always reports.

## Lessons learned (feed back into the migration plan)

- The "skipped-as-success gate" only works when the workflow itself always runs. Top-level `paths:` filters are incompatible with required-check enforcement.
- Dependabot's first run can happen within minutes of pushing `dependabot.yml`, not "24h". US-19's wait estimate in the plan can be reduced.
- Repo-admin permission on the GitHub UI ≠ PAT having `Administration` scope. Fine-grained PATs must explicitly grant that scope for rulesets to be API-creatable.
