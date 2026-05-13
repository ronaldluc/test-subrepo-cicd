# test-subrepo-cicd — root scope

Universal rules apply across all tiers.

## Tier map

- `prod/**` — production code. Strict gates: CODEOWNERS, prod-ci, heavy pre-commit.
- `ops/**` — operational scripts. Standard gates: ops-ci, fast pre-commit.
- `spikes/**` — throwaway experiments. Advisory checks only, no review required.
- `docs/**` — documentation. Advisory.

## Universal rules

- Linear history on `main`; no force-push, no merge commits.
- Fast pre-commit hooks run on every commit.
- Any binary asset of a type listed in `.gitattributes` is auto-routed to LFS.

@docs/company/principles.md
