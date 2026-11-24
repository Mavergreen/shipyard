publish-unchanged: a repo whose content did not change still publishes on a dispatch only when a deviation says why.

## Why
Reproducible releases D2: a rebuild whose CONTENT-MANIFEST.txt equals the previous release's publishes
nothing, so an ingredient bump that changes nothing a user installs costs no one an update.
release-decision.sh reads this deviation and publishes anyway, with every product changed, for a repo
whose users need every rebuild, such as shipyard, whose consumers take its workflows through a moving
@v1. The summary says so whenever the content is unchanged.

## Incident
None recorded.

## Limits
Only an unscoped deviation, or one scoped *, is read: the decision is per release, not per product.

## Deviating
Write .mavergreen/deviations/publish-unchanged/<label>/ with the scope *, a reason naming why users need
every rebuild, and a revisit.

New in the flag day (P6, reproducible releases)
