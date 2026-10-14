tracked-files: the list of tracked files can be read.

## Why
Many checks ask what the repo tracks: a committed VERSION, a build/ directory that is ignored, a vendored
copy, a stray Renovate config, files under .superpowers/. A check that cannot get that list must not pass
as if it had looked at an empty tree, so it fails and says why. This is the family's rule that
cannot-verify is a failure, never a pass.

## Incident
None recorded.

## Limits
It fails only when the list cannot be obtained: no git checkout (and git ls-files fails) and no
SHIPYARD_CHECK_FILES. It cannot tell that a supplied list is stale or partial.

## Deviating
No deviation is read for this id. Run in a git checkout, or set SHIPYARD_CHECK_FILES to a file with one
tracked path per line (the fixture runner does this for checks that need no git).

Formerly gate checks 7 and 27 (both read the tracked-file list)
