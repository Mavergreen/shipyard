legacy-top-level: no metadata in its pre-flag-day form sits at the top level of a repo; each has its place under .mavergreen/, or is retired.

## Why
Since the flag day every reader takes metadata from .mavergreen/, and none reads the old files. So an old file
is not a second copy that might disagree: it is a file that nothing reads and that still looks authoritative.
A deviation left in INGREDIENTS.md's "## Conformance deviations" no longer excuses anything, and a pin left
in components/ is never bumped, noted or repackaged on. The old names are INGREDIENTS.md, UPSTREAM_VERSION,
UPSTREAM_COMMIT, pins.env, MANIFEST, components/, .mavericks-intree, comment-reasons, msc.sh, build/msc.sh and
release-notes/. Each failure names where that file goes now, or says that it is retired.

## Incident
None recorded.

## Limits
It reads the tracked-file list, so an untracked or ignored file of one of those names passes. An INGREDIENTS.md
holding nothing but a "## Declared state" section passes, because declared state still lives there until it
retires with the rest of the nightly backstop; any other line outside that section, a title included, fails.
updater/ is not refused yet: it holds template sources, not metadata, and is named once the updaters retire.
It does not look below the top level, except for build/msc.sh.

## Deviating
No deviation is read for this id. Move each file to the place its failure names, or delete it when the failure
says it is retired.

New in the flag day (P2)
