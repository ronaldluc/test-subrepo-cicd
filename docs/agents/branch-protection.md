# Branch protection — desired state (not applied)

The fine-grained PAT used in this validation lacks `Administration: write` on the repo, so the rules below could not be created via API. Either regenerate the PAT with that permission or apply manually in **Settings → Rules → Rulesets**.

## Desired ruleset

```json
{
  "name": "main-protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {"type": "deletion"},
    {"type": "non_fast_forward"},
    {"type": "required_linear_history"},
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [
          {"context": "ci-gate"},
          {"context": "ops-gate"},
          {"context": "pass"}
        ],
        "strict_required_status_checks_policy": false
      }
    },
    {
      "type": "pull_request",
      "parameters": {
        "require_code_owner_review": true,
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    }
  ]
}
```

## API attempts (both 403)

```text
$ gh api -X POST repos/ronaldluc/test-subrepo-cicd/rulesets --input ruleset.json
{"message":"Resource not accessible by personal access token","status":"403"}

$ gh api -X PUT repos/ronaldluc/test-subrepo-cicd/branches/main/protection --input bp.json
{"message":"Resource not accessible by personal access token","status":"403"}
```

Existing rulesets (read-only call succeeded): `[]` — none configured yet.
