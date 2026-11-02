repackage-wiring: a repo with ingredients has the repackage caller, and a repo without them has none.

## Why
A bumped ingredient changes what ships. The caller, .github/workflows/repackage-on-ingredient-bump.yml, is
what turns that bump into a repackage release, so a repo with ingredients and no caller ships nothing when
one moves, and a caller in a repo with none runs a job that can only skip. The caller has no paths: filter and
no own-upstream-paths: the decision reads .mavergreen/ for what counts, so a filter either hides a change it
needs or repeats what the tree already says.

## Incident
None recorded.

## Limits
It finds the caller as any tracked workflow naming repackage-on-ingredient-bump.yml on a line that is not a
comment, and refuses a paths:, paths-ignore: or own-upstream-paths: line in it. An empty
.mavergreen/ingredients/ counts as no ingredients. It does not run the workflow or check its inputs.

## Deviating
Write .mavergreen/deviations/repackage-wiring/<label>/ with scope *, a reason (why a bump needs no
repackage dispatch, as in shipyard, where every push releases) and a revisit (what would make it need one).
It excuses a repo that has ingredients and no caller, and nothing else.

New in the flag day (P2, R15's repackage-caller rule)
