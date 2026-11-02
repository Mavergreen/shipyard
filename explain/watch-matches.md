watch-matches: every line of every .mavergreen/ingredients/*/watch is a glob that matches at least one tracked file.

## Why
A watch lists the repo paths whose change counts as its ingredient moving: patches, a vendored blob, a
script holding a pin. A change under one of them repackages the product and is reported in its notes. A glob
that matches nothing, mistyped or left behind by a move, never fires, and nothing else would notice.

## Incident
None recorded.

## Limits
It matches each line against the tracked files as a shell pattern, where * crosses a directory separator
and a space is literal. It checks that the glob matches something, not that it matches the right thing.

## Deviating
No deviation is read for this id. Correct the glob, or delete the line.

New in the flag day (P2, replacing ingredient-pins, which expanded the repackage caller's paths:)
