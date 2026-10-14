version-sh-tracked: build/version.sh is not git-ignored.

## Why
The version wrappers live in committed build/*.sh. A too-broad ignore (build/, build*/) makes git add skip
them without a word: everything works locally and only a fresh CI checkout fails, far from the cause.
Ignore build output directories (/_build/, build-*/, build/work/), never build/ itself. It applies where
the repo uses the wrappers.

## Incident
None recorded. The conventions skill describes the failure shape (passes locally, fails
only in a fresh checkout), and macports-legacy-support's build/ ignore silently dropped its
upstream-release-notes hook in the same way (see upstream-notes).

## Limits
It asks git whether build/version.sh would be ignored. It does not check the other build/*.sh files, and
it passes a repo that has no build/version.sh at all.

## Deviating
No deviation is read for this id. Narrow the .gitignore pattern, and git add -f the files it already
dropped.

Formerly gate check 7c
