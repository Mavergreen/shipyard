pin-well-formed: every PIN under .mavergreen/ holds <ref>@<commit> on line 1, the commit 40 lowercase hex characters.

## Why
A PIN names a git ref and the commit it pointed at when it was pinned. The build fetches that commit, and
Renovate moves the ref and the commit together in one change. Without the @ there is no commit, and the
build would follow the ref wherever it moves. A short commit can come to name two objects as the
repository grows, and an uppercase digit is a spelling that compares unequal to git's own.

## Incident
None recorded.

## Limits
It reads .mavergreen/upstream/PIN and every .mavergreen/ingredients/*/PIN, and checks the shape alone: it
never asks the remote whether the commit exists or is the one the ref names. Line 1 is split on the first @,
so a ref may not hold one.

## Deviating
No deviation is read for this id. Write line 1 as <ref>@<the full commit>.

New in the flag day (P2)
