# test-subrepo-cicd — validation plan for per-path monorepo protection

A throwaway repo to validate the protection model from
[`conjurehq/spikes` → `spikes/monorepo-migration/`](https://github.com/conjurehq/spikes/blob/main/spikes/monorepo-migration/README.md).

**Goal:** end the validation with binary answers to every mechanism in the migration plan — does each behave as designed in a real GitHub repo, with real CI, real CODEOWNERS, real LFS — *before* committing the conjure monorepo to it.

> **Status (2026-05-14):** First-pass validation done — 15 of 20 user stories pass under the live ruleset; US-3 dropped; US-8 mechanism documented. See `results.html` for verdicts and `executive-summary.html` for the LFS-vs-R2 and CI-runner findings. This README is now the *augmented* plan after the Q&A round below — additional stories US-21+ are open.

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
│   ├── conjure_tech/             # current conjure.tech (minus analytics)
│   │   ├── CLAUDE.md  AGENTS.md→
│   │   ├── frontend/ backend/    # each with its own CLAUDE.md
│   │   └── Makefile              # `make test` runs tests *for this project only*
│   ├── analytics/                # broken out of conjure.tech
│   │   └── CLAUDE.md
│   ├── conjure_weddings/         # future product
│   │   └── CLAUDE.md
│   └── shared/                   # only when something genuinely re-used; not now
├── ops/                          # source of truth for ordering/tracking/xlsx/glb
│   ├── CLAUDE.md
│   ├── orders/                   # references R2 objects by hash
│   │   ├── manifest.json
│   │   └── tracker.md
│   └── tests/
├── spikes/                       # per-developer subfolders: spikes/<user>/<topic>/
│   ├── CLAUDE.md
│   └── <user>/<topic>/...
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

## Augmentations (post first-pass Q&A)

The original plan was right on the mechanics but underspecified some product decisions. The clarifications below modify or extend it. Each ends with the user stories it adds (US-21 onwards) so they fit into the same matrix as US-1..US-20.

### A. Tier taxonomy under `prod/`

`prod/` is *not* a single application — it's a flat namespace of products. Each product owns its own folder, its own `make test`, its own CODEOWNERS line.

- `prod/conjure_tech/` — current `conjure.tech` minus analytics. (Was called `prod/conjure` in the first sketch; renamed for clarity.)
- `prod/analytics/` — the analytics product, broken out of `conjure_tech`.
- `prod/conjure_weddings/` — the weddings product. Greenfield-able without touching the others.
- `prod/shared/` — *only* when code is genuinely re-used across products. Not on the immediate plan.

**Implication for CI:** every `prod/<product>/` is a leaf with its own test target. Root `make test` delegates per-product based on touched files. `prod-ci / ci-gate` becomes a per-product matrix (or per-product workflow), not one global gate.

### B. `docs/` is *not* throwaway — it gets two-layer protection

The first-pass plan put `docs/` in the spikes-smoke bucket. That's wrong: docs drift is the actual failure mode we're trying to prevent.

- **Layer 1 (sanity-check on every PR):** a workflow gate that runs a Claude agent over `docs/**` diffs. Prompt: "did this PR delete or massively rewrite docs in a way that looks accidental?" Output: pass / human-review-required. Cheap, fast, blocks obvious mistakes (e.g. accidentally `rm -rf docs/architecture/`).
- **Layer 2 (drift detection):** a workflow that, for each PR, runs Claude Code as a dispatcher — it reads the diff, decides which `docs/` sections plausibly describe the changed code, and fans out subagents to read each section and check it still describes reality. Output: comments on the PR listing concrete drift findings. Doesn't block merge by default; can be promoted to a required check later.

Both live as their own workflow files (`docs-sanity.yml`, `docs-drift.yml`) and are wired into the ruleset's required-status-checks list once stable. Design note: `docs/agents/docs-protection.md`.

### C. Source-of-truth for testing orders / xlsx / model files = `ops/`, binaries in R2

The plan had a fuzzy spot around "where does the orders xlsx + .glb live". Decision:

- All ordering logic, tracking scripts, tests, and the human-readable index live under `ops/` (e.g. `ops/orders/`).
- `ops/orders/manifest.json` pins each binary asset (xlsx, glb, etc.) by **content hash**.
- The binaries themselves live in **Cloudflare R2** (the existing `conjure-artifacts` bucket or a sibling). The git repo stores only the manifest.
- Access pattern: **write/read only**. The R2 token used by code, CI, and any LLM agent has *no Delete permission*. Hard accidents (e.g. an agent calling `aws s3 rm`) can't destroy the artifact set.
- `docs/orders.md` becomes a pointer ("the source of truth is `ops/orders/`") — no duplicated metadata.

### D. CODEOWNERS rationale (clarification, not a change)

CODEOWNERS isn't there to "read all prod code." It's the *mechanism* we picked for two unrelated jobs:
1. **Required-PR gating** (`require_code_owner_review: true` with `count = 0`) — engages only on paths a code-owner matches.
2. **The AI-cannot-merge trick** — the `ai-cannot-approve` workflow combined with codeowner-required review means a bot-account approval can never satisfy the gate.

If a tier doesn't need either, it doesn't need a CODEOWNERS line.

### E. Spikes — collision behaviour (the Q5 deep-dive)

The concern: "person A has folder `spikes/X` with 10 uncommitted files; person B deletes folder `spikes/X` in a merged PR; A pulls. Do A's uncommitted files survive?"

**Empirically verified** on a throwaway repo (script in `_research/git-folder-collision.sh`):

| Alice's local state | `git pull` outcome | Result |
|---|---|---|
| Only **untracked** files in the folder | succeeds (fast-forward) | folder kept, untracked files survive, the deleted tracked files are gone |
| **Modified tracked** + untracked files | **refused** with *"Your local changes to the following files would be overwritten by merge"* | nothing changes |
| **Staged-but-uncommitted** new files | succeeds | staged file survives, tracked files removed |
| Any of the above + then runs `git clean -fd` | (after pull) | **untracked files are obliterated** — only real risk path |

**Linux mechanics:** git does not `rm -rf` the folder. It calls `unlink()` per tracked file and `rmdir()` on the directory; `rmdir` silently fails if untracked content remains. There is no kernel-level concern about "unlinking a folder with files" — `rmdir` returns `ENOTEMPTY` in that case, which is exactly the protection we want.

**Therefore the actual risks for spikes:**

1. **`git clean -fd`** wipes untracked content. Mitigation: convention — never run it without `git clean -nd` first to preview. Add to `CLAUDE.md` as a hard rule for any agent operating in this repo.
2. **A coworker's PR deletes your spike folder** — git pull won't lose your work, but you might not notice. Mitigation: put spikes under `spikes/<user>/<topic>/` so deletions are author-scoped; codeowner the spike-root (`spikes/*/ @author-of-that-spike`) so no one accidentally deletes a peer's spike folder without their review.
3. **Force-push to a shared spike branch** can rewrite history, dropping commits. Mitigation: spikes still get their own branches; force-push is allowed because spike branches aren't protected.

### F. Large-file enforcement

Files > 2 MB that aren't routed through LFS via `.gitattributes` are rejected at commit by `check-added-large-files`. CI re-runs the same check on every PR. An admin can override in the UI (bypass-actor on the ruleset, used sparingly) — but the default path is "add an LFS pattern, recommit". This was already validated as US-11; restated here as a *policy*, not a "test".

### G. `make test` is project-aware (not a wrapper that runs everything)

Each `prod/<product>/` has a `Makefile` with `make test`, `make lint`, `make typecheck`. The root `Makefile` is a *dispatcher*: given the changed-paths set (from CI's `dorny/paths-filter`), it runs the matching targets in parallel. CI calls `make test PATHS="$CHANGED"`; locally a developer can call `make test` from a product folder and only test that product.

### H. Worktrees — not prod-only

Worktrees work fine across the whole repo. The first-pass plan said "worktrees are prod-only by design"; what it meant was "we expect worktrees to be used *primarily* for prod work because prod is where multi-day, multi-branch changes happen". No actual restriction. Spikes and ops can use worktrees too. Remove the prod-only language.

### I. AI review pipeline — replace `claude-ai-review`

The hosted `claude-ai-review` GitHub App auto-disables itself periodically (rate-limited, billing, etc.) and we don't control it. Replace with three controlled pieces:

1. **CodeRabbit** as the front-line, fast, broad reviewer — style, `CLAUDE.md` compliance, obvious issues. Praised as reliable and is the cheaper layer.
2. **Claude Code via a bot account** for deep review — invoked from a workflow with `GITHUB_TOKEN` or a dedicated bot PAT. Reads the diff, the relevant `CLAUDE.md` chain, and the linked architecture docs. Posts findings as PR comments. (Same product family as our local Claude Code, run headless.)
3. **Claude Code + Chrome MCP** for end-to-end journey tests on a deployed preview — drives the UI like a user would, reports concrete failures. Zero-setup-effort according to today's experiment.

Design note: `docs/agents/ai-review-pipeline.md`.

### Added user stories

| # | Story | Mechanism |
|---|---|---|
| US-21 | A PR that deletes ≥ 20 docs files is flagged by `docs-sanity` workflow | Layer 1 docs protection |
| US-22 | A code-only PR that contradicts its sibling doc gets a drift comment from `docs-drift` workflow | Layer 2 docs protection |
| US-23 | Asset reference in `ops/orders/manifest.json` resolves to an existing R2 object | R2 hash-pin + fetch script |
| US-24 | The R2 token configured in CI cannot delete objects (Delete returns 403) | scoped IAM policy |
| US-25 | Alice's untracked files in `spikes/alice/X/` survive a `git pull` that deletes `spikes/alice/X/` | empirically verified above |
| US-26 | Every `prod/<product>/` has its own `make test` that runs *only* that product's tests | per-product Makefile |
| US-27 | Root `make test PATHS=...` dispatches correctly given a changed-paths set | dispatcher Makefile |
| US-28 | CodeRabbit posts review comments on every PR within ≤ 5 min | CodeRabbit GitHub App |
| US-29 | Claude-Code-bot review comments appear on PRs touching `prod/**` | bot workflow |
| US-30 | Chrome MCP journey-test workflow finds a regression on a known-broken preview | Chrome MCP + Claude Code |

These slot into the existing matrix; verdicts will be filled in as each is built.

---

| # | Story | Mechanism |
|---|---|---|
| US-1 | Force-push to `main` is rejected on every tier | branch ruleset |
| US-2 | Merge commits to `main` are rejected (linear history) | branch ruleset |
| ~~US-3~~ | ~~Push to `spikes/foo` directly on `main` succeeds (no PR required)~~ | **dropped** — rulesets aren't path-scoped; all paths now go through PRs |
| US-4 | PR touching `prod/` requires CODEOWNER review | CODEOWNERS + ruleset (`count=0 + codeowner=true`) |
| US-5 | PR touching only `spikes/` does **not** require review | natively works under `count=0 + codeowner=true`: the rule has nothing to fire on |
| US-6 | PR touching both `prod/` and `spikes/` is governed by prod rules | "strictest tier touched" via CODEOWNERS pattern match |
| US-7 | `prod-ci / ci-gate` reports **success** when no `prod/**` paths changed | skipped-as-success gate (inner `dorny/paths-filter`, not top-level `paths:`) |
| US-8 | Author can merge their own prod PR once required checks pass | works when author is the sole CODEOWNER of touched paths (rule no-ops); for multi-codeowner paths a peer approves. **NOT** literal self-approval — GitHub blocks that at the API. |
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
| US-2 | Open a PR with a merge commit in its history; try to merge via "Create a merge commit". Expect blocked. (Also: any direct push to `main` is rejected with *"Changes must be made through a pull request"*.) |
| ~~US-3~~ | ~~Direct push of spike change to main~~. **Dropped:** GitHub rulesets are per-branch, not per-path. All work goes through PRs. |
| US-4 | PR editing `prod/mock-app/frontend/index.js` from a feature branch with author ≠ codeowner. Expect "Review required" badge. |
| US-5 | PR editing only `spikes/mock-spike/README.md`. Expect merge button green without review (codeowner rule has no codeowner files to gate on). |
| US-6 | PR editing one file in each of `prod/`, `spikes/`. Expect prod review required. |
| US-7 | Same as US-5. Expect `prod-ci / ci-gate` to appear as a green check (skipped-as-success), not "expected"/"missing". |
| US-8 | As the sole CODEOWNER (or any user when no other reviewer is possible), open a prod PR. Once required checks pass, click Merge. Expect success — the codeowner rule silently no-ops. **DO NOT** try to literally Approve your own PR; the GraphQL API returns `Review — Can not approve your own pull request`. |
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
- ✅ Require a PR before merging — **Required approvals: 0**, **Require review from Code Owners: ON** (this is the cleanest combo; details below)
- ✅ Require status checks to pass — pin `ci-gate`, `ops-gate`, `pass` (and any future workflow gates) as required contexts

Capture the JSON via `gh api repos/ronaldluc/test-subrepo-cicd/rulesets > docs/agents/branch-protection.json` so the config is in code.

**Test:** US-1, US-2. Both should fail to land.

### Layer 2 — Path-scoped CI + skipped-as-success gate

Three workflows, each starting **always** with an inner `dorny/paths-filter` job that decides whether downstream jobs do real work or skip. A final aggregator job uses `if: always()` and exits success if all needed jobs are `success` OR `skipped`. Mark `prod-ci / ci-gate`, `ops-ci / ops-gate`, and `pre-commit-fast / pass` as **required status checks** in the ruleset.

> **Gotcha (learned the hard way):** top-level `on: pull_request: paths:` filters make the workflow not even start on non-matching paths, so the required check shows up as *"expected / missing"* and PRs are stuck forever. Put the path filter inside an inner job; the workflow always runs, the gate always reports.

**Test US-5, US-7:** PR with only spike changes. Required checks turn green via skip. Merge button enables. (Direct push to `main` is rejected by the ruleset, so US-3 is dropped — see the user-story table.)

### Layer 3 — CODEOWNERS

```
prod/**     @ronaldluc
.github/**  @ronaldluc
docs/agents/** @ronaldluc
```

In the ruleset (set under Layer 1):
- ✅ Require pull request before merging
- **Required approvals: 0** (not 1)
- ✅ Require review from Code Owners
- ❌ Require approval of the most recent reviewable push (leave off so the author can still merge after pushing)

**Why `count = 0` + `codeowner = true`:** with `count = 1`, *every* PR would need a review, breaking US-5. With `count = 0` + codeowner enforcement, GitHub only blocks PRs that touch codeowner-matched files **and** have no approving review from a codeowner who isn't the author. PRs that don't touch codeowner files merge straight through (US-5). PRs that touch them and have other codeowners need that peer approval (US-4, US-6). PRs where the author is the **sole** codeowner of all touched paths merge silently because no valid reviewer exists (US-8).

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

- [x] US-1, US-2, US-4, US-5, US-6, US-7, US-8 (sole-codeowner pattern), US-9–US-14, US-17–US-19 produce the expected outcome.
- [x] US-3 dropped from scope (rulesets aren't path-scoped; not worth a workflow gate for the ~30s saved per spike PR).
- [x] US-8 wording fixed: GitHub blocks literal self-approval; the cleanest pattern is `count=0 + codeowner=true` + ≥ 1 codeowner per path (= author can merge when sole owner of touched paths).
- [x] Branch ruleset JSON committed at `docs/agents/branch-protection.json`.
- [ ] US-15, US-16 (Claude scope sentinels) — needs an interactive `claude` session at the relevant directory; deferred.
- [ ] US-20 Step B (live bot review) — needs a real bot identity; defer to migration day.
- See `results.html` for the final user-story matrix and `executive-summary.html` for the LFS-vs-R2 and CI-runner findings that came out of this validation.

---

## Cleanup

Don't delete the repo when done — keep it as a reproducible reference. Archive it on GitHub instead. The migration to the real monorepo references this repo as the validation artifact.
