unlinked: not a check but a deviation key: "- unlinked:<pin path>[:KEY]: <reason>" says why a moved pin links no change notes.

## Why
A release's Build ingredients section links where each moved ingredient's change is described, so a reader
can see what the bump brought. Where a pin has no such source (no Renovate manager captures it, no REPO=
beside it), ingredient-notes.sh writes the declared reason in place of the link, and check-release-notes.sh
accepts it. It is the one kind whose scope may end in :KEY, uppercase as the pin's assignment spells it,
because a link belongs to a pin, the file plus its key.

## Incident
None recorded.

## Limits
It excuses only the release-notes link rule, for the pins it names. deviations.sh refuses it with no
scope or "*", which would switch the rule off for the whole repo.

## Deviating
Write "- unlinked:<pin path>[:KEY]: <reason>". A good reason says why the ingredient has no change notes
to link, and what would give it some.

Formerly ingredient-notes.sh's unlinked declaration
