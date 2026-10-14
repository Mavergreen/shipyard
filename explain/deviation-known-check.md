deviation-known-check: every deviation names a check id that exists.

## Why
A deviation that names a check nothing reads excuses nothing, and looks as if it did. The old names are
retired with no aliases: product-layout is now stage-product (and registered), artifact-conformance is now
artifact-checks-wired, scheme is now version-scheme and ingredients is now variant-build-info. sparkle-updater,
release-assets and python3 are read by nothing, so the line is deleted. Any other unknown name is a typo or a
rule that was never written. Names come from shipyard-check --list.

## Incident
2026-10-14: the survey behind this check found that 11 of the org's 81 deviations named checks that nothing
read.

## Limits
It checks the id exists, not that the id reads deviations. A deviation under an id whose check consults none
(for instance release-concurrency) passes here and excuses nothing. The Deviating section of each
explanation says whether its check reads one.

## Deviating
No deviation is read for this id. Re-point the line at the right id, or delete it.

New in the flag day (K5, conventions-as-checks design)
