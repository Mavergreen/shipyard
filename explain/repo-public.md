repo-public: every repo of the org is public.

## Why
On the org's free plan a private repo gets no org secrets, so its signing and VM jobs cannot run, and it
fails in ways that point nowhere near the cause. Visibility is GitHub repo state, reachable only through
the API, so the check runs as shipyard-check --repo-state with an admin gh credential, over every repo of
the org.

## Incident
None recorded. The rule follows the org's secrets reaching public repos only.

## Limits
It reads the visibility the API reports; a repo it cannot read reports "?" and fails.

## Deviating
No deviation is read for this id. Run sh scripts/setup-family-repo.sh settle <repo>, which writes every
family repo setting, or make the repo public by hand.

Formerly audit-repo-settings.sh's visibility check
