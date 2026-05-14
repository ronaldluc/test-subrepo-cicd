# Branch protection — applied state

The live ruleset is at <https://github.com/ronaldluc/test-subrepo-cicd/rules/16355175>. JSON snapshot in `branch-protection.json` (refresh via `gh api repos/ronaldluc/test-subrepo-cicd/rulesets/16355175 > docs/agents/branch-protection.json`).

## Config in one place

```json
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "required_linear_history" },
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [
          { "context": "ci-gate" },
          { "context": "ops-gate" },
          { "context": "pass" }
        ],
        "strict_required_status_checks_policy": false
      }
    },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash", "rebase"]
      }
    }
  ]
}
```

## Why this exact shape

| Knob | Value | Reason |
|---|---|---|
| `required_approving_review_count` | **0** | With 1, every PR (including spike-only) would need a review and US-5 breaks. |
| `require_code_owner_review` | **true** | Engages CODEOWNERS only on PRs that touch codeowner-matched paths. Spike-only PRs sail through; prod-touching PRs need a peer codeowner. |
| `require_last_push_approval` | **false** | Lets the author push fixups and still merge without re-approval (relevant when the author IS the sole codeowner). |
| `bypass_actors` | **`[]`** | None. Bypass is the same through CLI and UI, so adding admins to bypass doesn't enforce a "UI-only override". |
| `allowed_merge_methods` | `["squash", "rebase"]` | No merge commits — keeps history linear (also enforced by `required_linear_history`). |

## Sole-CODEOWNER caveat (the US-8 mechanism)

When the PR author is the **only** CODEOWNER of every touched path, GitHub silently treats the codeowner-review rule as satisfied — there's no valid reviewer who isn't the author. The PR is mergeable. This is how the author-merges-own-prod-PR pattern works without literal self-approval.

The moment a second person is added to CODEOWNERS for a protected path, the author can no longer merge alone — that peer must approve. This is the desired behaviour at conjure scale.

## What is NOT enforced

- **Path-scoped direct push to `main`** — rulesets are per-branch. All paths require a PR (US-3 dropped).
- **UI-only merge / no-CLI-merge** — GitHub's API and web UI use the same endpoint. No native way to allow one but not the other.
- **Bot-as-codeowner blocking** — handled by the workflow `ai-cannot-approve.yml`, not by ruleset.
