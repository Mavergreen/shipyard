repo-auto-merge: a product repo allows auto-merge.

## Why
For a green-gated pull request to merge promptly, native auto-merge needs both the repo's Allow auto-merge
setting (off by GitHub default) and branch protection on main that requires the PR build check; either alone
is inert. Allow auto-merge is GitHub repo state, reachable only through the API, so no renovate.json preset
can set it and a checkout cannot show it. It runs as shipyard-check --repo-state, which needs an admin
token: reading branch protection is admin-only, so it is not a CI gate on a default token. It exits non-zero
when a green bump could not merge.

## Incident
Four repos created from 2026-08-02 to 2026-08-04 had neither setting, so their Renovate bumps never merged:
signal-desktop's Signal 8.26.0 sat green and unmerged for a month with nothing anywhere going red.

## Limits
It reads the setting for every repo of the org that has a release.yml. It needs an admin gh credential, and
refuses to run without one rather than pass. QUEUE #38 records a related gap, not covered: a required check
that can be skipped counts as passed.

## Deviating
No deviation is read for this id. Fix the setting: gh api -X PATCH repos/OWNER/REPO -F allow_auto_merge=true.

Formerly audit-repo-settings.sh
