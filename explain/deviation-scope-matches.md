deviation-scope-matches: a deviation's scope matches at least one tracked path.

## Why
An exception that covers nothing is stale (the file moved or went away) or mistyped. The check matches the
scope as a shell pattern, where "*" spans "/" and a space matches only a space, against the tracked paths,
for checks that scope by a path. A scope of * covers the repo and needs no match. Deviations of a check that
works on artifacts rather than tracked files (an identifier, a Label, an installed path) are not matched
against the tree, and nor are the two checkout scopes that name no path: on-target's <part> (a gap in the
10.9 job's coverage) and macos-runner's <workflow file>:<job>.

## Incident
None recorded.

## Limits
It matches against tracked paths only, so a scope for a built artifact's name is not tested here, and a
too-broad scope that happens to match something passes.

## Deviating
No deviation is read for this id. Correct the scope so it names a tracked path, or delete the deviation.

New in the flag day (K5, conventions-as-checks design)
