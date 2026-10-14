shell-portability: no tracked script uses a shell construct the 10.9 base system lacks.

## Why
These hazards work on a CI runner and fail on the platform the family exists to support, so CI is
structurally unable to catch them. The table in check-shell-portability.sh lists each construct with what
to write instead: sort -V (10.9's BSD sort has no -V), a bare mktemp -d with no template, lipo -archs (10.9's
lipo has none), and two assertion forms that cannot fail on 10.9's bash: a bare [[ ]] mid-test and a bare
negated command. It scans tracked *.sh and *.bats, so vendored or fetched upstream trees are out of scope.
Every rule must still match its own sample, so a pattern that quietly stopped matching makes the check fail
rather than stay green.

## Incident
Undated in the conventions skill: shipyard itself shipped two of these and reached all seven repos through
@v1 before anyone noticed. sort -V in previous-release-tag.sh silently emptied a release-notes baseline, and
a bare mktemp -d in run-repo-tests.sh and twelve test files meant the suite could not start on 10.9. A
first cut that checked only *.sh reported ed25519 clean while tests/version.bats died on the same bare
mktemp -d. The assertion rules found seventeen bare forms in shipyard and fourteen in ed25519, all green on
10.9 whatever the code did.

## Limits
It is a line-based pattern lint, one rule per construct. It sees only the constructs in its table, so a new
10.9 hazard is invisible until someone adds a row. It does not parse the shell: a pattern in a string or a
heredoc can match. bash32-parse covers a different gap, constructs a real bash 3.2 refuses to parse.

## Deviating
No deviation is read for this id. Rewrite the line as the message says. A new hazard is a new row in the
rule table, with a sample line the pattern must match.

Formerly gate check 10
