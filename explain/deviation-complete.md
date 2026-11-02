deviation-complete: every deviation under .mavergreen/deviations/ is complete, and names a check id.

## Why
A deviation is an exception to a check, declared as a product fact in its own directory,
.mavergreen/deviations/<check>/<label>/, holding scope, reason and revisit. An exception with no reason is
indistinguishable from drift, and one with no revisit trigger never ends, so one reader, deviations.sh, reads
the tree for every checker and refuses a deviation that lacks either. It also refuses an empty scope, a scope
with a second line, a label that does not match ^[a-z0-9][a-z0-9.-]*$, and a scope its check cannot honour
(a :KEY scope, a macos-runner that is not <workflow file>:<job>, an arm64 of nothing but wildcards, and
the like). The same refusal applies at package time and at build time, so one deviation cannot mean two
things. A <check> that is not a registered id excuses nothing, so it fails here too.

## Incident
None recorded.

## Limits
It checks that a reason and a revisit are present, not that they are good. A label that starts with a dot is
hidden, as any dotfile is, and is not read at all.

## Deviating
No deviation is read for this id: an incomplete deviation is the failure itself. Write the missing file. A
good reason says what the exception covers and why the rule cannot hold yet; a good revisit says what
evidence would end it.

Formerly the refusal in deviations.sh
