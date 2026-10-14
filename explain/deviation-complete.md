deviation-complete: every entry under INGREDIENTS.md's Conformance deviations section has a reason.

## Why
A deviation is an exception to a check, declared as a product fact. An exception with no reason is
indistinguishable from drift, so one parser, deviations.sh, reads the section for every checker and refuses
an entry that has none. It also refuses an empty glob (the "- check:reason" spelling with no space), which
would otherwise look like an exception while no checker honoured it, and let a reader that splits on
whitespace take the first word of the reason as the scope. The same refusal applies at package time and at
build time, so one entry cannot mean two things.

## Incident
None recorded.

## Limits
It checks that a reason is present, not that it is good. The grammar is "- <id>[:<glob>]: <reason>" on one
line; a line that does not start that way is not an entry and is ignored. Explanatory prose in the section
must not start with a dash.

## Deviating
No deviation is read for this id: an entry with no reason is the failure itself. Write the reason. A good reason says what the exception covers, why
the rule cannot hold yet, and when it ends ("Revisit when <condition>.").

Formerly the refusal in deviations.sh
