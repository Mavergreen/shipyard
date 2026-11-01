repo-requires-on-target: a product repo's main requires its 10.9 acceptance job.

## Why
A 10.9 acceptance job that main does not require is a report, not a gate: a pull request can merge with it
red. So every release.yml job whose steps use Mavergreen/mavericks-vm is among main's required checks, by
its check name: its name: if set, else its job id, and for a job calling a local reusable workflow,
"<caller> / <called job>", as GitHub names it. Branch protection is admin-only state, so this runs as
shipyard-check --repo-state.

## Incident
None recorded. The rule follows the decision that every pkg is accepted on real 10.9 before it publishes.

## Limits
It reads release.yml only, and a release.yml or a called workflow it cannot read fails. A job that runs
the guest some other way is not seen.

## Deviating
No deviation is read for this id. Run sh scripts/setup-family-repo.sh settle <repo>, which requires it.

Formerly audit-repo-settings.sh's on-target check
