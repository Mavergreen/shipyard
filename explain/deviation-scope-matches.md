deviation-scope-matches: a deviation's glob matches at least one tracked path.

## Why
An exception that covers nothing is stale (the file moved or went away) or mistyped. The check matches the
glob as a shell pattern, where "*" spans "/" and spaces, against the tracked paths, for checks that scope by
a path. A "*" glob, or no glob, covers the repo and needs no match. The comments deviation is repo-wide
only, so any glob on it fails here: "- comments:vendor/*: ..." is not honoured, rather than narrowing the
check. Deviations of a check that works on artifacts rather than tracked files (an identifier, a Label, an
installed path) are not matched against the tree.

## Incident
None recorded.

## Limits
It matches against tracked paths only, so a glob for a built artifact's name is not tested here, and a
too-broad glob that happens to match something passes.

## Deviating
No deviation is read for this id. Correct the glob so it names a tracked path, or delete the entry.

New in the flag day (K5, conventions-as-checks design)
