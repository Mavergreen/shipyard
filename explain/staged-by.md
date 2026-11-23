staged-by: a pkg staged by a pinned library's own script is excused from calling stage_product.sh, and only while the library is pinned.

## Why
stage-product requires a repo that builds a pkg to call stage_product.sh. A line whose pkg is built by a
pinned build-chain library's script (golang-127 runs golang-port's build/package.sh) calls it there, not
in its own tree. A staged-by deviation names that library, and the gate honours it only while
.mavergreen/ingredients/<library>/VERSION is tracked and non-empty; otherwise stage-product fails,
naming the pin.

## Incident
None recorded.

## Limits
It excuses stage-product alone. Revisit when a second library-staged line appears whose library is not a
family repo with a release tarball: then the check should read the pinned library's tarball instead.

## Deviating
Write .mavergreen/deviations/staged-by/<label>/ with a scope of the library's name, as in
.mavergreen/ingredients/<library>/, a reason and a revisit.

New in the flag day (from main's staged-by)
