deviation-known-check: no deviation is filed under a retired check name.

## Why
A deviation filed under a name that no check reads any more excuses nothing, and looks as if it did. The old
names are retired with no aliases: product-layout is now stage-product (and registered), artifact-conformance
is now artifact-checks-wired, scheme is now version-scheme, ingredients is now variant-build-info, and
msc-template is now the shipyard-scripts command. sparkle-updater, release-assets and python3 are read by
nothing, so the directory is deleted. Any other name that is not a check id fails deviation-complete.

## Incident
2026-10-14: the survey behind this check found that 11 of the org's 81 deviations named checks that nothing
read.

## Limits
It knows only the retired names listed above. It checks the name, not that the id reads deviations: a
deviation under an id whose check consults none (for instance release-concurrency) passes here and excuses
nothing. The Deviating section of each explanation says whether its check reads one.

## Deviating
No deviation is read for this id. Move the directory to the right id, or delete it.

New in the flag day (K5, conventions-as-checks design)
