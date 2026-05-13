# test-subrepo-cicd — validation plan for per-path monorepo protection

A throwaway repo to validate the protection model from
[`conjurehq/spikes` → `spikes/monorepo-migration/`](https://github.com/conjurehq/spikes/blob/main/spikes/monorepo-migration/README.md).

**Goal:** end the validation with binary answers to every mechanism in the migration plan — does each behave as designed in a real GitHub repo, with real CI, real CODEOWNERS, real LFS — *before* committing the conjure monorepo to it.

## Architecture under test (simplest viable version)

```
test-subrepo-cicd/
├── .github/
│   ├── CODEOWNERS                # prod/** → @ronaldluc
│   └── workflows/
│       ├── prod-ci.yml           # paths: prod/**           gate: prod-ci / ci-gate
│       ├── ops-ci.yml            # paths: ops/**            gate: ops-ci / ops-gate
│       ├── spikes-smoke.yml      # paths: spikes/** docs/** advisory only
│       └── pre-commit-fast.yml   # all paths                always required
├── .gitattributes                # LFS patterns
├── .pre-commit-config.yaml       # fast stage (all); heavy stage (prod only)
├── CLAUDE.md                     # ~20 lines — tier map + universal rules
├── AGENTS.md → CLAUDE.md         # symlink
├── prod/
│   ├── CLAUDE.md  AGENTS.md→
│   └── mock-app/
│       ├── CLAUDE.md  AGENTS.md→
│       ├── package.json          # for Dependabot test
│       ├── frontend/
│       │   ├── CLAUDE.md         # @-includes docs/architecture/frontend.md
│       │   └── index.js
│       └── backend/
│           ├── CLAUDE.md         # @-includes docs/architecture/backend.md
│           └── main.py
├── ops/
│   ├── CLAUDE.md
│   └── mock-script/
│       └── run.py
├── spikes/
│   ├── CLAUDE.md
│   └── mock-spike/README.md
└── docs/
    ├── README.md
    ├── company/principles.md
    ├── architecture/
    │   ├── frontend.md           # contains sentinel: SENTINEL-FRONTEND-7A3B
    │   └── backend.md            # contains sentinel: SENTINEL-BACKEND-9F1C
    └── agents/routing.md
```

**Sentinels** in the architecture docs are how we prove an agent's context loaded the right scope (Layer 6).

---

## What we're testing — user stories

| # | Story | Mechanism |
|---|---|---|
| US-1 | Force-push to `main` is rejected on every tier | branch ruleset |
| US-2 | Merge commits to `main` are rejected (linear history) | branch ruleset |
| US-3 | Push to `spikes/foo` directly on `main` succeeds (no PR required) | branch ruleset path scope |
| US-4 | PR touching `prod/` requires CODEOWNER review | CODEOWNERS + ruleset |
| US-5 | PR touching only `spikes/` does **not** require review or pass CI | path-filtered required checks |
| US-6 | PR touching both `prod/` and `spikes/` is governed by prod rules | "strictest tier touched" |
| US-7 | `prod-ci / ci-gate` reports **success** when no `prod/**` paths changed | skipped-as-success gate |
| US-8 | Author can self-approve their own prod PR if they are a CODEOWNER | ruleset config |
| US-9 | Pre-commit fast stage runs on every commit, every tier | `.pre-commit-config.yaml` |
| US-10 | Pre-commit heavy stage runs only on prod paths | `files:` scoping in pre-commit |
| US-11 | A 2 MB file with no LFS pattern is rejected at commit time | `check-added-large-files` |
| US-12 | A 5 MB `.mp4` is routed to LFS automatically | `.gitattributes` clean filter |
| US-13 | Fresh clone fetches LFS blobs as real bytes | LFS smudge on checkout |
| US-14 | CI without `lfs: true` sees pointer files; with `lfs: true` sees blobs | `actions/checkout` |
| US-15 | Claude Code in `prod/mock-app/frontend/` loads **frontend** sentinel only | nested `CLAUDE.md` + `@-include` |
| US-16 | Claude Code in `ops/` loads **neither** frontend nor backend sentinel | scope isolation |
| US-17 | `AGENTS.md` symlink resolves to `CLAUDE.md` at every level | git-tracked symlink |
| US-18 | Pre-commit hook fails if a `CLAUDE.md` exists without a sibling `AGENTS.md` symlink | local hook |
| US-19 | Dependabot opens PRs for `prod/mock-app/package.json` but not `spikes/` | `dependabot.yml` directory list |
| US-20 | A bot-account review on a prod PR does **not** satisfy CODEOWNER review | `ai-cannot-approve.yml` |

Stretch (cost/time-bound, not blocking validation):
- LFS bandwidth metering visibility in GitHub billing.
- Worktree behavior with nested `CLAUDE.md`s.

---

## How to test each — minimal action

| US | Action |
|---|---|
| US-1 | `git push --force-with-lease origin main` from a clean clone. Expect rejection. |
| US-2 | Open a PR with a merge commit in its history; try to merge via "Create a merge commit". Expect blocked. |
| US-3 | `echo x >> spikes/mock-spike/README.md && git commit -am x && git push origin main`. Expect success. |
| US-4 | PR editing `prod/mock-app/frontend/index.js` from a feature branch. Expect "Review required" badge. |
| US-5 | PR editing only `spikes/mock-spike/README.md`. Expect merge button green without review. |
| US-6 | PR editing one file in each of `prod/`, `spikes/`. Expect prod review required. |
| US-7 | Same as US-5. Expect `prod-ci / ci-gate` to appear as a green check (skipped-as-success), not "expected"/"missing". |
| US-8 | As CODEOWNER, open a PR, "Approve" own PR (GitHub allows this if branch protection permits). Merge. Expect success. |
| US-9 | Commit a file with trailing whitespace. Expect local pre-commit failure. |
| US-10 | Commit a Python file under `ops/`. Expect ruff to NOT run. Commit one under `prod/`. Expect ruff to run. |
| US-11 | `dd if=/dev/urandom of=prod/mock-app/blob.bin bs=1M count=2 && git add … && git commit`. Expect block. |
| US-12 | `dd if=/dev/urandom of=prod/mock-app/clip.mp4 bs=1M count=5 && git lfs ls-files` after commit. Expect entry. |
| US-13 | `git clone … /tmp/check && file /tmp/check/prod/mock-app/clip.mp4`. Expect `ISO Media`, not `ASCII text` (pointer). |
| US-14 | Workflow run viewing the file's `wc -c` — pointer = ~130 bytes, blob = millions. |
| US-15 | `cd prod/mock-app/frontend && claude` → ask "search your loaded context for the strings SENTINEL-FRONTEND-7A3B and SENTINEL-BACKEND-9F1C". Expect frontend yes, backend no. |
| US-16 | `cd ops && claude` → same query. Expect both no. |
| US-17 | `ls -la prod/AGENTS.md` shows `-> CLAUDE.md`. `diff <(cat prod/AGENTS.md) <(cat prod/CLAUDE.md)`. Expect empty. |
| US-18 | Delete a symlink, attempt commit. Expect failure. |
| US-19 | Add an outdated dep to `prod/mock-app/package.json` (e.g. `"lodash": "4.17.0"`). Wait 24h. Expect PR. Same for `spikes/`. Expect nothing. |
| US-20 | Create a fine-grained PAT for `@github-actions[bot]` or use a second account; submit an approving review on a prod PR. Verify the `ai-cannot-approve` workflow flags it and the merge stays blocked. |

---

## Execution plan — fundamental → composite

### Layer 0 — Scaffold (no protection yet)

1. Create the folder tree above with **minimal** content per file (one line of placeholder is fine).
2. Create `docs/architecture/frontend.md` containing literally:
   ```
   # Frontend architecture
   SENTINEL-FRONTEND-7A3B
   The mock app's frontend.
   ```
   Same shape for `backend.md` with `SENTINEL-BACKEND-9F1C`.
3. Wire one stub workflow per tier that just echoes the path filter it caught — full CI is not the point yet.
4. Push to `origin/main` directly. No branch protection on yet, so this works.

**Verify:** repo on GitHub shows the tree, the three workflows appear under Actions.

### Layer 1 — Universal rules (branch ruleset)

In GitHub UI: Settings → Rules → Rulesets → New ruleset for `main`:

- ✅ Restrict deletions
- ✅ Require linear history
- ✅ Block force pushes
- ❌ Require a PR (this kicks in via path-scoped required checks instead)

Capture the JSON via `gh api repos/ronaldluc/test-subrepo-cicd/rulesets > docs/agents/branch-protection.json` so the config is in code.

**Test:** US-1, US-2. Both should fail to land.

### Layer 2 — Path-scoped CI + skipped-as-success gate

Three workflows, each with `paths:` filters AND a final aggregator job that uses `if: always()` and returns success if all needed jobs are `success` OR `skipped`. Mark `prod-ci / ci-gate`, `ops-ci / ops-gate`, and `pre-commit-fast / pass` as **required status checks** in the ruleset.

**Test US-3:** push to `main` editing only a spike file → green required checks via skipped-as-success. Direct push allowed because no PR-required rule.
**Test US-5, US-7:** PR with only spike changes. Required checks turn green via skip. Merge button enables.

### Layer 3 — CODEOWNERS

```
prod/**     @ronaldluc
.github/**  @ronaldluc
docs/agents/** @ronaldluc
```

In the ruleset: ✅ Require pull request before merging → ✅ Require review from Code Owners (for the `prod/**` and `.github/**` matchers — done by enabling "Require approval of the most recent reviewable push" with code owner enforcement).

**Test US-4, US-6, US-8.**

### Layer 4 — Pre-commit (fast + heavy stages)

`.pre-commit-config.yaml`:

- Fast stage (always): `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`, `check-added-large-files --maxkb=1000`, `gitleaks`, `detect-private-key`.
- Heavy stage (scoped via `files: ^prod/`): `ruff`, `ruff-format`, `eslint` (on `prod/**/*.{ts,tsx,js,jsx}`).

Mirror as a `pre-commit-fast.yml` workflow so the same checks run in CI as a required check.

**Test US-9, US-10, US-11.**

### Layer 5 — LFS

`.gitattributes`:
```
*.mp4   filter=lfs diff=lfs merge=lfs -text
*.mkv   filter=lfs diff=lfs merge=lfs -text
*.glb   filter=lfs diff=lfs merge=lfs -text
*.safetensors filter=lfs diff=lfs merge=lfs -text
```

Enable LFS on the GitHub repo (Settings → Storage and Bandwidth — usually on by default).

Local: `git lfs install` once. Then run US-12. Then US-13 in a separate temp checkout.

For US-14: add a job to `prod-ci.yml` that does `wc -c prod/mock-app/clip.mp4` and prints the result. Run it once with `lfs: true`, once without (toggle in a branch). Compare.

**Test US-12, US-13, US-14.**

### Layer 6 — Nested CLAUDE.md + sentinels

Per-folder `CLAUDE.md` content (telegraphic, ~10 lines each):

`prod/mock-app/frontend/CLAUDE.md`:
```
# Frontend scope.
@../../docs/architecture/frontend.md
@../../docs/company/principles.md
Do not touch backend code from this scope.
```

`prod/mock-app/backend/CLAUDE.md`:
```
# Backend scope.
@../../docs/architecture/backend.md
@../../docs/company/principles.md
```

`ops/CLAUDE.md`:
```
# Ops scope.
@../docs/company/principles.md
No architecture docs; ops doesn't share code with prod.
```

`docs/agents/routing.md` mirrors what each scope includes.

**Test US-15:** open `claude` from each folder; ask it to grep its loaded context for both sentinels.
**Test US-16:** same from `ops/`.

### Layer 7 — AGENTS.md symlinks

```bash
find . -name CLAUDE.md -execdir ln -sf CLAUDE.md AGENTS.md \;
git add -A && git commit -m "agents: symlinks"
```

Add a local pre-commit hook `agents-md-symlink` that fails if any directory contains `CLAUDE.md` but no `AGENTS.md → CLAUDE.md` symlink.

**Test US-17, US-18.**

### Layer 8 — Mixed PR

One PR that changes a line in `prod/mock-app/frontend/index.js` AND a line in `spikes/mock-spike/README.md`.

**Test US-6:** prod-ci runs, CODEOWNER review required, spike-smoke runs advisory.

### Layer 9 — Dependabot (24h cycle, parallel with other work)

`.github/dependabot.yml`:
```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/prod/mock-app"
    schedule: { interval: "daily" }
  - package-ecosystem: "npm"
    directory: "/ops/mock-script"
    schedule: { interval: "daily" }
```

Put an outdated `lodash` in `prod/mock-app/package.json`. **Do not** list `spikes/` in `dependabot.yml`.

**Test US-19** after 24h. Expect one PR for prod, none for spikes.

### Layer 10 — AI-cannot-approve

The hardest to validate without a real bot account. Two-step approach:

**Step A — workflow logic test** (immediate): write `ai-cannot-approve.yml` that triggers on `pull_request_review`, fetches the reviewer via `gh api`, and fails if `user.type == "Bot"`. Test by manually firing the workflow with a synthetic event payload (`gh workflow run --ref … -f event=…`).

**Step B — live test** (when a bot account is available): create a fine-grained PAT for `@dependabot[bot]` or a second test account configured as a bot. Have it review a prod PR. Verify required-check fails and merge is blocked.

If Step B can't be done in the sandbox, document the gap explicitly — this gets re-tested when migrating the real repo.

**Test US-20** (partial in sandbox, full at migration time).

---

## Order of execution

Run layers strictly in order. Each layer's tests must pass before the next is built on top — otherwise a Layer 4 failure could be masked by a Layer 5 problem. The dependency chain:

```
0 scaffold
└─ 1 universal rules
   ├─ 2 path-scoped CI + skipped-as-success
   │  ├─ 3 CODEOWNERS
   │  │  ├─ 4 pre-commit
   │  │  │  └─ 5 LFS
   │  │  │     └─ 8 mixed PR (uses 2+3)
   │  │  └─ 10 AI-cannot-approve (uses 3)
   │  └─ 9 Dependabot (parallel; 24h)
   └─ 6 nested CLAUDE.md (independent of CI)
      └─ 7 AGENTS.md symlinks (uses 6)
```

Practical ordering for one human:

1. **Day 1 morning:** Layers 0–3. Validates the core gating.
2. **Day 1 afternoon:** Layers 4–5. Validates the local + asset story.
3. **Day 1 end:** Layer 9 setup (so it ticks overnight).
4. **Day 2 morning:** Layers 6–7. Validates the agent story.
5. **Day 2 afternoon:** Layer 8 (mixed PR), then 9 verification, then Layer 10 (workflow-only).

Total ~1.5 days of focused work assuming no GitHub UI surprises.

---

## What this sandbox **cannot** prove

- **Real LFS bandwidth limits at scale** — needs production-scale clones and fork activity.
- **Multi-dev review conflicts** — only one operator here.
- **Live bot-account approval** unless a real bot identity is provisioned (Layer 10 Step B).
- **Cross-tier worktree behavior** — worktrees are prod-only by design and the test repo has minimal prod content.
- **Performance at conjure scale** — turbo affected-package math, CI minutes, clone time.

These get re-tested at migration time, against the real monorepo. Document each gap as it appears so it ends up on the migration checklist.

---

## Done criteria

The sandbox is "validated" when:

- [ ] All US-1 through US-19 produce the expected outcome at least once.
- [ ] US-20 Step A passes (Step B optional in sandbox).
- [ ] The branch ruleset JSON is committed at `docs/agents/branch-protection.json`.
- [ ] Each layer's test commands are captured in `docs/agents/test-log.md` with screenshots/output snippets for any non-obvious behavior.
- [ ] Any deviation from the migration plan is fed back to `conjurehq/spikes/spikes/monorepo-migration/README.md` as a "lessons learned" appendix.

---

## Cleanup

Don't delete the repo when done — keep it as a reproducible reference. Archive it on GitHub instead. The migration to the real monorepo references this repo as the validation artifact.
