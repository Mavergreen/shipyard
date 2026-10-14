superpowers-ignored: .gitignore ignores .superpowers/ and .idea/, and nothing is tracked under them.

## Why
Specs, plans, ledgers and backlogs in .superpowers/ are ephemeral: a plan describes a transition, not a
system, and once the transition lands it is wrong about the system it produced. Committed, it reads as
documentation and misleads the next reader. docs/superpowers/ is not a place the family uses at all. An
IDE's per-user state (.idea/) is the user's, not the project's: committed, it churns on every checkout and
fights each contributor's own settings. An ignore line alone is not enough, since it does nothing for a file
already tracked, so the check asks git as well. No tracked file cites a working file either.

## Incident
None recorded.

## Limits
The ignore line may be .superpowers/, /.superpowers/, .superpowers or /.superpowers (likewise .idea). The
check looks at tracked paths under .superpowers/, docs/superpowers/ and .idea/. It does not scan tracked
files for citations of working files, which stays a judgment for review.

## Deviating
No deviation is read for this id. Add the ignore lines, and git rm -r --cached whatever is tracked.

Formerly gate check 27
